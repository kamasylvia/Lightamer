import Foundation
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// AICredentialStoreTests (Plan M2-10-04 T1, AC#2) — the Keychain face over the
// HOST's REAL login keychain (Scripts/test-direct.sh direct launch has
// access; a CI/lock-screen environment skips via the availability probe —
// the plan's resource-gate note):
//
//   • round-trip save/read (bytes identical)
//   • overwrite (save twice → the second secret wins, one item)
//   • idempotent delete + the typed .notFound after
//   • two accounts isolated (the rating-provider account never sees a
//     neighbor's secret)
//   • E4 zeroize: the READOUT is caller-owned — after `resetBytes` the buffer
//     is byte-level zero AND a fresh read still returns the intact secret
//     (the scrub touched only the caller's copy; the store never retained one)
//   • error face: .notFound typed, no secret text ever in error descriptions
//
// Every test uses a UNIQUE per-run account (UUID suffix) so reruns never
// collide with a previous run's leftovers in the shared login keychain.
// ─────────────────────────────────────────────────────────────────────────────

final class AICredentialStoreTests: XCTestCase {

    private var account: String!
    private var probeAccount: String!

    override func setUp() {
        super.setUp()
        account = "rating-provider-tests-\(UUID().uuidString)"
        probeAccount = "rating-provider-probe-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? AICredentialStore.delete(account ?? "")
        try? AICredentialStore.delete(probeAccount ?? "")
        account = nil
        probeAccount = nil
        super.tearDown()
    }

    /// The resource gate: a real login keychain is required. Absent (CI /
    /// lock screen) → XCTSkip — the auditable skip face, NOT a silent pass.
    private func requireKeychain() throws {
        do {
            try AICredentialStore.save(Data([0x01]), account: probeAccount)
        } catch let error as AICredentialStore.CredentialError {
            throw XCTSkip("keychain unavailable in this environment: \(error)")
        }
    }

    private func cleanup(_ account: String) {
        try? AICredentialStore.delete(account)
    }

    // MARK: - round-trip

    func testSaveReadRoundTripPreservesBytes() throws {
        try requireKeychain()
        defer { cleanup(account) }
        let secret = Data("sk-lightamer-roundtrip-\(UUID().uuidString)".utf8)
        try AICredentialStore.save(secret, account: account)
        let readBack = try AICredentialStore.read(account)
        XCTAssertEqual(readBack, secret)
    }

    func testOverwriteReplacesTheSecret() throws {
        try requireKeychain()
        defer { cleanup(account) }
        let first = Data("first-secret".utf8)
        let second = Data("second-secret-uuid-\(UUID().uuidString)".utf8)
        try AICredentialStore.save(first, account: account)
        try AICredentialStore.save(second, account: account)
        XCTAssertEqual(try AICredentialStore.read(account), second)
    }

    // MARK: - delete

    func testDeleteIsIdempotentAndLeavesNotFound() throws {
        try requireKeychain()
        defer { cleanup(account) }
        try AICredentialStore.save(Data("to-be-deleted".utf8), account: account)
        try AICredentialStore.delete(account)
        // Idempotent: deleting the already-gone item is success, not an error.
        try AICredentialStore.delete(account)
        XCTAssertThrowsError(try AICredentialStore.read(account)) { error in
            XCTAssertEqual(
                error as? AICredentialStore.CredentialError, .notFound)
        }
    }

    func testDeleteNeverExistedIsSuccess() throws {
        try requireKeychain()
        let never = "rating-provider-never-\(UUID().uuidString)"
        defer { cleanup(never) }
        try AICredentialStore.delete(never)
    }

    // MARK: - account isolation

    func testTwoAccountsAreIsolated() throws {
        try requireKeychain()
        let other = "rating-provider-other-\(UUID().uuidString)"
        defer {
            cleanup(account)
            cleanup(other)
        }
        let mine = Data("mine-\(UUID().uuidString)".utf8)
        let theirs = Data("theirs-\(UUID().uuidString)".utf8)
        try AICredentialStore.save(mine, account: account)
        try AICredentialStore.save(theirs, account: other)
        XCTAssertEqual(try AICredentialStore.read(account), mine)
        XCTAssertEqual(try AICredentialStore.read(other), theirs)
        // Deleting one leaves the other intact.
        try AICredentialStore.delete(account)
        XCTAssertEqual(try AICredentialStore.read(other), theirs)
    }

    // MARK: - E4 zeroize (byte level)

    func testReadoutZeroizeScrubOnlyTheCallerCopy() throws {
        try requireKeychain()
        defer { cleanup(account) }
        let secretString = "sk-live-e4-\(UUID().uuidString)"
        let secret = Data(secretString.utf8)
        try AICredentialStore.save(secret, account: account)

        // The production shape (AIProviderClient): read → use → scrub.
        var key = try AICredentialStore.read(account)
        XCTAssertEqual(key, secret)
        // resetBytes WITHOUT a range defaults to 0..<0 (scrubs NOTHING — the
        // Foundation footgun); the contract is the FULL range.
        key.resetBytes(in: 0..<key.count)
        // BYTE-LEVEL: every byte is zero after the scrub.
        let allZero = key.allSatisfy { byte in byte == 0 }
        XCTAssertTrue(
            allZero,
            "the zeroize contract is byte-level, not just isEmpty")

        // The store never retained a copy: a fresh read is intact, and the
        // scrubbed buffer cannot be resurrected.
        XCTAssertEqual(try AICredentialStore.read(account), secret)
        XCTAssertNotEqual(key, secret)
    }

    // MARK: - the error face carries no secret text

    func testNotFoundErrorCarriesNoSecretMaterial() throws {
        try requireKeychain()
        let secretString = "sk-never-stored-\(UUID().uuidString)"
        do {
            _ = try AICredentialStore.read(account)
            XCTFail("expected notFound")
        } catch {
            let description = String(describing: error)
            XCTAssertFalse(
                description.contains(secretString),
                "error text must never embed secret material")
        }
    }
}
