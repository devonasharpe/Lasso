import SwiftUI

/// "Is this the correct drive?" and "couldn't be ejected", styled like the mockup.
struct DriveAlertView: View {
    @EnvironmentObject var app: AppState
    let alert: DriveAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch alert {
            case .renamed(let uuid, let oldName, let newName, let volume):
                icon("externaldrive", background: Theme.powderLight, color: Theme.denim)
                Text("Is this the correct drive?").font(.fraunces(22, .semibold))
                Text("Lasso recognizes this drive, but its name has changed since you last connected it.")
                    .font(.inter(14)).foregroundStyle(Color(hex: "2E4562")).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top) {
                    nameBox("Saved in library", oldName)
                    nameBox("Name now", newName)
                }
                .padding(12)
                .background(Theme.cream).clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Continuing switches the library to the new name.").font(.inter(12.5)).foregroundStyle(Theme.slate)
                HStack(spacing: 10) {
                    Spacer()
                    Button("No, disconnect") { app.disconnectDrive(name: newName, volume: volume) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Yes, continue") { app.acceptDriveRename(uuid: uuid, from: oldName, to: newName) }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }

            case .blocked(let name, let volume, let users):
                icon("exclamationmark.triangle", background: Theme.gold, color: Theme.denim)
                Text("“\(name)” couldn’t be ejected").font(.fraunces(22, .semibold))
                Text("These apps are using files on the drive. Close them, then try again.")
                    .font(.inter(14)).foregroundStyle(Color(hex: "2E4562")).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(users, id: \.self) { u in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.app).font(.inter(14, .semibold))
                            Text(u.file).font(.mono(12)).foregroundStyle(Theme.slate).lineLimit(1).truncationMode(.middle)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cream).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { app.driveAlert = nil }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Try again") { app.disconnectDrive(name: name, volume: volume) }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Theme.surface)
        .foregroundStyle(Theme.denim)
    }

    private func icon(_ name: String, background: Color, color: Color) -> some View {
        Image(systemName: name).font(.system(size: 20)).foregroundStyle(color)
            .frame(width: 44, height: 44).background(background).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func nameBox(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.inter(12)).foregroundStyle(Theme.slate)
            Text(value).font(.inter(14, .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
