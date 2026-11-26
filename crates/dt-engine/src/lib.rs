// SPDX-License-Identifier: GPL-3.0-or-later
//! Session commands, history application, jobs, export, import (A7a fills it).

#[cfg(test)]
mod tests {
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
