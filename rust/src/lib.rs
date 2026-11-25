//! Appninjas ADB: everything that can be tested without a menu bar or tray.
//!
//! The binary in `main.rs` builds the tray icon and menu on top of this. The behaviour follows
//! `adb-tray.py` (Linux) and `macos/` (Swift), which this crate is meant to replace on every platform.

pub mod autostart;
pub mod device;
pub mod gettext;
pub mod hosts;
pub mod icons;
pub mod product;
pub mod tools;
