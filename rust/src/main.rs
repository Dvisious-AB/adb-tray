//! Appninjas ADB: the tray icon and its menu. Same menu and actions as adb-tray.py (Linux) and the
//! Swift app (macOS); the logic that can be tested lives in the library (lib.rs).

// No console window on Windows: this is a tray program.
#![cfg_attr(windows, windows_subsystem = "windows")]

mod actions;
mod platform;

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Child;
use std::sync::mpsc;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use adb_tray::device::Device;
use adb_tray::gettext::{Catalog, format};
use adb_tray::hosts::HostStore;
use adb_tray::tools::Tools;
use adb_tray::{icons, product};
use tao::event::{Event, StartCause};
use tao::event_loop::{ControlFlow, EventLoopBuilder, EventLoopProxy};
use tray_icon::menu::{
    IconMenuItem, IsMenuItem, Menu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem, Submenu,
};
use tray_icon::{Icon, TrayIcon, TrayIconBuilder};

/// The translations for the user's language, chosen once at start.
static CATALOG: OnceLock<Catalog> = OnceLock::new();

pub fn tr(msgid: &str) -> &str {
    CATALOG.get().map(|c| c.gettext(msgid)).unwrap_or(msgid)
}

pub fn trn<'a>(msgid: &'a str, plural: &'a str, n: u64) -> &'a str {
    match CATALOG.get() {
        Some(catalog) => catalog.ngettext(msgid, plural, n),
        None if n == 1 => msgid,
        None => plural,
    }
}

/// Events from worker threads and the menu to the main thread, which owns the tray icon.
pub enum UserEvent {
    Menu(MenuEvent),
    Devices {
        devices: Vec<Device>,
        adb: Option<PathBuf>,
        scrcpy: Option<PathBuf>,
    },
    MirrorsChanged,
}

/// What a menu item does. Kept in a table keyed by the item's id, rebuilt with the menu.
#[derive(Clone)]
pub enum Action {
    Mirror(Device),
    StopMirror(String),
    Rotate(String, Option<u8>),
    Screenshot(Device),
    Shell(String),
    SwitchToWifi(String),
    Disconnect(String),
    Connect(String),
    NewAddress,
    Pair,
    Refresh,
    RestartServer,
    CopyInstall(&'static str),
    Help,
    About,
    Quit,
}

/// What the worker threads share with the main thread.
pub struct Shared {
    pub tools: Tools,
    pub hosts: HostStore,
    pub support_dir: PathBuf,
    pub mirrors: Mutex<HashMap<String, Arc<Mutex<Child>>>>,
    proxy: Mutex<EventLoopProxy<UserEvent>>,
    refresh: Mutex<mpsc::Sender<()>>,
}

impl Shared {
    /// Polls adb now instead of at the next tick.
    pub fn poll_now(&self) {
        let _ = self.refresh.lock().unwrap().send(());
    }

    pub fn send(&self, event: UserEvent) {
        let _ = self.proxy.lock().unwrap().send_event(event);
    }
}

fn main() {
    if std::env::args().any(|a| a == "--version") {
        platform::attach_console();
        println!("{} {}", product::COMMAND, product::VERSION);
        return;
    }

    let mut languages: Vec<String> = std::env::var("LANGUAGE")
        .ok()
        .into_iter()
        .filter(|l| !l.is_empty())
        .collect();
    languages.extend(sys_locale::get_locales());
    let _ = CATALOG.set(Catalog::for_languages(&languages).0);

    let support_dir = platform::support_dir();
    let _ = std::fs::create_dir_all(&support_dir);
    // Kept open for the process lifetime; the lock is the single-instance guard, as on Linux and macOS.
    let lock = std::fs::File::create(support_dir.join("tray.lock")).ok();
    if lock.as_ref().is_some_and(|f| f.try_lock().is_err()) {
        platform::attach_console();
        eprintln!(
            "{}",
            format(tr("{name} is already running"), &[("name", &product::NAME)])
        );
        return;
    }

    let mut event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();
    platform::prepare_event_loop(&mut event_loop);
    let proxy = event_loop.create_proxy();
    let menu_proxy = proxy.clone();
    MenuEvent::set_event_handler(Some(move |event| {
        let _ = menu_proxy.send_event(UserEvent::Menu(event));
    }));

    let (refresh_sender, refresh_receiver) = mpsc::channel::<()>();
    let shared = Arc::new(Shared {
        tools: Tools::new(),
        hosts: HostStore::new(support_dir.join("hosts.json")),
        support_dir,
        mirrors: Mutex::new(HashMap::new()),
        proxy: Mutex::new(proxy),
        refresh: Mutex::new(refresh_sender),
    });

    // Polls adb every few seconds, or at once when asked to.
    {
        let shared = shared.clone();
        std::thread::spawn(move || {
            if let Some(adb) = shared.tools.adb() {
                shared
                    .tools
                    .run(&adb, &["start-server"], Duration::from_secs(30));
            }
            loop {
                let adb = shared.tools.adb();
                let devices = adb
                    .as_ref()
                    .map(|adb| {
                        let (_, output) =
                            shared
                                .tools
                                .run(adb, &["devices", "-l"], Duration::from_secs(10));
                        Device::parse(&String::from_utf8_lossy(&output))
                    })
                    .unwrap_or_default();
                shared.send(UserEvent::Devices {
                    devices,
                    adb,
                    scrcpy: shared.tools.scrcpy(),
                });
                // Wait for the next tick, or for a request to poll now.
                let _ = refresh_receiver.recv_timeout(Duration::from_secs(product::POLL_SECONDS));
                while refresh_receiver.try_recv().is_ok() {}
            }
        });
    }

    let mut tray: Option<TrayIcon> = None;
    let mut state = MenuState::default();

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;
        match event {
            Event::NewEvents(StartCause::Init) => {
                let menu = state.build(&[]);
                let builder = TrayIconBuilder::new()
                    .with_menu(Box::new(menu))
                    .with_tooltip(product::NAME);
                // macOS draws a template image in the menu bar's own colour.
                #[cfg(target_os = "macos")]
                let builder = builder.with_icon_templated(tray_icon_image(false));
                #[cfg(not(target_os = "macos"))]
                let builder = builder.with_icon(tray_icon_image(false));
                tray = builder.build().ok();
                if let Some(tray) = &tray {
                    platform::remember_tray(tray);
                }
                state.mirroring_shown = Some(false);
            }
            Event::UserEvent(UserEvent::Devices {
                devices,
                adb,
                scrcpy,
            }) => {
                state.devices = devices;
                state.adb = adb;
                state.scrcpy = scrcpy;
                state.refresh_tray(tray.as_ref(), &shared);
            }
            Event::UserEvent(UserEvent::MirrorsChanged) => {
                state.refresh_tray(tray.as_ref(), &shared)
            }
            Event::UserEvent(UserEvent::Menu(event)) => {
                let Some(action) = state.actions.get(&event.id).cloned() else {
                    return;
                };
                if matches!(action, Action::Quit) {
                    tray.take();
                    *control_flow = ControlFlow::Exit;
                    return;
                }
                actions::run(action, &shared, &state.hosts);
            }
            _ => {}
        }
    });
}

fn tray_icon_image(mirroring: bool) -> Icon {
    let name = if mirroring {
        icons::TRAY_MIRRORING
    } else {
        icons::TRAY
    };
    let size = 64;
    let rgba = icons::render_svg(
        icons::phosphor(name).unwrap(),
        size,
        platform::tray_icon_colour(),
    )
    .unwrap();
    Icon::from_rgba(rgba, size, size).unwrap()
}

fn menu_icon(name: &str) -> Option<tray_icon::menu::Icon> {
    let size = 32;
    let rgba = icons::render_svg(icons::phosphor(name)?, size, platform::menu_icon_colour())?;
    tray_icon::menu::Icon::from_rgba(rgba, size, size).ok()
}

#[derive(Default)]
struct MenuState {
    devices: Vec<Device>,
    adb: Option<PathBuf>,
    scrcpy: Option<PathBuf>,
    hosts: Vec<String>,
    actions: HashMap<MenuId, Action>,
    signature: String,
    mirroring_shown: Option<bool>,
    next_id: u64,
}

impl MenuState {
    fn refresh_tray(&mut self, tray: Option<&TrayIcon>, shared: &Shared) {
        let Some(tray) = tray else { return };
        let mirrors: Vec<String> = {
            let mut mirrors = shared.mirrors.lock().unwrap();
            mirrors.retain(|_, child| matches!(child.lock().unwrap().try_wait(), Ok(None)));
            let mut keys: Vec<String> = mirrors.keys().cloned().collect();
            keys.sort();
            keys
        };

        let ready = self.devices.iter().filter(|d| d.is_ready()).count() as u64;
        let mut tooltip = format!(
            "{}: {}",
            product::NAME,
            format(
                trn("{n} device connected", "{n} devices connected", ready),
                &[("n", &ready)]
            )
        );
        if !mirrors.is_empty() {
            let n = mirrors.len() as u64;
            tooltip.push_str(&format!(
                ", {}",
                format(trn("{n} mirroring", "{n} mirroring", n), &[("n", &n)])
            ));
        }
        let _ = tray.set_tooltip(Some(&tooltip));

        let mirroring = !mirrors.is_empty();
        if self.mirroring_shown != Some(mirroring) {
            self.mirroring_shown = Some(mirroring);
            let icon = Some(tray_icon_image(mirroring));
            #[cfg(target_os = "macos")]
            let _ = tray.set_icon_templated(icon);
            #[cfg(not(target_os = "macos"))]
            let _ = tray.set_icon(icon);
        }

        self.hosts = shared.hosts.load();
        let signature = format!(
            "{:?}|{mirrors:?}|{:?}|{:?}|{:?}",
            self.devices
                .iter()
                .map(|d| (&d.serial, &d.state, &d.model))
                .collect::<Vec<_>>(),
            self.hosts,
            self.adb,
            self.scrcpy
        );
        if signature != self.signature {
            self.signature = signature;
            tray.set_menu(Some(Box::new(self.build(&mirrors))));
        }
    }

    fn item(
        &mut self,
        text: &str,
        icon: Option<&str>,
        action: Option<Action>,
        enabled: bool,
    ) -> IconMenuItem {
        self.next_id += 1;
        let id = MenuId::new(self.next_id.to_string());
        let enabled = enabled && action.is_some();
        if let Some(action) = action {
            self.actions.insert(id.clone(), action);
        }
        let item = IconMenuItem::with_id(id, escape(text), enabled, None, None);
        if let Some(icon) = icon.and_then(menu_icon) {
            #[cfg(target_os = "macos")]
            item.set_icon_templated(Some(icon));
            #[cfg(not(target_os = "macos"))]
            item.set_icon(Some(icon));
        }
        item
    }

    fn build(&mut self, mirrors: &[String]) -> Menu {
        self.actions.clear();
        let menu = Menu::new();
        let separator = PredefinedMenuItem::separator;

        let missing = if self.adb.is_none() {
            Some((tr("adb is not installed"), product::adb_install_command()))
        } else if self.scrcpy.is_none() {
            Some((
                tr("scrcpy is not installed"),
                product::scrcpy_install_command(),
            ))
        } else {
            None
        };
        if let Some((text, command)) = missing {
            let _ = menu.append(&self.item(text, None, None, false));
            let _ = menu.append(&self.item(
                tr("Copy the install command"),
                Some("copy"),
                Some(Action::CopyInstall(command)),
                true,
            ));
            let _ = menu.append(&separator());
        }

        if self.devices.is_empty() {
            let _ = menu.append(&self.item(tr("No devices connected"), None, None, false));
        }
        for device in self.devices.clone() {
            let submenu = self.device_menu(&device, mirrors.contains(&device.serial));
            let _ = menu.append(&submenu);
        }

        let _ = menu.append(&separator());
        let wifi = Submenu::new(escape(tr("Connect via Wi-Fi")), self.adb.is_some());
        if let Some(icon) = menu_icon("wifi-high") {
            set_submenu_icon(&wifi, icon);
        }
        let connected: Vec<String> = self.devices.iter().map(|d| d.serial.clone()).collect();
        for host in self.hosts.clone() {
            let enabled = !connected.contains(&host);
            let _ =
                wifi.append(&self.item(&host, None, Some(Action::Connect(host.clone())), enabled));
        }
        if !self.hosts.is_empty() {
            let _ = wifi.append(&separator());
        }
        let _ = wifi.append(&self.item(tr("New address..."), None, Some(Action::NewAddress), true));
        let _ = wifi.append(&self.item(
            tr("Pair (wireless debugging)..."),
            None,
            Some(Action::Pair),
            true,
        ));
        let _ = menu.append(&wifi);

        let _ = menu.append(&self.item(
            tr("Refresh"),
            Some("arrows-clockwise"),
            Some(Action::Refresh),
            true,
        ));
        let has_adb = self.adb.is_some();
        let _ = menu.append(&self.item(
            tr("Restart adb server"),
            Some("power"),
            Some(Action::RestartServer),
            has_adb,
        ));
        let _ = menu.append(&separator());
        let _ = menu.append(&self.item(tr("Help"), Some("question"), Some(Action::Help), true));
        let about = format(tr("About {name}"), &[("name", &product::NAME)]);
        let _ = menu.append(&self.item(&about, Some("info"), Some(Action::About), true));
        let _ = menu.append(&self.item(tr("Quit"), None, Some(Action::Quit), true));
        menu
    }

    fn device_menu(&mut self, device: &Device, mirroring: bool) -> Submenu {
        let serial = device.serial.clone();
        let mut label = format!(
            "{}  ({})",
            device.display_name(),
            if device.wifi { "Wi-Fi" } else { "USB" }
        );
        if mirroring {
            label = format!("▶ {label}");
        }
        if !device.is_ready() {
            let state = match device.state.as_str() {
                "unauthorized" => tr("authorize on device"),
                "offline" => tr("offline"),
                other => other,
            };
            label = format!("{label} – {state}");
        }
        let sub = Submenu::new(escape(&label), true);
        if let Some(icon) = menu_icon(if mirroring {
            icons::TRAY_MIRRORING
        } else {
            icons::TRAY
        }) {
            set_submenu_icon(&sub, icon);
        }

        let mut items: Vec<Box<dyn IsMenuItem>> = Vec::new();
        if device.is_ready() {
            if mirroring {
                items.push(Box::new(self.item(
                    tr("Stop mirroring"),
                    Some("screencast"),
                    Some(Action::StopMirror(serial.clone())),
                    true,
                )));
            } else {
                let has_scrcpy = self.scrcpy.is_some();
                items.push(Box::new(self.item(
                    tr("Mirror screen"),
                    Some("screencast"),
                    Some(Action::Mirror(device.clone())),
                    has_scrcpy,
                )));
            }
            items.push(Box::new(PredefinedMenuItem::separator()));
            for (text, rotation) in [
                (tr("Lock portrait"), Some(0)),
                (tr("Lock landscape"), Some(1)),
                (tr("Auto-rotate"), None),
            ] {
                items.push(Box::new(self.item(
                    text,
                    Some("device-rotate"),
                    Some(Action::Rotate(serial.clone(), rotation)),
                    true,
                )));
            }
            items.push(Box::new(PredefinedMenuItem::separator()));
            items.push(Box::new(self.item(
                tr("Take screenshot"),
                Some("camera"),
                Some(Action::Screenshot(device.clone())),
                true,
            )));
            items.push(Box::new(self.item(
                tr("Open adb shell"),
                Some("terminal-window"),
                Some(Action::Shell(serial.clone())),
                true,
            )));
            if device.wifi {
                items.push(Box::new(self.item(
                    tr("Disconnect"),
                    Some("plugs"),
                    Some(Action::Disconnect(serial.clone())),
                    true,
                )));
            } else {
                items.push(Box::new(self.item(
                    tr("Switch to Wi-Fi"),
                    Some("wifi-high"),
                    Some(Action::SwitchToWifi(serial.clone())),
                    true,
                )));
            }
        } else {
            if device.state == "unauthorized" {
                items.push(Box::new(self.item(
                    tr("Tap Allow in the dialog on the device"),
                    None,
                    None,
                    false,
                )));
            }
            if device.wifi {
                items.push(Box::new(self.item(
                    tr("Disconnect"),
                    Some("plugs"),
                    Some(Action::Disconnect(serial.clone())),
                    true,
                )));
            }
        }
        for item in &items {
            let _ = sub.append(item.as_ref());
        }
        let _ = sub.append(&PredefinedMenuItem::separator());
        let serial_label = format(tr("Serial number: {serial}"), &[("serial", &serial)]);
        let _ = sub.append(&MenuItem::new(escape(&serial_label), false, None));
        sub
    }
}

fn set_submenu_icon(submenu: &Submenu, icon: tray_icon::menu::Icon) {
    #[cfg(target_os = "macos")]
    submenu.set_icon_templated(Some(icon));
    #[cfg(not(target_os = "macos"))]
    submenu.set_icon(Some(icon));
}

/// muda treats `&` as a mnemonic marker; device names and addresses must show it as it is.
fn escape(text: &str) -> String {
    text.replace('&', "&&")
}
