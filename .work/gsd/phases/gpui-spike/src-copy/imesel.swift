// imesel: list and select macOS input sources (for the IME test).
// usage: imesel list | imesel select <source-id>

import Carbon
import Foundation

func sources(_ includeAll: Bool) -> [(String, String, TISInputSource)] {
    var out: [(String, String, TISInputSource)] = []
    guard let list = TISCreateInputSourceList(nil, includeAll)?.takeRetainedValue() as? [TISInputSource] else {
        return out
    }
    for s in list {
        func prop(_ key: CFString) -> String {
            guard let p = TISGetInputSourceProperty(s, key) else { return "" }
            return (Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String)
        }
        out.append((prop(kTISPropertyInputSourceID), prop(kTISPropertyLocalizedName), s))
    }
    return out
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "list" {
    for (id, name, s) in sources(true) {
        let sel = TISGetInputSourceProperty(s, kTISPropertyInputSourceIsSelected) != nil
        print("\(sel ? "*" : " ") \(id)\t\(name)")
    }
} else if args.first == "select", args.count > 1 {
    let want = args[1]
    for (id, _, s) in sources(true) where id == want {
        let err = TISSelectInputSource(s)
        print("select \(want) -> \(err)")
        exit(err == 0 ? 0 : 1)
    }
    print("not found: \(want)")
    exit(2)
} else {
    print("usage: imesel list | imesel select <source-id>")
}
