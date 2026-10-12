import Foundation
public enum BottleDiscovery {
    public static func discover(home: URL, configuredRoots: [URL]) throws -> [Bottle] {
        var roots = configuredRoots + [home.appendingPathComponent("cxbottles"), home.appendingPathComponent("Library/Application Support/CrossOver/Bottles")]
        if home == FileManager.default.homeDirectoryForCurrentUser,
           let pref = UserDefaults(suiteName: "com.codeweavers.CrossOver")?.string(forKey: "BottleDir") {
            roots.insert(URL(fileURLWithPath: NSString(string: pref).expandingTildeInPath), at: 0)
        }
        var found = Set<Bottle>()
        for root in roots {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("cxbottle.conf").path) {
                found.insert(Bottle(url: root))
            }
            for child in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] {
                if FileManager.default.fileExists(atPath: child.appendingPathComponent("cxbottle.conf").path) {
                    found.insert(Bottle(url: child))
                }
            }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
