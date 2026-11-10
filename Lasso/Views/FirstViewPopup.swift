import SwiftUI

/// The one-time welcome card shown the first time someone opens the Library or Wrangle Files.
struct FirstViewPopup: View {
    let title: String
    let paragraphs: [String]
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.fraunces(26, .semibold))
                ForEach(paragraphs, id: \.self) { p in
                    Text(p).font(.inter(15)).lineSpacing(4)
                        .foregroundStyle(Color(hex: "2E4562"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Got it", action: dismiss)
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(width: 480)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
            .foregroundStyle(Theme.denim)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}

extension FirstViewPopup {
    static let library = (
        title: "Your Lasso Library",
        paragraphs: [
            "All of the images and videos from the folders you've selected are displayed here in Library, giving you a universal view of all your files.",
            "Use the search bar, located at the top right, to find specific files. Use the filters in the left panel to narrow your search results."
        ]
    )
    static let wrangle = (
        title: "Wrangle Files",
        paragraphs: [
            "Let's get you organized.",
            "Your first scan has been completed and your first batch of files identified. You can select and analyze additional folders and files from the panel on the right. Once your files are given a polish, they'll appear in the Library tab."
        ]
    )
}
