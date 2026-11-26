// SPDX-License-Identifier: GPL-3.0-or-later
//! `capabilities` subcommand: the Apple capability table, one `key=value` line.
//!
//! Keys are stable (scripts parse them) and identical in both feature builds:
//! with `apple` the values come from [`dt_apple::capabilities()`], without it
//! the same keys print the empty backend.

/// Output keys in print order. Both feature builds emit exactly these.
pub const KEYS: &[&str] = &[
    "backend",
    "metal.device",
    "imageio.jpeg",
    "imageio.png",
    "imageio.tiff",
    "imageio.heic",
    "imageio.avif",
    "imageio.webp",
    "ciraw.available",
    "vision.face_rectangles",
    "vision.face_landmarks",
    "vision.rectangles",
    "vision.horizon",
    "vision.person_segmentation",
    "colorspace.srgb",
    "colorspace.display_p3",
];

/// Value when the `apple` feature is off (or no Metal device exists).
const NONE: &str = "none";

#[cfg(feature = "apple")]
fn bool_of(value: bool) -> &'static str {
    if value { "true" } else { "false" }
}

#[cfg(feature = "apple")]
fn collect_live() -> Vec<(String, String)> {
    use dt_apple::{Backend, ImageFormat, capabilities};

    let caps = capabilities();
    let backend = match caps.backend {
        Backend::MacOs => "macos",
        Backend::Empty => "empty",
    };
    let metal = caps.metal_device_name.as_deref().unwrap_or(NONE);
    let writable = |format| caps.writable_image_formats.contains(&format);
    let vision = &caps.vision_requests;
    let spaces = &caps.standard_spaces;
    [
        ("backend", backend.to_owned()),
        ("metal.device", metal.to_owned()),
        (
            "imageio.jpeg",
            bool_of(writable(ImageFormat::Jpeg)).to_owned(),
        ),
        (
            "imageio.png",
            bool_of(writable(ImageFormat::Png)).to_owned(),
        ),
        (
            "imageio.tiff",
            bool_of(writable(ImageFormat::Tiff)).to_owned(),
        ),
        (
            "imageio.heic",
            bool_of(writable(ImageFormat::Heic)).to_owned(),
        ),
        (
            "imageio.avif",
            bool_of(writable(ImageFormat::Avif)).to_owned(),
        ),
        (
            "imageio.webp",
            bool_of(writable(ImageFormat::WebP)).to_owned(),
        ),
        ("ciraw.available", bool_of(caps.ci_raw_filter).to_owned()),
        (
            "vision.face_rectangles",
            bool_of(vision.face_rectangles).to_owned(),
        ),
        (
            "vision.face_landmarks",
            bool_of(vision.face_landmarks).to_owned(),
        ),
        ("vision.rectangles", bool_of(vision.rectangles).to_owned()),
        ("vision.horizon", bool_of(vision.horizon).to_owned()),
        (
            "vision.person_segmentation",
            bool_of(vision.person_segmentation).to_owned(),
        ),
        ("colorspace.srgb", bool_of(spaces.srgb).to_owned()),
        (
            "colorspace.display_p3",
            bool_of(spaces.display_p3).to_owned(),
        ),
    ]
    .into_iter()
    .map(|(key, value)| (key.to_owned(), value))
    .collect()
}

#[cfg(not(feature = "apple"))]
fn collect_live() -> Vec<(String, String)> {
    KEYS.iter()
        .map(|key| {
            let value = if *key == "backend" {
                "empty"
            } else if *key == "metal.device" {
                NONE
            } else {
                "false"
            };
            ((*key).to_owned(), value.to_owned())
        })
        .collect()
}

/// The table as `(key, value)` lines in [`KEYS`] order.
#[must_use]
pub fn lines() -> Vec<(String, String)> {
    collect_live()
}

/// The table rendered as `key=value` lines (no trailing newline).
#[must_use]
pub fn render() -> String {
    lines()
        .iter()
        .map(|(key, value)| format!("{key}={value}"))
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_stable_and_complete() {
        let got = lines();
        assert_eq!(got.len(), KEYS.len());
        for ((key, _), want) in got.iter().zip(KEYS.iter()) {
            assert_eq!(key, want);
        }
    }

    #[test]
    fn render_is_key_value_lines() {
        let text = render();
        let rendered: Vec<&str> = text.lines().collect();
        assert_eq!(rendered.len(), KEYS.len());
        for (line, want) in rendered.iter().zip(KEYS.iter()) {
            assert!(line.starts_with(*want));
            assert!(line.contains('='));
        }
    }

    #[cfg(feature = "apple")]
    #[test]
    fn live_values_come_from_dt_apple() {
        let caps = dt_apple::capabilities();
        let got = lines();
        let find = |key: &str| {
            got.iter()
                .find(|(got_key, _)| got_key == key)
                .map_or_default(|(_, value)| value.clone())
        };
        let want_backend = match caps.backend {
            dt_apple::Backend::MacOs => "macos",
            dt_apple::Backend::Empty => "empty",
        };
        assert_eq!(find("backend"), want_backend);
        assert_eq!(
            find("ciraw.available"),
            if caps.ci_raw_filter { "true" } else { "false" }
        );
    }

    #[cfg(not(feature = "apple"))]
    #[test]
    fn feature_off_reports_empty_backend() {
        let got = lines();
        let find = |key: &str| {
            got.iter()
                .find(|(got_key, _)| got_key == key)
                .map_or_default(|(_, value)| value.clone())
        };
        assert_eq!(find("backend"), "empty");
        assert_eq!(find("metal.device"), "none");
    }
}
