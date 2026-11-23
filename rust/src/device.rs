//! Parsing what adb prints.

/// One line of `adb devices -l`.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Device {
    pub serial: String,
    pub state: String,
    pub model: String,
    pub wifi: bool,
}

impl Device {
    pub fn is_ready(&self) -> bool {
        self.state == "device"
    }

    pub fn display_name(&self) -> &str {
        if self.model.is_empty() {
            &self.serial
        } else {
            &self.model
        }
    }

    /// Parses the output of `adb devices -l`, the same way the Linux and macOS versions do.
    pub fn parse(output: &str) -> Vec<Device> {
        output
            .lines()
            .map(str::trim)
            .filter(|line| {
                !line.is_empty() && !line.starts_with("List of") && !line.starts_with('*')
            })
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() < 2 {
                    return None;
                }
                let model = parts[2..]
                    .iter()
                    .find_map(|part| part.strip_prefix("model:"))
                    .unwrap_or("")
                    .replace('_', "-");
                let serial = parts[0].to_string();
                let wifi = serial.contains(':') || serial.starts_with("adb-");
                Some(Device {
                    state: parts[1].to_string(),
                    model,
                    wifi,
                    serial,
                })
            })
            .collect()
    }
}

/// Finds the device's Wi-Fi IPv4 address in `ip -f inet addr show wlan0`.
pub fn wifi_address(ip_output: &str) -> Option<String> {
    ip_output
        .split_whitespace()
        .collect::<Vec<_>>()
        .windows(2)
        .find_map(|pair| {
            if pair[0] != "inet" {
                return None;
            }
            let address = pair[1].split('/').next()?;
            let octets: Vec<&str> = address.split('.').collect();
            let valid = octets.len() == 4
                && octets
                    .iter()
                    .all(|o| !o.is_empty() && o.parse::<u8>().is_ok());
            valid.then(|| address.to_string())
        })
}

/// `192.168.1.5` becomes `192.168.1.5:5555`; an address with a port is left as it is.
pub fn normalized_host(input: &str, default_port: u16) -> String {
    let trimmed = input.trim();
    if trimmed.contains(':') {
        trimmed.to_string()
    } else {
        format!("{trimmed}:{default_port}")
    }
}

/// True when `adb connect` reports success. adb exits 0 even when the connection fails.
pub fn connect_succeeded(output: &str) -> bool {
    output.contains("connected to") && !output.contains("failed")
}

/// A file name for a serial number: everything but letters and digits becomes `_`.
pub fn safe_name(serial: &str) -> String {
    serial
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_usb_wifi_and_unauthorized_devices() {
        let output = "* daemon not running; starting now at tcp:5037\n\
            * daemon started successfully\n\
            List of devices attached\n\
            R52W70ABCDE            device usb:1-1 product:gta9pwifixx model:SM_X210 device:gta9pwifi transport_id:1\n\
            192.168.1.42:5555      device product:gta9pwifixx model:SM_X210 device:gta9pwifi transport_id:2\n\
            adb-R52W70-abc._adb-tls-connect._tcp offline transport_id:3\n\
            0123456789             unauthorized usb:1-2 transport_id:4\n\r\n";
        let devices = Device::parse(output);
        let expected = [
            ("R52W70ABCDE", "device", "SM-X210", false),
            ("192.168.1.42:5555", "device", "SM-X210", true),
            ("adb-R52W70-abc._adb-tls-connect._tcp", "offline", "", true),
            ("0123456789", "unauthorized", "", false),
        ];
        assert_eq!(devices.len(), expected.len());
        for (device, (serial, state, model, wifi)) in devices.iter().zip(expected) {
            assert_eq!(
                (
                    device.serial.as_str(),
                    device.state.as_str(),
                    device.model.as_str(),
                    device.wifi
                ),
                (serial, state, model, wifi)
            );
        }
        assert_eq!(devices[3].display_name(), "0123456789");
        assert!(devices[0].is_ready());
        assert!(!devices[2].is_ready());
    }

    #[test]
    fn empty_list_gives_no_devices() {
        assert!(Device::parse("List of devices attached\r\n\r\n").is_empty());
    }

    #[test]
    fn finds_the_wifi_address() {
        let output = "3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n    inet 192.168.1.42/24 brd 192.168.1.255 scope global wlan0";
        assert_eq!(wifi_address(output).as_deref(), Some("192.168.1.42"));
        assert_eq!(wifi_address("Device \"wlan0\" does not exist."), None);
        assert_eq!(wifi_address("inet 999.1.1.1/24"), None);
    }

    #[test]
    fn normalizes_hosts_and_reads_connect_output() {
        assert_eq!(normalized_host(" 192.168.1.5 ", 5555), "192.168.1.5:5555");
        assert_eq!(
            normalized_host("192.168.1.5:37000", 5555),
            "192.168.1.5:37000"
        );
        assert!(connect_succeeded("connected to 192.168.1.5:5555"));
        assert!(connect_succeeded("already connected to 192.168.1.5:5555"));
        assert!(!connect_succeeded(
            "failed to connect to '192.168.1.5:5555': Connection refused"
        ));
        assert_eq!(safe_name("192.168.1.5:5555"), "192_168_1_5_5555");
    }
}
