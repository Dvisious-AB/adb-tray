//! The product's name, version and addresses. The name follows the Appninjas product architecture,
//! "Appninjas {Product}"; the command, the packages and the bundle identifier stay `adb-tray`.

pub const NAME: &str = "Appninjas ADB";
pub const COMMAND: &str = "adb-tray";
/// From the VERSION file at the root of the repository (build.rs).
pub const VERSION: &str = env!("ADB_TRAY_VERSION");
pub const REPOSITORY: &str = "https://github.com/Dvisious-AB/adb-tray";
/// The help pages: `<HELP_BASE>/<language>`, where the language is the system's two-letter code
/// (ISO 639-1). appninjas.se sends each code to the manual in that language, or to the English one.
pub const HELP_BASE: &str = "https://appninjas.se/adb/help";

pub const POLL_SECONDS: u64 = 4;
pub const TCP_PORT: u16 = 5555;
pub const SCRCPY_OPTIONS: &[&str] = &["-m", "1600", "--stay-awake"];

/// The command that installs adb on this platform, offered in the menu when adb is missing.
pub fn adb_install_command() -> &'static str {
    if cfg!(windows) {
        // scrcpy's Windows release ships adb.exe next to scrcpy.exe.
        "winget install Genymobile.scrcpy"
    } else if cfg!(target_os = "macos") {
        "brew install --cask android-platform-tools"
    } else {
        "sudo apt install adb"
    }
}

pub fn scrcpy_install_command() -> &'static str {
    if cfg!(windows) {
        "winget install Genymobile.scrcpy"
    } else if cfg!(target_os = "macos") {
        "brew install scrcpy"
    } else {
        "sudo apt install scrcpy"
    }
}

/// The two- or three-letter language code of the first usable entry in `preferred` (BCP 47 tags such
/// as `sv-SE`, or POSIX locales such as `sv_SE.UTF-8`), lower case; `en` when there is none.
pub fn help_language(preferred: &[String]) -> String {
    preferred
        .iter()
        .flat_map(|tag| tag.split(':'))
        .filter_map(|tag| tag.split(['-', '_', '.', '@']).next())
        .map(str::to_ascii_lowercase)
        .find(|code| (2..=3).contains(&code.len()) && code.chars().all(|c| c.is_ascii_lowercase()) && code != "c")
        .unwrap_or_else(|| "en".to_string())
}

/// The help page for `language` (see help_language).
pub fn help_url(language: &str) -> String {
    format!("{HELP_BASE}/{language}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn help_links_use_the_two_letter_language_code() {
        let tags = |v: &[&str]| v.iter().map(|t| t.to_string()).collect::<Vec<_>>();
        assert_eq!(help_language(&tags(&["sv-SE", "en-US"])), "sv");
        assert_eq!(help_language(&tags(&["sv_SE.UTF-8"])), "sv");
        assert_eq!(help_language(&tags(&["fi:en"])), "fi");
        assert_eq!(help_language(&tags(&["C", "en-GB"])), "en");
        assert_eq!(help_language(&tags(&["zh-Hans-CN"])), "zh");
        assert_eq!(help_language(&[]), "en");
        assert_eq!(help_url("sv"), "https://appninjas.se/adb/help/sv");
    }
}
