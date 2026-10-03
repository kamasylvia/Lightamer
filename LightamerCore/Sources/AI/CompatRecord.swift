import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// CompatRecord (Plan M2-10-05 KD-4 / D-M2-10-CONTEXT-6) — the persistent
// memory of compute-unit combinations that crashed natively, per machine
// (hardware model + OS build) per model. Lumen `gpu-compat.json` /
// `ai_worker.py:106-142` paradigm, MIT read-only (structure ported, not code).
//
// File shape (`~/Library/Application Support/Lightamer/ai-compat.json`):
//
//   { "<machineKey>": { "<units>": {
//        "models": ["<profileID>", …],   // the models that crashed on these units
//        "all": false,                   // TWO DIFFERENT models → the units
//                                        // themselves are unusable here (Lumen
//                                        // ai_worker.py:132 parity)
//        "last": {"model": "…", "detail": "…≤300", "time": "…"}
//   } } }
//
// Rules that are not re-openable here:
//   • A CPU crash is NEVER recorded (the CPU fallback has nowhere left to
//     degrade to — recording it would brick the chain permanently; Lumen
//     :124-125 parity).
//   • Atomic write: JSON bytes land in a SAME-DIRECTORY `.tmp` file that is
//     renamed over the target (L009 — never a cross-volume rename).
//   • Corrupt JSON is tolerated as an EMPTY record: the next bookkeeping
//     write rebuilds the file; a broken memo must never break the editor.
//   • Path injection everywhere: tests pass a temp path; the DEFAULT path
//     is resolved ONLY at the App assembly point (AIInferenceService).
// ─────────────────────────────────────────────────────────────────────────────

/// One per-(machine, units) bookkeeping entry.
public struct CompatEntry: Codable, Sendable, Equatable {
    public struct LastCrash: Codable, Sendable, Equatable {
        public var model: String
        public var detail: String
        public var time: String

        public init(model: String, detail: String, time: String) {
            self.model = model
            self.detail = detail
            self.time = time
        }
    }

    /// The model profileIDs that crashed on these units.
    public var models: [String]
    /// Two DIFFERENT models crashed on these units → the units themselves
    /// are excluded for every model on this machine.
    public var all: Bool
    public var last: LastCrash?

    public init(models: [String], all: Bool, last: LastCrash?) {
        self.models = models
        self.all = all
        self.last = last
    }
}

public final class CompatRecord: @unchecked Sendable {

    /// The detail text truncation bound (KD-4; Lumen :133 parity).
    public static let detailLimit = 300

    private let path: URL
    private let lock = NSLock()

    /// - Parameter path: the injected store location. The DEFAULT path is
    ///   resolved only at the App assembly point (`defaultPath()`), never
    ///   inside this class — tests never touch the real Application Support.
    public init(path: URL) {
        self.path = path
    }

    /// `~/Library/Application Support/Lightamer/ai-compat.json`.
    /// App-assembly-only resolution (the M2-10-07 reset button consumes the
    /// same location).
    public static func defaultPath() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("Lightamer", isDirectory: true)
            .appendingPathComponent("ai-compat.json")
    }

    /// The machine identity the record is keyed by: hardware model + OS
    /// build (e.g. `Mac15,6/27A123`). Same machine → stable; an OS update
    /// (new build) → a fresh slate, which is the intended semantics (the
    /// M2-10-07 reset button remains the manual override).
    public static func currentMachineKey() -> String {
        machineKey(
            hwModel: sysctlString("hw.model") ?? "unknown-model",
            osBuild: sysctlString("kern.osversion") ?? "unknown-build")
    }

    /// The pure composition (the injectable seam — tests never read sysctl).
    public static func machineKey(hwModel: String, osBuild: String) -> String {
        "\(hwModel)/\(osBuild)"
    }

    /// The units the client must remove from the attempt chain for THIS
    /// model: a units is excluded when it was fully disabled (`all`) or when
    /// THIS model already crashed on it (Lumen `excluded` :119-121 parity).
    public func excluded(
        machineKey: String, model: String
    ) -> Set<AIComputeUnits> {
        lock.lock(); defer { lock.unlock() }
        let data = load()
        guard let perUnits = data[machineKey] else { return [] }
        var excluded = Set<AIComputeUnits>()
        for units in AIComputeUnits.allCases {
            guard let entry = perUnits[units.rawValue] else { continue }
            if entry.all || entry.models.contains(model) {
                excluded.insert(units)
            }
        }
        return excluded
    }

    /// Records one native crash. CPU crashes are ignored (see the class
    /// comment); everything else is a locked read-modify-write followed by
    /// the same-directory atomic promotion.
    public func record(
        machineKey: String, model: String, units: AIComputeUnits, detail: String
    ) {
        guard units != .cpuOnly else { return }
        lock.lock(); defer { lock.unlock() }
        var data = load()
        var entry = data[machineKey]?[units.rawValue]
            ?? CompatEntry(models: [], all: false, last: nil)
        if !entry.models.contains(model) {
            entry.models.append(model)
        }
        entry.all = entry.models.count >= 2
        entry.last = CompatEntry.LastCrash(
            model: model,
            detail: String(detail.prefix(Self.detailLimit)),
            time: Self.timestamp())
        data[machineKey, default: [:]][units.rawValue] = entry
        save(data)
    }

    /// The M2-10-07 reset face: forget everything (the file is the only
    /// state).
    public func resetAll() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: path)
    }

    // MARK: - Storage (callers hold the lock)

    private func load() -> [String: [String: CompatEntry]] {
        guard let bytes = try? Data(contentsOf: path) else { return [:] }
        // Corrupt JSON == an empty record (the class comment: the memo never
        // breaks the editor; the next write rebuilds the file).
        return (try? JSONDecoder().decode(
            [String: [String: CompatEntry]].self, from: bytes)) ?? [:]
    }

    private func save(_ data: [String: [String: CompatEntry]]) {
        do {
            let directory = path.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let bytes = try JSONEncoder().encode(data)
            // L009: the tmp file lives in the SAME directory as the target —
            // the promotion is one atomic rename (replace swaps atomically
            // when the file exists; the first write is a plain rename).
            let tmp = directory.appendingPathComponent(
                path.lastPathComponent + ".tmp")
            try bytes.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: path.path) {
                _ = try FileManager.default.replaceItemAt(path, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: path)
            }
        } catch {
            // Best-effort memo (Lumen :139-140 parity): a failed bookkeeping
            // write degrades to memory-only for this session.
            return
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }
}
