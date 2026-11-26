// SPDX-License-Identifier: GPL-3.0-or-later
//! Adopting an existing folder: structure is filled in, existing files are
//! never moved or touched.

mod common;

use lightamer_catalog::{close_session, open_session};

use common::{ScratchDir, relative_file_list};

#[test]
fn adopt_leaves_existing_files_untouched() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("adopt")?;
    let root = scratch.path().join("Old");
    std::fs::create_dir_all(root.join("Sub"))?;
    std::fs::write(root.join("a.arw"), [1_u8, 2, 3, 4])?;
    std::fs::write(root.join("b.jpg"), [9_u8; 64])?;
    std::fs::write(root.join("Sub").join("c.arw"), [7_u8; 129])?;
    let before_files = relative_file_list(&root)?;
    let before_a = std::fs::read(root.join("a.arw"))?;
    let before_b = std::fs::read(root.join("b.jpg"))?;
    let before_c = std::fs::read(root.join("Sub").join("c.arw"))?;

    let session = open_session(&root, "b12p-a-test")?;
    for dir in ["Capture", "Selects", "Output", "Trash"] {
        assert!(root.join(dir).is_dir(), "missing subdir {dir}");
    }
    assert!(root.join("Old.lmsessiondb").is_file());

    let after_files = relative_file_list(&root)?;
    for before in &before_files {
        assert!(
            after_files.contains(before),
            "adopted file vanished or moved: {before}"
        );
    }
    assert_eq!(std::fs::read(root.join("a.arw"))?, before_a);
    assert_eq!(std::fs::read(root.join("b.jpg"))?, before_b);
    assert_eq!(std::fs::read(root.join("Sub").join("c.arw"))?, before_c);
    close_session(session)?;

    // Opening by the database path reaches the same session.
    let session = open_session(&root.join("Old.lmsessiondb"), "b12p-a-test")?;
    assert_eq!(session.root(), root.as_path());
    close_session(session)?;
    Ok(())
}

#[test]
fn misnamed_database_path_is_refused() -> Result<(), Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new("misnamed")?;
    let root = scratch.path().join("Old");
    std::fs::create_dir_all(&root)?;
    std::fs::write(root.join("Wrong.lmsessiondb"), b"not a database")?;
    let Err(err) = open_session(&root.join("Wrong.lmsessiondb"), "b12p-a-test") else {
        return Err("misnamed database was accepted".into());
    };
    assert!(
        matches!(err, lightamer_catalog::CatalogError::BadPath(_)),
        "expected BadPath, got {err}"
    );
    assert!(!root.join("Old.lmsessiondb").exists());
    assert!(!root.join("session.lock").exists());
    Ok(())
}
