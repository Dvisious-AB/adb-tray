//! Renders the brand SVGs to pixels. Also used by build.rs for the Windows .ico, so it depends on
//! nothing but resvg.

/// Renders `svg` into a square of `size` pixels, centred, with `currentColor` drawn as `color`
/// (`#rrggbb`). Returns straight (not premultiplied) RGBA.
pub fn render_svg(svg: &str, size: u32, color: &str) -> Option<Vec<u8>> {
    use resvg::{tiny_skia, usvg};
    let svg = svg.replace("currentColor", color);
    let tree = usvg::Tree::from_str(&svg, &usvg::Options::default()).ok()?;
    let mut pixmap = tiny_skia::Pixmap::new(size, size)?;
    let view = tree.size();
    let scale = (size as f32 / view.width()).min(size as f32 / view.height());
    let dx = (size as f32 - view.width() * scale) / 2.0;
    let dy = (size as f32 - view.height() * scale) / 2.0;
    resvg::render(
        &tree,
        tiny_skia::Transform::from_row(scale, 0.0, 0.0, scale, dx, dy),
        &mut pixmap.as_mut(),
    );
    Some(pixmap.take_demultiplied())
}
