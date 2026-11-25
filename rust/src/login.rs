//! Start at login, offered in the menu on Windows. On macOS `brew services` starts the program at
//! login, and on Linux the package's /etc/xdg/autostart entry does.
//!
//! The values and their meaning are in `adb_tray::autostart`. Only HKEY_CURRENT_USER is written, so
//! it needs no administrator rights and applies to the current user only.

/// Whether the menu offers Start at login on this platform.
pub const SUPPORTED: bool = cfg!(windows);

#[cfg(windows)]
pub use windows::{enabled, refresh, set};

#[cfg(not(windows))]
pub fn enabled() -> bool {
    false
}

#[cfg(not(windows))]
pub fn set(_on: bool) -> std::io::Result<()> {
    Err(std::io::ErrorKind::Unsupported.into())
}

#[cfg(not(windows))]
pub fn refresh() {}

#[cfg(windows)]
mod windows {
    use std::io;
    use std::path::Path;

    use adb_tray::autostart::{
        APPROVED_KEY, RUN_KEY, VALUE_NAME, approved, command_line, program_path,
    };
    use windows_sys::Win32::Foundation::{
        ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND, ERROR_SUCCESS,
    };
    use windows_sys::Win32::System::Registry::{
        HKEY_CURRENT_USER, REG_ROUTINE_FLAGS, REG_SZ, RRF_RT_REG_BINARY, RRF_RT_REG_SZ,
        RegDeleteKeyValueW, RegGetValueW, RegSetKeyValueW,
    };

    fn wide(text: &str) -> Vec<u16> {
        text.encode_utf16().chain([0]).collect()
    }

    fn result(code: u32) -> io::Result<()> {
        if code == ERROR_SUCCESS {
            Ok(())
        } else {
            Err(io::Error::from_raw_os_error(code as i32))
        }
    }

    /// The product's value under `key` in HKEY_CURRENT_USER, if it is there and of the type in `flags`.
    fn read(key: &str, flags: REG_ROUTINE_FLAGS) -> Option<Vec<u8>> {
        let (key, name) = (wide(key), wide(VALUE_NAME));
        let mut size = 0u32;
        let code = unsafe {
            RegGetValueW(
                HKEY_CURRENT_USER,
                key.as_ptr(),
                name.as_ptr(),
                flags,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                &mut size,
            )
        };
        if code != ERROR_SUCCESS {
            return None;
        }
        let mut data = vec![0u8; size as usize];
        let code = unsafe {
            RegGetValueW(
                HKEY_CURRENT_USER,
                key.as_ptr(),
                name.as_ptr(),
                flags,
                std::ptr::null_mut(),
                data.as_mut_ptr().cast(),
                &mut size,
            )
        };
        if code != ERROR_SUCCESS {
            return None;
        }
        data.truncate(size as usize);
        Some(data)
    }

    /// The Run value's command line, if there is one.
    fn run_value() -> Option<String> {
        let data = read(RUN_KEY, RRF_RT_REG_SZ)?;
        let units: Vec<u16> = data
            .chunks_exact(2)
            .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
            .take_while(|&unit| unit != 0)
            .collect();
        Some(String::from_utf16_lossy(&units))
    }

    fn write_run_value(exe: &Path) -> io::Result<()> {
        let (key, name) = (wide(RUN_KEY), wide(VALUE_NAME));
        let data = wide(&command_line(exe));
        result(unsafe {
            RegSetKeyValueW(
                HKEY_CURRENT_USER,
                key.as_ptr(),
                name.as_ptr(),
                REG_SZ,
                data.as_ptr().cast(),
                (data.len() * 2) as u32,
            )
        })
    }

    /// Removes the product's value under `key`; a value or key that is not there is not an error.
    fn delete(key: &str) -> io::Result<()> {
        let (key, name) = (wide(key), wide(VALUE_NAME));
        let code = unsafe { RegDeleteKeyValueW(HKEY_CURRENT_USER, key.as_ptr(), name.as_ptr()) };
        if code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND {
            Ok(())
        } else {
            result(code)
        }
    }

    /// On when there is a Run value and it is not turned off in Task Manager or Settings.
    pub fn enabled() -> bool {
        run_value().is_some() && approved(read(APPROVED_KEY, RRF_RT_REG_BINARY).as_deref())
    }

    /// Turns Start at login on for this program, or off. Turning it on also clears an earlier
    /// "disabled" mark from Task Manager, which would otherwise keep it from starting.
    pub fn set(on: bool) -> io::Result<()> {
        if on {
            write_run_value(&std::env::current_exe()?)?;
        } else {
            delete(RUN_KEY)?;
        }
        delete(APPROVED_KEY)
    }

    /// When Start at login is on but the program it starts is no longer there (it was moved, or
    /// unpacked again somewhere else), points it at this copy. A copy that is still there is left
    /// alone, so running a second copy from Downloads does not take over.
    pub fn refresh() {
        let (Some(line), Ok(exe)) = (run_value(), std::env::current_exe()) else {
            return;
        };
        if !Path::new(program_path(&line)).exists() {
            let _ = write_run_value(&exe);
        }
    }
}
