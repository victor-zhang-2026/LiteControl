import Foundation

enum PostWindow {
    static let hostID = "org.hammerspoon.Hammerspoon"

    static func installedScript() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let custom = UserDefaults(suiteName: hostID)?.string(forKey: "MJConfigFile")
        let config = custom.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, relativeTo: home) }
            ?? home.appendingPathComponent(".hammerspoon/init.lua")
        let script = config.deletingLastPathComponent().appendingPathComponent("Spoons/Post.spoon/init.lua")
        guard let file = try? FileHandle(forReadingFrom: script) else { return nil }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: 4096), !data.isEmpty else { return nil }
        let header = String(decoding: data, as: UTF8.self)
        guard header.contains("obj.name = \"Post\""), header.contains("obj.author = \"Victor Zhang × Hammerspoon\"")
        else { return nil }
        return script
    }

    enum Command: String { case status, show, hide }

    // An unavailable endpoint is distinct from a closed window.
    static func request(_ command: Command, host: URL) async -> Bool? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = host.appendingPathComponent("Contents/Frameworks/hs/hs")
            let expression = """
            local p = spoon and spoon.Post
            if not p or p.name ~= 'Post' or p.author ~= 'Victor Zhang × Hammerspoon'
              or type(p.status) ~= 'function' or type(p.show) ~= 'function' or type(p.hide) ~= 'function' then return end
            local cmd = '\(command.rawValue)'
            if cmd == 'show' and not p:status() then p:show() end
            if cmd == 'hide' and p:status() then p:hide() end
            return p:status() and '1' or '0'
            """
            process.arguments = ["-q", "-t", "1", "-c", expression]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                switch String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) {
                case "1": return true
                case "0": return false
                default: return nil
                }
            } catch { return nil }
        }.value
    }
}
