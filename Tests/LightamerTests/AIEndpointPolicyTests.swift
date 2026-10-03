import Foundation
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// AIEndpointPolicyTests (Plan M2-10-04 T1, AC#1) — the admission MATRIX, one
// test per cell (the E4 observability pin: admission is asserted to the grid,
// not spot-checked):
//
//   https × any host            → pass
//   http  × localhost           → pass (dev loopback)
//   http  × 127.0.0.1           → pass
//   http  × ::1 / [::1]         → pass (both IPv6 spellings)
//   http  × example.com         → REFUSE (.insecureEndpoint)
//   ftp/ws/other × any host     → REFUSE
//   scheme-less / bare host     → REFUSE (no scheme = not provably secure)
//
// Plus the two gate faces: `isAuthorized` mirrors `authorize`, and the host
// normalization folds case + the IPv6 bracket spelling.
// ─────────────────────────────────────────────────────────────────────────────

final class AIEndpointPolicyTests: XCTestCase {

    private func assertAllowed(_ string: String, line: UInt = #line) {
        guard let url = URL(string: string) else {
            XCTFail("fixture URL unparseable: \(string)", line: line)
            return
        }
        guard case .success = AIEndpointPolicy.authorize(url) else {
            XCTFail("expected ALLOW for \(string)", line: line)
            return
        }
        XCTAssertTrue(AIEndpointPolicy.isAuthorized(url), line: line)
    }

    private func assertRefused(_ string: String, line: UInt = #line) {
        guard let url = URL(string: string) else {
            XCTFail("fixture URL unparseable: \(string)", line: line)
            return
        }
        guard case .failure(let error) = AIEndpointPolicy.authorize(url) else {
            XCTFail("expected REFUSE for \(string)", line: line)
            return
        }
        // The typed refusal carries the offending URL (the honest face).
        XCTAssertEqual(error, .insecureEndpoint(url), line: line)
        XCTAssertFalse(AIEndpointPolicy.isAuthorized(url), line: line)
    }

    // MARK: - https arm

    func testHTTPSPassesForAnyHost() {
        assertAllowed("https://api.anthropic.com")
        assertAllowed("https://api.openai.com/v1")
        assertAllowed("https://10.0.0.7:1234")
        assertAllowed("HTTPS://Api.Example.Com")  // scheme case folds
    }

    // MARK: - the three loopback http cells

    func testHTTPLocalhostPasses() {
        assertAllowed("http://localhost:11434/v1")
    }

    func testHTTP127LoopbackPasses() {
        assertAllowed("http://127.0.0.1:8080")
    }

    func testHTTPIPv6LoopbackPassesInBothSpellings() {
        assertAllowed("http://[::1]:11434")
        // The bracket-less spelling folds through normalizeHost (Foundation
        // keeps the brackets in URL.host on some versions, not others):
        XCTAssertEqual(AIEndpointPolicy.normalizeHost("[::1]"), "::1")
    }

    // MARK: - the refusal cells

    func testHTTPRemoteHostRefused() {
        assertRefused("http://example.com")
        assertRefused("http://192.168.1.10:1234")
        assertRefused("http://localhost.attacker.dev")  // suffix games refuse
    }

    func testNonHTTPSchemesRefused() {
        assertRefused("ftp://example.com/file")
        assertRefused("ws://localhost:9000")  // loopback does not rescue a non-http scheme
        assertRefused("file:///tmp/x")
    }

    func testSchemelessInputRefused() {
        assertRefused("localhost:11434")
    }

    // MARK: - normalization (the bracket/case fold)

    func testNormalizeHostFoldsCaseAndBrackets() {
        XCTAssertEqual(AIEndpointPolicy.normalizeHost("LOCALHOST"), "localhost")
        XCTAssertEqual(AIEndpointPolicy.normalizeHost("127.0.0.1"), "127.0.0.1")
        XCTAssertEqual(AIEndpointPolicy.normalizeHost("[::1]"), "::1")
        XCTAssertEqual(AIEndpointPolicy.normalizeHost("::1"), "::1")
    }

    func testHTTPLoopbackPortsAndPathsDoNotMatter() {
        // The admission judgment is scheme+host only — port/path/quary ride along.
        assertAllowed("http://localhost/v1/chat/completions")
        assertAllowed("http://127.0.0.1:1/")
        assertAllowed("http://[::1]:65535/deep/path")
    }
}
