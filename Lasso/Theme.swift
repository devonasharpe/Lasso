import SwiftUI

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

enum Theme {
    static let cream = Color(hex: "F6F0E1")
    static let surface = Color(hex: "FFFDF8")
    static let line = Color(hex: "E3D9C3")
    static let denim = Color(hex: "1E3A5F")
    static let slate = Color(hex: "4F5D70")
    static let powder = Color(hex: "B7D2E8")
    static let powderLight = Color(hex: "DCE9F4")
    static let gold = Color(hex: "DCBA1F")
    static let goldWash = Color(hex: "FBF4D6")
    static let red = Color(hex: "A3322A")
    static let thumbBG = Color(hex: "2A2926")

    static let title = Font.fraunces(30, .semibold)
    static let logo = Font.wordmark(46)
    static let section = Font.inter(12, .semibold)
    static let mono = Font.mono(12, .medium)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(Theme.section).kerning(0.8).foregroundStyle(Theme.slate)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(14, .semibold))
            .padding(.horizontal, 18).frame(height: 40)
            .background(enabled ? Theme.denim : Theme.line)
            .foregroundStyle(enabled ? Color.white : Theme.slate)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(13, .medium))
            .padding(.horizontal, 14).frame(height: 34)
            .background(Theme.surface)
            .foregroundStyle(Theme.denim)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "CBBFA6"), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(12.5, .semibold))
            .padding(.horizontal, 12).frame(height: 30)
            .background(Theme.gold)
            .foregroundStyle(Theme.denim)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
