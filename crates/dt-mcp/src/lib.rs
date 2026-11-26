// SPDX-License-Identifier: GPL-3.0-or-later
//! MCP server over engine commands, phase C placeholder (C fills it).

#[cfg(test)]
mod tests {
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
