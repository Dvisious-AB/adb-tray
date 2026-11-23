//! Finds `adb` and `scrcpy` and runs them.
//!
//! A program started at login does not always get the user's PATH: launchd's is minimal on macOS, and on
//! Windows a PATH that winget changed only reaches programs started after the next sign-in. The usual
//! install locations are therefore searched as well, and the PATH handed to child processes is widened
//! the same way, so that scrcpy, which starts adb itself, finds the same adb.

use std::collections::HashSet;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::time::Duration;

pub struct Tools {
    search_path: Vec<PathBuf>,
}

/// Directories searched after PATH, per platform. `~` and `%LOCALAPPDATA%` are expanded.
fn fallback_directories() -> Vec<PathBuf> {
    let home = dirs::home_dir().unwrap_or_default();
    let mut directories = Vec::new();
    if cfg!(target_os = "macos") {
        directories.push(PathBuf::from("/opt/homebrew/bin")); // Homebrew on Apple silicon
        directories.push(PathBuf::from("/usr/local/bin")); // Homebrew on Intel
        directories.push(home.join("Library/Android/sdk/platform-tools")); // Android Studio
    } else if cfg!(windows) {
        if let Some(local) = dirs::data_local_dir() {
            directories.push(local.join("Microsoft").join("WinGet").join("Links")); // winget portable packages
            directories.extend(winget_package_directories(
                &local.join("Microsoft").join("WinGet").join("Packages"),
            ));
            directories.push(local.join("Android").join("Sdk").join("platform-tools")); // Android Studio
        }
        directories.push(PathBuf::from(r"C:\ProgramData\chocolatey\bin"));
        directories.push(home.join("scoop").join("shims"));
    } else {
        directories.push(home.join("Android/Sdk/platform-tools"));
    }
    directories
}

/// winget unpacks scrcpy to `Packages\Genymobile.scrcpy_<source>\scrcpy-win64-v<version>\`.
fn winget_package_directories(packages: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let Ok(entries) = std::fs::read_dir(packages) else {
        return found;
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_lowercase();
        if !name.starts_with("genymobile.scrcpy") && !name.starts_with("google.platformtools") {
            continue;
        }
        found.push(entry.path());
        if let Ok(inner) = std::fs::read_dir(entry.path()) {
            found.extend(inner.flatten().map(|e| e.path()).filter(|p| p.is_dir()));
        }
    }
    found.sort();
    found.reverse(); // the newest version directory first
    found
}

impl Tools {
    pub fn new() -> Self {
        let from_environment: Vec<PathBuf> = std::env::var_os("PATH")
            .map(|p| std::env::split_paths(&p).collect())
            .unwrap_or_default();
        Self::with_search_path(from_environment.into_iter().chain(fallback_directories()))
    }

    pub fn with_search_path(directories: impl IntoIterator<Item = PathBuf>) -> Self {
        let mut seen = HashSet::new();
        let search_path = directories
            .into_iter()
            .filter(|d| !d.as_os_str().is_empty() && seen.insert(d.clone()))
            .collect();
        Self { search_path }
    }

    pub fn find(&self, name: &str) -> Option<PathBuf> {
        let file = if cfg!(windows) {
            format!("{name}.exe")
        } else {
            name.to_string()
        };
        self.search_path
            .iter()
            .map(|d| d.join(&file))
            .find(|p| is_executable(p))
    }

    pub fn adb(&self) -> Option<PathBuf> {
        self.find("adb")
    }

    pub fn scrcpy(&self) -> Option<PathBuf> {
        self.find("scrcpy")
    }

    /// PATH for child processes, and `ADB` so scrcpy uses the same adb as the menu.
    pub fn child_environment(&self) -> Vec<(OsString, OsString)> {
        let mut environment = Vec::new();
        if let Ok(path) = std::env::join_paths(&self.search_path) {
            environment.push((OsString::from("PATH"), path));
        }
        if let Some(adb) = self.adb() {
            environment.push((OsString::from("ADB"), adb.into_os_string()));
        }
        environment
    }

    /// A command for `program` with the widened environment and no console window on Windows.
    pub fn command(&self, program: &Path) -> Command {
        let mut command = Command::new(program);
        command.envs(self.child_environment());
        hide_console(&mut command);
        command
    }

    /// Runs `program` and returns its exit code and combined output; gives up after `timeout`.
    pub fn run(&self, program: &Path, args: &[&str], timeout: Duration) -> (i32, Vec<u8>) {
        let mut command = self.command(program);
        command.args(args).stdin(Stdio::null());
        match run_with_timeout(command, timeout) {
            Some(output) => {
                let mut combined = output.stdout;
                combined.extend_from_slice(&output.stderr);
                (output.status.code().unwrap_or(1), combined)
            }
            None => (1, b"timeout".to_vec()),
        }
    }
}

impl Default for Tools {
    fn default() -> Self {
        Self::new()
    }
}

fn run_with_timeout(mut command: Command, timeout: Duration) -> Option<Output> {
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = command.spawn().ok()?;
    let (sender, receiver) = std::sync::mpsc::channel();
    let id = child.id();
    let stdout = child.stdout.take();
    let stderr = child.stderr.take();
    std::thread::spawn(move || {
        let read = |pipe: Option<Box<dyn std::io::Read + Send>>| {
            let mut buffer = Vec::new();
            if let Some(mut pipe) = pipe {
                let _ = pipe.read_to_end(&mut buffer);
            }
            buffer
        };
        let err_thread = std::thread::spawn(move || read(stderr.map(|p| Box::new(p) as _)));
        let out = read(stdout.map(|p| Box::new(p) as _));
        let err = err_thread.join().unwrap_or_default();
        let _ = sender.send((out, err));
    });
    match receiver.recv_timeout(timeout) {
        Ok((stdout, stderr)) => {
            let status = child.wait().ok()?;
            Some(Output {
                status,
                stdout,
                stderr,
            })
        }
        Err(_) => {
            let _ = child.kill();
            let _ = child.wait();
            let _ = id;
            None
        }
    }
}

#[cfg(windows)]
pub fn hide_console(command: &mut Command) {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    command.creation_flags(CREATE_NO_WINDOW);
}

#[cfg(not(windows))]
pub fn hide_console(_command: &mut Command) {}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(path: &Path) -> bool {
    path.is_file()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_programs_in_the_search_path_in_order() {
        let base = std::env::temp_dir().join(format!("adb-tray-tools-{}", std::process::id()));
        let (first, second) = (base.join("first"), base.join("second"));
        std::fs::create_dir_all(&first).unwrap();
        std::fs::create_dir_all(&second).unwrap();
        let name = if cfg!(windows) { "adb.exe" } else { "adb" };
        for dir in [&first, &second] {
            std::fs::write(dir.join(name), "").unwrap();
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                std::fs::set_permissions(dir.join(name), std::fs::Permissions::from_mode(0o755))
                    .unwrap();
            }
        }
        let tools =
            Tools::with_search_path([PathBuf::new(), first.clone(), second.clone(), first.clone()]);
        assert_eq!(tools.adb(), Some(first.join(name)));
        assert_eq!(tools.scrcpy(), None);
        let environment = tools.child_environment();
        assert!(
            environment
                .iter()
                .any(|(k, v)| k == "ADB" && PathBuf::from(v) == first.join(name))
        );
        std::fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn runs_a_program_and_times_out() {
        let tools = Tools::with_search_path([]);
        #[cfg(unix)]
        {
            let (code, output) = tools.run(
                Path::new("/bin/sh"),
                &["-c", "echo out; echo err >&2; exit 3"],
                Duration::from_secs(5),
            );
            assert_eq!(code, 3);
            assert_eq!(String::from_utf8_lossy(&output), "out\nerr\n");
            let (code, output) =
                tools.run(Path::new("/bin/sleep"), &["5"], Duration::from_millis(200));
            assert_eq!((code, output.as_slice()), (1, b"timeout".as_slice()));
        }
        #[cfg(windows)]
        {
            let (code, output) = tools.run(
                Path::new("cmd"),
                &["/C", "echo out& exit 3"],
                Duration::from_secs(5),
            );
            assert_eq!(code, 3);
            assert!(String::from_utf8_lossy(&output).contains("out"));
        }
    }
}
