// SPDX-License-Identifier: GPL-3.0-or-later
//! CLI + oracle comparison tool + perf probes (A4b/A5 fill it; no arg parser at A2).

fn main() {
    println!("{} {}", env!("CARGO_PKG_NAME"), env!("CARGO_PKG_VERSION"));
}

#[cfg(test)]
mod tests {
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
