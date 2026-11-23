//! What the menu items do. Anything that waits on adb runs on a worker thread; dialogs run on the
//! main thread, like the modal dialogs of the other versions.

use std::fs::File;
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use adb_tray::device::{Device, connect_succeeded, normalized_host, safe_name, wifi_address};
use adb_tray::gettext::format;
use adb_tray::product;

use crate::{Action, Shared, UserEvent, platform, tr};

pub fn run(action: Action, shared: &Arc<Shared>, hosts: &[String]) {
    match action {
        Action::Refresh => shared.poll_now(),
        Action::Help => {
            let _ = opener::open_browser(help_url());
        }
        Action::About => about(),
        Action::CopyInstall(command) => {
            if arboard::Clipboard::new()
                .and_then(|mut c| c.set_text(command))
                .is_ok()
            {
                notify(&format(
                    tr("Copied {command}. Paste it into Terminal to install."),
                    &[("command", &command)],
                ));
            }
        }
        Action::Mirror(device) => start_mirror(shared, &device),
        Action::StopMirror(serial) => {
            if let Some(child) = shared.mirrors.lock().unwrap().get(&serial) {
                let _ = child.lock().unwrap().kill();
            }
        }
        Action::Shell(serial) => {
            if let Some(adb) = shared.tools.adb() {
                if let Err(error) = platform::open_shell(&adb, &serial) {
                    let _ = error;
                    notify(tr(
                        "Could not open adb shell because no terminal program was found. Install one, for example gnome-terminal.",
                    ));
                }
            }
        }
        Action::NewAddress => {
            let default = hosts.first().map(String::as_str).unwrap_or("");
            if let Some(address) = tinyfiledialogs::input_box(
                tr("Connect via Wi-Fi"),
                tr("Address (IP:port)"),
                default,
            ) {
                let address = address.trim().to_string();
                if !address.is_empty() {
                    let host = normalized_host(&address, product::TCP_PORT);
                    background(shared, move |shared| connect(shared, &host));
                }
            }
        }
        Action::Pair => pair(shared),
        other => background(shared, move |shared| work(shared, other)),
    }
}

/// Runs `job` on a worker thread, then polls so the menu shows the result.
fn background(shared: &Arc<Shared>, job: impl FnOnce(&Shared) + Send + 'static) {
    let shared = shared.clone();
    std::thread::spawn(move || {
        job(&shared);
        shared.poll_now();
    });
}

fn work(shared: &Shared, action: Action) {
    let adb = |args: &[&str], serial: Option<&str>| -> (i32, String) {
        let Some(adb) = shared.tools.adb() else {
            return (1, tr("adb is not installed").to_string());
        };
        let mut full: Vec<&str> = serial.map(|s| vec!["-s", s]).unwrap_or_default();
        full.extend_from_slice(args);
        let (code, output) = shared.tools.run(&adb, &full, Duration::from_secs(15));
        (code, String::from_utf8_lossy(&output).trim().to_string())
    };
    match action {
        Action::Rotate(serial, rotation) => {
            let serial = Some(serial.as_str());
            match rotation {
                None => {
                    adb(
                        &[
                            "shell",
                            "settings",
                            "put",
                            "system",
                            "accelerometer_rotation",
                            "1",
                        ],
                        serial,
                    );
                }
                Some(rotation) => {
                    adb(
                        &[
                            "shell",
                            "settings",
                            "put",
                            "system",
                            "accelerometer_rotation",
                            "0",
                        ],
                        serial,
                    );
                    adb(
                        &[
                            "shell",
                            "settings",
                            "put",
                            "system",
                            "user_rotation",
                            &rotation.to_string(),
                        ],
                        serial,
                    );
                }
            }
        }
        Action::Screenshot(device) => screenshot(shared, &device),
        Action::SwitchToWifi(serial) => {
            let (_, output) = adb(
                &["shell", "ip", "-f", "inet", "addr", "show", "wlan0"],
                Some(&serial),
            );
            let Some(address) = wifi_address(&output) else {
                notify(tr(
                    "Could not switch to Wi-Fi because the device has no Wi-Fi address. Connect it to a Wi-Fi network and try again.",
                ));
                return;
            };
            adb(&["tcpip", &product::TCP_PORT.to_string()], Some(&serial));
            std::thread::sleep(Duration::from_secs(2));
            connect(shared, &format!("{address}:{}", product::TCP_PORT));
        }
        Action::Disconnect(serial) => {
            adb(&["disconnect", &serial], None);
            notify(&format(
                tr("Disconnected from {serial}"),
                &[("serial", &serial)],
            ));
        }
        Action::Connect(host) => connect(shared, &host),
        Action::RestartServer => {
            adb(&["kill-server"], None);
            adb(&["start-server"], None);
            notify(tr("The adb server has been restarted"));
        }
        _ => {}
    }
}

fn connect(shared: &Shared, host: &str) {
    let Some(adb) = shared.tools.adb() else {
        return;
    };
    let (_, output) = shared
        .tools
        .run(&adb, &["connect", host], Duration::from_secs(10));
    let output = String::from_utf8_lossy(&output).trim().to_string();
    if connect_succeeded(&output) {
        let _ = shared.hosts.save(host);
        notify(&format(tr("Connected to {host}"), &[("host", &host)]));
    } else {
        let message = tr(
            "Could not connect to {host}. Check that the device is on the same network and that wireless debugging is on.",
        );
        notify(&format!(
            "{}\n{output}",
            format(message, &[("host", &host)])
        ));
    }
}

/// Three questions in a row: tinyfiledialogs asks for one value at a time.
fn pair(shared: &Arc<Shared>) {
    let title = tr("Pair - wireless debugging");
    let Some(address) = tinyfiledialogs::input_box(title, tr("Pairing address (IP:port)"), "")
    else {
        return;
    };
    let Some(code) = tinyfiledialogs::input_box(title, tr("Pairing code"), "") else {
        return;
    };
    let connect_to = tinyfiledialogs::input_box(title, tr("Connection address (optional)"), "")
        .unwrap_or_default();
    let (address, code, connect_to) = (
        address.trim().to_string(),
        code.trim().to_string(),
        connect_to.trim().to_string(),
    );
    if address.is_empty() || code.is_empty() {
        return;
    }
    background(shared, move |shared| {
        let Some(adb) = shared.tools.adb() else {
            return;
        };
        let (_, output) =
            shared
                .tools
                .run(&adb, &["pair", &address, &code], Duration::from_secs(20));
        let output = String::from_utf8_lossy(&output).trim().to_string();
        if !output.contains("Successfully paired") {
            let message = tr(
                "Pairing failed. Check the pairing address and code under Wireless debugging on the device, and try again.",
            );
            notify(&format!("{message}\n{output}"));
            return;
        }
        notify(tr("Pairing succeeded"));
        if !connect_to.is_empty() {
            connect(shared, &normalized_host(&connect_to, product::TCP_PORT));
        }
    });
}

fn screenshot(shared: &Shared, device: &Device) {
    let Some(adb) = shared.tools.adb() else {
        return;
    };
    let name = if device.model.is_empty() {
        "android"
    } else {
        &device.model
    };
    let target = platform::pictures_dir().join(format!(
        "{name}-{}.png",
        chrono::Local::now().format("%Y%m%d-%H%M%S")
    ));
    let mut command = shared.tools.command(&adb);
    command
        .args(["-s", &device.serial, "exec-out", "screencap", "-p"])
        .stdin(Stdio::null())
        .stderr(Stdio::null());
    let saved = command
        .output()
        .ok()
        .filter(|o| o.status.success() && !o.stdout.is_empty())
        .is_some_and(|o| std::fs::write(&target, o.stdout).is_ok());
    if saved {
        notify(&format(
            tr("Screenshot saved: {path}"),
            &[("path", &target.display())],
        ));
    } else {
        notify(tr(
            "Could not take a screenshot. Check that the device is connected and unlocked, and try again.",
        ));
    }
}

fn start_mirror(shared: &Arc<Shared>, device: &Device) {
    let Some(scrcpy) = shared.tools.scrcpy() else {
        return;
    };
    let log = shared
        .support_dir
        .join(format!("scrcpy-{}.log", safe_name(&device.serial)));
    let Ok(log_file) = File::create(&log) else {
        return;
    };
    let Ok(log_err) = log_file.try_clone() else {
        return;
    };
    let mut command = shared.tools.command(&scrcpy);
    command
        .args([
            "-s",
            &device.serial,
            "--window-title",
            device.display_name(),
        ])
        .args(product::SCRCPY_OPTIONS)
        .stdin(Stdio::null())
        .stdout(log_file)
        .stderr(log_err);
    if device.wifi {
        command.args(["-b", "6M"]);
    }
    let child = match command.spawn() {
        Ok(child) => Arc::new(Mutex::new(child)),
        Err(error) => {
            notify(&error.to_string());
            return;
        }
    };
    shared
        .mirrors
        .lock()
        .unwrap()
        .insert(device.serial.clone(), child.clone());
    shared.send(UserEvent::MirrorsChanged);

    // Watches the mirror: a quick failure is reported, and the menu follows when it ends.
    let shared = shared.clone();
    let started = Instant::now();
    std::thread::spawn(move || {
        let status = loop {
            if let Ok(Some(status)) = child.lock().unwrap().try_wait() {
                break status;
            }
            std::thread::sleep(Duration::from_millis(500));
        };
        if !status.success() && started.elapsed() < Duration::from_secs(10) {
            let code = status.code().unwrap_or(-1);
            notify(&format(
                tr(
                    "Mirroring stopped because scrcpy exited with error {code}. The details are in {log}.",
                ),
                &[("code", &code), ("log", &log.display())],
            ));
        }
        shared.send(UserEvent::MirrorsChanged);
    });
}

fn about() {
    let text = [
        format!("{} {}", product::NAME, product::VERSION),
        String::new(),
        tr("System tray icon for adb devices and scrcpy screen mirroring").to_string(),
        String::new(),
        format!("{}: {}", tr("Help and common questions"), help_url()),
        format!("{}: {}", tr("Source code on GitHub"), product::REPOSITORY),
        String::new(),
        tr("The program is free software under the MIT License. The Appninjas name and logo are trademarks of Dvisious AB and are not covered by the MIT License.").to_string(),
        tr("Icons: Phosphor Icons, MIT License.").to_string(),
    ]
    .join("\n");
    let title = format(tr("About {name}"), &[("name", &product::NAME)]);
    tinyfiledialogs::message_box_ok(&title, &text, tinyfiledialogs::MessageBoxIcon::Info);
}

fn help_url() -> String {
    crate::HELP_URL.get().cloned().unwrap_or_else(|| product::help_url("en"))
}

pub fn notify(message: &str) {
    let message = message.to_string();
    // Notification back ends may block briefly; never on the main thread.
    std::thread::spawn(move || {
        if !platform::tray_notification(product::NAME, &message) {
            let _ = notify_rust::Notification::new()
                .summary(product::NAME)
                .body(&message)
                .show();
        }
    });
}
