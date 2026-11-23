//! Recently used Wi-Fi addresses, newest first, at most ten. The same JSON file format as the Linux
//! and macOS versions, so a list moves over with the user's settings.

use std::fs;
use std::path::{Path, PathBuf};

pub const LIMIT: usize = 10;

pub struct HostStore {
    file: PathBuf,
}

impl HostStore {
    pub fn new(file: impl Into<PathBuf>) -> Self {
        Self { file: file.into() }
    }

    pub fn file(&self) -> &Path {
        &self.file
    }

    pub fn load(&self) -> Vec<String> {
        fs::read(&self.file)
            .ok()
            .and_then(|data| serde_json::from_slice::<Vec<String>>(&data).ok())
            .unwrap_or_default()
    }

    pub fn save(&self, host: &str) -> std::io::Result<()> {
        let mut hosts: Vec<String> = self.load().into_iter().filter(|h| h != host).collect();
        hosts.insert(0, host.to_string());
        hosts.truncate(LIMIT);
        if let Some(parent) = self.file.parent() {
            fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string_pretty(&hosts).map_err(std::io::Error::other)?;
        // Write and rename, so a crash never leaves half a file.
        let temporary = self.file.with_extension("json.tmp");
        fs::write(&temporary, json)?;
        fs::rename(&temporary, &self.file)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_the_newest_ten_without_duplicates() {
        let dir = std::env::temp_dir().join(format!("adb-tray-hosts-{}", std::process::id()));
        let store = HostStore::new(dir.join("hosts.json"));
        assert!(store.load().is_empty());
        for i in 0..12 {
            store.save(&format!("10.0.0.{i}:5555")).unwrap();
        }
        store.save("10.0.0.5:5555").unwrap();
        let hosts = store.load();
        assert_eq!(hosts.len(), LIMIT);
        assert_eq!(hosts[0], "10.0.0.5:5555");
        assert_eq!(hosts[1], "10.0.0.11:5555");
        assert_eq!(hosts.iter().filter(|h| *h == "10.0.0.5:5555").count(), 1);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn reads_the_python_format() {
        let dir = std::env::temp_dir().join(format!("adb-tray-hosts-py-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("hosts.json"), "[\n  \"192.168.50.24:5555\"\n]").unwrap();
        assert_eq!(
            HostStore::new(dir.join("hosts.json")).load(),
            ["192.168.50.24:5555"]
        );
        fs::remove_dir_all(dir).unwrap();
    }
}
