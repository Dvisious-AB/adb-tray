//! What differs between Windows, macOS and Linux.

use std::path::{Path, PathBuf};
use std::process::Command;

use tao::event_loop::EventLoop;

/// Settings, saved addresses and scrcpy logs: `%APPDATA%\adb-tray`, `~/Library/Application Support/adb-tray`
/// or `~/.config/adb-tray`, the same folders the Swift and Python versions use.
pub fn support_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join(adb_tray::product::COMMAND)
}

/// A Windows GUI program has no console; `--version` and errors are printed to the one it was started
/// from, if any.
#[cfg(windows)]
pub fn attach_console() {
    use windows_sys::Win32::System::Console::{ATTACH_PARENT_PROCESS, AttachConsole};
    unsafe {
        AttachConsole(ATTACH_PARENT_PROCESS);
    }
}

#[cfg(not(windows))]
pub fn attach_console() {}

/// The tray icon's window on Windows, kept for balloon notifications from worker threads.
static TRAY_WINDOW: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

pub fn remember_tray(tray: &tray_icon::TrayIcon) {
    #[cfg(windows)]
    TRAY_WINDOW.store(
        tray.window_handle() as usize,
        std::sync::atomic::Ordering::Relaxed,
    );
    let _ = tray;
}

/// Shows `message` as a notification from the tray icon itself. Windows only shows toasts from an app
/// with a registered AppUserModelID, which a portable program does not have; a balloon on the tray
/// icon needs none and is shown as a toast under the program's own name and icon.
/// Returns false where this is not available, and the caller falls back to notify-rust.
pub fn tray_notification(title: &str, message: &str) -> bool {
    #[cfg(windows)]
    {
        use windows_sys::Win32::UI::Shell::{
            NIF_INFO, NIIF_NONE, NIM_MODIFY, NOTIFYICONDATAW, Shell_NotifyIconW,
        };
        let window = TRAY_WINDOW.load(std::sync::atomic::Ordering::Relaxed);
        if window == 0 {
            return false;
        }
        fn copy(target: &mut [u16], text: &str) {
            let wide: Vec<u16> = text.encode_utf16().take(target.len() - 1).collect();
            target[..wide.len()].copy_from_slice(&wide);
            target[wide.len()] = 0;
        }
        let mut data: NOTIFYICONDATAW = unsafe { std::mem::zeroed() };
        data.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        data.hWnd = window as _;
        // tray-icon numbers its icons from 1, and this program has exactly one.
        data.uID = 1;
        data.uFlags = NIF_INFO;
        data.dwInfoFlags = NIIF_NONE;
        copy(&mut data.szInfoTitle, title);
        copy(&mut data.szInfo, message);
        unsafe { Shell_NotifyIconW(NIM_MODIFY, &data) != 0 }
    }
    #[cfg(not(windows))]
    {
        let _ = (title, message, &TRAY_WINDOW);
        false
    }
}

/// Menu bar only on macOS: no Dock icon and no app menu.
pub fn prepare_event_loop<T>(event_loop: &mut EventLoop<T>) {
    #[cfg(target_os = "macos")]
    {
        use tao::platform::macos::{ActivationPolicy, EventLoopExtMacOS};
        event_loop.set_activation_policy(ActivationPolicy::Accessory);
    }
    let _ = event_loop;
}

/// The colour of the tray icon. macOS colours its template image itself. Windows draws it light on a
/// dark taskbar and dark on a light one.
pub fn tray_icon_colour() -> &'static str {
    if cfg!(target_os = "macos") {
        "#000000"
    } else if cfg!(windows) && windows_light_taskbar() {
        "#1b1b1b"
    } else {
        "#ffffff"
    }
}

/// Menu icons: template images on macOS; Windows and GTK menus are light by default.
pub fn menu_icon_colour() -> &'static str {
    if cfg!(target_os = "macos") {
        "#000000"
    } else {
        "#1b1b1b"
    }
}

/// `SystemUsesLightTheme` is 1 when the taskbar is light. Read with reg.exe to need no registry crate.
fn windows_light_taskbar() -> bool {
    let mut command = Command::new("reg");
    command.args([
        "query",
        r"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
        "/v",
        "SystemUsesLightTheme",
    ]);
    adb_tray::tools::hide_console(&mut command);
    command
        .output()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .trim_end()
                .ends_with("0x1")
        })
        .unwrap_or(false)
}

pub fn pictures_dir() -> PathBuf {
    dirs::picture_dir()
        .or_else(dirs::home_dir)
        .unwrap_or_else(std::env::temp_dir)
}

/// Opens `adb -s <serial> shell` in a terminal window of its own.
pub fn open_shell(adb: &Path, serial: &str) -> std::io::Result<()> {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        // start opens a new console window; the empty title argument keeps start from reading the
        // quoted program path as the title.
        let line = format!(
            "/C start \"adb shell {serial}\" \"{}\" -s {serial} shell",
            adb.display()
        );
        Command::new("cmd").raw_arg(line).spawn().map(|_| ())
    }
    #[cfg(target_os = "macos")]
    {
        // A temporary .command file opened in Terminal needs no Automation permission.
        let script = std::env::temp_dir().join(format!("adb-shell-{}.command", std::process::id()));
        let quote = |s: &str| format!("'{}'", s.replace('\'', r"'\''"));
        let body = format!(
            "#!/bin/sh\nrm -f {}\nexec {} -s {} shell\n",
            quote(&script.to_string_lossy()),
            quote(&adb.to_string_lossy()),
            quote(serial)
        );
        std::fs::write(&script, body)?;
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o700))?;
        Command::new("open")
            .args(["-a", "Terminal"])
            .arg(&script)
            .spawn()
            .map(|_| ())
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        let terminal = ["x-terminal-emulator", "gnome-terminal"]
            .into_iter()
            .find(|t| {
                Command::new("sh")
                    .args(["-c", &format!("command -v {t}")])
                    .output()
                    .is_ok_and(|o| o.status.success())
            })
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no terminal"))?;
        let quote = |s: &str| format!("'{}'", s.replace('\'', r"'\''"));
        let line = format!(
            "{} -s {} shell",
            quote(&adb.to_string_lossy()),
            quote(serial)
        );
        Command::new(terminal)
            .args(["-e", &line])
            .spawn()
            .map(|_| ())
    }
}
