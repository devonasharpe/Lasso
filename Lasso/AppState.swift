import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    enum Tab { case library, wrangle, settings }

    @Published var tab: Tab = .wrangle { didSet { presentNamingIfReady() } }

    // Settings, remembered between launches
    @Published var libraryURL: URL { didSet { save(); renumber() } }
    @Published var sources: [URL] { didSet { save() } }
    @Published var location: String { didSet { save(); renumber() } }
    @Published var mode: RenameMode { didSet { save(); renumber() } }
    @Published var order: [NameToken] { didSet { save(); renumber() } }
    @Published var project: String { didSet { save(); renumber() } }
    @Published var projects: [String] { didSet { save() } }
    @Published var savedLocations: [String] { didSet { save() } }
    @Published var writeTags: Bool { didSet { save() } }
    @Published var keepLog: Bool { didSet { save() } }
    @Published var skipLibraryDuplicates: Bool { didSet { save() } }
    @Published var detection: Bool { didSet { save() } }
    @Published var transcribe: Bool { didSet { save() } }
    /// False until the user finishes the Welcome steps.
    @Published var onboarded: Bool { didSet { save(); presentNamingIfReady() } }
    /// The one-time welcome cards on Library and Wrangle Files.
    @Published var seenLibraryIntro: Bool { didSet { save(); presentNamingIfReady() } }
    @Published var seenWrangleIntro: Bool { didSet { save(); presentNamingIfReady() } }
    /// Drives and cards Lasso has seen, by built-in ID.
    @Published var drives: [DriveRecord] { didSet { save() } }
    @Published var driveAlert: DriveAlert? = nil

    // People (face grouping). Off until the user turns it on.
    @Published var faceGrouping: Bool { didSet { save() } }
    @Published var faceData = Faces.load()
    @Published var faceGroups: [FaceGroup] = []
    @Published var faceConfirms: [FaceConfirm] = []
    @Published var showNaming = false
    /// New people are waiting to be named; the window opens once no welcome step or card is in the way.
    var namingPending = false
    /// Set when the Welcome steps finish: the window always appears once during first run,
    /// with an example when there's no one to name yet, so the feature is easy to discover.
    var onboardingNamingDue = false

    func presentNamingIfReady() {
        guard namingPending || onboardingNamingDue, !showNaming, onboarded else { return }
        if tab == .wrangle && !seenWrangleIntro { return }
        if tab == .library && !seenLibraryIntro { return }
        namingPending = false
        onboardingNamingDue = false
        showNaming = true
    }

    /// From the example window: turn face mapping on and look through the files already found.
    func turnOnFaceMapping() {
        faceGrouping = true
        showNaming = false
        let files = items.map { ($0.url, $0.isVideo) } + libraryFiles.filter { !$0.isOffline }.map { ($0.url, $0.isVideo) }
        Task { await scanForPeople(files) }
    }
    private var watchingDrives = false

    // Transcription model
    @Published var modelInstalled = Transcriber.installedModelFolder() != nil
    /// 0…1 while the model downloads, nil otherwise.
    @Published var modelProgress: Double? = nil
    /// Files the user removed from Wrangle Files. Lasso leaves them alone until they're shown again.
    @Published var hiddenPaths: Set<String> { didSet { save() } }

    // Wrangle Files
    @Published var items: [WrangleItem] = []
    @Published var selectedSource: URL? = nil { didSet { renumber() } }
    @Published var checked: Set<WrangleItem.ID> = [] {
        didSet {
            if visibleChecked == 0 && locationInput != location { locationInput = location }
            if checked != oldValue { renumber() }
        }
    }
    /// What's typed in the Location field. With no files ticked it is the default location
    /// and updates the names straight away. With files ticked it is only a draft for Apply.
    @Published var locationInput: String = "" {
        didSet { if visibleChecked == 0 && location != locationInput { location = locationInput } }
    }
    /// Locations set by hand for ticked files, keyed by file path. Kept through Analyze again.
    @Published var manualLocations: [String: String] = [:]
    @Published var isWorking = false
    /// True while Analyze (and the people check that follows it) is running, so it can be stopped.
    @Published var isAnalyzing = false
    private var stopRequested = false
    @Published var progress = 0.0
    @Published var status = "" { didSet { if !status.isEmpty { showAnalysisSummary = false } } }
    /// After Analyze, the action panel shows the count for the folder on screen instead of a fixed message.
    @Published var showAnalysisSummary = false

    // Library
    @Published var libraryFiles: [LibraryFile] = []

    init() {
        let d = UserDefaults.standard
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        libraryURL = d.string(forKey: "libraryPath").map { URL(fileURLWithPath: $0) } ?? pictures.appendingPathComponent("Lasso")
        sources = (d.stringArray(forKey: "sources") ?? []).map { URL(fileURLWithPath: $0) }
        location = d.string(forKey: "location") ?? "NoLocation"
        mode = RenameMode(rawValue: d.string(forKey: "mode") ?? "") ?? .copy
        let savedOrder = (d.stringArray(forKey: "order") ?? []).compactMap { NameToken(rawValue: $0) }
        order = savedOrder.count == 4 ? savedOrder : NameToken.defaultOrder
        project = d.string(forKey: "project") ?? "ParisReel"
        projects = d.stringArray(forKey: "projects") ?? ["ParisReel"]
        savedLocations = d.stringArray(forKey: "savedLocations") ?? ["NoLocation"]
        writeTags = d.object(forKey: "writeTags") as? Bool ?? true
        keepLog = d.object(forKey: "keepLog") as? Bool ?? true
        skipLibraryDuplicates = d.object(forKey: "skipLibraryDuplicates") as? Bool ?? true
        detection = d.object(forKey: "detection") as? Bool ?? true
        transcribe = d.object(forKey: "transcribe") as? Bool ?? true
        onboarded = d.bool(forKey: "onboarded")
        seenLibraryIntro = d.bool(forKey: "seenLibraryIntro")
        seenWrangleIntro = d.bool(forKey: "seenWrangleIntro")
        faceGrouping = d.bool(forKey: "faceGrouping")
        drives = (d.data(forKey: "drives")).flatMap { try? JSONDecoder().decode([DriveRecord].self, from: $0) } ?? []
        hiddenPaths = Set(d.stringArray(forKey: "hiddenPaths") ?? [])
        locationInput = location
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(libraryURL.path, forKey: "libraryPath")
        d.set(sources.map(\.path), forKey: "sources")
        d.set(location, forKey: "location")
        d.set(mode.rawValue, forKey: "mode")
        d.set(order.map(\.rawValue), forKey: "order")
        d.set(project, forKey: "project")
        d.set(projects, forKey: "projects")
        d.set(savedLocations, forKey: "savedLocations")
        d.removeObject(forKey: "zipCopy")
        d.set(writeTags, forKey: "writeTags")
        d.set(keepLog, forKey: "keepLog")
        d.set(skipLibraryDuplicates, forKey: "skipLibraryDuplicates")
        d.set(detection, forKey: "detection")
        d.set(transcribe, forKey: "transcribe")
        d.set(onboarded, forKey: "onboarded")
        d.set(seenLibraryIntro, forKey: "seenLibraryIntro")
        d.set(seenWrangleIntro, forKey: "seenWrangleIntro")
        d.set(try? JSONEncoder().encode(drives), forKey: "drives")
        d.set(faceGrouping, forKey: "faceGrouping")
        d.set(Array(hiddenPaths), forKey: "hiddenPaths")
    }

    // MARK: Counts

    var pendingCount: Int { items.filter { $0.duplicateOf == nil }.count }

    /// The folder shown on Wrangle Files: one source folder at a time.
    var currentSource: URL? {
        if let s = selectedSource, sources.contains(s) { return s }
        return sources.first(where: { s in items.contains { $0.sourceURL == s && $0.duplicateOf == nil } }) ?? sources.first
    }
    var visibleItems: [WrangleItem] { items.filter { $0.sourceURL == currentSource } }
    var visiblePending: Int { visibleItems.filter { $0.duplicateOf == nil }.count }
    var visibleNeedsInput: Int { visibleItems.filter(\.needsInput).count }
    func pending(in source: URL) -> Int { items.filter { $0.sourceURL == source && $0.duplicateOf == nil }.count }
    func isOnline(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// What the wrangle button acts on: only the ticked files. Unticked files are left alone.
    var wrangleBatch: [WrangleItem] {
        visibleItems.filter { checked.contains($0.id) }
    }
    var batchIsSelection: Bool { visibleItems.contains { checked.contains($0.id) } }
    var batchPending: Int { wrangleBatch.filter { $0.duplicateOf == nil }.count }
    var batchNeedsInput: Int { wrangleBatch.filter(\.needsInput).count }

    var canApply: Bool {
        guard let s = currentSource else { return false }
        return !isWorking && isOnline(s) && batchPending > 0 && batchNeedsInput == 0
    }
    /// True when the folder on screen is on a drive that can't be written to (a locked card, a read-only disk).
    var currentSourceReadOnly: Bool {
        guard let s = currentSource, isOnline(s) else { return false }
        if (try? s.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true { return true }
        return !FileManager.default.isWritableFile(atPath: s.path)
    }
    /// On a read-only drive files can only be copied, whatever is chosen under Safety.
    var effectiveMode: RenameMode { currentSourceReadOnly ? .copy : mode }

    var primaryLabel: String {
        if let s = currentSource, !isOnline(s) { return "Drive offline" }
        if batchNeedsInput > 0 { return "Confirm \(batchNeedsInput) \(batchNeedsInput == 1 ? "type" : "types") first" }
        let n = batchPending
        if visiblePending == 0 { return "Nothing to wrangle" }
        if n == 0 { return "Select files to wrangle" }
        let files = "\(n) selected \(n == 1 ? "file" : "files")"
        switch effectiveMode {
        case .copy: return "Rename and copy \(files)"
        case .move: return "Rename and move \(files)"
        case .inPlace: return "Rename \(files) in place"
        }
    }

    /// "Where files will go": each destination folder with how many files land there.
    var destinationSummary: [(folder: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in visibleItems where item.duplicateOf == nil {
            guard let dest = item.destination else { continue }
            let folder = dest.deletingLastPathComponent().path
            let shown = folder.hasPrefix(libraryURL.path)
                ? libraryURL.lastPathComponent + String(folder.dropFirst(libraryURL.path.count))
                : (folder as NSString).abbreviatingWithTildeInPath
            counts[shown, default: 0] += 1
        }
        return counts.keys.sorted().map { ($0, counts[$0]!) }
    }

    // MARK: Folders

    func addSources() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose the folders that hold photos and videos to wrangle."
        if panel.runModal() == .OK {
            for url in panel.urls where !sources.contains(url) { sources.append(url) }
        }
    }

    // MARK: Removing files from the list

    var visibleChecked: Int { visibleItems.filter { checked.contains($0.id) }.count }
    var allVisibleChecked: Bool { !visibleItems.isEmpty && visibleChecked == visibleItems.count }

    func toggleChecked(_ id: WrangleItem.ID) {
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    }
    func setAllChecked(_ on: Bool) {
        let ids = Set(visibleItems.map(\.id))
        if on { checked.formUnion(ids) } else { checked.subtract(ids) }
    }
    func removeChecked() {
        let removing = items.filter { checked.contains($0.id) }
        guard !removing.isEmpty else { return }
        hiddenPaths.formUnion(removing.map { $0.url.standardizedFileURL.path })
        items.removeAll { checked.contains($0.id) }
        checked = []
        renumber()
        status = "Removed \(removing.count) \(removing.count == 1 ? "file" : "files") from the list. The files themselves weren't touched."
    }
    // MARK: Location for ticked files

    var typedLocation: String { Wrangler.cleanToken(locationInput, fallback: "") }
    var canApplyLocation: Bool {
        visibleChecked > 0 && !typedLocation.isEmpty && typedLocation != "NoLocation"
    }
    var checkedWithManualLocation: Int {
        visibleItems.filter { checked.contains($0.id) && $0.manualLocation != nil }.count
    }
    func applyLocationToChecked() {
        let value = typedLocation
        guard canApplyLocation else { return }
        let targets = visibleItems.filter { checked.contains($0.id) }
        for item in targets { manualLocations[item.url.standardizedFileURL.path] = value }
        locationInput = location   // the field goes back to showing the default
        renumber()
        status = "Set the location to \(value) for \(targets.count) \(targets.count == 1 ? "file" : "files")."
    }
    func clearLocationForChecked() {
        let targets = visibleItems.filter { checked.contains($0.id) && $0.manualLocation != nil }
        guard !targets.isEmpty else { return }
        for item in targets { manualLocations.removeValue(forKey: item.url.standardizedFileURL.path) }
        renumber()
        status = "Cleared the location you set for \(targets.count) \(targets.count == 1 ? "file" : "files")."
    }

    func hiddenCount(in source: URL?) -> Int {
        guard let s = source else { return 0 }
        let root = s.standardizedFileURL.path + "/"
        return hiddenPaths.filter { $0.hasPrefix(root) }.count
    }
    func showHidden(in source: URL?) {
        guard let s = source else { return }
        let root = s.standardizedFileURL.path + "/"
        hiddenPaths = hiddenPaths.filter { !$0.hasPrefix(root) }
        analyze()
    }

    func removeSource(_ url: URL) {
        sources.removeAll { $0 == url }
        items.removeAll { $0.sourceURL == url }
        // The last result described folders that have changed, so it no longer applies.
        if !isWorking { status = "" }
    }

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        panel.message = "Choose where Lasso keeps organized copies."
        if panel.runModal() == .OK, let url = panel.url { libraryURL = url }
    }

    // MARK: Naming pattern

    func moveToken(at i: Int, by delta: Int) {
        let j = i + delta
        guard order.indices.contains(i), order.indices.contains(j) else { return }
        order.swapAt(i, j)
    }
    func replaceToken(at i: Int, with t: NameToken) {
        guard order.indices.contains(i) else { return }
        order[i] = t
    }
    func resetOrder() { order = NameToken.defaultOrder }

    func addProject(_ name: String) {
        let clean = Wrangler.cleanToken(name, fallback: "")
        guard !clean.isEmpty else { return }
        if !projects.contains(clean) { projects.append(clean) }
        project = clean
    }

    // MARK: Wrangle

    /// Stops Analyze after the file it is on. Files already analyzed stay in the list.
    func stopAnalysis() {
        guard isAnalyzing else { return }
        stopRequested = true
        status = "Stopping after this file…"
    }

    func analyze() {
        guard !isWorking else { return }
        isWorking = true
        isAnalyzing = true
        stopRequested = false
        progress = 0
        items = []
        checked = []
        status = "Looking for photos and videos…"
        let sources = self.sources.filter { isOnline($0) }
        let library = libraryURL
        let detection = self.detection
        let skipLibrary = skipLibraryDuplicates
        Task {
            var seen: [String: String] = [:]
            if skipLibrary {
                self.status = "Checking what's already in your library…"
                seen = await Task.detached { Wrangler.libraryFingerprints(library) }.value
            }
            var found: [(URL, URL)] = []
            let hidden = self.hiddenPaths
            for s in sources {
                found += Wrangler.mediaFiles(in: s, excluding: [library])
                    .filter { !hidden.contains($0.path) && !hidden.contains($0.standardizedFileURL.path) }
                    .map { (s, $0) }
            }
            var results: [WrangleItem] = []
            for (i, pair) in found.enumerated() {
                if self.stopRequested { break }
                let (source, url) = pair
                self.status = "Analyzing \(url.lastPathComponent) (\(i + 1) of \(found.count))"
                self.progress = Double(i) / Double(max(found.count, 1))
                let size = Wrangler.fileSize(url)
                let fp = await Task.detached { Wrangler.fingerprint(url, size: size) }.value
                if let first = seen[fp] {
                    var dup = WrangleItem(url: url, sourceURL: source, sourceLabel: Wrangler.sourceLabel(for: url, source: source),
                                          isVideo: Wrangler.videoExts.contains(url.pathExtension.lowercased()),
                                          created: Date(), dateFromFile: false)
                    dup.duplicateOf = first
                    results.append(dup)
                    continue
                }
                var item = await Task.detached { await Wrangler.analyze(url, source: source, detection: detection) }.value
                if let g = item.gps {
                    self.status = "Finding where \(url.lastPathComponent) was taken…"
                    item.place = await PlaceNamer.shared.name(for: g)
                }
                seen[fp] = item.sourceLabel + "/" + url.lastPathComponent
                results.append(item)
            }
            self.items = results
            self.renumber()
            self.progress = 1
            self.isWorking = false
            if self.stopRequested {
                let n = results.count
                self.status = "Analysis stopped. \(n) of \(found.count) files were analyzed. Click Analyze again to start over."
                self.stopRequested = false
                self.isAnalyzing = false
                return
            }
            let dups = results.filter { $0.duplicateOf != nil }.count
            if results.isEmpty {
                self.status = "No photos or videos found in these folders."
            } else {
                _ = dups
                self.status = ""
                self.showAnalysisSummary = true
            }
            if self.faceGrouping && !results.isEmpty {
                // Every file found, duplicates included: a file already in the library may never have been
                // checked for people. Files checked before are skipped by fingerprint, so nothing is done twice.
                await self.scanForPeople(results.map { ($0.url, Wrangler.videoExts.contains($0.url.pathExtension.lowercased())) })
                if self.stopRequested {
                    self.status = "Stopped looking for people. Click Analyze again to finish."
                }
            }
            self.stopRequested = false
            self.isAnalyzing = false
        }
    }

    // MARK: People

    /// File fingerprint → names of the people in it.
    var peopleByFingerprint: [String: [String]] {
        let names = Dictionary(uniqueKeysWithValues: faceData.people.map { ($0.id, $0.name) })
        var out: [String: Set<String>] = [:]
        for f in faceData.faces {
            if let pid = f.personID, let n = names[pid] { out[f.fingerprint, default: []].insert(n) }
        }
        return out.mapValues { $0.sorted() }
    }

    func fileCount(of person: Person) -> Int {
        Set(faceData.faces.filter { $0.personID == person.id }.map(\.fingerprint)).count
    }

    /// Looks for faces in files Lasso hasn't looked at yet, recognises known people silently,
    /// and opens the naming window for new people and uncertain matches.
    func scanForPeople(_ files: [(URL, Bool)]) async {
        guard faceGrouping, !files.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        var data = faceData
        var found: [FaceRecord] = []
        for (i, file) in files.enumerated() {
            if stopRequested { break }
            let (url, isVideo) = file
            let fp = await Task.detached { Wrangler.fingerprint(url, size: Wrangler.fileSize(url)) }.value
            if data.scanned.contains(fp) { continue }
            status = "Looking for people in \(url.lastPathComponent) (\(i + 1) of \(files.count))…"
            progress = Double(i) / Double(files.count)
            found += await FaceScanner.shared.scan(url, fingerprint: fp, isVideo: isVideo)
            data.scanned.insert(fp)
        }
        progress = 1

        // Known people
        let named: [(Person, [Float])] = data.people.map { p in
            (p, Faces.centroid(data.faces.filter { $0.personID == p.id }.map(\.embedding)))
        }
        var maybe: [UUID: [FaceRecord]] = [:]
        var unknown: [FaceRecord] = []
        var recognised: [String: Set<String>] = [:]
        for var f in found {
            let best = named.map { ($0.0, Faces.cosine($0.1, f.embedding)) }.max { $0.1 < $1.1 }
            let ignoredSim = data.ignored.map { Faces.cosine($0, f.embedding) }.max() ?? -1
            if ignoredSim >= Faces.sureMatch && ignoredSim > (best?.1 ?? -1) {
                try? FileManager.default.removeItem(at: Faces.thumbURL(f))     // "Don't track this person"
                continue
            }
            if let b = best, b.1 >= Faces.sureMatch {
                f.personID = b.0.id
                data.faces.append(f)
                recognised[b.0.name, default: []].insert(f.fingerprint)
            } else if let b = best, b.1 >= Faces.maybeMatch {
                maybe[b.0.id, default: []].append(f)
            } else {
                unknown.append(f)
            }
        }

        // New people: groups seen in at least 2 files. Others wait, unnamed, for more files.
        let pending = data.faces.filter { $0.personID == nil } + unknown
        data.faces.removeAll { $0.personID == nil }
        let clusters = await Task.detached { Faces.cluster(pending) }.value
        var groups: [FaceGroup] = []
        for c in clusters {
            if Set(c.map(\.fingerprint)).count >= 2 { groups.append(FaceGroup(faces: c)) } else { data.faces += c }
        }
        let confirms: [FaceConfirm] = maybe.compactMap { pid, faces in
            data.people.first { $0.id == pid }.map { FaceConfirm(faces: faces, person: $0) }
        }

        faceData = data
        Faces.save(data)
        if !recognised.isEmpty {
            status = "Found " + recognised.map { "\($0.key) in \($0.value.count) \($0.value.count == 1 ? "file" : "files")" }
                .sorted().joined(separator: ", ") + "."
        } else if !showAnalysisSummary {
            status = ""
            showAnalysisSummary = true
        }
        if !groups.isEmpty || !confirms.isEmpty {
            faceGroups = groups.sorted { $0.fileCount > $1.fileCount }
            faceConfirms = confirms
            namingPending = true
            presentNamingIfReady()
        }
        await refreshLibrary()
    }

    /// Looks for people in everything already in the library (Settings › People).
    func scanLibraryForPeople() {
        let files = libraryFiles.filter { !$0.isOffline }.map { ($0.url, $0.isVideo) }
        Task { await scanForPeople(files) }
    }

    private func person(named raw: String, isMe: Bool, in data: inout FaceData) -> UUID {
        let name = raw.trimmingCharacters(in: .whitespaces)
        if let p = data.people.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if isMe, let i = data.people.firstIndex(of: p) { data.people[i].isMe = true }
            return p.id
        }
        let p = Person(name: name, isMe: isMe)
        data.people.append(p)
        return p.id
    }

    /// Closes the naming window. Unnamed people aren't tracked and aren't asked about again.
    func finishNaming(trackNobody: Bool) {
        var data = faceData
        func forget(_ faces: [FaceRecord], remember: Bool) {
            for f in faces { try? FileManager.default.removeItem(at: Faces.thumbURL(f)) }
            if remember, !faces.isEmpty { data.ignored.append(Faces.centroid(faces.map(\.embedding))) }
        }
        func assign(_ faces: [FaceRecord], to id: UUID) {
            data.faces += faces.map { var f = $0; f.personID = id; return f }
        }
        for c in faceConfirms {
            let other = c.otherName.trimmingCharacters(in: .whitespaces)
            if trackNobody { forget(c.faces, remember: false); continue }
            switch c.answer {
            case true?: assign(c.faces, to: c.person.id)
            case false? where !other.isEmpty: assign(c.faces, to: person(named: other, isMe: false, in: &data))
            case false?: forget(c.faces, remember: true)
            case nil: forget(c.faces, remember: false)
            }
        }
        for g in faceGroups {
            let name = g.name.trimmingCharacters(in: .whitespaces)
            if !trackNobody && g.track && !name.isEmpty {
                assign(g.faces, to: person(named: name, isMe: g.isMe, in: &data))
            } else {
                forget(g.faces, remember: true)
            }
        }
        faceData = data
        Faces.save(data)
        faceGroups = []
        faceConfirms = []
        showNaming = false
        Task { await refreshLibrary() }
    }

    /// Renames a person. If another person already has that name, the two are merged into one.
    func renamePerson(_ p: Person, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != p.name else { return }
        var data = faceData
        if let other = data.people.first(where: { $0.id != p.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            for i in data.faces.indices where data.faces[i].personID == p.id { data.faces[i].personID = other.id }
            if p.isMe, let j = data.people.firstIndex(where: { $0.id == other.id }) { data.people[j].isMe = true }
            data.people.removeAll { $0.id == p.id }
        } else if let i = data.people.firstIndex(where: { $0.id == p.id }) {
            data.people[i].name = name
        }
        faceData = data
        Faces.save(data)
        Task { await refreshLibrary() }
    }

    /// Forgets one person: their name, faceprints and face pictures. Lasso won't ask about them again.
    func removePerson(_ p: Person) {
        var data = faceData
        let theirs = data.faces.filter { $0.personID == p.id }
        for f in theirs { try? FileManager.default.removeItem(at: Faces.thumbURL(f)) }
        if !theirs.isEmpty { data.ignored.append(Faces.centroid(theirs.map(\.embedding))) }
        data.faces.removeAll { $0.personID == p.id }
        data.people.removeAll { $0.id == p.id }
        faceData = data
        Faces.save(data)
        Task { await refreshLibrary() }
    }

    func deleteAllFaceData() {
        Faces.deleteAll()
        faceData = FaceData()
        faceGroups = []
        faceConfirms = []
        Task { await refreshLibrary() }
    }

    func renumber() {
        guard !items.isEmpty else { return }
        var copy = items
        for i in copy.indices { copy[i].manualLocation = manualLocations[copy[i].url.standardizedFileURL.path] }
        Wrangler.assignNames(&copy, .init(order: order, location: location, project: project, library: libraryURL,
                                          mode: effectiveMode, priority: checked))
        items = copy
    }

    func setType(_ id: WrangleItem.ID, _ type: FootageType) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].type = type
        items[i].accepted = true
        renumber()
    }

    func accept(_ id: WrangleItem.ID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].accepted = true
        renumber()
    }

    func apply() {
        guard canApply, let source = currentSource else { return }
        let mode = effectiveMode
        if mode == .move && !confirmMove(count: batchPending) { return }
        isWorking = true
        switch mode {
        case .copy: status = "Copying files into your library…"
        case .move: status = "Moving files into your library…"
        case .inPlace: status = "Renaming files…"
        }
        let batch = wrangleBatch
        let batchIDs = Set(batch.map(\.id))
        let opts = Wrangler.ApplyOptions(mode: mode, library: libraryURL, writeTags: writeTags, keepLog: keepLog,
                                         location: location, transcribe: transcribe)
        Task {
            let result = await Task.detached { await Wrangler.apply(batch, opts) }.value
            self.isWorking = false
            for item in batch { self.manualLocations.removeValue(forKey: item.url.standardizedFileURL.path) }
            // Only the wrangled files leave the list; anything left unticked stays for later.
            self.items.removeAll { batchIDs.contains($0.id) }
            self.checked.subtract(batchIDs)
            if !self.items.contains(where: { $0.sourceURL == source }) { self.selectedSource = nil }
            var msg: String
            switch opts.mode {
            case .copy: msg = "\(result.done) files renamed and copied to your library."
            case .move: msg = "\(result.done) files renamed and moved to your library. The originals are in the Trash."
            case .inPlace: msg = "\(result.done) files renamed in place."
            }
            if !result.skipped.isEmpty { msg += " \(result.skipped.count) skipped: " + result.skipped.joined(separator: "; ") }
            self.status = msg
            self.renumber()
            // First time through: after the first wrangle, show the Library (and its welcome card) next.
            let firstVisit = !self.seenLibraryIntro && result.done > 0
            if opts.transcribe {
                await self.transcribeClips(result.placed.filter { Transcriber.wantsTranscript($0.type) }.map(\.url))
            }
            await self.refreshLibrary()
            if firstVisit { self.tab = .library }
        }
    }

    // MARK: Transcription

    /// Downloads Whisper's model once. Returns false if it couldn't.
    @discardableResult
    func downloadModel() async -> Bool {
        if modelInstalled { return true }
        modelProgress = 0
        defer { modelProgress = nil }
        do {
            _ = try await Transcriber.shared.ensureModel { p in
                Task { @MainActor in self.modelProgress = p }
            }
            modelInstalled = true
            return true
        } catch {
            status = "The transcription model couldn't be downloaded. Check your internet connection, then try again from Settings."
            return false
        }
    }

    /// Library clips with speech that don't have a transcript yet.
    var untranscribedClips: [URL] {
        libraryFiles.filter { f in
            f.standardized && f.isVideo && !f.isOffline && f.transcript == nil
                && (f.type.map(Transcriber.wantsTranscript) ?? false)
        }.map(\.url)
    }

    /// What happened the last time library clips were transcribed from Settings.
    @Published var transcribeResult = ""

    func transcribeLibrary() {
        let clips = untranscribedClips
        guard !clips.isEmpty, !isWorking else { return }
        transcribeResult = ""
        status = "Library:"
        Task {
            await transcribeClips(clips)
            await refreshLibrary()
            transcribeResult = lastTranscribeSummary
        }
    }

    private var lastTranscribeSummary = ""

    /// Writes a .srt transcript next to each clip that has speech.
    func transcribeClips(_ clips: [URL]) async {
        guard !clips.isEmpty else { return }
        let summary = status
        isWorking = true
        defer { isWorking = false }
        if !modelInstalled {
            status = "Downloading the transcription model (about 0.5 GB, one time only)…"
            guard await downloadModel() else { return }
        }
        var made = 0
        var noSpeech: [String] = []
        var failed: [String] = []
        for (i, clip) in clips.enumerated() {
            status = "Transcribing \(clip.lastPathComponent) (\(i + 1) of \(clips.count))…"
            progress = Double(i) / Double(clips.count)
            do {
                let lines = try await Transcriber.shared.transcribe(clip)
                if try Transcriber.writeSRT(lines, for: clip) { made += 1 } else { noSpeech.append(clip.lastPathComponent) }
            } catch {
                failed.append("\(clip.lastPathComponent) (\(error.localizedDescription))")
            }
        }
        progress = 1
        var msg = "\(made) \(made == 1 ? "transcript" : "transcripts") saved."
        if !noSpeech.isEmpty { msg += " No speech was heard in " + noSpeech.joined(separator: ", ") + "." }
        if !failed.isEmpty { msg += " Couldn't transcribe " + failed.joined(separator: "; ") + "." }
        lastTranscribeSummary = msg
        status = summary + " " + msg
    }

    /// Asks once before Move mode sends originals to the Trash, unless the user chose "Don't ask again".
    private func confirmMove(count: Int) -> Bool {
        let key = "skipMoveConfirm"
        if UserDefaults.standard.bool(forKey: key) { return true }
        let alert = NSAlert()
        alert.messageText = "Move \(count) \(count == 1 ? "file" : "files") to your library?"
        alert.informativeText = "Your file will be cloned and then moved. One copy goes to the library and is checked, and the other moves to the Trash where you can restore it or delete it.\n\nFiles from a drive or card stay in that drive's Trash, so the space is freed once you empty it."
        alert.addButton(withTitle: "Move files")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let ok = alert.runModal() == .alertFirstButtonReturn
        if ok && alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: key) }
        return ok
    }

    // MARK: Drives

    /// Watches for drives being plugged in, removed or renamed.
    func startDriveWatching() {
        guard !watchingDrives else { return }
        watchingDrives = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.checkDrives() }
            }
        }
        checkDrives()
    }

    func checkDrives() {
        // Remember the built-in ID of every drive that holds a source folder.
        for s in sources {
            guard let v = Drives.volumeRoot(of: s), isOnline(v), let id = Drives.uuid(of: v) else { continue }
            if !drives.contains(where: { $0.uuid == id }) { drives.append(DriveRecord(uuid: id, name: v.lastPathComponent)) }
        }
        objectWillChange.send()   // online / offline badges
        guard driveAlert == nil else { return }
        // A known drive that's plugged in under a different name.
        for v in Drives.mountedVolumes() {
            guard let id = Drives.uuid(of: v), let rec = drives.first(where: { $0.uuid == id }),
                  rec.name != v.lastPathComponent else { continue }
            driveAlert = .renamed(uuid: id, oldName: rec.name, newName: v.lastPathComponent, volume: v)
            return
        }
    }

    /// "Yes, continue": every folder, removed file and location on the drive follows the new name.
    func acceptDriveRename(uuid: String, from old: String, to new: String) {
        let oldRoot = "/Volumes/" + old, newRoot = "/Volumes/" + new
        func swap(_ path: String) -> String {
            path == oldRoot || path.hasPrefix(oldRoot + "/") ? newRoot + String(path.dropFirst(oldRoot.count)) : path
        }
        sources = sources.map { URL(fileURLWithPath: swap($0.standardizedFileURL.path), isDirectory: true) }
        if let s = selectedSource { selectedSource = URL(fileURLWithPath: swap(s.standardizedFileURL.path), isDirectory: true) }
        hiddenPaths = Set(hiddenPaths.map(swap))
        manualLocations = Dictionary(manualLocations.map { (swap($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
        if let i = drives.firstIndex(where: { $0.uuid == uuid }) { drives[i].name = new }
        driveAlert = nil
        status = "“\(new)” is the same drive as “\(old)”. Your library now uses the new name."
        Task { await refreshLibrary() }
        checkDrives()
    }

    /// "No, disconnect" and "Try again": safely ejects, or lists the apps that are in the way.
    func disconnectDrive(name: String, volume: URL) {
        driveAlert = nil
        Task {
            let ejected = await Task.detached { Drives.eject(volume) }.value
            if ejected {
                self.status = "“\(name)” was ejected. You can unplug it now."
                return
            }
            let users = await Task.detached { Drives.users(of: volume) }.value
            self.driveAlert = .blocked(name: name, volume: volume, users: users)
        }
    }

    // MARK: Library

    func refreshLibrary() async {
        let library = libraryURL
        let sources = self.sources
        let people = peopleByFingerprint
        libraryFiles = await Task.detached { Wrangler.libraryFiles(library: library, sources: sources, people: people) }.value
    }

    func copy(_ files: [LibraryFile]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Copy here"
        panel.message = "Choose a folder for copies of \(files.count) files."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        var n = 0
        for f in files {
            let dest = folder.appendingPathComponent(f.name)
            if !FileManager.default.fileExists(atPath: dest.path), (try? FileManager.default.copyItem(at: f.url, to: dest)) != nil {
                n += 1
                let srt = f.url.deletingPathExtension().appendingPathExtension("srt")
                if FileManager.default.fileExists(atPath: srt.path) {
                    try? FileManager.default.copyItem(at: srt, to: dest.deletingPathExtension().appendingPathExtension("srt"))
                }
            }
        }
        status = "Copied \(n) files to \(folder.lastPathComponent)."
    }

    func moveToTrash(_ files: [LibraryFile]) {
        // A clip's transcript goes with it.
        let srts = files.map { $0.url.deletingPathExtension().appendingPathExtension("srt") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        NSWorkspace.shared.recycle(files.map(\.url) + srts) { _, _ in
            Task { @MainActor in await self.refreshLibrary() }
        }
    }

    /// The file shown in the Quick Look window (the same preview as pressing Space in Finder).
    @Published var previewURL: URL?

    func preview(_ url: URL) {
        previewURL = url
    }
}
