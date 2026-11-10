import SwiftUI
import AppKit

/// First-run setup: Welcome, Detection, Library location, Source folders, Naming pattern, First scan.
struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @State private var step = 0
    @State private var useLassoFolder = true
    @State private var candidates: [SourceCandidate] = []
    @State private var chosen: Set<URL> = []

    private let stepNames = ["Welcome", "Detection and transcription add-ons", "Library location",
                             "Source folders", "Naming pattern", "First scan"]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch step {
                case 0: IntroAnimation().padding(.horizontal, 32)
                case 1: detectionStep
                case 2: libraryStep
                case 3: sourcesStep
                case 4: namingStep
                default: scanStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Theme.line).frame(height: 1)
            footer
        }
        .background(Theme.cream)
        .onAppear(perform: loadCandidates)
    }

    // MARK: Top bar and footer

    private var topBar: some View {
        HStack {
            Text("\u{2002}\u{2002}Lasso ").font(.wordmark(40)).fixedSize().padding(.leading, -24)
                .frame(width: 160, alignment: .leading)
            Spacer()
            HStack(spacing: 8) {
                ForEach(stepNames.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Theme.denim : (i < step ? Color(hex: "3D6E9E") : Color(hex: "CBBFA6")))
                        .frame(width: i == step ? 28 : 8, height: 8)
                        .accessibilityLabel(stepNames[i] + (i == step ? ", current step" : i < step ? ", done" : ""))
                }
            }
            .animation(.easeOut(duration: 0.2), value: step)
            Spacer()
            Text("Step \(step + 1) of 6").font(.inter(13)).foregroundStyle(Theme.slate)
                .frame(width: 160, alignment: .trailing)
        }
        .padding(.horizontal, 32).padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { go(-1) }.buttonStyle(SecondaryButtonStyle())
                    .disabled(step == 5 && app.isWorking)
            }
            Spacer()
            if step == 0 {
                Button("Skip intro") { go(1) }.buttonStyle(.plain).foregroundStyle(Theme.slate).padding(.trailing, 12)
            }
            if step < 5 {
                Button(step == 0 ? "Get started" : (step == 4 ? "Scan my folders" : "Continue")) { go(1) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Open Wrangle Files") {
                    app.tab = .wrangle
                    app.onboardingNamingDue = true
                    app.onboarded = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(app.isWorking)
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 18)
        .overlay(alignment: .center) { downloadBadge }
    }

    /// Shows the add-on download while setup continues.
    @ViewBuilder private var downloadBadge: some View {
        if let p = app.modelProgress {
            HStack(spacing: 8) {
                ProgressView(value: p).frame(width: 120)
                Text("Downloading transcription add-on… \(Int(p * 100))%").font(.inter(12.5)).foregroundStyle(Theme.slate)
            }
        } else if step > 1 && app.transcribe && app.modelInstalled {
            Label("Transcription add-on ready", systemImage: "checkmark.circle.fill")
                .font(.inter(12.5)).foregroundStyle(Color(hex: "5B7A57"))
        }
    }

    private func go(_ delta: Int) {
        // Save each step's choices as the user leaves it.
        // Leaving the add-ons step with transcription ticked starts the model download straight away;
        // it carries on in the background through the rest of setup.
        if step == 1 && delta > 0 && app.transcribe && !app.modelInstalled && app.modelProgress == nil {
            Task { await app.downloadModel() }
        }
        if step == 2 { applyLibraryChoice() }
        if step == 3 { applySources() }
        step = max(0, min(5, step + delta))
        if step == 5 && delta > 0 { app.analyze() }
    }

    // MARK: Steps

    private func stepTitle(_ s: String) -> some View {
        Text(s).font(.fraunces(36, .semibold))
    }
    private func lead(_ s: String) -> some View {
        Text(s).font(.inter(16)).lineSpacing(5).foregroundStyle(Color(hex: "2E4562"))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var detectionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Detection and transcription add-ons")
            lead("Lasso runs entirely on your Mac, but needs additional add-ons to support its full function. Your existing files’ details and the add-ons will enhance your ability to organize and search files.")
            optionCard(isOn: $app.detection, title: "Detect speech and likeness add-ons",
                       detail: "Suggests footage type (b-roll, voice over, etc.) for each clip. Uses current features from your Mac.")
            optionCard(isOn: $app.transcribe, title: "Transcribe footage add-ons",
                       detail: "Saves a searchable text file with each clip. One-time download of about 0.5 GB.")
            optionCard(isOn: $app.faceGrouping, title: "Group people by face add-ons",
                       detail: "Identify the people who appear in your photos and videos so you can search for them by name. Uses current features from your Mac for facial mapping.")
            if !app.detection {
                Text("With detection off, you’ll set every footage type by hand. You can turn it on later in Settings.")
                    .font(.inter(14))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "F7EBB0")).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: 680)
    }

    private func optionCard(isOn: Binding<Bool>, title: String, detail: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.inter(15, .semibold))
                Text(detail).font(.inter(14)).foregroundStyle(Theme.slate)
            }
            .padding(.leading, 6)
        }
        .toggleStyle(.checkbox)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var libraryStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Choose your library location")
            lead("This is where Lasso keeps organized copies of your files. You can change it later in Settings.")
            HStack(alignment: .top, spacing: 14) {
                libraryCard(lasso: true, title: "Lasso folder", path: "~/Pictures/Lasso",
                            detail: "A dedicated folder that holds only what Lasso organizes. Easy to back up or move.")
                libraryCard(lasso: false, title: "Pictures folder", path: "~/Pictures",
                            detail: "Your Mac’s standard Pictures folder, alongside anything already there.")
            }
            Text("Lasso never adds files inside the Apple Photos library, which Photos manages on its own.")
                .font(.inter(13)).foregroundStyle(Theme.slate)
        }
        .frame(maxWidth: 760)
    }

    private func libraryCard(lasso: Bool, title: String, path: String, detail: String) -> some View {
        let on = useLassoFolder == lasso
        return Button { useLassoFolder = lasso } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.inter(16, .semibold))
                    Spacer()
                    if lasso {
                        Text("Recommended").font(.inter(12, .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Theme.gold).clipShape(Capsule())
                    }
                }
                Text(path).font(.mono(13))
                Text(detail).font(.inter(14)).foregroundStyle(Theme.slate).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.denim : Theme.line, lineWidth: 2))
            .background(RoundedRectangle(cornerRadius: 14).stroke(on ? Theme.powderLight : .clear, lineWidth: 8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func applyLibraryChoice() {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        app.libraryURL = useLassoFolder ? pictures.appendingPathComponent("Lasso") : pictures
    }

    private var sourcesStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Add source folders")
            lead("Point Lasso at the places your footage lands. We recommend starting with no more than 3 folders. You can add more anytime.")
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(candidates) { c in sourceRow(c) }
                }
            }
            .frame(maxHeight: 300)
            HStack {
                Button("+ Choose another folder…", action: chooseFolder)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16).frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "9FB7CC"), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                if hasHistory {
                    Button("Clear History", action: clearHistory)
                        .buttonStyle(.plain)
                        .font(.inter(13.5, .semibold)).foregroundStyle(Color(hex: "3D6E9E"))
                        .padding(.leading, 8)
                        .help("Remove folders added before and untick everything. Nothing changes until you continue.")
                }
                Spacer()
                let n = chosen.count
                Text(n > 3 ? "\(n) selected · more than 3 can slow your first scan" : "\(n) selected")
                    .font(.inter(14))
                    .foregroundStyle(n > 3 ? Theme.denim : Theme.slate)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(n > 3 ? Color(hex: "F7EBB0") : Color.clear)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: 700)
    }

    private func sourceRow(_ c: SourceCandidate) -> some View {
        let on = chosen.contains(c.url)
        return Toggle(isOn: Binding(get: { on }, set: { v in if v { chosen.insert(c.url) } else { chosen.remove(c.url) } })) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.inter(15, .semibold))
                    Text((c.url.path as NSString).abbreviatingWithTildeInPath).font(.mono(12.5)).foregroundStyle(Theme.slate)
                }
                .padding(.leading, 6)
                Spacer()
                Text(c.note).font(.inter(13)).foregroundStyle(Theme.slate)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color(hex: "3D6E9E") : Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// The standard places offered to everyone: Desktop, Downloads, Movies and connected drives.
    private var standardCandidates: [SourceCandidate] {
        let fm = FileManager.default
        var list: [SourceCandidate] = []
        for dir in [FileManager.SearchPathDirectory.desktopDirectory, .downloadsDirectory, .moviesDirectory] {
            if let url = fm.urls(for: dir, in: .userDomainMask).first {
                list.append(SourceCandidate(url: url, name: url.lastPathComponent, note: ""))
            }
        }
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsInternalKey, .volumeLocalizedNameKey]
        for vol in fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [] {
            guard vol.path.hasPrefix("/Volumes/") else { continue }
            let v = try? vol.resourceValues(forKeys: Set(keys))
            let note = v?.volumeIsRemovable == true ? "Removable" : (v?.volumeIsInternal == false ? "External drive" : "")
            list.append(SourceCandidate(url: vol, name: v?.volumeLocalizedName ?? vol.lastPathComponent, note: note))
        }
        return list
    }

    /// Folders added in the past (beyond the standard places), or anything ticked.
    private var hasHistory: Bool {
        candidates.count > standardCandidates.count || !chosen.isEmpty
    }

    /// "Clear History": back to the standard places with nothing ticked. Saved when the user continues.
    private func clearHistory() {
        candidates = standardCandidates
        chosen = []
    }

    private func loadCandidates() {
        guard candidates.isEmpty else { return }
        let fm = FileManager.default
        var list: [SourceCandidate] = []
        for dir in [FileManager.SearchPathDirectory.desktopDirectory, .downloadsDirectory, .moviesDirectory] {
            if let url = fm.urls(for: dir, in: .userDomainMask).first {
                list.append(SourceCandidate(url: url, name: url.lastPathComponent, note: ""))
            }
        }
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsInternalKey, .volumeLocalizedNameKey]
        for vol in fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [] {
            guard vol.path.hasPrefix("/Volumes/") else { continue }
            let v = try? vol.resourceValues(forKeys: Set(keys))
            let note = v?.volumeIsRemovable == true ? "Removable" : (v?.volumeIsInternal == false ? "External drive" : "")
            list.append(SourceCandidate(url: vol, name: v?.volumeLocalizedName ?? vol.lastPathComponent, note: note))
        }
        for s in app.sources where !list.contains(where: { $0.url.standardizedFileURL == s.standardizedFileURL }) {
            list.append(SourceCandidate(url: s, name: s.lastPathComponent, note: ""))
        }
        candidates = list
        chosen = Set(list.map(\.url).filter { u in app.sources.contains { $0.standardizedFileURL == u.standardizedFileURL } })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose the folders that hold photos and videos to wrangle."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if !candidates.contains(where: { $0.url == url }) {
                candidates.append(SourceCandidate(url: url, name: url.lastPathComponent, note: ""))
            }
            chosen.insert(url)
        }
    }

    private func applySources() {
        // Keep the on-screen order; drop folders that were unticked.
        app.sources = candidates.map(\.url).filter { chosen.contains($0) }
    }

    private var namingStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Naming pattern")
            lead("Every file Lasso wrangles gets a standardized name, so it sorts and searches the same way everywhere.")
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(Array(app.order.enumerated()), id: \.offset) { i, token in
                        Text(token.label).font(.mono(15))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.powderLight).clipShape(RoundedRectangle(cornerRadius: 8))
                        if i < app.order.count - 1 { Text("_").font(.mono(15)).foregroundStyle(Theme.slate) }
                    }
                }
                HStack(spacing: 8) {
                    Text("→").foregroundStyle(Theme.slate)
                    Text("2026-11-04_Belleville_BROLL_001.mp4").font(.mono(15, .medium))
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("You can reorder or swap in the filename segments such as Time, Camera, or Project later from Settings or the Wrangle Files tab.")
                .font(.inter(14)).foregroundStyle(Theme.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 700)
    }

    private var scanStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle(app.isWorking ? "Scanning your folders…" : "Scan complete")
            ProgressView(value: app.isWorking ? app.progress : 1)
                .progressViewStyle(.linear)
                .tint(Color(hex: "ED643F"))
            if app.isWorking {
                Text(app.status).font(.inter(13)).foregroundStyle(Theme.slate).lineLimit(1)
            }
            HStack(spacing: 12) {
                counter("Source folders", app.sources.count, highlight: false)
                counter("Files found", app.items.count, highlight: false)
                counter("Needs wrangling", app.pendingCount, highlight: true)
            }
            if !app.isWorking {
                Text("Your \(app.items.count) files are now centrally visible in the tab Library. Open the tab Wrangle Files whenever you're ready to begin organizing your \(app.pendingCount) files.")
                    .font(.inter(15)).foregroundStyle(Color(hex: "2E4562"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 640)
    }

    private func counter(_ label: String, _ n: Int, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.inter(13)).foregroundStyle(highlight ? Theme.denim : Theme.slate)
            Text("\(n)").font(.fraunces(32, .semibold))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? Color(hex: "F7EBB0") : Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlight ? Theme.gold : Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SourceCandidate: Identifiable {
    var id: URL { url }
    let url: URL
    let name: String
    let note: String
}
