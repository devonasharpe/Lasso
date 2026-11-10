import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    enum Section: String, CaseIterable, Identifiable {
        case library = "Library", naming = "File Naming and Labels", importDefaults = "Import defaults",
             detection = "Detection and transcripts", people = "People", drives = "Drives", resources = "Resources"
        var id: String { rawValue }
    }
    @State private var section: Section = .library
    @State private var newProject = ""
    @State private var newLocation = ""
    @State private var confirmDelete = false
    @State private var wipeData = false

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings").font(Theme.title).padding(.bottom, 12)
                ForEach(Section.allCases.filter { $0 != .resources }) { s in navButton(s) }
                Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 14)
                navButton(.resources)
                Button { wipeData = false; confirmDelete = true } label: {
                    Label("Delete Lasso…", systemImage: "trash")
                        .font(.inter(14, .semibold))
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "E8C9C5"), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .frame(width: 250)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch section {
                    case .library: librarySection
                    case .naming: namingSection
                    case .importDefaults: importSection
                    case .detection: detectionSection
                    case .people: peopleSection
                    case .drives: drivesSection
                    case .resources: resourcesSection
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
            }
        }
        .padding(28)
        .sheet(isPresented: $confirmDelete) { deleteSheet }
    }

    private func navButton(_ s: Section) -> some View {
        Button { section = s } label: {
            Text(s.rawValue)
                .font(.inter(14.5, section == s ? .semibold : .regular))
                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(section == s ? Theme.powder : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Library location").font(.inter(13.5, .semibold))
                    Text("Where Lasso keeps organized copies. It's recommended to only use Lasso's default folder or your system Pictures folder.").foregroundStyle(Theme.slate)
                    HStack {
                        Text((app.libraryURL.path as NSString).abbreviatingWithTildeInPath).font(Theme.mono).textSelection(.enabled)
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.libraryURL]) }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Change…") { app.chooseLibrary() }.buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(12).background(Theme.cream).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Changing it affects new imports only. Files already in the old location stay there.")
                        .font(.inter(11.5)).foregroundStyle(Theme.slate)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Source folders").font(.inter(13.5, .semibold))
                        Spacer()
                        Button("+ Add folder…") { app.addSources() }.buttonStyle(SecondaryButtonStyle())
                    }
                    ForEach(app.sources, id: \.self) { url in
                        HStack(spacing: 10) {
                            Circle().fill(app.isOnline(url) ? Color(hex: "5B7A57") : Color(hex: "9A968E")).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent).font(.inter(14, .semibold))
                                Text((url.path as NSString).abbreviatingWithTildeInPath).font(.mono(11.5)).foregroundStyle(Theme.slate)
                            }
                            Spacer()
                            Button("Remove") { app.removeSource(url) }.buttonStyle(.plain).foregroundStyle(Theme.red)
                        }
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                    }
                    Text("Removing a folder only stops Lasso from watching it. Your files stay where they are.")
                        .font(.inter(11.5)).foregroundStyle(Theme.slate)
                }
            }
        }
    }

    private var namingSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Naming pattern").font(.inter(13.5, .semibold))
                    Text(app.order.map(\.label).joined(separator: "_")).font(.mono(14))
                    HStack {
                        Text("Change the order on the Wrangle Files screen.").font(.inter(11.5)).foregroundStyle(Theme.slate)
                        Spacer()
                        if app.order != NameToken.defaultOrder {
                            Button("Reset to default") { app.resetOrder() }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 20) {
                listCard(title: "Projects", items: $app.projects, draft: $newProject, placeholder: "SpringCampaign")
                listCard(title: "Locations", items: $app.savedLocations, draft: $newLocation, placeholder: "Concorde")
            }
        }
    }

    private func listCard(title: String, items: Binding<[String]>, draft: Binding<String>, placeholder: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.inter(13.5, .semibold))
                ForEach(items.wrappedValue, id: \.self) { value in
                    HStack {
                        Text(value).font(.inter(13.5))
                        Spacer()
                        Button { items.wrappedValue.removeAll { $0 == value } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundStyle(Theme.slate).help("Remove \(value)")
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Theme.cream).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    TextField(placeholder, text: draft).textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let v = Wrangler.cleanToken(draft.wrappedValue, fallback: "")
                        if !v.isEmpty && !items.wrappedValue.contains(v) { items.wrappedValue.append(v) }
                        draft.wrappedValue = ""
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var importSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import defaults").font(.inter(13.5, .semibold))
                Picker("When renaming", selection: $app.mode) {
                    ForEach(RenameMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Rectangle().fill(Theme.line).frame(height: 1)
                Toggle("Write tags into the files so your global Finder can search them", isOn: $app.writeTags).toggleStyle(.checkbox)
                Toggle("Keep a log of old → new names", isOn: $app.keepLog).toggleStyle(.checkbox)
                Toggle("Skip duplicates already in the library", isOn: $app.skipLibraryDuplicates).toggleStyle(.checkbox)
            }
        }
    }

    private var detectionSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Detection and transcripts").font(.inter(13.5, .semibold))
                    .task { await app.refreshLibrary() }
                Text("Everything runs on your Mac. Nothing is uploaded to a server.").foregroundStyle(Theme.slate)
                Toggle(isOn: $app.detection) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detect speech, faces and people").font(.inter(14, .semibold))
                        Text("Suggests a footage type for each clip. With this off, you set every type by hand.")
                            .font(.inter(12.5)).foregroundStyle(Theme.slate)
                    }
                }
                .toggleStyle(.checkbox)
                Toggle(isOn: $app.transcribe) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcribe footage (Whisper)").font(.inter(14, .semibold))
                        Text("Saves a searchable text file with each clip that has speech. Uses the Fast model, a one-time download of about 0.5 GB.")
                            .font(.inter(12.5)).foregroundStyle(Theme.slate)
                    }
                }
                .toggleStyle(.checkbox)
                HStack(spacing: 10) {
                    if let p = app.modelProgress {
                        ProgressView(value: p).frame(width: 200)
                        Text("Downloading the model… \(Int(p * 100))%").font(.inter(12.5)).foregroundStyle(Theme.slate)
                    } else if app.modelInstalled {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: "5B7A57"))
                        Text("Model downloaded").font(.inter(12.5)).foregroundStyle(Theme.slate)
                    } else {
                        Text("Not downloaded yet. It downloads the first time Lasso transcribes a clip.")
                            .font(.inter(12.5)).foregroundStyle(Theme.slate)
                        Button("Download now") { Task { await app.downloadModel() } }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.leading, 22)
                if app.transcribe {
                    HStack(spacing: 10) {
                        let waiting = app.untranscribedClips.count
                        Button("Transcribe \(waiting) library \(waiting == 1 ? "clip" : "clips")") { app.transcribeLibrary() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(waiting == 0 || app.isWorking)
                        Text("For clips wrangled before transcription was on.").font(.inter(12.5)).foregroundStyle(Theme.slate)
                    }
                    .padding(.leading, 22)
                    if app.isWorking && !app.status.isEmpty {
                        Text(app.status).font(.inter(12.5)).foregroundStyle(Theme.slate).lineLimit(2).padding(.leading, 22)
                    } else if !app.transcribeResult.isEmpty {
                        Text(app.transcribeResult).font(.inter(12.5)).foregroundStyle(Theme.denim)
                            .fixedSize(horizontal: false, vertical: true).padding(.leading, 22)
                    }
                }
            }
        }
    }

    @State private var confirmFaceDelete = false
    @State private var personToRemove: Person? = nil
    @State private var legalDoc: LegalDoc? = nil
    @State private var renaming: UUID? = nil
    @State private var newName = ""

    private var peopleSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("People").font(.inter(13.5, .semibold))
                Text("Lasso can enhance your ability to search photos and videos by identifying people in your images and videos. The mapping information for people you choose to label is kept only on this Mac. Names are never sent to the cloud, placed into the file name, or added to global Finder tags.")
                    .foregroundStyle(Theme.slate).fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: $app.faceGrouping) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Group people by face").font(.inter(14, .semibold))
                        Text("After each analysis, Lasso will ask you to name new people if they've been identified in at least two files. If you choose not to identify someone, you will not be asked to identify that person in the future.")
                            .font(.inter(12.5)).foregroundStyle(Theme.slate)
                    .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)
                if app.faceGrouping {
                    if app.faceData.people.isEmpty {
                        Text("No one named yet.").font(.inter(13)).foregroundStyle(Theme.slate).padding(.leading, 22)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(app.faceData.people) { p in
                                HStack {
                                    if renaming == p.id {
                                        TextField("Name", text: $newName, onCommit: {
                                            app.renamePerson(p, to: newName); renaming = nil
                                        })
                                        .textFieldStyle(.roundedBorder).frame(width: 200)
                                        Button("Save") { app.renamePerson(p, to: newName); renaming = nil }
                                            .buttonStyle(SecondaryButtonStyle())
                                        Button("Cancel") { renaming = nil }
                                            .buttonStyle(.plain).foregroundStyle(Theme.slate)
                                    } else {
                                        Text(p.name + (p.isMe ? " (me)" : "")).font(.inter(14, .semibold))
                                        Button { newName = p.name; renaming = p.id } label: {
                                            Image(systemName: "pencil").font(.system(size: 12, weight: .semibold))
                                        }
                                        .buttonStyle(.plain).foregroundStyle(Color(hex: "3D6E9E"))
                                        .help("Rename \(p.name)")
                                    }
                                    Spacer()
                                    let n = app.fileCount(of: p)
                                    Text("\(n) \(n == 1 ? "file" : "files")").foregroundStyle(Theme.slate)
                                    Button { personToRemove = p } label: {
                                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                                            .frame(width: 22, height: 22)
                                            .background(Theme.surface)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain).foregroundStyle(Theme.slate)
                                    .help("Remove \(p.name)'s face data")
                                    .padding(.leading, 6)
                                }
                                .padding(.horizontal, 12).frame(minHeight: 34)
                                .background(Theme.cream).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.leading, 22)
                    }
                    HStack(spacing: 10) {
                        Button("Look for people in your library") { app.scanLibraryForPeople() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(app.isWorking)
                        if app.isWorking && !app.status.isEmpty {
                            Text(app.status).font(.inter(12.5)).foregroundStyle(Theme.slate).lineLimit(1)
                        }
                    }
                    .padding(.leading, 22)
                    .task { await app.refreshLibrary() }
                }
                Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4)
                Button("Delete All Face Mapping Data") { confirmFaceDelete = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .foregroundStyle(Theme.red)
                Text("By clicking this button, you will delete all names and facial mapping data associated with your images and videos. Your files, however, will not be changed or deleted.")
                    .font(.inter(12)).foregroundStyle(Theme.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("Remove \(personToRemove?.name ?? "")?", isPresented: Binding(get: { personToRemove != nil }, set: { if !$0 { personToRemove = nil } })) {
            Button("Cancel", role: .cancel) { personToRemove = nil }
            Button("Remove", role: .destructive) {
                if let p = personToRemove { app.removePerson(p) }
                personToRemove = nil
            }
        } message: {
            Text("Lasso forgets this person's name, faceprints and face pictures, and won't ask about them again. Their photos and videos aren't touched.")
        }
        .alert("Delete all face mapping data?", isPresented: $confirmFaceDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { app.deleteAllFaceData() }
        } message: {
            Text("Every name and all facial mapping data are removed from this Mac. This can't be undone. Your files aren't changed.")
        }
    }

    private var drivesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Drives").font(.inter(13.5, .semibold))
                Text("Lasso recognizes each drive by its built-in ID, so a drive that's been renamed is still matched to your library.")
                    .foregroundStyle(Theme.slate).fixedSize(horizontal: false, vertical: true)
                if app.drives.isEmpty {
                    Text("No external drives yet. Add a folder on a drive or card from the Library section and it appears here.")
                        .font(.inter(13)).foregroundStyle(Theme.slate)
                }
                ForEach(app.drives, id: \.uuid) { drive in
                    let mounted = Drives.mountedVolumes().first { Drives.uuid(of: $0) == drive.uuid }
                    HStack(spacing: 10) {
                        Circle().fill(mounted != nil ? Color(hex: "5B7A57") : Color(hex: "9A968E")).frame(width: 9, height: 9)
                        Text(drive.name).font(.inter(14, .semibold))
                        Spacer()
                        Text(mounted != nil ? "online" : "offline").foregroundStyle(Theme.slate)
                        if let volume = mounted {
                            Button("Eject") { app.disconnectDrive(name: drive.name, volume: volume) }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var resourcesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Resources").font(.inter(13.5, .semibold))
                Text("Lasso is built with help from Claude and the open-source projects listed below:")
                    .font(.inter(15)).lineSpacing(3)
                credit("Apple Vision, SoundAnalysis and AVFoundation", "Face, people and speech detection, built into macOS.", "Built in")
                credit("Opus Motion Library by Govindu Sasanka", "The intro animation's motion, adapted from “Voxel burst swirl.”", "MIT")
                credit("WhisperKit by Argmax", "On-device Whisper transcription of clips with speech.", "MIT")
                credit("SFace (OpenCV Zoo)", "On-device face matching for grouping people.", "Apache 2.0")
                credit("ONNX Runtime by Microsoft", "Runs the face model on your Mac.", "MIT")
                credit("Fraunces, Inter, Sacramento and JetBrains Mono", "Lasso's fonts. License texts are included in the app.", "SIL Open Font License")
                HStack(spacing: 18) {
                    LegalLink(title: "Terms of Use and Privacy") { legalDoc = .terms }
                    LegalLink(title: "Open-source Licenses") { legalDoc = .licenses }
                }
                .padding(.top, 4)
                // Sign-off
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thank you to the true Megabrains whose work made it possible for me to create Lasso.")
                        .font(.inter(15)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Spacer()
                        Text("—").font(.inter(15))
                        Text("\u{2002}Devona Sharpe ").font(.wordmark(26)).fixedSize().padding(.leading, -10)
                    }
                    .padding(.top, 6).padding(.trailing, 12)
                }
                .padding(.top, 28)
            }
        }
        .sheet(item: $legalDoc) { doc in LegalDocView(doc: doc) }
    }

    private func credit(_ name: String, _ use: String, _ license: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.inter(14.5, .semibold))
                Text(use).font(.inter(13)).foregroundStyle(Theme.slate)
            }
            Spacer()
            Text(license).font(.inter(11.5, .semibold))
                .padding(.horizontal, 10).padding(.vertical, 3).background(Theme.powderLight).clipShape(Capsule())
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: Delete Lasso

    private var deleteSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "trash").font(.system(size: 20)).foregroundStyle(Theme.red)
                .frame(width: 44, height: 44).background(Color(hex: "F3DCD9")).clipShape(RoundedRectangle(cornerRadius: 12))
            Text("Are you sure you want to delete Lasso?").font(.fraunces(22, .semibold))
            Text("The app will be moved to the Trash. Your photos and videos, including your Lasso folder, stay exactly where they are.")
                .foregroundStyle(Theme.slate).fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $wipeData) {
                Text("Remove Lasso’s catalog, thumbnails and AI models. You'll begin with a fresh slate if you decide to reinstall Lasso.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
            .padding(12).background(Theme.cream).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                Spacer()
                Button("Cancel") { confirmDelete = false }.buttonStyle(SecondaryButtonStyle())
                Button("Yes, delete") { deleteLasso() }
                    .buttonStyle(PrimaryButtonStyle()).tint(Theme.red)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.surface)
        .foregroundStyle(Theme.denim)
    }

    private func deleteLasso() {
        var urls = [Bundle.main.bundleURL]
        if wipeData {
            urls.append(app.libraryURL.appendingPathComponent(".lasso"))
            urls.append(Transcriber.modelsBase.deletingLastPathComponent())   // Application Support/Lasso: the AI model
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        }
        NSWorkspace.shared.recycle(urls) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}


/// A text link that opens a file, underlined on hover like a web link.
private struct LegalLink: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.inter(14, .medium))
                .underline(hovering)
                .foregroundStyle(Color(hex: "3D6E9E"))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityAddTraits(.isLink)
    }
}
