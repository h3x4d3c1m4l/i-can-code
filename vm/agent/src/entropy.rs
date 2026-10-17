//! The kernel's random pool. Every restored machine starts from the pool the snapshot saved, so
//! without the host's bytes each run would draw from the same state.

use std::io;

pub const BYTES: usize = 64;

/// HELLO's `entropy`: 128 lower-case hex digits. `None` for anything else.
pub fn decode_hex(text: &str) -> Option<[u8; BYTES]> {
    let digits = text.as_bytes();
    if digits.len() != BYTES * 2 {
        return None;
    }
    let value = |digit: u8| match digit {
        b'0'..=b'9' => Some(digit - b'0'),
        b'a'..=b'f' => Some(digit - b'a' + 10),
        _ => None,
    };
    let mut bytes = [0u8; BYTES];
    for (byte, pair) in bytes.iter_mut().zip(digits.chunks(2)) {
        *byte = (value(pair[0])? << 4) | value(pair[1])?;
    }
    Some(bytes)
}

/// Mixes `bytes` into the input pool, credited as entropy, and has the CRNG reseed from it at once
/// rather than at its next scheduled reseed, which can be minutes away.
#[cfg(target_os = "linux")]
pub fn add(bytes: &[u8; BYTES]) -> io::Result<()> {
    use std::fs::File;
    use std::os::fd::AsRawFd;

    // <linux/random.h>: _IOW('R', 0x03, int[2]) and _IO('R', 0x07). Both need CAP_SYS_ADMIN.
    const RNDADDENTROPY: libc::Ioctl = 0x4008_5203;
    const RNDRESEEDCRNG: libc::Ioctl = 0x5207;

    #[repr(C)]
    struct RandPoolInfo {
        entropy_count: libc::c_int,
        buf_size: libc::c_int,
        buf: [u8; BYTES],
    }

    let info = RandPoolInfo {
        entropy_count: (BYTES * 8) as libc::c_int,
        buf_size: BYTES as libc::c_int,
        buf: *bytes,
    };
    let random = File::open("/dev/urandom")?;
    // SAFETY: both ioctls take the fd of a random device; the first reads the struct it is given.
    unsafe {
        if libc::ioctl(random.as_raw_fd(), RNDADDENTROPY, &info) == -1 {
            return Err(io::Error::last_os_error());
        }
        if libc::ioctl(random.as_raw_fd(), RNDRESEEDCRNG) == -1 {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

#[cfg(not(target_os = "linux"))]
pub fn add(_: &[u8; BYTES]) -> io::Result<()> {
    Err(io::ErrorKind::Unsupported.into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_exactly_128_lower_case_digits() {
        let text: String = (0..64u8).map(|b| format!("{b:02x}")).collect();
        let bytes = decode_hex(&text).unwrap();
        assert_eq!(bytes[0], 0);
        assert_eq!(bytes[63], 63);
        assert_eq!(decode_hex(&text[..126]), None);
        assert_eq!(decode_hex(&text.to_uppercase()), None);
        assert_eq!(decode_hex(&"g".repeat(128)), None);
    }
}
