import Foundation
import AppKit

/// A drive or card Lasso has seen, recognised by its built-in ID (volume UUID), not its name.
struct DriveRecord: Codable, Hashable {
    var uuid: String
    var name: String
}

/// An app that has a file open on a drive, so the drive can't be ejected.
struct DriveUser: Hashable {
    let app: String
    let file: String
}

enum DriveAlert: Identifiable {
    case renamed(uuid: String, oldName: String, newName: String, volume: URL)
    case blocked(name: String, volume: URL, users: [DriveUser])

    var id: String {
        switch self {
        case .renamed(let uuid, _, let newName, _): return "renamed-\(uuid)-\(newName)"
        case .blocked(let name, _, let users): return "blocked-\(name)-\(users.count)"
        }
    }
}

enum Drives {
    /// "/Volumes/Travel SSD/Clips" → "/Volumes/Travel SSD". Nil for folders on the Mac itself.
    static func volumeRoot(of url: URL) -> URL? {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes/" + parts[2], isDirectory: true)
    }

    static func uuid(of volume: URL) -> String? {
        try? volume.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }

    /// External drives and cards that are plugged in right now.
    static func mountedVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeUUIDStringKey, .volumeNameKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [])
            .filter { $0.path.hasPrefix("/Volumes/") }
    }

    static func isMounted(uuid: String) -> Bool {
        mountedVolumes().contains { Self.uuid(of: $0) == uuid }
    }

    /// Safely ejects a drive. Returns false if something is still using it.
    static func eject(_ volume: URL) -> Bool {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            return true
        } catch {
            return false
        }
    }

    /// Which apps have files open on the drive, using macOS's built-in `lsof`.
    static func users(of volume: URL) -> [DriveUser] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-F", "pn", "+f", "--", volume.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let me = ProcessInfo.processInfo.processIdentifier
        var seen = Set<String>()
        var out: [DriveUser] = []
        var pid: Int32 = 0
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            if tag == "p" { pid = Int32(value) ?? 0; continue }
            guard tag == "n", pid != me, value.hasPrefix(volume.path + "/") else { continue }
            let file = URL(fileURLWithPath: value)
            let inside = value.dropFirst(volume.path.count + 1).split(separator: "/")
            if inside.contains(where: { $0.hasPrefix(".") }) { continue }   // Spotlight and other system files
            let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Process \(pid)"
            if seen.insert(app).inserted { out.append(DriveUser(app: app, file: file.lastPathComponent)) }
        }
        return out
    }
}
