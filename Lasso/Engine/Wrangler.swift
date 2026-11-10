import Foundation
import CryptoKit

/// Finding files, spotting duplicates, naming, and copying or renaming.
enum Wrangler {
    static let videoExts: Set<String> = ["mp4", "mov", "m4v"]
    static let photoExts: Set<String> = ["jpg", "jpeg", "heic", "png"]
    static let skipFolders: Set<String> = ["lasso-engine", "_Lasso preview", ".lasso"]

    static func isMedia(_ url: URL) -> Bool {
        let e = url.pathExtension.lowercased()
        return videoExts.contains(e) || photoExts.contains(e)
    }

    static func mediaFiles(in folder: URL, excluding: [URL]) -> [URL] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let excluded = excluding.map { $0.standardizedFileURL.path }
        var out: [URL] = []
        for case let url as URL in en {
            let path = url.standardizedFileURL.path
            if excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) || skipFolders.contains(url.lastPathComponent) {
                en.skipDescendants(); continue
            }
            if isMedia(url) { out.append(url) }
        }
        return out.sorted { $0.path < $1.path }
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    /// Same size and same first and last megabyte = the same file.
    static func fingerprint(_ url: URL, size: Int64) -> String {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return UUID().uuidString }
        defer { try? fh.close() }
        var hasher = Insecure.SHA1()
        hasher.update(data: Data(String(size).utf8))
        if let d = try? fh.read(upToCount: 1 << 20) { hasher.update(data: d) }
        if size > 2 << 20 {
            try? fh.seek(toOffset: UInt64(size) - UInt64(1 << 20))
            if let d = try? fh.read(upToCount: 1 << 20) { hasher.update(data: d) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Fingerprints of everything already in the library, to skip files that were wrangled before.
    static func libraryFingerprints(_ library: URL) -> [String: String] {
        var out: [String: String] = [:]
        for url in mediaFiles(in: library, excluding: []) {
            out[fingerprint(url, size: fileSize(url))] = "your library/" + url.lastPathComponent
        }
        return out
    }

    static func sourceLabel(for url: URL, source: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let root = source.standardizedFileURL.path
        if parent == root { return source.lastPathComponent }
        return source.lastPathComponent + "/" + parent.replacingOccurrences(of: root + "/", with: "")
    }

    static func cleanToken(_ s: String, fallback: String) -> String {
        let k = s.filter { $0.isLetter || $0.isNumber }
        return k.isEmpty ? fallback : k
    }

    /// Reads and analyses one file. Runs off the main thread.
    static func analyze(_ url: URL, source: URL, detection: Bool) async -> WrangleItem {
        let isVideo = videoExts.contains(url.pathExtension.lowercased())
        let modified = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date) ?? Date()
        var item = WrangleItem(url: url, sourceURL: source, sourceLabel: sourceLabel(for: url, source: source),
                               isVideo: isVideo, created: modified, dateFromFile: true)
        item.bytes = fileSize(url)
        if isVideo {
            guard let meta = await MediaAnalyzer.videoMeta(url) else { return item }
            item.duration = meta.duration
            item.fps = meta.fps
            item.pixelSize = meta.size
            if let m = meta.model { item.camera = cleanToken(m, fallback: "Phone") }
            if let c = meta.created { item.created = c; item.dateFromFile = false }
            item.gps = await Places.videoGPS(url)
            guard detection else { item.type = .broll; item.confident = false; return item }
            var a = Analysis()
            var audio = MediaAnalyzer.AudioResult()
            if meta.hasAudio { audio = await MediaAnalyzer.audio(url) }
            let speech = MediaAnalyzer.speechStats(audio)
            a.speechShare = speech.share
            a.longestRun = speech.longest
            let people = await MediaAnalyzer.people(url, duration: meta.duration)
            a.faceShare = people.faceShare
            a.faceSize = people.faceSize
            a.personShare = people.personShare
            let cuts = await MediaAnalyzer.cuts(url, duration: meta.duration)
            a.cuts = cuts.count
            a.narrated = MediaAnalyzer.narrationCarriesOverCuts(cuts, audio: audio)
            item.analysis = a
            let (type, confident) = Classifier.classify(fps: meta.fps, a: a)
            item.type = type
            item.confident = confident
        } else {
            let meta = MediaAnalyzer.photoMeta(url)
            item.pixelSize = meta.size
            if let m = meta.model { item.camera = cleanToken(m, fallback: "Phone") }
            if let c = meta.created { item.created = c; item.dateFromFile = false }
            item.gps = Places.photoGPS(url)
            item.type = .photo
            item.confident = true
        }
        return item
    }

    struct NamingOptions {
        var order: [NameToken]
        var location: String
        var project: String
        var library: URL
        var mode: RenameMode
        /// Ticked files get their numbers first, so a wrangled selection is numbered 001, 002, … with no gaps.
        var priority: Set<UUID> = []
    }

    /// Gives every file its new name, following the naming pattern.
    /// Numbers continue from files already in the destination, so nothing clashes.
    static func assignNames(_ items: inout [WrangleItem], _ o: NamingOptions) {
        let fm = FileManager.default
        let runLocation = cleanToken(o.location, fallback: "NoLocation")
        let proj = cleanToken(o.project, fallback: "Project")
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        let hm = DateFormatter(); hm.dateFormat = "HHmm"
        var counters: [String: Int] = [:]
        var used = Set<String>()
        let order = items.indices.filter { items[$0].duplicateOf == nil }.sorted { a, b in
            let pa = o.priority.contains(items[a].id), pb = o.priority.contains(items[b].id)
            return pa != pb ? pa : items[a].created < items[b].created
        }
        for i in order {
            let d = day.string(from: items[i].created)
            let loc = items[i].manualLocation ?? items[i].place ?? runLocation
            items[i].location = loc
            let folder: URL
            switch o.mode {
            case .copy, .move:
                folder = o.library
                    .appendingPathComponent(String(d.prefix(4)))
                    .appendingPathComponent("\(d.prefix(7))_\(loc)")
                    .appendingPathComponent(items[i].type.folder)
            case .inPlace:
                folder = items[i].url.deletingLastPathComponent()
            }
            let key = folder.path + "|" + d + items[i].type.code
            var seq = counters[key, default: 0]
            var name = ""
            var attempt = 0
            repeat {
                seq += 1
                attempt += 1
                let parts: [String] = o.order.map { t in
                    switch t {
                    case .date: return d
                    case .location: return loc
                    case .type: return items[i].type.code
                    case .seq: return String(format: "%03d", seq)
                    case .time: return hm.string(from: items[i].created)
                    case .camera: return items[i].camera
                    case .project: return proj
                    }
                }
                var base = parts.joined(separator: "_")
                if !o.order.contains(.seq) && attempt > 1 { base += "-\(attempt)" }
                name = base + "." + items[i].ext
                let target = folder.appendingPathComponent(name).path
                let isSelf = o.mode == .inPlace && target == items[i].url.path
                if (!fm.fileExists(atPath: target) || isSelf) && !used.contains(target) { break }
            } while attempt < 9999
            counters[key] = seq
            items[i].newName = name
            items[i].destination = folder.appendingPathComponent(name)
            used.insert(folder.appendingPathComponent(name).path)
        }
    }

    struct ApplyOptions {
        var mode: RenameMode
        var library: URL
        var writeTags: Bool
        var keepLog: Bool
        var location: String
        var transcribe = false
    }

    struct LogEntry: Codable {
        let from: String; let to: String; let mode: String; let date: Date
        /// Move only: where the original went in the Trash, so it can be put back.
        var trashed: String? = nil
    }

    /// Copies, moves or renames files. Never deletes anything permanently:
    /// in Move mode the original goes to the Trash, and only after its copy has been checked.
    static func apply(_ items: [WrangleItem], _ o: ApplyOptions) async -> (done: Int, skipped: [String], placed: [(url: URL, type: FootageType)]) {
        let fm = FileManager.default
        var done = 0
        var skipped: [String] = []
        var log: [LogEntry] = []
        var placed: [(url: URL, type: FootageType)] = []
        for item in items where item.duplicateOf == nil {
            guard let dest = item.destination else { continue }
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) && dest.path != item.url.path {
                    skipped.append("\(item.url.lastPathComponent): a file named \(dest.lastPathComponent) already exists")
                    continue
                }
                var trashedTo: String? = nil
                switch o.mode {
                case .copy:
                    try fm.copyItem(at: item.url, to: dest)
                case .move:
                    try fm.copyItem(at: item.url, to: dest)
                    // Check the copy byte for byte before the original goes anywhere.
                    guard fm.contentsEqual(atPath: item.url.path, andPath: dest.path) else {
                        try? fm.removeItem(at: dest)   // only the faulty copy Lasso just made
                        skipped.append("\(item.url.lastPathComponent): the copy didn't match the original, so the original was kept")
                        continue
                    }
                    var trashURL: NSURL? = nil
                    do {
                        try fm.trashItem(at: item.url, resultingItemURL: &trashURL)
                        trashedTo = trashURL?.path
                    } catch {
                        skipped.append("\(item.url.lastPathComponent): copied, but the original couldn't be moved to the Trash")
                    }
                case .inPlace:
                    if dest.path != item.url.path { try fm.moveItem(at: item.url, to: dest) }
                }
                if o.writeTags {
                    // Finder tags (works on every supported macOS version)
                    let tags = [item.type.label, item.location.isEmpty ? cleanToken(o.location, fallback: "NoLocation") : item.location]
                    try? (dest as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
                }
                log.append(LogEntry(from: item.url.path, to: dest.path, mode: o.mode.rawValue, date: Date(), trashed: trashedTo))
                done += 1
                placed.append((dest, item.type))
            } catch {
                skipped.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if o.keepLog && !log.isEmpty {
            let dir = o.library.appendingPathComponent(".lasso/rename-logs")
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]; enc.dateEncodingStrategy = .iso8601
            if let data = try? enc.encode(log) { try? data.write(to: dir.appendingPathComponent("rename-\(stamp).json")) }
        }
        return (done, skipped, placed)
    }

    // MARK: Library

    static let namePattern = try! NSRegularExpression(pattern: "^(\\d{4}-\\d{2}-\\d{2})_([A-Za-z0-9]+)_([A-Z]+)_(\\d{3})")

    /// New path → original file name, read from the rename logs.
    static func previousNames(_ library: URL) -> [String: String] {
        let dir = library.appendingPathComponent(".lasso/rename-logs")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        var out: [String: String] = [:]
        for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f), let entries = try? dec.decode([LogEntry].self, from: data) else { continue }
            for e in entries {
                out[URL(fileURLWithPath: e.to).standardizedFileURL.path] = URL(fileURLWithPath: e.from).lastPathComponent
            }
        }
        return out
    }

    static func libraryFiles(library: URL, sources: [URL], people: [String: [String]] = [:]) -> [LibraryFile] {
        var out: [LibraryFile] = []
        var roots: [(URL, Bool)] = [(library, true)]
        roots += sources.filter { $0.standardizedFileURL.path != library.standardizedFileURL.path }.map { ($0, false) }
        // Originals that were already copied into the library are shown once, as the library copy,
        // not again as a "not wrangled" file in their source folder.
        let inLibrary = roots.count > 1 ? Set(libraryFingerprints(library).keys) : []
        let previous = previousNames(library)
        for (root, isLibrary) in roots {
            let reachable = FileManager.default.fileExists(atPath: root.path)
            for url in mediaFiles(in: root, excluding: isLibrary ? [] : [library]) {
                if !isLibrary && reachable && inLibrary.contains(fingerprint(url, size: fileSize(url))) { continue }
                let name = url.lastPathComponent
                let video = videoExts.contains(url.pathExtension.lowercased())
                let range = NSRange(name.startIndex..., in: name)
                if let m = namePattern.firstMatch(in: name, range: range) {
                    func g(_ i: Int) -> String { (Range(m.range(at: i), in: name)).map { String(name[$0]) } ?? "" }
                    out.append(LibraryFile(url: url, name: name, type: FootageType.from(code: g(3)), date: g(1), location: g(2),
                                           standardized: true, bytes: fileSize(url), folder: url.deletingLastPathComponent().path,
                                           isOffline: !reachable, isVideo: video,
                                           transcript: video ? Transcriber.transcriptText(for: url) : nil,
                                           previousName: previous[url.standardizedFileURL.path],
                                           people: people.isEmpty ? [] : (people[fingerprint(url, size: fileSize(url))] ?? [])))
                } else if !isLibrary {
                    out.append(LibraryFile(url: url, name: name, type: nil, date: "", location: "", standardized: false,
                                           bytes: fileSize(url), folder: url.deletingLastPathComponent().path,
                                           isOffline: !reachable, isVideo: video,
                                           people: people.isEmpty || !reachable ? [] : (people[fingerprint(url, size: fileSize(url))] ?? [])))
                }
            }
        }
        return out.sorted { ($0.date, $0.name) > ($1.date, $1.name) }
    }
}
