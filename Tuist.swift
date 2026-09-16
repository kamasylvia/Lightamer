import ProjectDescription

// Tuist configuration (root Tuist.swift — Tuist 4.208 deprecated the old
// Tuist/Config.swift location).
//
// Phase 1 has ZERO external dependencies (D-02a: dependency minimalization —
// Apple-native frameworks only). This manifest stays minimal on purpose.
//
// Phase 11 (Export) will add `tuist install`-managed SPM dependencies here:
//   - libwebp binding  (WebP encode — no native CGImageDestination writer)
//   - libavif binding  (AVIF encode fallback / bit-depth control)
// See .planning/PROJECT.md "依赖最小化" and STACK.md Export Encoder Matrix.

let config = Config()
