//! The brand's icons, compiled into the program: the app icon and the Phosphor icons in the weight
//! fill, unchanged from `branding/` (see branding/README.md).

#[path = "render.rs"]
mod render;
pub use render::render_svg;

pub const APP_ICON: &str = include_str!("../../branding/appninjas-adb.svg");

macro_rules! phosphor {
    ($($name:literal),* $(,)?) => {
        /// (name, SVG) for every Phosphor icon the menus use.
        pub const PHOSPHOR: &[(&str, &str)] = &[
            $(($name, include_str!(concat!("../../branding/phosphor/", $name, "-fill.svg")))),*
        ];
    };
}

phosphor!(
    "device-mobile",
    "screencast",
    "device-rotate",
    "camera",
    "terminal-window",
    "wifi-high",
    "plugs",
    "arrows-clockwise",
    "power",
    "copy",
    "info",
    "question",
);

/// The tray icon while nothing is mirrored, and while something is.
pub const TRAY: &str = "device-mobile";
pub const TRAY_MIRRORING: &str = "screencast";

pub fn phosphor(name: &str) -> Option<&'static str> {
    PHOSPHOR
        .iter()
        .find(|(n, _)| *n == name)
        .map(|(_, svg)| *svg)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_icon_renders() {
        for (name, svg) in PHOSPHOR {
            let pixels =
                render_svg(svg, 32, "#000000").unwrap_or_else(|| panic!("{name} does not render"));
            assert_eq!(pixels.len(), 32 * 32 * 4);
            assert!(pixels.chunks(4).any(|p| p[3] == 255), "{name} is empty");
        }
    }

    #[test]
    fn app_icon_has_the_tile_the_hood_and_the_band() {
        let pixels = render_svg(APP_ICON, 256, "#000000").unwrap();
        let at = |x: usize, y: usize| &pixels[(y * 256 + x) * 4..(y * 256 + x) * 4 + 4];
        assert_eq!(at(2, 2)[3], 0, "outside the tile is transparent");
        assert_eq!(at(40, 40), [0xf6, 0xf7, 0xf7, 255], "the tile");
        // The same points as the Swift test: symbol scale 560/62.83/4, origin (58, 76.75).
        let scale = 560.0 / 62.83 / 4.0;
        let point =
            |x: f64, y: f64| at((58.0 + x * scale) as usize, (76.75 + y * scale) as usize).to_vec();
        assert_eq!(point(23.0, 4.0), [0x12, 0x17, 0x18, 255], "the hood");
        assert_eq!(point(23.0, 12.5), [0x0b, 0x66, 0x70, 255], "the band");
        assert_eq!(point(23.0, 28.0), [0xf6, 0xf7, 0xf7, 255], "the eye slit");
    }
}
