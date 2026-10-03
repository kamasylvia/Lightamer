import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// AIEndpointPolicy (Plan M2-10-04 KD-1, D-M2-10-CONTEXT-5, M2AI-06) — the URL
// admission gate for every remote AI endpoint.
//
// THE RULE (two gates, one function): `https://` always passes; plain `http://`
// passes ONLY for the explicit dev-loopback hosts (localhost / 127.0.0.1 /
// ::1) — the local ollama/LM Studio/vLLM endpoints. EVERYTHING else is a
// typed `.insecureEndpoint` refusal.
//
// THE LOOPBACK EXCEPTION HAS NO TOGGLE (D-5: the「输入即放行」arm was picked
// over a settings switch on purpose — a hidden allow-HTTP switch is a
// footgun; a user typing an http:// loopback URL has made an informed dev
// choice, and non-loopback http can never be configured).
//
// THE GATE RUNS TWICE (KD-1): before the key is SAVED (the configuration
// face — a key must never be stored for an endpoint the client would refuse)
// and before EVERY SEND (the transport face). The client's send-side check
// is the load-bearing one; the storage-side check is the early UX one.
// ─────────────────────────────────────────────────────────────────────────────

public enum AIEndpointPolicy {

    public enum PolicyError: Error, Equatable {
        /// The URL failed admission (scheme not https and host not loopback).
        case insecureEndpoint(URL)
    }

    /// The loopback dev hosts. `[::1]` is listed for the Foundation spelling
    /// that keeps IPv6 brackets in `URL.host`; `normalizeHost` folds both
    /// spellings anyway (defense in depth, and the matrix test pins both).
    static let loopbackHosts: Set<String> = [
        "localhost", "127.0.0.1", "::1", "[::1]",
    ]

    /// The admission verdict as a `Result` (the plan's face).
    public static func authorize(_ url: URL) -> Result<Void, PolicyError> {
        guard let scheme = url.scheme?.lowercased() else {
            return .failure(.insecureEndpoint(url))
        }
        if scheme == "https" {
            return .success(())
        }
        if scheme == "http",
           let host = url.host.map(normalizeHost),
           loopbackHosts.contains(host) {
            return .success(())
        }
        return .failure(.insecureEndpoint(url))
    }

    /// The boolean convenience (the client's guard shape).
    public static func isAuthorized(_ url: URL) -> Bool {
        if case .success = authorize(url) { return true }
        return false
    }

    /// Fold the host spellings that must compare equal: case, and the IPv6
    /// bracket form (`[::1]` vs `::1`).
    static func normalizeHost(_ host: String) -> String {
        let lowered = host.lowercased()
        if lowered.hasPrefix("["), lowered.hasSuffix("]") {
            return String(lowered.dropFirst().dropLast())
        }
        return lowered
    }
}
