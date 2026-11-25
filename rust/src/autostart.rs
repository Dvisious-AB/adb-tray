//! Start at login on Windows: what the program writes to and reads from the registry, without the
//! registry itself, so it can be tested on every platform.
//!
//! The program is started at login by a value named after the product under
//! `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. Turning it off in Task Manager or in
//! Settings > Apps > Startup keeps that value and marks it disabled under
//! `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run` instead.

use std::path::Path;

pub const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
pub const APPROVED_KEY: &str =
    r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
pub const VALUE_NAME: &str = crate::product::NAME;

/// The command line stored in the Run value: the program's path in quotes, since it may contain
/// spaces.
pub fn command_line(exe: &Path) -> String {
    format!("\"{}\"", exe.display())
}

/// The program path in a Run value's command line, with any quotes and arguments taken off.
pub fn program_path(command_line: &str) -> &str {
    let line = command_line.trim();
    match line.strip_prefix('"') {
        Some(rest) => rest.split('"').next().unwrap_or(rest),
        None => line.split(' ').next().unwrap_or(line),
    }
}

/// Whether a StartupApproved value lets the Run value start the program. Windows writes 02 (or 06)
/// followed by zeros when it is on, and 03 (or 01, 07) followed by the time it was turned off: an
/// odd first byte means off. No value at all means on.
pub fn approved(value: Option<&[u8]>) -> bool {
    match value.and_then(|v| v.first()) {
        Some(first) => first % 2 == 0,
        None => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn command_line_quotes_the_path() {
        let exe = PathBuf::from(r"C:\Program Files\Appninjas ADB\adb-tray.exe");
        assert_eq!(
            command_line(&exe),
            r#""C:\Program Files\Appninjas ADB\adb-tray.exe""#
        );
    }

    #[test]
    fn program_path_reads_quoted_and_bare_command_lines() {
        assert_eq!(
            program_path(r#""C:\Program Files\adb-tray.exe" --flag"#),
            r"C:\Program Files\adb-tray.exe"
        );
        assert_eq!(
            program_path(r"C:\Tools\adb-tray.exe --flag"),
            r"C:\Tools\adb-tray.exe"
        );
        assert_eq!(program_path(r#"  "C:\x.exe"  "#), r"C:\x.exe");
        assert_eq!(program_path(""), "");
    }

    #[test]
    fn approved_follows_the_first_byte() {
        assert!(approved(None));
        assert!(approved(Some(&[])));
        assert!(approved(Some(&[0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])));
        assert!(approved(Some(&[0x06, 0, 0, 0])));
        assert!(!approved(Some(&[0x03, 0, 0, 0, 0x8a, 0x1f, 0x3c, 0x4e])));
        assert!(!approved(Some(&[0x01])));
    }
}
