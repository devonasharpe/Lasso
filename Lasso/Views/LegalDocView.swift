import SwiftUI
import AppKit

/// The two documents bundled with the app, shown in a branded window from Settings › Resources.
enum LegalDoc: String, Identifiable {
    case terms = "Lasso-Terms-and-Privacy"
    case licenses = "Lasso-Third-Party-Notices"
    var id: String { rawValue }
    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: "txt") }
}

struct LegalDocView: View {
    let doc: LegalDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let blocks = MarkdownBlocks.parse((doc.url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "")
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(blocks) { block in block.view }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                Button {
                    if let url = doc.url { NSWorkspace.shared.open(url) }
                } label: {
                    Text("Open as text file").font(.inter(13, .medium)).foregroundStyle(Color(hex: "3D6E9E"))
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 760, height: 680)
        .background(Theme.cream)
        .foregroundStyle(Theme.denim)
    }
}

/// A small reader for the simple Markdown in Lasso's own documents:
/// headings, paragraphs, bullet lists, tables and code blocks.
struct MarkdownBlocks: Identifiable {
    enum Kind {
        case title(String), heading(String), subheading(String)
        case paragraph(String), bullet(String)
        case table([[String]])
        case code(String)
    }
    let id: Int
    let kind: Kind

    static func parse(_ text: String) -> [MarkdownBlocks] {
        var out: [Kind] = []
        var para: [String] = []
        var table: [[String]] = []
        var code: [String]? = nil
        func flushPara() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] } }
        func flushTable() { if !table.isEmpty { out.append(.table(table)); table = [] } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if code != nil {
                if line.hasPrefix("```") { out.append(.code(code!.joined(separator: "\n"))); code = nil }
                else { code!.append(raw) }
                continue
            }
            if line.hasPrefix("```") { flushPara(); flushTable(); code = []; continue }
            if line.hasPrefix("|") {
                flushPara()
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if !cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) { table.append(cells) }
                continue
            }
            flushTable()
            if line.isEmpty { flushPara(); continue }
            if line.hasPrefix("### ") { flushPara(); out.append(.subheading(String(line.dropFirst(4)))) }
            else if line.hasPrefix("## ") { flushPara(); out.append(.heading(String(line.dropFirst(3)))) }
            else if line.hasPrefix("# ") { flushPara(); out.append(.title(String(line.dropFirst(2)))) }
            else if line.hasPrefix("- ") { flushPara(); out.append(.bullet(String(line.dropFirst(2)))) }
            else { para.append(line) }
        }
        flushPara(); flushTable()
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        return out.enumerated().map { MarkdownBlocks(id: $0.offset, kind: $0.element) }
    }

    /// Bold, italics and links inside a line.
    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    @ViewBuilder var view: some View {
        switch kind {
        case .title(let t):
            Text(t).font(.fraunces(28, .semibold)).fixedSize(horizontal: false, vertical: true)
        case .heading(let t):
            Text(t).font(.fraunces(21, .semibold)).padding(.top, 10)
        case .subheading(let t):
            Text(t).font(.inter(15, .semibold)).padding(.top, 4)
        case .paragraph(let t):
            Text(Self.inline(t)).font(.inter(14)).lineSpacing(4)
                .foregroundStyle(Color(hex: "2E4562"))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let t):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").font(.inter(14))
                Text(Self.inline(t)).font(.inter(14)).lineSpacing(4)
                    .foregroundStyle(Color(hex: "2E4562"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(Self.inline(cell))
                                .font(.inter(13, i == 0 ? .semibold : .regular))
                                .foregroundStyle(i == 0 ? Theme.denim : Color(hex: "2E4562"))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 8)
                        }
                    }
                    if i < rows.count - 1 { Divider().gridCellUnsizedAxes(.horizontal) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        case .code(let t):
            Text(t).font(.mono(11.5)).lineSpacing(2)
                .foregroundStyle(Color(hex: "2E4562"))
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
