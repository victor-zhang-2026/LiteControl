import AppKit

struct LiteProduct: Identifiable {
    enum Control {
        case application(String)
        case postWindow
    }

    let name: String
    let control: Control
    var id: String { name }
    let repository: URL?

    private static func published(_ name: String, _ control: Control) -> LiteProduct {
        LiteProduct(name: name, control: control,
                    repository: URL(string: "https://github.com/victor-zhang-2026/\(name)"))
    }

    static let post = published("LitePost", .postWindow)

    static let publicProducts = [
        published("LiteTick", .application("io.github.victor-zhang-2026.litetick")),
        published("LitePark", .application("local.chatgpt.desktop.later-queue")),
        published("LiteNum", .application("com.victor.litenum")),
        published("LiteCount", .application("io.github.victor-zhang-2026.litecount")),
        published("LiteFocus", .application("io.github.victor-zhang-2026.litefocus")),
        published("LiteCal", .application("app.litecal.mac")),
        published("LiteStick", .application("io.github.victor-zhang-2026.litestick")),
        post
    ]

    private struct LocalEntry: Decodable {
        let name: String
        let bundleID: String
        let repository: URL?
    }

    static let all: [LiteProduct] = {
        let file = URL.applicationSupportDirectory.appending(path: "LiteControl/local-products.json")
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([LocalEntry].self, from: data)
        else { return publicProducts }

        var products = publicProducts
        var names = Set(products.map(\.name))
        var bundleIDs = Set(products.compactMap { product -> String? in
            if case let .application(id) = product.control { return id }
            return nil
        })
        for entry in entries {
            guard !entry.name.isEmpty, !entry.bundleID.isEmpty,
                  !names.contains(entry.name), !bundleIDs.contains(entry.bundleID),
                  entry.bundleID != Bundle.main.bundleIdentifier, entry.bundleID != PostWindow.hostID else { continue }
            let repository = entry.repository.flatMap { url in
                url.scheme == "https" && url.host == "github.com" ? url : nil
            }
            products.append(LiteProduct(name: entry.name, control: .application(entry.bundleID), repository: repository))
            names.insert(entry.name)
            bundleIDs.insert(entry.bundleID)
        }
        return products
    }()

    func icon(at location: URL?) -> NSImage {
        if case .postWindow = control {
            return NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: name) ?? NSImage()
        }
        if let location { return NSWorkspace.shared.icon(forFile: location.path) }
        if let resource = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "ProductIcons"),
           let image = NSImage(contentsOf: resource) { return image }
        return NSImage(systemSymbolName: "app", accessibilityDescription: name) ?? NSImage()
    }
}

enum ApplicationLocator {
    static func matches(_ url: URL, bundleID: String) -> Bool {
        let root = url.resolvingSymlinksInPath()
        guard root.pathExtension.lowercased() == "app",
              !root.pathComponents.contains(".Trash"), !root.pathComponents.contains(".Trashes"),
              let data = try? Data(contentsOf: root.appendingPathComponent("Contents/Info.plist")),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              info["CFBundlePackageType"] as? String == "APPL",
              info["CFBundleIdentifier"] as? String == bundleID,
              let executable = info["CFBundleExecutable"] as? String else { return false }
        return FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("Contents/MacOS/\(executable)").path)
    }

    static func find(_ product: LiteProduct, bundleID: String, running: [NSRunningApplication]) -> URL? {
        // Keep V1's per-bundle manual selection, including renamed applications.
        if let path = UserDefaults.standard.string(forKey: "applicationPath.\(bundleID)") {
            let url = URL(fileURLWithPath: path)
            if matches(url, bundleID: bundleID) { return url }
        }
        let folders = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        for folder in folders {
            let url = folder.appendingPathComponent("\(product.name).app")
            if matches(url, bundleID: bundleID) { return url }
        }
        let live = running.compactMap(\.bundleURL)
        if let url = live.first(where: { matches($0, bundleID: bundleID) }) { return url }
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first { url in
            // Launch Services also indexes Xcode products, project backups and translocated copies.
            let parts = Set(url.standardizedFileURL.pathComponents)
            let transient: Set<String> = ["DerivedData", ".build", "build", "dist", "download-verification", "Backups.backupdb", "AppTranslocation"]
            return parts.isDisjoint(with: transient) && matches(url, bundleID: bundleID)
        }
    }
}
