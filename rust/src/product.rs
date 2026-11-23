//! The product's name, version and addresses. The name follows the Appninjas product architecture,
//! "Appninjas {Product}"; the command, the packages and the bundle identifier stay `adb-tray`.

pub const NAME: &str = "Appninjas ADB";
pub const COMMAND: &str = "adb-tray";
/// From the VERSION file at the root of the repository (build.rs).
pub const VERSION: &str = env!("ADB_TRAY_VERSION");
pub const REPOSITORY: &str = "https://github.com/Dvisious-AB/adb-tray";
/// The English manual. The menu translates this address (po/*.po) to the manual in its own language.
pub const HELP_URL_ENGLISH: &str = "https://appninjas.se/en/hjalp/adb";

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
