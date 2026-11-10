import SwiftUI
import AppKit

/// After analysis: name the new people Lasso found, and confirm uncertain matches.
struct PeopleNamingView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if app.faceGroups.isEmpty && app.faceConfirms.isEmpty {
            PeopleExampleView()
        } else {
            namingWindow
        }
    }

    private var namingWindow: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who's in your files?").font(.fraunces(26, .semibold))
                Text("Looking for a friend? You can search for someone by name if you identify them below in Lasso. People you decide not to track won't be tracked. It's that simple. You can manage face mapping data in Settings > People.")
                    .font(.inter(13.5)).foregroundStyle(Theme.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            Rectangle().fill(Theme.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach($app.faceConfirms) { $c in ConfirmCard(confirm: $c) }
                    ForEach($app.faceGroups) { $g in GroupCard(group: $g) }
                }
                .padding(24)
            }

            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                Button("Don't track anyone here") { app.finishNaming(trackNobody: true) }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Done") { app.finishNaming(trackNobody: false) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 720, height: 640)
        .background(Theme.cream)
        .foregroundStyle(Theme.denim)
    }
}

private struct FaceThumb: View {
    let face: FaceRecord
    var size: CGFloat = 56
    var body: some View {
        Group {
            if let img = NSImage(contentsOf: Faces.thumbURL(face)) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Theme.line
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 5))
    }
}

/// "Is this Marie?"
private struct ConfirmCard: View {
    @Binding var confirm: FaceConfirm

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let f = confirm.faces.first { FaceThumb(face: f, size: 88) }
            VStack(alignment: .leading, spacing: 10) {
                Text("Is this \(confirm.person.name)?").font(.inter(16, .semibold))
                Text("Appears in \(Set(confirm.faces.map(\.fingerprint)).count) new \(Set(confirm.faces.map(\.fingerprint)).count == 1 ? "file" : "files")")
                    .font(.inter(12.5)).foregroundStyle(Theme.slate)
                HStack(spacing: 10) {
                    Button("Yes") { confirm.answer = true }
                        .buttonStyle(ChoiceStyle(on: confirm.answer == true))
                    Button("No") { confirm.answer = false }
                        .buttonStyle(ChoiceStyle(on: confirm.answer == false))
                    if confirm.answer == false {
                        TextField("Who is it? (leave empty to not track)", text: $confirm.otherName)
                            .textFieldStyle(.roundedBorder).frame(width: 260)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.powder, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// A new person: a close-up, the files they're in, and a name.
private struct GroupCard: View {
    @Binding var group: FaceGroup

    /// One face per file, for the strip.
    private var perFile: [FaceRecord] {
        var seen = Set<String>()
        return group.faces.filter { seen.insert($0.fingerprint).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                if let f = group.faces.first { FaceThumb(face: f, size: 88) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Appears in \(group.fileCount) files").font(.inter(12.5)).foregroundStyle(Theme.slate)
                    HStack(spacing: 10) {
                        TextField("Name", text: $group.name)
                            .textFieldStyle(.roundedBorder).frame(width: 220)
                            .disabled(!group.track)
                        Button(group.isMe ? "This is me ✓" : "This is me") {
                            group.isMe.toggle()
                            if group.isMe && group.name.isEmpty { group.name = "Me" }
                        }
                        .buttonStyle(ChoiceStyle(on: group.isMe))
                        .disabled(!group.track)
                    }
                    Button(group.track ? "Don't track this person" : "Track this person after all") { group.track.toggle() }
                        .buttonStyle(.plain).font(.inter(12.5, .semibold)).foregroundStyle(Color(hex: "3D6E9E"))
                }
                Spacer()
            }
            if group.track {
                Text("Click a picture that isn't this person to take it out.").font(.inter(12)).foregroundStyle(Theme.slate)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(perFile) { f in
                            Button {
                                group.faces.removeAll { $0.fingerprint == f.fingerprint }
                            } label: {
                                FaceThumb(face: f, size: 52)
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                                            .foregroundStyle(.white, Theme.denim.opacity(0.75)).padding(2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(f.fileName)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(group.track ? 1 : 0.55)
    }
}

private struct ChoiceStyle: ButtonStyle {
    let on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(13, .semibold))
            .padding(.horizontal, 14).frame(height: 32)
            .background(on ? Theme.denim : Theme.surface)
            .foregroundStyle(on ? Color.white : Theme.denim)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.denim : Color(hex: "CBBFA6"), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}


/// Shown during first run when there's no one to name yet: an illustrated example of the feature.
private struct PeopleExampleView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who's in your files?").font(.fraunces(26, .semibold))
                Group {
                    if app.faceGrouping {
                        Text("Lasso didn't find anyone in two or more of your files yet. As you add folders, people who appear in at least two files will show up here, ready for you to name, like the example below.")
                    } else {
                        // *…* shows in italics
                        Text("Lasso can recognize the people in your photos and videos so you can search for them by name, like the example below. You've turned *Face mapping off*. You can turn it on now or later in Settings > People.")
                    }
                }
                .font(.inter(13.5)).foregroundStyle(Theme.slate)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            Rectangle().fill(Theme.line).frame(height: 1)

            VStack(spacing: 14) {
                ExampleCard(name: "Marie", color: Color(hex: "88074D"), files: 6)
                ExampleCard(name: "", color: Color(hex: "3D6E9E"), files: 3)
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)

            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                // Shown for illustration only: in the real window this skips everyone listed.
                Text("Don't track anyone here")
                    .font(.inter(13, .medium))
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "CBBFA6"), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .opacity(0.5)
                    .help("Example")
                    .accessibilityHidden(true)
                Spacer()
                if app.faceGrouping {
                    Button("Got it") { app.showNaming = false }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Keep off") { app.showNaming = false }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Turn on") { app.turnOnFaceMapping() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 720, height: 640)
        .background(Theme.cream)
        .foregroundStyle(Theme.denim)
    }
}

/// An illustrated person card: a drawn silhouette and placeholder pictures, never a real face.
private struct ExampleCard: View {
    let name: String
    let color: Color
    let files: Int

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            silhouette(size: 88)
            VStack(alignment: .leading, spacing: 8) {
                Text("Appears in \(files) files").font(.inter(12.5)).foregroundStyle(Theme.slate)
                HStack(spacing: 10) {
                    Text(name.isEmpty ? "Name" : name)
                        .font(.inter(13))
                        .foregroundStyle(name.isEmpty ? Theme.slate : Theme.denim)
                        .padding(.horizontal, 8).frame(width: 220, height: 24, alignment: .leading)
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.line, lineWidth: 1))
                    Text("This is me").font(.inter(13, .semibold))
                        .padding(.horizontal, 14).frame(height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "CBBFA6"), lineWidth: 1))
                }
                Text("Don't track this person")
                    .font(.inter(12.5, .semibold)).foregroundStyle(Color(hex: "3D6E9E"))
                Text("Click a picture that isn't this person to take it out.")
                    .font(.inter(12)).foregroundStyle(Theme.slate)
                HStack(spacing: 8) {
                    ForEach(0..<min(files, 5), id: \.self) { i in
                        silhouette(size: 44).opacity(1 - Double(i) * 0.12)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                                    .foregroundStyle(.white, Theme.denim.opacity(0.75)).padding(2)
                            }
                    }
                }
            }
            Spacer()
            Text("Example").font(.inter(11.5, .semibold))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Theme.goldWash)
                .overlay(Capsule().stroke(Theme.gold, lineWidth: 1))
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Example of a person Lasso found\(name.isEmpty ? "" : ", named \(name)"), in \(files) files")
    }

    private func silhouette(size: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            color.opacity(0.18)
            Circle().fill(color.opacity(0.55))
                .frame(width: size * 0.38, height: size * 0.38)
                .offset(y: -size * 0.42)
            Ellipse().fill(color.opacity(0.55))
                .frame(width: size * 0.72, height: size * 0.5)
                .offset(y: size * 0.18)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 5))
    }
}
