import SwiftUI
import CoreText

/// Lasso's brand fonts, bundled in the Fonts folder (all under the SIL Open Font License).
enum Brand {
    static func registerFonts() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }

    static func weightName(_ w: Font.Weight, hasMedium: Bool = true) -> String {
        switch w {
        case .bold, .heavy, .black: return "Bold"
        case .semibold: return "SemiBold"
        case .medium: return hasMedium ? "Medium" : "Regular"
        default: return "Regular"
        }
    }
}

extension Font {
    /// Inter: everyday interface text.
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Inter18pt-" + Brand.weightName(weight), size: size)
    }
    /// JetBrains Mono: file names and paths.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("JetBrainsMono-" + Brand.weightName(weight), size: size)
    }
    /// Fraunces: headings.
    static func fraunces(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Fraunces72pt-" + Brand.weightName(weight, hasMedium: false), size: size)
    }
    /// Sacramento: the Lasso wordmark.
    static func wordmark(_ size: CGFloat) -> Font { .custom("Sacramento-Regular", size: size) }
}
