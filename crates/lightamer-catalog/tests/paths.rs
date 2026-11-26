// SPDX-License-Identifier: GPL-3.0-or-later
//! Stored paths: both directions, dot cleaning, and refusing escapes.

mod common;

use std::path::Path;

use lightamer_catalog::{CatalogError, PathKind, to_absolute, to_stored};

use common::ScratchDir;

#[test]
fn path_conversions_roundtrip_and_refuse_escapes() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("paths")?;
    let root = scratch.path().join("S");

    let (kind, stored) = to_stored(&root, &root.join("Capture/a.arw"))?;
    assert_eq!(kind, PathKind::InSession);
    assert_eq!(stored, "Capture/a.arw");
    assert_eq!(
        to_absolute(&root, kind, &stored)?,
        root.join("Capture/a.arw")
    );

    let (kind, stored) = to_stored(&root, Path::new("Capture/b.arw"))?;
    assert_eq!(
        (kind, stored.as_str()),
        (PathKind::InSession, "Capture/b.arw")
    );

    let outside = scratch.path().join("Outside/x.tif");
    let (kind, stored) = to_stored(&root, &outside)?;
    assert_eq!(kind, PathKind::External);
    assert_eq!(stored, outside.to_string_lossy());
    assert_eq!(to_absolute(&root, kind, &stored)?, outside);

    for (input, expected) in [
        ("Capture/./x.arw", "Capture/x.arw"),
        ("Capture/a/../x.arw", "Capture/x.arw"),
        ("Capture//x.arw", "Capture/x.arw"),
        ("Capture/a/b/../../x.arw", "Capture/x.arw"),
    ] {
        let (kind, stored) = to_stored(&root, Path::new(input))?;
        assert_eq!(kind, PathKind::InSession);
        assert_eq!(stored, expected, "input {input}");
    }

    for bad in ["../escape.arw", "Capture/../../escape.arw", ""] {
        let err = match to_stored(&root, Path::new(bad)) {
            Ok(ok) => return Err(format!("in-session input accepted: {bad:?} -> {ok:?}").into()),
            Err(err) => err,
        };
        assert!(
            matches!(err, CatalogError::BadPath(_)),
            "input {bad:?}: expected BadPath, got {err}"
        );
    }
    // An absolute input equal to the root itself stores as empty relative:
    // refused, since empty is not a photo path.
    let err = match to_stored(&root, &root) {
        Ok(ok) => return Err(format!("root itself accepted: {ok:?}").into()),
        Err(err) => err,
    };
    assert!(matches!(err, CatalogError::BadPath(_)), "root: got {err}");

    for bad in ["../escape.arw", "/absolute.arw", ""] {
        let Err(err) = to_absolute(&root, PathKind::InSession, bad) else {
            return Err(format!("in-session stored accepted: {bad:?}").into());
        };
        assert!(
            matches!(err, CatalogError::BadPath(_)),
            "stored {bad:?}: expected BadPath, got {err}"
        );
    }
    assert!(to_absolute(&root, PathKind::External, "relative/x.tif").is_err());
    assert!(to_absolute(&root, PathKind::External, "/a/../../escape.tif").is_err());

    assert_eq!(PathKind::InSession.as_db(), 0);
    assert_eq!(PathKind::External.as_db(), 1);
    assert_eq!(PathKind::from_db(0), Some(PathKind::InSession));
    assert_eq!(PathKind::from_db(1), Some(PathKind::External));
    assert_eq!(PathKind::from_db(7), None);
    Ok(())
}
