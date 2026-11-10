import AppKit
import AVFoundation
import QuickLookThumbnailing
import SwiftUI

/// Thumbnails from macOS Quick Look, cached in memory.
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL, size: CGSize) async -> NSImage? {
        let key = "\(url.path)#\(Int(size.width))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        cache.setObject(rep.nsImage, forKey: key)
        return rep.nsImage
    }
}

struct ThumbnailView: View {
    let url: URL
    var size = CGSize(width: 320, height: 200)
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Theme.thumbBG
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: Wrangler.videoExts.contains(url.pathExtension.lowercased()) ? "film" : "photo")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .clipped()
        .task(id: url) { image = await Thumbnails.shared.image(for: url, size: size) }
    }
}

struct TypeTag: View {
    let type: FootageType
    var body: some View {
        Text(type.label)
            .font(.inter(11.5, .semibold))
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(type.color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}


/// Video lengths, read once and remembered.
actor DurationCache {
    static let shared = DurationCache()
    private var cache: [URL: Double] = [:]
    func duration(of url: URL) async -> Double? {
        if let d = cache[url] { return d }
        guard let d = try? await AVURLAsset(url: url).load(.duration).seconds, d.isFinite, d > 0 else { return nil }
        cache[url] = d
        return d
    }
}

/// The video length shown on the bottom right of a thumbnail, e.g. "0:18".
struct DurationBadge: View {
    let url: URL
    var compact = false
    @State private var text: String? = nil

    var body: some View {
        Text(text ?? "")
            .font(.mono(compact ? 10.5 : 12))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 6 : 8).padding(.vertical, 3)
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(compact ? 6 : 10)
            .opacity(text == nil ? 0 : 1)
            .task(id: url) {
                if let d = await DurationCache.shared.duration(of: url) { text = Self.format(d) }
            }
    }

    static func format(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }
}
