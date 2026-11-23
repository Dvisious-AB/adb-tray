//! Compiles the release version, the translations and (on Windows) the program icon into the binary.

use std::path::Path;
use std::{env, fs};

#[path = "src/render.rs"]
mod render;

fn main() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    let out = env::var("OUT_DIR").unwrap();

    // The version: ADB_TRAY_VERSION wins (the Homebrew formula and CI pass the tag), else VERSION.
    println!("cargo:rerun-if-env-changed=ADB_TRAY_VERSION");
    println!("cargo:rerun-if-changed=../VERSION");
    let version = env::var("ADB_TRAY_VERSION").unwrap_or_else(|_| {
        fs::read_to_string(root.join("VERSION"))
            .expect("VERSION")
            .trim()
            .to_string()
    });
    println!("cargo:rustc-env=ADB_TRAY_VERSION={version}");

    // Every language in po/LINGUAS, compiled in.
    println!("cargo:rerun-if-changed=../po");
    let linguas = fs::read_to_string(root.join("po/LINGUAS")).expect("po/LINGUAS");
    let mut catalogs = String::from(
        "/// (language, .po text) for every translation, from po/LINGUAS.\npub const CATALOGS: &[(&str, &str)] = &[\n",
    );
    for language in linguas
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
    {
        let path = root
            .join("po")
            .join(format!("{language}.po"))
            .canonicalize()
            .expect("po file");
        catalogs.push_str(&format!(
            "    ({language:?}, include_str!({:?})),\n",
            path.display().to_string()
        ));
    }
    catalogs.push_str("];\n");
    fs::write(Path::new(&out).join("catalogs.rs"), catalogs).unwrap();

    println!("cargo:rerun-if-changed=../branding");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        windows_resources(&root, &out, &version);
    }
}

/// The .ico from branding/appninjas-adb.svg, and the version shown in the file's properties.
fn windows_resources(root: &Path, out: &str, version: &str) {
    let svg = fs::read_to_string(root.join("branding/appninjas-adb.svg")).unwrap();
    let mut icon_dir = ico::IconDir::new(ico::ResourceType::Icon);
    for size in [16, 24, 32, 48, 64, 128, 256] {
        let rgba = render::render_svg(&svg, size, "#000000").expect("render the app icon");
        let image = ico::IconImage::from_rgba_data(size, size, rgba);
        icon_dir.add_entry(ico::IconDirEntry::encode(&image).unwrap());
    }
    let ico_path = Path::new(out).join("appninjas-adb.ico");
    icon_dir
        .write(fs::File::create(&ico_path).unwrap())
        .unwrap();

    #[cfg(windows)]
    let mut resource = winresource::WindowsResource::new();
    #[cfg(not(windows))]
    let mut resource = {
        // Cross-compiling from macOS or Linux: use MinGW's windres.
        let mut r = winresource::WindowsResource::new();
        r.set_toolkit_path("/opt/homebrew/bin")
            .set_windres_path("x86_64-w64-mingw32-windres")
            .set_ar_path("x86_64-w64-mingw32-ar");
        r
    };
    let numeric: Vec<u64> = version
        .split(['.', '-'])
        .filter_map(|p| p.parse().ok())
        .chain([0, 0, 0, 0])
        .take(4)
        .collect();
    let packed = (numeric[0] << 48) | (numeric[1] << 32) | (numeric[2] << 16) | numeric[3];
    resource
        .set_icon(ico_path.to_str().unwrap())
        .set("ProductName", "Appninjas ADB")
        .set("FileDescription", "Appninjas ADB")
        .set("CompanyName", "Dvisious AB")
        .set(
            "LegalCopyright",
            "© 2026 Anders Elmén and Dvisious AB. MIT License; the Appninjas logo is not.",
        )
        .set("OriginalFilename", "adb-tray.exe")
        .set("ProductVersion", version)
        .set("FileVersion", version)
        .set_version_info(winresource::VersionInfo::PRODUCTVERSION, packed)
        .set_version_info(winresource::VersionInfo::FILEVERSION, packed);
    resource.compile().expect("compile the Windows resources");
}
