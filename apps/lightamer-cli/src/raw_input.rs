// SPDX-License-Identifier: GPL-3.0-or-later
//! `RawFileSource`: the engine's RAW file input (B3-0b).
//!
//! Photo ids are file paths. `probe` answers metadata without pixels,
//! `fetch` decodes the whole mosaic, `fetch_region` crops pieces out of the
//! one cached decode. Non-RAW files are typed refusals, never a fallback:
//! raster inputs arrive in a later wave. Lives here (not a new crate) until
//! the UI wave needs it higher up.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use lightamer_decode::{DecodedImage, RawImage, decode_file};
use lightamer_engine::{InputError, InputSource, RenderFacts, RenderInput};
use lightamer_raster::FrameExtent;

// FNV-1a 64 over bytes (input identities; same algorithm family as the
// pipe cache keys, computed locally so this module stays dependency-flat).
fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 14_695_981_039_346_656_037;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(1_099_511_628_211);
    }
    hash
}

// Fold one `u64` into a running FNV-1a hash.
fn fold(hash: u64, value: u64) -> u64 {
    let mut hash = hash;
    for byte in value.to_le_bytes() {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(1_099_511_628_211);
    }
    hash
}

// Input identity: path plus size plus mtime. A cache hit compares the path
// only and does not re-stat, so an overwritten file still serves the cached
// plane within one source's life; wire a fresh source per request (or re-stat
// on hit) when this gains a production caller. An unstattable path hashes by
// name alone; the open right after fails typed anyway.
fn input_id_for(path: &Path) -> u64 {
    let mut id = fnv1a(path.as_os_str().as_encoded_bytes());
    if let Ok(stat) = std::fs::metadata(path) {
        id = fold(id, stat.len());
        let mtime = stat
            .modified()
            .ok()
            .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok());
        if let Some(mtime) = mtime {
            id = fold(id, mtime.as_secs());
            id = fold(id, u64::from(mtime.subsec_nanos()));
        }
    }
    id
}

// One cached decode: everything `fetch_region` needs without re-decoding.
struct CachedRaw {
    /// File this decode came from (cache key).
    path: PathBuf,
    /// Owned metadata plus the cropped mosaic plane.
    decoded: DecodedImage,
    /// Identity captured at decode time.
    input_id: u64,
}

/// File-backed RAW input for engine renders: photo id in, mosaic out.
pub struct RawFileSource {
    /// The most recent decode, shared across a streaming request's pieces.
    /// `InputSource` carries no request scope — region calls cannot tell
    /// request boundaries — so the source retains one decode: bounded to a
    /// single mosaic, evicted by the next file. Never pre-filled, never
    /// swept.
    cached: Mutex<Option<Arc<CachedRaw>>>,
}

impl RawFileSource {
    /// An empty source: the first call for a file decodes it.
    #[must_use]
    pub fn new() -> Self {
        Self {
            cached: Mutex::new(None),
        }
    }

    // The cached decode when it already serves `path`.
    fn cached_hit(&self, path: &Path) -> Option<Arc<CachedRaw>> {
        let cached = self
            .cached
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        cached.as_ref().filter(|hit| hit.path == path).cloned()
    }

    // Decode `path`, evicting whatever was cached.
    fn decode_and_cache(&self, path: &Path) -> Result<Arc<CachedRaw>, InputError> {
        // `decode_file` drops its handle before returning, so the C++ pixels
        // are already freed when the caller converts the owned mosaic.
        let decoded = decode_file(path).map_err(|err| refuse(path, &err))?;
        let input_id = input_id_for(path);
        let hit = Arc::new(CachedRaw {
            path: path.to_path_buf(),
            decoded,
            input_id,
        });
        *self
            .cached
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(hit.clone());
        Ok(hit)
    }

    // The decode serving `path`, cached or freshly decoded.
    fn ensure_cached(&self, path: &Path) -> Result<Arc<CachedRaw>, InputError> {
        if let Some(hit) = self.cached_hit(path) {
            return Ok(hit);
        }
        self.decode_and_cache(path)
    }
}

impl Default for RawFileSource {
    fn default() -> Self {
        Self::new()
    }
}

// Typed refusal naming the file, the decode failure, and its code.
fn refuse(path: &Path, err: &lightamer_decode::DecodeError) -> InputError {
    InputError::new(format!(
        "cannot use {} as a RAW input: {err} ({:?})",
        path.display(),
        err.code()
    ))
}

// Full cropped-frame extent of a decoded capture.
fn full_extent(decoded: &DecodedImage) -> FrameExtent {
    FrameExtent::new(0, 0, decoded.meta.width, decoded.meta.height)
}

// Pipe facts for a cached decode (facts only, no pixels converted).
fn facts_for(path: &Path, hit: &Arc<CachedRaw>) -> Result<RenderFacts, InputError> {
    let image =
        lightamer_decode::pipe::pipe_image(&hit.decoded.meta).map_err(|err| refuse(path, &err))?;
    Ok(RenderFacts {
        image,
        extent: full_extent(&hit.decoded),
    })
}

impl InputSource for RawFileSource {
    fn fetch(&self, photo: &str) -> Result<RenderInput, InputError> {
        let path = PathBuf::from(photo);
        let hit = self.ensure_cached(&path)?;
        let extent = full_extent(&hit.decoded);
        let (frame, image) = hit
            .decoded
            .pipe_input(extent)
            .map_err(|err| refuse(&path, &err))?;
        Ok(RenderInput {
            frame,
            image,
            input_id: hit.input_id,
        })
    }

    fn probe(&self, photo: &str) -> Result<RenderFacts, InputError> {
        let path = PathBuf::from(photo);
        if let Some(hit) = self.cached_hit(&path) {
            return facts_for(&path, &hit);
        }
        // The fast probe only parses metadata; the fallback decodes, and
        // its pixels stay cached so `fetch` never decodes twice.
        let mut image = RawImage::open(&path).map_err(|err| refuse(&path, &err))?;
        let meta = image.probe_metadata().map_err(|err| refuse(&path, &err))?;
        if image.is_decoded() {
            let mosaic = image.mosaic().map_err(|err| refuse(&path, &err))?;
            drop(image);
            let input_id = input_id_for(&path);
            let hit = Arc::new(CachedRaw {
                path: path.clone(),
                decoded: DecodedImage { meta, mosaic },
                input_id,
            });
            let facts = facts_for(&path, &hit);
            *self
                .cached
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(hit);
            facts
        } else {
            // Fast path: facts without pixels and without caching anything.
            let extent = FrameExtent::new(0, 0, meta.width, meta.height);
            let image =
                lightamer_decode::pipe::pipe_image(&meta).map_err(|err| refuse(&path, &err))?;
            Ok(RenderFacts { image, extent })
        }
    }

    fn fetch_region(&self, photo: &str, region: FrameExtent) -> Result<RenderInput, InputError> {
        let path = PathBuf::from(photo);
        let hit = self.ensure_cached(&path)?;
        let (frame, image) = hit
            .decoded
            .pipe_input(region)
            .map_err(|err| refuse(&path, &err))?;
        Ok(RenderInput {
            frame,
            image,
            input_id: hit.input_id,
        })
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{fnv1a, input_id_for};
    use std::path::PathBuf;

    #[test]
    fn fnv_matches_the_standard_vectors() {
        assert_eq!(fnv1a(b""), 14_695_981_039_346_656_037);
        assert_eq!(fnv1a(b"foobar"), 0x8594_4171_f739_67e8);
    }

    #[test]
    fn input_ids_are_stable_and_path_sensitive() {
        let one = PathBuf::from("/nonexistent/a.ARW");
        let two = PathBuf::from("/nonexistent/b.ARW");
        assert_eq!(input_id_for(&one), input_id_for(&one));
        assert_ne!(input_id_for(&one), input_id_for(&two));
    }
}
