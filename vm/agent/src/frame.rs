//! Frames on the control line: `version | type | id | payload | crc`, COBS-encoded and followed by one
//! zero byte. vm/protocol/README.md section 2.

pub const VERSION: u8 = 1;

const HEADER_BYTES: usize = 6;
const CRC_BYTES: usize = 4;
const OVERHEAD: usize = HEADER_BYTES + CRC_BYTES;

pub const MAX_PAYLOAD_TO_AGENT: usize = 4096;
pub const MAX_PAYLOAD_TO_HOST: usize = 16384;

/// The longest encoding of a frame with `max_payload` bytes of payload, without its delimiter.
pub const fn max_encoded_len(max_payload: usize) -> usize {
    let n = OVERHEAD + max_payload;
    n + 1 + n / 254
}

/// A frame that passed every check. Its version is [`VERSION`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub type_code: u8,
    pub id: u32,
    pub payload: Vec<u8>,
}

/// Why a chunk between two delimiters was not a frame. The checks run in this order, and the first
/// that fails names the drop.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DropReason {
    Oversize,
    Cobs,
    Short,
    Crc,
    Version,
}

impl DropReason {
    pub const ALL: [DropReason; 5] = [
        DropReason::Oversize,
        DropReason::Cobs,
        DropReason::Short,
        DropReason::Crc,
        DropReason::Version,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            DropReason::Oversize => "oversize",
            DropReason::Cobs => "cobs",
            DropReason::Short => "short",
            DropReason::Crc => "crc",
            DropReason::Version => "version",
        }
    }
}

/// Returns the wire bytes of one frame, delimiter included. Checks no size limit: the message layer
/// does, because the limit depends on the direction.
pub fn encode(type_code: u8, id: u32, payload: &[u8]) -> Vec<u8> {
    let mut raw = Vec::with_capacity(OVERHEAD + payload.len());
    raw.push(VERSION);
    raw.push(type_code);
    raw.extend_from_slice(&id.to_le_bytes());
    raw.extend_from_slice(payload);
    let crc = crc32fast::hash(&raw);
    raw.extend_from_slice(&crc.to_le_bytes());

    let mut wire = Vec::with_capacity(max_encoded_len(payload.len()) + 1);
    cobs_encode(&raw, &mut wire);
    wire.push(0);
    wire
}

/// Judges one chunk, the bytes between two delimiters, for a receiver whose limit is `max_payload`.
pub fn decode(chunk: &[u8], max_payload: usize) -> Result<Frame, DropReason> {
    if chunk.len() > max_encoded_len(max_payload) {
        return Err(DropReason::Oversize);
    }
    let raw = cobs_decode(chunk).ok_or(DropReason::Cobs)?;
    if raw.len() < OVERHEAD {
        return Err(DropReason::Short);
    }
    let (covered, crc) = raw.split_at(raw.len() - CRC_BYTES);
    if crc32fast::hash(covered) != u32::from_le_bytes([crc[0], crc[1], crc[2], crc[3]]) {
        return Err(DropReason::Crc);
    }
    if covered[0] != VERSION {
        return Err(DropReason::Version);
    }
    let payload = &covered[HEADER_BYTES..];
    if payload.len() > max_payload {
        return Err(DropReason::Oversize);
    }
    Ok(Frame {
        type_code: covered[1],
        id: u32::from_le_bytes([covered[2], covered[3], covered[4], covered[5]]),
        payload: payload.to_vec(),
    })
}

/// Appends the COBS encoding of `data` to `out`, without a delimiter.
///
/// The final block is written even when it is empty, so 254 non-zero bytes end in `01`. That is the
/// unique form, the one the fixtures pin; some encoders leave the `01` out.
pub fn cobs_encode(data: &[u8], out: &mut Vec<u8>) {
    let mut code_at = out.len();
    out.push(0);
    let mut code: u8 = 1;
    for &byte in data {
        if byte != 0 {
            out.push(byte);
            code += 1;
            if code != 0xFF {
                continue;
            }
        }
        out[code_at] = code;
        code_at = out.len();
        out.push(0);
        code = 1;
    }
    out[code_at] = code;
}

/// Decodes one chunk without its delimiter, or returns `None` when it is not COBS. Also accepts the
/// form that leaves out an empty final block.
pub fn cobs_decode(chunk: &[u8]) -> Option<Vec<u8>> {
    if chunk.is_empty() {
        return None;
    }
    let mut out = Vec::with_capacity(chunk.len());
    let mut i = 0;
    while i < chunk.len() {
        let code = usize::from(chunk[i]);
        i += 1;
        if code == 0 || i + code - 1 > chunk.len() {
            return None;
        }
        let block = &chunk[i..i + code - 1];
        if block.contains(&0) {
            return None;
        }
        out.extend_from_slice(block);
        i += block.len();
        if code != 0xFF && i < chunk.len() {
            out.push(0);
        }
    }
    Some(out)
}

/// Frames dropped since the decoder was made, by reason.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct DropCounts([u64; DropReason::ALL.len()]);

impl DropCounts {
    pub fn get(&self, reason: DropReason) -> u64 {
        self.0[reason as usize]
    }

    fn add(&mut self, reason: DropReason) {
        self.0[reason as usize] += 1;
    }
}

/// Turns a byte stream split anywhere into frames, and resyncs at the next zero after anything it
/// cannot decode.
pub struct Decoder {
    max_payload: usize,
    chunk: Vec<u8>,
    overflowed: bool,
    drops: DropCounts,
}

impl Decoder {
    pub fn new(max_payload: usize) -> Decoder {
        Decoder {
            max_payload,
            chunk: Vec::with_capacity(max_encoded_len(max_payload)),
            overflowed: false,
            drops: DropCounts::default(),
        }
    }

    pub fn drops(&self) -> DropCounts {
        self.drops
    }

    /// Returns what the bytes completed, in order: a frame, or the reason a chunk was dropped.
    /// Empty chunks complete nothing.
    pub fn push(&mut self, bytes: &[u8]) -> Vec<Result<Frame, DropReason>> {
        let mut events = Vec::new();
        let mut rest = bytes;
        while let Some(zero) = rest.iter().position(|&b| b == 0) {
            self.append(&rest[..zero]);
            events.extend(self.finish());
            rest = &rest[zero + 1..];
        }
        self.append(rest);
        events
    }

    /// Stops storing a chunk once it passes the limit, so memory stays within one maximum frame
    /// whatever the peer sends. The rest of it up to the delimiter is discarded.
    fn append(&mut self, part: &[u8]) {
        if self.overflowed || part.is_empty() {
            return;
        }
        if self.chunk.len() + part.len() > max_encoded_len(self.max_payload) {
            self.overflowed = true;
            self.chunk.clear();
            return;
        }
        self.chunk.extend_from_slice(part);
    }

    fn finish(&mut self) -> Option<Result<Frame, DropReason>> {
        let event = if self.overflowed {
            Some(Err(DropReason::Oversize))
        } else if self.chunk.is_empty() {
            None
        } else {
            Some(decode(&self.chunk, self.max_payload))
        };
        self.chunk.clear();
        self.overflowed = false;
        if let Some(Err(reason)) = event {
            self.drops.add(reason);
        }
        event
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fixtures::{hex, load, to_hex};
    use serde_json::{Value, json};

    fn str_of<'a>(value: &'a Value, key: &str) -> &'a str {
        value[key]
            .as_str()
            .unwrap_or_else(|| panic!("{key} missing in {value}"))
    }

    #[test]
    fn constants_match_the_protocol_table() {
        let protocol = load("protocol.json");
        assert_eq!(protocol["version"], VERSION);
        assert_eq!(protocol["header_bytes"], HEADER_BYTES);
        assert_eq!(protocol["crc_bytes"], CRC_BYTES);
        assert_eq!(protocol["max_payload_to_agent"], MAX_PAYLOAD_TO_AGENT);
        assert_eq!(protocol["max_payload_to_host"], MAX_PAYLOAD_TO_HOST);
        assert_eq!(protocol["max_encoded_to_agent"], max_encoded_len(MAX_PAYLOAD_TO_AGENT));
        assert_eq!(protocol["max_encoded_to_host"], max_encoded_len(MAX_PAYLOAD_TO_HOST));
    }

    #[test]
    fn crc_matches_every_vector() {
        for vector in load("crc32.json")["vectors"].as_array().unwrap() {
            let input = hex(str_of(vector, "input_hex"));
            let crc = crc32fast::hash(&input);
            assert_eq!(format!("{crc:08x}"), str_of(vector, "crc"), "{}", vector["name"]);
            assert_eq!(
                to_hex(&crc.to_le_bytes()),
                str_of(vector, "crc_le_hex"),
                "{}",
                vector["name"]
            );
        }
    }

    #[test]
    fn cobs_round_trips_every_vector() {
        let cobs = load("cobs.json");
        for vector in cobs["vectors"].as_array().unwrap() {
            let decoded = hex(str_of(vector, "decoded_hex"));
            let encoded = hex(str_of(vector, "encoded_hex"));
            let mut out = Vec::new();
            cobs_encode(&decoded, &mut out);
            assert_eq!(to_hex(&out), to_hex(&encoded), "encode {}", vector["name"]);
            assert_eq!(cobs_decode(&encoded), Some(decoded), "decode {}", vector["name"]);
        }
    }

    #[test]
    fn cobs_accepts_but_never_produces_the_short_form() {
        for vector in load("cobs.json")["decode_only"].as_array().unwrap() {
            let decoded = hex(str_of(vector, "decoded_hex"));
            let encoded = hex(str_of(vector, "encoded_hex"));
            assert_eq!(cobs_decode(&encoded), Some(decoded.clone()), "{}", vector["name"]);
            let mut out = Vec::new();
            cobs_encode(&decoded, &mut out);
            assert_ne!(out, encoded, "{}", vector["name"]);
        }
    }

    #[test]
    fn cobs_rejects_every_invalid_encoding() {
        for vector in load("cobs.json")["invalid"].as_array().unwrap() {
            assert_eq!(
                cobs_decode(&hex(str_of(vector, "encoded_hex"))),
                None,
                "{}",
                vector["name"]
            );
        }
    }

    fn event_json(event: &Result<Frame, DropReason>) -> Value {
        match event {
            Ok(frame) => json!({"frame": {
                "version": VERSION,
                "type": frame.type_code,
                "id": frame.id,
                "payload_hex": to_hex(&frame.payload),
            }}),
            Err(reason) => json!({"error": reason.as_str()}),
        }
    }

    fn feed(max_payload: usize, chunks: &[Vec<u8>]) -> Vec<Value> {
        let mut decoder = Decoder::new(max_payload);
        chunks
            .iter()
            .flat_map(|chunk| decoder.push(chunk))
            .map(|e| event_json(&e))
            .collect()
    }

    #[test]
    fn stream_gives_the_same_events_however_it_is_split() {
        for case in load("stream.json")["cases"].as_array().unwrap() {
            let name = &case["name"];
            let max_payload = case["max_payload"].as_u64().unwrap() as usize;
            let chunks: Vec<Vec<u8>> = case["chunks_hex"]
                .as_array()
                .unwrap()
                .iter()
                .map(|c| hex(c.as_str().unwrap()))
                .collect();
            let expected = case["events"].as_array().unwrap();
            let all: Vec<u8> = chunks.concat();

            assert_eq!(&feed(max_payload, &chunks), expected, "as given: {name}");
            assert_eq!(
                &feed(max_payload, std::slice::from_ref(&all)),
                expected,
                "in one read: {name}"
            );
            let bytes: Vec<Vec<u8>> = all.iter().map(|&b| vec![b]).collect();
            assert_eq!(&feed(max_payload, &bytes), expected, "byte by byte: {name}");
            for size in [2, 3, 7, 254, 255, 4096] {
                let pieces: Vec<Vec<u8>> = all.chunks(size).map(<[u8]>::to_vec).collect();
                assert_eq!(&feed(max_payload, &pieces), expected, "in pieces of {size}: {name}");
            }
        }
    }

    #[test]
    fn decoder_counts_drops_by_reason() {
        let mut decoder = Decoder::new(MAX_PAYLOAD_TO_AGENT);
        let good = encode(0x05, 1, b"{}");
        let mut raw = cobs_decode(&good[..good.len() - 1]).unwrap();
        raw[HEADER_BYTES] = b'[';
        let mut bad_crc = Vec::new();
        cobs_encode(&raw, &mut bad_crc);
        bad_crc.push(0);
        let events = decoder.push(&[&[0x05, 0x11, 0x00][..], &bad_crc, &good].concat());
        assert_eq!(events.len(), 3);
        assert_eq!(events[0], Err(DropReason::Cobs));
        assert_eq!(events[1], Err(DropReason::Crc));
        assert!(events[2].is_ok());
        assert_eq!(decoder.drops().get(DropReason::Cobs), 1);
        assert_eq!(decoder.drops().get(DropReason::Crc), 1);
        assert_eq!(decoder.drops().get(DropReason::Short), 0);
    }

    #[test]
    fn an_endless_chunk_keeps_memory_bounded() {
        let mut decoder = Decoder::new(MAX_PAYLOAD_TO_AGENT);
        for _ in 0..1000 {
            assert!(decoder.push(&[0x7F; 1024]).is_empty());
            assert!(decoder.chunk.capacity() <= max_encoded_len(MAX_PAYLOAD_TO_AGENT));
        }
        assert_eq!(decoder.push(&[0]), vec![Err(DropReason::Oversize)]);
        let ping = encode(0x05, 2, b"{}");
        assert_eq!(decoder.push(&ping).len(), 1);
    }
}
