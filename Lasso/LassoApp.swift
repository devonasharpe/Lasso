import SwiftUI

@main
struct LassoApp: App {
    @StateObject private var app = AppState()

    init() { Brand.registerFonts() }

    var body: some Scene {
        WindowGroup("Lasso") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { app.tab = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .help) {
                Button("Show Welcome Steps Again") {
                    app.seenLibraryIntro = false
                    app.seenWrangleIntro = false
                    app.onboarded = false
                }
            }
            CommandGroup(before: .toolbar) {
                Button("Library") { app.tab = .library }.keyboardShortcut("1", modifiers: .command)
                Button("Wrangle Files") { app.tab = .wrangle }.keyboardShortcut("2", modifiers: .command)
            }
        }
    }
}
