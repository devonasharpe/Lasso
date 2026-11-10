import SwiftUI
import AppKit

struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @State private var typeFilter: FootageType? = nil
    @State private var locationFilter: String? = nil
    @State private var personFilter: String? = nil
    /// Sidebar groups the user has folded away. Everything starts open.
    @State private var collapsed: Set<String> = []
    @State private var mediaFilter: MediaFilter = .all
    @State private var size: ViewSize = .medium
    @State private var selection: Set<String> = []
    @State private var query = ""
    @State private var confirmTrash = false

    private var filtered: [LibraryFile] {
        app.libraryFiles.filter { f in
            if let t = typeFilter, f.type != t { return false }
            if let l = locationFilter, f.location != l { return false }
            if let p = personFilter, !f.people.contains(p) { return false }
            if mediaFilter == .video && !f.isVideo { return false }
            if mediaFilter == .photo && f.isVideo { return false }
            if !query.isEmpty && !Self.matches(f, query) { return false }
            return true
        }
    }
    /// Search across the name, place, date, type (code and full name), folder, and photo/video.
    /// Spaces, hyphens and capitals don't matter: "voice over", "Voice-over" and "VO" all find voice overs.
    static func matches(_ f: LibraryFile, _ query: String) -> Bool {
        func norm(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
        }
        var parts = [f.name, f.location, f.date, f.isVideo ? "video" : "photo", f.transcript ?? "", f.people.joined(separator: " "),
                     URL(fileURLWithPath: f.folder).lastPathComponent]
        if let t = f.type { parts += [t.label, t.code, t.folder] } else { parts += ["not wrangled", "needs wrangling"] }
        let hay = norm(parts.joined(separator: " "))
        let whole = norm(query)
        if !whole.isEmpty && hay.contains(whole) { return true }
        let words = query.split(whereSeparator: { $0 == " " || $0 == "," }).map { norm(String($0)) }.filter { !$0.isEmpty }
        return !words.isEmpty && words.allSatisfy { hay.contains($0) }
    }

    private var selectedFiles: [LibraryFile] { app.libraryFiles.filter { selection.contains($0.id) } }

    private var columns: [GridItem] {
        switch size {
        case .large: return Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .top), count: 3)
        case .small: return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 6)
        default: return [GridItem(.adaptive(minimum: 220), spacing: 18, alignment: .top)]
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ScrollView { sidebar }.frame(width: 250)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(heading).font(Theme.title)
                    Text("\(filtered.count) files").foregroundStyle(Theme.slate)
                    Spacer()
                    TextField("Search names, types and places", text: $query)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                    SizeSwitch(size: $size)
                }
                if selection.count > 1 { selectionBar }
                if !app.status.isEmpty && app.tab == .library {
                    Text(app.status).font(.inter(12.5)).foregroundStyle(Theme.slate)
                }
                if app.libraryFiles.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your library is empty").font(.inter(13.5, .semibold))
                            Text("Wrangle some files and they'll appear here, along with the files in your source folders that haven't been polished yet.")
                                .foregroundStyle(Theme.slate)
                        }
                    }
                } else if size == .list {
                    listView
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(filtered) { f in
                                LibraryCard(file: f, selected: selection.contains(f.id),
                                            showDetails: selection == [f.id], compact: size == .small)
                                    .onTapGesture(count: 2) { app.preview(f.url) }
                                    .onTapGesture { tap(f) }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .padding(28)
        .task { await app.refreshLibrary() }
        .alert("Move \(selection.count) files to Trash?", isPresented: $confirmTrash) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                let files = selectedFiles
                selection = []
                app.moveToTrash(files)
            }
        } message: {
            Text("You can restore the files from the Trash. Nothing is deleted permanently.")
        }
    }

    private func tap(_ f: LibraryFile) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(f.id) { selection.remove(f.id) } else { selection.insert(f.id) }
        } else {
            selection = selection == [f.id] ? [] : [f.id]
        }
    }

    private var heading: String {
        var parts: [String] = []
        if let t = typeFilter { parts.append(t.label) }
        if let l = locationFilter { parts.append(l) }
        if let p = personFilter { parts.append(p) }
        if mediaFilter != .all { parts.append(mediaFilter.rawValue) }
        if !query.isEmpty { parts.append("“\(query)”") }
        return parts.isEmpty ? "All footage" : parts.joined(separator: " · ")
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text("\(selection.count) files selected").font(.inter(14, .semibold))
            Spacer()
            Button("Copy to folder…") { app.copy(selectedFiles) }
                .buttonStyle(SecondaryButtonStyle())
            Button("Move to Trash") { confirmTrash = true }
                .buttonStyle(SecondaryButtonStyle())
            Button("Clear") { selection = [] }.buttonStyle(.plain).foregroundStyle(Theme.powderLight)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.denim)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        let online = app.sources.filter { app.isOnline($0) }.count
        let offline = app.sources.count - online
        let locations = Array(Set(app.libraryFiles.map(\.location).filter { !$0.isEmpty })).sorted()
        return VStack(alignment: .leading, spacing: 22) {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(app.sources.count) source \(app.sources.count == 1 ? "folder" : "folders")").font(.inter(14, .semibold))
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "5B7A57")).frame(width: 8, height: 8)
                        Text("\(online) online")
                        Circle().fill(Color(hex: "9A968E")).frame(width: 8, height: 8).padding(.leading, 6)
                        Text("\(offline) offline")
                    }
                    .font(.inter(12.5)).foregroundStyle(Theme.slate)
                }
            }
            filterGroup("Type of footage") {
                filterRow("All types", count: app.libraryFiles.filter { $0.type != nil }.count, color: Color(hex: "B8AE98"), active: typeFilter == nil) { typeFilter = nil }
                ForEach(FootageType.allCases) { t in
                    let n = app.libraryFiles.filter { $0.type == t }.count
                    if n > 0 {
                        filterRow(t.label, count: n, color: t.color, active: typeFilter == t) { typeFilter = t }
                    }
                }
            }
            filterGroup("Location") {
                filterRow("All locations", count: app.libraryFiles.filter { !$0.location.isEmpty }.count, color: nil, active: locationFilter == nil) { locationFilter = nil }
                ForEach(locations, id: \.self) { l in
                    filterRow(l, count: app.libraryFiles.filter { $0.location == l }.count, color: nil, active: locationFilter == l) { locationFilter = l }
                }
            }
            let people = Array(Set(app.libraryFiles.flatMap(\.people))).sorted()
            if !people.isEmpty {
                filterGroup("People") {
                    filterRow("Everyone", count: app.libraryFiles.filter { !$0.people.isEmpty }.count, color: nil, active: personFilter == nil) { personFilter = nil }
                    ForEach(people, id: \.self) { p in
                        filterRow(p, count: app.libraryFiles.filter { $0.people.contains(p) }.count, color: nil, active: personFilter == p) { personFilter = p }
                    }
                }
            }
            filterGroup("Media") {
                ForEach(MediaFilter.allCases) { m in
                    let n = app.libraryFiles.filter { m == .all || (m == .video) == $0.isVideo }.count
                    filterRow(m.rawValue, count: n, color: nil, active: mediaFilter == m) { mediaFilter = m }
                }
            }
            Text("Click a card for details. Double-click the picture to preview. ⌘-click to select several.")
                .font(.inter(12)).foregroundStyle(Theme.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func filterGroup<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        let open = !collapsed.contains(title)
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if open { collapsed.insert(title) } else { collapsed.remove(title) }
                }
            } label: {
                HStack(spacing: 6) {
                    SectionLabel(text: title)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.slate)
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
            .help(open ? "Collapse \(title)" : "Expand \(title)")
            .accessibilityLabel(title)
            .accessibilityValue(open ? "expanded" : "collapsed")
            if open { content() }
        }
    }

    private func filterRow(_ label: String, count: Int, color: Color?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let color { RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10) }
                Text(label).lineLimit(1)
                Spacer()
                Text("\(count)").foregroundStyle(Theme.slate)
            }
            .font(.inter(13.5, active ? .semibold : .regular))
            .padding(.horizontal, 12).frame(height: 36)
            .background(active ? Theme.powder : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text("").frame(width: 64)
                    Text("Name").frame(width: 330, alignment: .leading)
                    Text("Type").frame(width: 150, alignment: .leading)
                    Text("Location").frame(width: 130, alignment: .leading)
                    Text("Date").frame(width: 90, alignment: .leading)
                    Text("Size").frame(width: 80, alignment: .trailing)
                    Spacer(minLength: 0)
                }
                .font(.inter(11, .semibold)).foregroundStyle(Theme.slate)
                .padding(.horizontal, 14).padding(.vertical, 10)
                Rectangle().fill(Theme.line).frame(height: 1)
                ForEach(filtered) { f in
                    HStack(spacing: 14) {
                        ZStack(alignment: .topLeading) {
                            ThumbnailView(url: f.url, size: CGSize(width: 128, height: 80))
                                .frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 5))
                            if !f.standardized {
                                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                                    .foregroundStyle(Theme.gold).padding(3)
                            }
                        }
                        .frame(width: 64)
                        Text(f.name).font(Theme.mono).lineLimit(1).truncationMode(.middle)
                            .frame(width: 330, alignment: .leading)
                        Group {
                            if let t = f.type { TypeTag(type: t) } else { Text("—").foregroundStyle(Theme.slate) }
                        }
                        .frame(width: 150, alignment: .leading)
                        Text(f.location).lineLimit(1).frame(width: 130, alignment: .leading)
                        Text(f.date).frame(width: 90, alignment: .leading)
                        Text(ByteCountFormatter.string(fromByteCount: f.bytes, countStyle: .file)).frame(width: 80, alignment: .trailing)
                        Spacer(minLength: 0)
                    }
                    .font(.inter(12.5))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(selection.contains(f.id) ? Theme.powderLight : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { app.preview(f.url) }
                    .onTapGesture { tap(f) }
                    Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 1)
                }
            }
        }
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct SizeSwitch: View {
    @Binding var size: ViewSize

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewSize.allCases) { s in
                Button { size = s } label: {
                    Image(systemName: icon(s)).font(.system(size: 14, weight: size == s ? .semibold : .regular))
                    .frame(width: 38, height: 32)
                    .background(size == s ? Theme.powder : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(s.rawValue) view")
            }
        }
        .padding(3)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "D9CDB3"), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func icon(_ s: ViewSize) -> String {
        switch s {
        case .large: return "square.grid.2x2"
        case .medium: return "square.grid.3x2"
        case .small: return "square.grid.4x3.fill"
        case .list: return "list.bullet"
        }
    }
}

struct LibraryCard: View {
    let file: LibraryFile
    let selected: Bool
    let showDetails: Bool
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(ThumbnailView(url: file.url))
                .clipped()
                .overlay(alignment: .topLeading) {
                    if !file.standardized {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .padding(7)
                            .background(Theme.gold)
                            .clipShape(Circle())
                            .padding(8)
                            .help("Not wrangled yet. Open Wrangle Files to fix it.")
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if file.isVideo { DurationBadge(url: file.url, compact: compact) }
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                            .foregroundStyle(.white, Theme.denim).padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                if let t = file.type { TypeTag(type: t) }
                Text(file.name).font(Theme.mono).lineLimit(compact ? 1 : 2).truncationMode(.middle)
                if !compact {
                    Text(infoLine)
                        .font(.inter(12)).foregroundStyle(Theme.slate)
                }
                if showDetails {
                    Rectangle().fill(Theme.powder).frame(height: 2).padding(.vertical, 2)
                    detail("File type", file.url.pathExtension.uppercased() + (file.isVideo ? " video" : " image"))
                    detail("Previous name", file.previousName ?? "Not recorded")
                    detail("Folder", (file.folder as NSString).abbreviatingWithTildeInPath)
                    if !file.people.isEmpty { detail("People", file.people.joined(separator: ", ")) }
                    if file.isVideo {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transcription").font(.inter(11)).foregroundStyle(Theme.slate)
                            Text(file.transcript.flatMap { $0.isEmpty ? nil : $0 } ?? "None")
                                .font(.inter(12)).lineSpacing(2)
                                .lineLimit(2).truncationMode(.tail)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(compact ? 8 : 12)
            .padding(.bottom, showDetails ? 6 : 0)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.denim : (file.standardized ? Theme.line : Theme.gold), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }

    /// "Paris · Nov 08 · 24.3 MB"
    private var infoLine: String {
        let size = ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file)
        guard file.standardized else { return URL(fileURLWithPath: file.folder).lastPathComponent + " · " + size }
        return [file.location, Self.shortDate(file.date), size].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "2026-11-08" → "Nov 08"
    static func shortDate(_ iso: String) -> String {
        let inF = DateFormatter(); inF.locale = Locale(identifier: "en_US_POSIX"); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: iso) else { return iso }
        let outF = DateFormatter(); outF.locale = Locale(identifier: "en_US"); outF.dateFormat = "MMM dd"
        return outF.string(from: d)
    }

    private func detail(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.inter(11)).foregroundStyle(Theme.slate)
            Text(v).font(.mono(11.5)).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
