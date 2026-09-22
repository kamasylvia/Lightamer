import Foundation
import LightamerCore

// Is JSONEncoder byte output stable across calls within a process?
struct Two: Codable, Hashable, Sendable {
    var outputProfile: String
    var intent: String
    init() { outputProfile = "display"; intent = "relativeColorimetric" }
}
let enc = JSONEncoder()
var hashes: [UInt64] = []
var bytesSet: Set<String> = []
for _ in 0..<5 {
    let d = try! enc.encode(Two())
    bytesSet.insert(String(decoding: d, as: UTF8.self))
    hashes.append(StableHash.hash(d))
}
print("hashes:", hashes)
for b in bytesSet { print("bytes:", b) }

// sortedKeys variant
let enc2 = JSONEncoder()
enc2.outputFormatting = .sortedKeys
var hashes2: [UInt64] = []
for _ in 0..<5 { hashes2.append(StableHash.hash(try! enc2.encode(Two()))) }
print("sortedKeys hashes:", hashes2)
