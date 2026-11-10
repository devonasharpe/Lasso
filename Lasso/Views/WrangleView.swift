import SwiftUI

struct WrangleView: View {
    @EnvironmentObject var app: AppState
    @State private var slot: Int? = nil
    @State private var newProject = ""
    @State private var addingProject = false

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                mainColumn.frame(maxWidth: .infinity, alignment: .leading)
                sideColumn.frame(width: 340)
            }
            .padding(28)
        }
    }

    // MARK: Main column

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.currentSource?.lastPathComponent ?? "Wrangle Files").font(Theme.title)
                    if let s = app.currentSource {
                        HStack(spacing: 8) {
                            Text((s.path as NSString).abbreviatingWithTildeInPath).font(.mono(12))
                            Circle().fill(app.isOnline(s) ? Color(hex: "5B7A57") : Color(hex: "9A968E")).frame(width: 8, height: 8)
                            Text(app.isOnline(s) ? "online" : "offline")
                        }
                        .foregroundStyle(Theme.slate).font(.inter(12))
                    }
                }
                Spacer()
            }

            patternCard

            // Instructions (when there's nothing to list) come before the action panel.
            if app.visibleItems.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.sources.isEmpty ? "Add a folder to get started" : "Nothing here needs wrangling").font(.inter(13.5, .semibold))
                        let hidden = app.hiddenCount(in: app.currentSource)
                        if hidden > 0 {
                            Text("You removed \(hidden) \(hidden == 1 ? "file" : "files") from this folder's view list. Click the button below to view the \(hidden == 1 ? "file" : "files") again.")
                                .foregroundStyle(Theme.slate)
                            Button("Show \(hidden) removed") { app.showHidden(in: app.currentSource) }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(app.isWorking)
                        } else {
                            Text("Add the folders that hold your photos and videos, then click Analyze. Lasso suggests a type and a new name for each file. Nothing is renamed until you confirm.")
                                .foregroundStyle(Theme.slate)
                        }
                    }
                }
            }

            // The action button, with status messages and progress to its right.
            ActionPanel()

            if !app.visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Button { app.setAllChecked(!app.allVisibleChecked) } label: {
                            Image(systemName: app.allVisibleChecked ? "checkmark.square.fill"
                                  : app.visibleChecked > 0 ? "minus.square.fill" : "square")
                                .font(.inter(17))
                                .foregroundStyle(app.visibleChecked > 0 ? Theme.denim : Theme.slate)
                        }
                        .buttonStyle(.plain)
                        .help(app.allVisibleChecked ? "Deselect all" : "Select all")
                        Text("\(app.visiblePending) \(app.visiblePending == 1 ? "file needs" : "files need") wrangling").font(.inter(13.5, .semibold))
                        if app.visibleChecked > 0 {
                            Button("Remove \(app.visibleChecked) from list") { app.removeChecked() }
                                .buttonStyle(SecondaryButtonStyle())
                                .help("Lasso won't wrangle these files. The files themselves aren't touched.")
                        }
                        let hidden = app.hiddenCount(in: app.currentSource)
                        if hidden > 0 {
                            Button("Show \(hidden) removed") { app.showHidden(in: app.currentSource) }
                                .buttonStyle(.plain).foregroundStyle(Color(hex: "3D6E9E"))
                                .font(.inter(13, .semibold))
                                .disabled(app.isWorking)
                        }
                        Spacer()
                        if app.visibleNeedsInput > 0 {
                            Text("Accept the suggestion or pick another type for outlined rows")
                                .font(.inter(12.5)).foregroundStyle(Theme.slate)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    // Column headings, lined up with the rows below
                    HStack(spacing: 14) {
                        Color.clear.frame(width: 17, height: 1)
                        Text("File Details").frame(width: 80 + 14 + 250, alignment: .leading)
                        Text("File Type")
                        Spacer(minLength: 12)
                        Text("New Filename")
                    }
                    .font(.inter(12.5, .semibold)).foregroundStyle(Theme.slate)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.cream.opacity(0.6))
                    Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 1)
                    LazyVStack(spacing: 0) {
                        ForEach(app.visibleItems) { item in
                            WrangleRow(item: item)
                            Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 1)
                        }
                    }
                }
                .background(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var patternCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Naming pattern")
                    Spacer()
                    if app.order != NameToken.defaultOrder {
                        Button("Reset to default") { app.resetOrder(); slot = nil }
                            .buttonStyle(.plain).foregroundStyle(Color(hex: "3D6E9E")).font(.inter(13, .semibold))
                    }
                }
                Text("Click a filename block to swap or rearrange it.")
                    .font(.inter(12.5)).foregroundStyle(Theme.slate)
                    .padding(.top, -6)
                HStack(spacing: 8) {
                    ForEach(Array(app.order.enumerated()), id: \.offset) { i, token in
                        Button { slot = slot == i ? nil : i } label: {
                            Text(token.label).font(.mono(14))
                                .padding(.horizontal, 12).frame(height: 34)
                                .background(slot == i ? Theme.denim : Theme.powderLight)
                                .foregroundStyle(slot == i ? Color.white : Theme.denim)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.powder, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        if i < app.order.count - 1 { Text("_").foregroundStyle(Theme.slate) }
                    }
                    Text("→").foregroundStyle(Theme.slate).padding(.horizontal, 4)
                    Text(exampleName).font(Theme.mono).lineLimit(1).truncationMode(.middle)
                }
                if let i = slot, app.order.indices.contains(i) {
                    HStack(spacing: 8) {
                        Text("Position \(i + 1): ").font(.inter(13)) + Text(app.order[i].label).font(.inter(13, .bold))
                        Button("← Move left") { app.moveToken(at: i, by: -1); slot = i - 1 }
                            .buttonStyle(SecondaryButtonStyle()).disabled(i == 0)
                        Button("Move right →") { app.moveToken(at: i, by: 1); slot = i + 1 }
                            .buttonStyle(SecondaryButtonStyle()).disabled(i == app.order.count - 1)
                        Text("Replace with").font(.inter(13)).foregroundStyle(Theme.slate).padding(.leading, 6)
                        ForEach(NameToken.allCases.filter { !app.order.contains($0) }) { t in
                            Button(t.label) { app.replaceToken(at: i, with: t) }.buttonStyle(SecondaryButtonStyle())
                        }
                        Spacer()
                        Button("Done") { slot = nil }.buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(12).background(Theme.cream).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if app.order.contains(.project) {
                    HStack(spacing: 10) {
                        Text("Project").font(.inter(13, .semibold))
                        if addingProject {
                            TextField("BrandCollab", text: $newProject).textFieldStyle(.roundedBorder).frame(width: 200)
                            Button("Save project") { app.addProject(newProject); newProject = ""; addingProject = false }
                                .buttonStyle(PrimaryButtonStyle())
                            Button("Cancel") { addingProject = false }.buttonStyle(.plain)
                        } else {
                            Picker("", selection: $app.project) {
                                ForEach(app.projects, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden().frame(width: 200)
                            Button("Add new project…") { addingProject = true }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(12).background(Theme.powderLight).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                HStack(spacing: 10) {
                    TextField("Location: letters and numbers only", text: $app.locationInput)
                        .textFieldStyle(.roundedBorder).frame(width: 260)
                    if app.canApplyLocation {
                        Button("Apply \u{201C}\(app.typedLocation)\u{201D} to \(app.visibleChecked) \(app.visibleChecked == 1 ? "file" : "files")") {
                            app.applyLocationToChecked()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .help("Use this location for the selected files.")
                    }
                    if app.visibleChecked > 0 {
                        Button("Clear location") { app.clearLocationForChecked() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(app.checkedWithManualLocation == 0)
                            .help(app.checkedWithManualLocation == 0
                                  ? "None of the ticked files has a location you set."
                                  : "The location of the selected file(s) will return to its default.")
                    }
                }
            }
        }
    }

    private var exampleName: String {
        app.visibleItems.first(where: { $0.duplicateOf == nil })?.newName
            ?? app.order.map { $0 == .date ? "2026-11-04" : $0 == .location ? Wrangler.cleanToken(app.location, fallback: "NoLocation")
                : $0 == .type ? "BROLL" : $0 == .seq ? "001" : $0 == .time ? "1830" : $0 == .camera ? "S23" : app.project }
                .joined(separator: "_") + ".mp4"
    }

    // MARK: Side column

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Where files will go")
                    if app.destinationSummary.isEmpty {
                        Text(app.effectiveMode.usesLibrary ? (app.libraryURL.path as NSString).abbreviatingWithTildeInPath : "Each file is renamed and stays in its folder")
                            .font(.mono(12))
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(app.destinationSummary, id: \.folder) { row in
                                HStack(alignment: .top) {
                                    Image(systemName: "folder").foregroundStyle(Theme.slate)
                                    Text(row.folder).font(.mono(11.5)).lineLimit(2)
                                    Spacer()
                                    Text("\(row.count)").font(.inter(12, .semibold))
                                }
                            }
                        }
                    }

                    Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4)

                    Text("Source folders that need wrangling").font(.inter(13, .semibold))
                    if app.sources.isEmpty {
                        Text("No folders yet.").foregroundStyle(Theme.slate).font(.inter(13))
                    }
                    ForEach(app.sources, id: \.self) { url in
                        SourceRow(url: url)
                    }
                    HStack {
                        Button("Add folder…") { app.addSources() }.buttonStyle(SecondaryButtonStyle())
                        Spacer()
                        Button(app.items.isEmpty ? "Analyze" : "Analyze again") { app.analyze() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(app.sources.isEmpty || app.isWorking)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Safety")
                    Text("When renaming").font(.inter(13, .semibold))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(RenameMode.allCases) { m in
                            RadioRow(label: m.label, selected: app.effectiveMode == m,
                                     enabled: !app.currentSourceReadOnly || m == .copy) { app.mode = m }
                        }
                    }
                    if app.effectiveMode == .move {
                        Text("Your file is cloned. One version is moved to the library and the other version to the Trash where it stays until it's restored or deleted.")
                            .font(.inter(11.5)).foregroundStyle(Theme.slate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4)
                    Toggle("Write tags into the files so your global Finder can search them", isOn: $app.writeTags).toggleStyle(.checkbox)
                    Toggle("Keep a log of old → new names", isOn: $app.keepLog).toggleStyle(.checkbox)
                    Toggle("Skip duplicates already in the library", isOn: $app.skipLibraryDuplicates).toggleStyle(.checkbox)
                    Text("Lasso never permanently deletes anything.").font(.inter(11.5)).foregroundStyle(Theme.slate)
                }
            }
            if app.currentSourceReadOnly {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.denim)
                    Text("Lasso has detected a read-only drive. Your files can only be copied into Lasso.")
                        .font(.inter(13)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.goldWash)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

/// The main action: the wrangle button on the left, what's happening on the right.
struct ActionPanel: View {
    @EnvironmentObject var app: AppState

    private enum Tone { case working, success, warning, info }

    private var tone: Tone {
        if app.isWorking { return .working }
        if app.sources.isEmpty { return .info }
        let s = app.status.lowercased()
        if s.contains("skipped:") || s.contains("couldn") || s.contains("didn't") { return .warning }
        if s.contains("renamed") || s.contains("saved") || s.contains("ejected") || s.contains("removed") || s.contains("set the location") || s.contains("cleared") { return .success }
        return .info
    }

    /// What to show when nothing has happened yet.
    private var message: String {
        if app.sources.isEmpty { return "Add a source folder on the right to get started." }
        if !app.status.isEmpty { return app.status }
        if app.batchIsSelection && app.batchPending > 0 {
            let n = app.batchPending
            return "Only the \(n) selected \(n == 1 ? "file" : "files") will be wrangled."
        }
        if app.showAnalysisSummary && !app.items.isEmpty {
            // Counts for the folder on screen, not all folders.
            let n = app.visiblePending
            let d = app.visibleItems.filter { $0.duplicateOf != nil }.count
            return "\(n) \(n == 1 ? "file" : "files") to wrangle · \(d) \(d == 1 ? "duplicate" : "duplicates") skipped" + (n > 0 ? ". Tick the files you want to wrangle." : "")
        }
        if app.items.isEmpty { return "Click Analyze to find the photos and videos in your folders." }
        if app.batchNeedsInput > 0 { return "Confirm the outlined types below, then wrangle." }
        if app.visiblePending > 0 { return "Tick the files you want to wrangle, then click the button. Use the box at the top of the list to select them all." }
        return "Everything in this folder has been wrangled."
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Button { app.apply() } label: {
                Label(app.primaryLabel, systemImage: "wand.and.stars")
                    .font(.inter(15, .semibold))
                    .padding(.horizontal, 20).frame(height: 48)
                    .background(app.canApply ? Theme.denim : Theme.line)
                    .foregroundStyle(app.canApply ? Color.white : Theme.slate)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!app.canApply)
            .fixedSize()

            HStack(alignment: .top, spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 8) {
                    if app.isWorking {
                        HStack(spacing: 12) {
                            ProgressView(value: app.progress).progressViewStyle(.linear).tint(Theme.denim)
                            if app.isAnalyzing {
                                Button("Stop") { app.stopAnalysis() }
                                    .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                    Text(message)
                        .font(.inter(15, .medium))
                        .foregroundStyle(Theme.denim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.2), value: app.status)
    }

    @ViewBuilder private var icon: some View {
        switch tone {
        case .working: ProgressView().controlSize(.small).frame(width: 22, height: 22)
        case .success: Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color(hex: "5B7A57"))
        case .warning: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 19)).foregroundStyle(Color(hex: "B8860B"))
        case .info: Image(systemName: "info.circle.fill").font(.system(size: 20)).foregroundStyle(Color(hex: "3D6E9E"))
        }
    }

    private var background: Color {
        switch tone {
        case .warning: return Theme.goldWash
        case .success: return Color(hex: "E8F0E4")
        default: return Theme.powderLight
        }
    }
    private var border: Color {
        switch tone {
        case .warning: return Theme.gold
        case .success: return Color(hex: "A9C29E")
        default: return Theme.powder
        }
    }
}

/// A radio button that can be greyed out on its own (the system radio group can't).
struct RadioRow: View {
    let label: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle().stroke(selected ? Theme.denim : Color(hex: "B8AE98"), lineWidth: 1.5).frame(width: 16, height: 16)
                    if selected { Circle().fill(Theme.denim).frame(width: 8, height: 8) }
                }
                .padding(.top, 1)
                Text(label).font(.inter(13)).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct SourceRow: View {
    @EnvironmentObject var app: AppState
    let url: URL

    var body: some View {
        let current = app.currentSource == url
        let online = app.isOnline(url)
        let n = app.pending(in: url)
        HStack(spacing: 10) {
            Button { app.selectedSource = url } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.inter(13.5, .semibold))
                        Text((url.path as NSString).abbreviatingWithTildeInPath)
                            .font(.mono(11)).foregroundStyle(Theme.slate)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(n) \(n == 1 ? "file" : "files")").font(.inter(12.5, .medium))
                        HStack(spacing: 5) {
                            Circle().fill(online ? Color(hex: "5B7A57") : Color(hex: "9A968E")).frame(width: 7, height: 7)
                            Text(online ? "online" : "offline").font(.inter(11.5)).foregroundStyle(Theme.slate)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { app.removeSource(url) } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(Theme.slate).help("Stop watching this folder")
        }
        .padding(10)
        .background(current ? Theme.powderLight : Color.white)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(current ? Theme.denim : Theme.line, lineWidth: current ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct WrangleRow: View {
    @EnvironmentObject var app: AppState
    let item: WrangleItem

    var body: some View {
        HStack(spacing: 14) {
            Button { app.toggleChecked(item.id) } label: {
                Image(systemName: app.checked.contains(item.id) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17))
                    .foregroundStyle(app.checked.contains(item.id) ? Theme.denim : Theme.slate)
            }
            .buttonStyle(.plain)
            ThumbnailView(url: item.url, size: CGSize(width: 160, height: 100))
                .frame(width: 80, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent).font(Theme.mono).lineLimit(1)
                Text(item.duplicateOf == nil ? "\(item.sourceLabel) · \(item.createdText)" : item.sourceLabel)
                    .font(.inter(11.5)).foregroundStyle(Theme.slate).lineLimit(1)
                if item.duplicateOf == nil {
                    if let manual = item.manualLocation {
                        Label(manual, systemImage: "pencil")
                            .font(.inter(11.5, .medium)).foregroundStyle(Theme.denim)
                            .help("Location you set")
                    } else if let place = item.place {
                        Label(place, systemImage: "mappin.and.ellipse")
                            .font(.inter(11.5, .medium)).foregroundStyle(Theme.denim)
                            .help("Location from the file's GPS")
                    }
                }
                if item.dateFromFile && item.duplicateOf == nil {
                    Text("Date from file, check").font(.inter(11, .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Theme.goldWash).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(width: 250, alignment: .leading)

            if let dup = item.duplicateOf {
                Text("Skipped. Duplicate of \(dup).").font(.inter(12.5)).foregroundStyle(Theme.slate)
                Spacer()
            } else {
                typeControl
                if item.needsInput {
                    Button { app.accept(item.id) } label: { Label("Accept suggestion", systemImage: "checkmark") }
                        .buttonStyle(GoldButtonStyle())
                }
                Spacer(minLength: 12)
                Text(item.newName).font(Theme.mono).textSelection(.enabled).lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(app.checked.contains(item.id) ? Theme.powderLight : (item.needsInput ? Theme.goldWash : Color.clear))
        .opacity(item.duplicateOf == nil ? 1 : 0.6)
    }

    @ViewBuilder var typeControl: some View {
        if item.type == .photo {
            TypeTag(type: .photo)
        } else {
            Menu {
                ForEach(FootageType.videoTypes) { t in
                    Button(t.label) { app.setType(item.id, t) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(item.type.label).font(.inter(12, .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(item.needsInput ? item.type.color : Color.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(item.needsInput ? Theme.surface : item.type.color)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(item.type.color, style: StrokeStyle(lineWidth: 2, dash: item.needsInput ? [5, 3] : []))
                )
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change the footage type")
        }
    }
}
