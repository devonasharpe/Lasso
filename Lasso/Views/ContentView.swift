import SwiftUI
import QuickLook

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if app.onboarded {
                VStack(spacing: 0) {
                    HeaderBar()
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Group {
                        switch app.tab {
                        case .library: LibraryView()
                        case .wrangle: WrangleView()
                        case .settings: SettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // The naming window waits until the tab's welcome card has been read.
                    .sheet(isPresented: $app.showNaming) {
                        PeopleNamingView().environmentObject(app).interactiveDismissDisabled()
                    }
                }
                .overlay { introCard }
                .sheet(item: $app.driveAlert) { alert in
                    DriveAlertView(alert: alert).environmentObject(app)
                }
                .onAppear { app.startDriveWatching() }
                .quickLookPreview($app.previewURL)
                .animation(.easeOut(duration: 0.2), value: app.seenLibraryIntro)
                .animation(.easeOut(duration: 0.2), value: app.seenWrangleIntro)
            } else {
                OnboardingView()
            }
        }
        .background(Theme.cream)
        .foregroundStyle(Theme.denim)
        .tint(Theme.denim)
        .font(.inter(13.5))
    }
}

extension ContentView {
    @ViewBuilder var introCard: some View {
        if app.tab == .library && !app.seenLibraryIntro {
            FirstViewPopup(title: FirstViewPopup.library.title, paragraphs: FirstViewPopup.library.paragraphs) {
                app.seenLibraryIntro = true
            }
        } else if app.tab == .wrangle && !app.seenWrangleIntro {
            FirstViewPopup(title: FirstViewPopup.wrangle.title, paragraphs: FirstViewPopup.wrangle.paragraphs) {
                app.seenWrangleIntro = true
            }
        }
    }
}

struct HeaderBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 28) {
            // Sacramento's capital L curls out past the left edge of its letter box,
            // and SwiftUI cuts off anything outside that box. A leading en space gives
            // the curl room inside the text; the negative padding pulls it back left.
            Text("\u{2002}Lasso ")
                .font(Theme.logo)
                .fixedSize()
                .padding(.leading, -14)
                .frame(width: 250, alignment: .leading)

            HStack(spacing: 6) {
                TabButton(title: "Library", selected: app.tab == .library) { app.tab = .library }
                TabButton(title: "Wrangle Files", selected: app.tab == .wrangle, badge: app.pendingCount) { app.tab = .wrangle }
            }
            Spacer()
            if let p = app.modelProgress {
                HStack(spacing: 8) {
                    ProgressView(value: p).frame(width: 90)
                    Text("Add-on \(Int(p * 100))%").font(.inter(12)).foregroundStyle(Theme.slate)
                }
                .help("Downloading the transcription add-on")
            }
            TabButton(title: "Settings", systemImage: "gearshape", selected: app.tab == .settings) { app.tab = .settings }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }
}

struct TabButton: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(.inter(14, selected ? .semibold : .medium))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.inter(11, .bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.gold)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(selected ? Theme.powder : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.powder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
