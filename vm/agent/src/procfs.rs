//! Readers for the /proc text formats PREPARE measures memory with. They take the text rather than
//! a path, so they are tested on any host.

/// A `Key:   123 kB` line of /proc/meminfo or /proc/<pid>/status, in kB.
pub fn kb_field(text: &str, key: &str) -> Option<u64> {
    text.lines().find_map(|line| {
        let value = line.strip_prefix(key)?.strip_prefix(':')?;
        value.split_whitespace().next()?.parse().ok()
    })
}

/// A `name 123` counter of /proc/vmstat.
pub fn counter(text: &str, name: &str) -> Option<u64> {
    text.lines().find_map(|line| {
        let (key, value) = line.split_once(' ')?;
        (key == name).then(|| value.trim().parse().ok()).flatten()
    })
}

/// Each zone's `min`, `low` and `high` watermarks from /proc/zoneinfo, in pages. Below `low` the
/// kernel starts reclaiming.
pub fn watermarks(zoneinfo: &str) -> Vec<(String, [u64; 3])> {
    let mut zones: Vec<(String, [Option<u64>; 3])> = Vec::new();
    for line in zoneinfo.lines() {
        if line.starts_with("Node ") {
            if let Some(zone) = line.split_whitespace().last() {
                zones.push((zone.to_owned(), [None; 3]));
            }
            continue;
        }
        let mut words = line.split_whitespace();
        let (Some(key), Some(value), None) = (words.next(), words.next(), words.next()) else {
            continue;
        };
        let Some(at) = ["min", "low", "high"].iter().position(|name| *name == key) else {
            continue;
        };
        if let (Some((_, marks)), Ok(value)) = (zones.last_mut(), value.parse()) {
            marks[at].get_or_insert(value);
        }
    }
    zones
        .into_iter()
        .filter_map(|(zone, [min, low, high])| Some((zone, [min?, low?, high?])))
        .collect()
}

/// The files a process maps, from its /proc/<pid>/maps, each once and in the order first mapped.
/// Anonymous and special mappings (`[heap]`, `[vdso]`) and deleted files are left out.
pub fn mapped_paths(maps: &str) -> Vec<String> {
    let mut paths: Vec<String> = Vec::new();
    for line in maps.lines() {
        // address perms offset dev inode path: the path is the rest of the line, spaces and all.
        let Some(path) = line.splitn(6, ' ').nth(5).map(str::trim_start) else {
            continue;
        };
        if !path.starts_with('/') || path.ends_with(" (deleted)") {
            continue;
        }
        if !paths.iter().any(|seen| seen == path) {
            paths.push(path.to_owned());
        }
    }
    paths
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_meminfo_and_status_fields() {
        let meminfo = "MemTotal:          93456 kB\nMemFree:           41234 kB\nMemAvailable:      60000 kB\n";
        assert_eq!(kb_field(meminfo, "MemFree"), Some(41234));
        assert_eq!(kb_field(meminfo, "MemAvailable"), Some(60000));
        assert_eq!(kb_field(meminfo, "Mem"), None);
        assert_eq!(kb_field(meminfo, "SwapTotal"), None);
        let status = "Name:\tpython3\nVmRSS:\t   23456 kB\nRssFile:\t   12000 kB\n";
        assert_eq!(kb_field(status, "RssFile"), Some(12000));
    }

    #[test]
    fn reads_vmstat_counters_by_whole_name() {
        let vmstat = "pgscan_kswapd 12\npgscan_kswapd_normal 3\noom_kill 0\n";
        assert_eq!(counter(vmstat, "pgscan_kswapd"), Some(12));
        assert_eq!(counter(vmstat, "oom_kill"), Some(0));
        assert_eq!(counter(vmstat, "pgscan"), None);
    }

    #[test]
    fn reads_each_zones_watermarks() {
        let zoneinfo = "\
Node 0, zone      DMA
  per-node stats
      nr_inactive_anon 0
  pages free     3843
        boost    0
        min      47
        low      58
        high     69
        spanned  4095
Node 0, zone   Normal
  pages free     2000
        min      235
        low      293
        high     351
Node 0, zone  HighMem
  pages free     0
";
        assert_eq!(
            watermarks(zoneinfo),
            vec![("DMA".to_owned(), [47, 58, 69]), ("Normal".to_owned(), [235, 293, 351])]
        );
    }

    #[test]
    fn lists_each_mapped_file_once() {
        let maps = "\
08048000-08049000 r--p 00000000 00:14 12  /usr/bin/python3.12
08049000-0804a000 r-xp 00001000 00:14 12  /usr/bin/python3.12
0804b000-0806c000 rw-p 00000000 00:00 0   [heap]
b7600000-b7700000 r--p 00000000 00:14 88  /usr/share/fonts/dejavu/Deja Vu Sans.ttf
b7700000-b7800000 r--p 00000000 00:14 99  /tmp/gone (deleted)
b7800000-b7900000 rw-s 00000000 00:05 7   /dev/fb0
b7f00000-b7f01000 r-xp 00000000 00:00 0   [vdso]
b7f01000-b7f02000 rw-p 00000000 00:00 0
";
        assert_eq!(
            mapped_paths(maps),
            vec![
                "/usr/bin/python3.12",
                "/usr/share/fonts/dejavu/Deja Vu Sans.ttf",
                "/dev/fb0"
            ]
        );
    }
}
