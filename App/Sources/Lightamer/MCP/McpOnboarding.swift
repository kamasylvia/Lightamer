// Copyright (c) 2026 the Lightamer authors (GPL-3.0). Shape derived from
// SpektraLab RFC-026 (c) Hanze Qiu and contributors (GPL-3.0), upstream
// commit 85c9c16 — see NOTICE §V.
import Foundation
// ─────────────────────────────────────────────────────────────────────────────
// UQ-S2/UQ-S3 (MCP-UQ batch, SpektraLab RFC-026 AgentAccess 借鉴): the Agents
// onboarding model — what Settings ▸ MCP ▸ 接入向导 shows with Copy buttons,
// and what the one-shot CLI gate (`Lightamer mcp call`, UQ-S3) executes.
//
// ONBOARDING (UQ-S2): two paste-ready config blocks, generated from the
// LIVE discovery path (McpEndpointPaths.makeDefault — never a hardcoded
// path): the Claude Code `claude mcp add` terminal line (stdio) and the
// Claude Desktop JSON block (stdio). Plus the CLI install face: a two-line
// sh script at ~/.local/bin/lightamer (the upstream two-line-script shape:
// a symlink would break Bundle.main resource/defaults resolution).
//
// ONE-SHOT CLI (UQ-S3): `Lightamer mcp call <tool> '<json>'` — read the
// discovery file → SDK HTTP client handshake → tools/call → print → exit.
// Protocol-level reuse (zero new tool definitions = natural parity).
// `Lightamer mcp list` lists the tools. Typed errors (exit 2 = caller's
// to fix: app off / MCP off / unknown tool / bad JSON; exit 1 = ours).
//
// Both faces share the discovery-path + executable-path single sources
// below — the Settings text and the CLI behavior cannot drift apart.
// ─────────────────────────────────────────────────────────────────────────────

enum McpOnboarding {

    /// The app's own executable: what the MCP configs name and what the
    /// installed script runs.
    static var executablePath: String {
        Bundle.main.executableURL?.resolvingSymlinksInPath().path
            ?? CommandLine.arguments[0]
    }

    /// The discovery file the configs point at (live path, ~-collapsed
    /// for display).
    static var discoveryPath: String {
        McpEndpointPaths.makeDefault().jsonURL.path
    }

    static var discoveryDisplayPath: String {
        discoveryPath.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~")
    }

    // MARK: - The paste-ready configs

    /// `claude mcp add lightamer -- '<exe>' --mcp-stdio` (stdio).
    static var claudeCodeCommand: String {
        "claude mcp add lightamer -- '\(shellQuoted(executablePath))' --mcp-stdio"
    }

    /// The Claude Desktop mcpServers JSON block (stdio).
    static var desktopConfig: String {
        let block: [String: Any] = [
            "mcpServers": [
                "lightamer": [
                    "command": executablePath,
                    "args": ["--mcp-stdio"],
                ]
            ]
        ]
        let data = try? JSONSerialization.data(
            withJSONObject: block, options: [.prettyPrinted, .sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// The CLI one-shot usage line (shown after install).
    static var cliUsage: String {
        "lightamer mcp call <tool> '<json-args>'   # one-shot call via \(discoveryDisplayPath)"
    }

    // MARK: - The CLI install face (the upstream script shape)

    /// Where Install puts the command (`~/.local/bin` — no admin needed).
    static var installURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".local/bin/lightamer")
    }
    /// The install-marker single source (M-9: full-string match — the
    /// install/uninstall guards compare against THIS, not a prefix).
    static let installMarker = "Installed by Settings ▸ MCP ▸ 接入向导"

    /// The two-line script (NOT a symlink — see the header note).
    static var script: String {
        """
        #!/bin/sh
        # Lightamer one-shot MCP gate (UQ-S3). \(installMarker).
        exec '\(shellQuoted(executablePath))' "$@"
        """ + "\n"
    }

    static var installState: InstallState {
        guard let text = try? String(contentsOf: installURL, encoding: .utf8)
        else { return .absent }
        return text == script ? .current : .other
    }

    enum InstallState: Equatable { case absent, current, other }

    /// Write the script. Replaces only a script this app wrote before;
    /// anything else at that path is someone else's file and is left alone.
    static func install() throws {
        let fm = FileManager.default
        if let text = try? String(contentsOf: installURL, encoding: .utf8),
           !text.contains(installMarker)
        {
            throw McpOneShotError.refused(
                "\(installURL.path) exists and is not Lightamer's; it was left alone.")
        }
        try fm.createDirectory(
            at: installURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try script.write(to: installURL, atomically: true, encoding: .utf8)
        try fm.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: installURL.path)
    }

    static func uninstall() throws {
        guard installState != .absent else { return }
        guard let text = try? String(contentsOf: installURL, encoding: .utf8),
              text.contains(installMarker)
        else {
            throw McpOneShotError.refused(
                "\(installURL.path) is not Lightamer's; it was left alone.")
        }
        try FileManager.default.removeItem(at: installURL)
    }

    /// Single-quote a shell word.
    static func shellQuoted(_ word: String) -> String {
        word.replacingOccurrences(of: "'", with: "'\\''")
    }
}
