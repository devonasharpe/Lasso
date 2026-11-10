import Foundation
import AVFoundation
import Vision
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import OnnxRuntimeBindings   // ONNX Runtime (Swift Package name for its Objective-C API)

// MARK: - Stored face data (private to this Mac)

struct Person: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var isMe = false
}

/// One face found in one file. Linked to the file by content fingerprint, so renames and moves keep the link.
struct FaceRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var fingerprint: String
    var fileName: String
    var embedding: [Float]
    var personID: UUID?
    var thumb: String          // file name of the small face picture in Faces/thumbs
}

struct FaceData: Codable {
    var people: [Person] = []
    var faces: [FaceRecord] = []
    /// "Don't track this person": an unnamed faceprint only, so Lasso doesn't ask again.
    var ignored: [[Float]] = []
    /// Files already looked at, by fingerprint.
    var scanned: Set<String> = []
}

/// A new group of faces waiting for a name in the naming window.
struct FaceGroup: Identifiable {
    let id = UUID()
    var faces: [FaceRecord]
    var name = ""
    var isMe = false
    var track = true
    var fileCount: Int { Set(faces.map(\.fingerprint)).count }
}

/// "Is this Marie?" — faces that look like someone already named, but not certainly.
struct FaceConfirm: Identifiable {
    let id = UUID()
    var faces: [FaceRecord]
    var person: Person
    var answer: Bool? = nil     // nil = not answered yet
    var otherName = ""
}

// MARK: - Engine

enum Faces {
    /// ~/Library/Application Support/Lasso/Faces
    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Lasso/Faces", isDirectory: true)
    }
    static var thumbsFolder: URL { folder.appendingPathComponent("thumbs", isDirectory: true) }
    static var dataFile: URL { folder.appendingPathComponent("faces.json") }

    // Matching thresholds (cosine similarity of SFace faceprints)
    static let sameGroup: Float = 0.363      // SFace's published threshold for "same person"
    static let sureMatch: Float = 0.42       // recognised silently
    static let maybeMatch: Float = 0.32      // ask "Is this …?"

    static func load() -> FaceData {
        guard let data = try? Data(contentsOf: dataFile),
              let d = try? JSONDecoder().decode(FaceData.self, from: data) else { return FaceData() }
        return d
    }

    static func save(_ d: FaceData) {
        try? FileManager.default.createDirectory(at: thumbsFolder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(d) { try? data.write(to: dataFile, options: .atomic) }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    static func thumbURL(_ f: FaceRecord) -> URL { thumbsFolder.appendingPathComponent(f.thumb) }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { s += a[i] * b[i] }
        return s
    }

    static func centroid(_ vs: [[Float]]) -> [Float] {
        guard let first = vs.first else { return [] }
        var c = [Float](repeating: 0, count: first.count)
        for v in vs { for i in 0..<c.count { c[i] += v[i] } }
        let n = sqrt(c.reduce(0) { $0 + $1 * $1 })
        return n > 0 ? c.map { $0 / n } : c
    }

    /// Groups faces that belong together (average linkage, updated incrementally so it stays quick).
    static func cluster(_ faces: [FaceRecord]) -> [[FaceRecord]] {
        let n = faces.count
        guard n > 1 else { return faces.map { [$0] } }
        var sim = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for i in 0..<n { for j in (i + 1)..<n { let v = cosine(faces[i].embedding, faces[j].embedding); sim[i][j] = v; sim[j][i] = v } }
        var members: [[Int]] = (0..<n).map { [$0] }
        var alive = [Bool](repeating: true, count: n)
        while true {
            var best: Float = -2, ba = -1, bb = -1
            for a in 0..<n where alive[a] {
                for b in (a + 1)..<n where alive[b] && sim[a][b] > best { best = sim[a][b]; ba = a; bb = b }
            }
            guard ba >= 0, best >= sameGroup else { break }
            let na = Float(members[ba].count), nb = Float(members[bb].count)
            for k in 0..<n where alive[k] && k != ba && k != bb {
                let v = (na * sim[ba][k] + nb * sim[bb][k]) / (na + nb)
                sim[ba][k] = v; sim[k][ba] = v
            }
            members[ba] += members[bb]
            alive[bb] = false
        }
        return (0..<n).filter { alive[$0] }.map { c in members[c].map { i in faces[i] } }
    }
}

/// Finds faces in a photo or video and turns each into a faceprint. Runs on the Mac only.
actor FaceScanner {
    static let shared = FaceScanner()

    private var session: ORTSession?
    private var env: ORTEnv?

    private func model() throws -> ORTSession {
        if let session { return session }
        guard let path = Bundle.main.path(forResource: "face_recognition_sface_2021dec", ofType: "onnx") else {
            throw NSError(domain: "Lasso", code: 1, userInfo: [NSLocalizedDescriptionKey: "The face model is missing from the app."])
        }
        let e = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let s = try ORTSession(env: e, modelPath: path, sessionOptions: try ORTSessionOptions())
        env = e
        session = s
        return s
    }

    /// All usable faces in a file: big enough, facing the camera.
    func scan(_ url: URL, fingerprint: String, isVideo: Bool) async -> [FaceRecord] {
        var out: [FaceRecord] = []
        for image in await Self.frames(url, isVideo: isVideo) {
            for face in Self.detect(image) {
                guard let aligned = Self.align(face, in: image),
                      let emb = try? embed(aligned) else { continue }
                let thumbName = UUID().uuidString + ".jpg"
                Self.saveThumb(face, in: image, name: thumbName)
                out.append(FaceRecord(fingerprint: fingerprint, fileName: url.lastPathComponent,
                                      embedding: emb, personID: nil, thumb: thumbName))
            }
        }
        return out
    }

    // MARK: Frames

    struct Pixels {
        let width: Int
        let height: Int
        let data: [UInt8]      // RGBA
        let cg: CGImage
    }

    static func frames(_ url: URL, isVideo: Bool) async -> [Pixels] {
        var images: [CGImage] = []
        if isVideo {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return [] }
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 960, height: 960)
            for k in [0.1, 0.3, 0.5, 0.7, 0.9] {
                let t = CMTime(seconds: duration * k, preferredTimescale: 600)
                if let img = try? await gen.image(at: t).image { images.append(img) }
            }
        } else {
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceCreateThumbnailWithTransform: true,
                                         kCGImageSourceThumbnailMaxPixelSize: 1280]
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) { images.append(img) }
        }
        return images.compactMap(pixels)
    }

    static func pixels(_ cg: CGImage) -> Pixels? {
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Pixels(width: w, height: h, data: data, cg: cg) : nil
    }

    // MARK: Detection (Apple Vision)

    struct Face {
        let box: CGRect             // top-left origin, pixels
        let points: [CGPoint]       // left eye, right eye, nose, left mouth, right mouth (as seen in the image)
    }

    static func detect(_ img: Pixels) -> [Face] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: img.cg, options: [:])
        try? handler.perform([request])
        let W = Double(img.width), H = Double(img.height)
        var faces: [Face] = []
        for obs in request.results ?? [] {
            guard obs.confidence > 0.6, let lm = obs.landmarks else { continue }
            let r = VNImageRectForNormalizedRect(obs.boundingBox, img.width, img.height)
            let box = CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height)
            guard box.width >= 0.08 * min(W, H) else { continue }         // too small to recognise
            let size = CGSize(width: W, height: H)
            func pts(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                (region?.pointsInImage(imageSize: size) ?? []).map { CGPoint(x: $0.x, y: H - $0.y) }
            }
            func centre(_ p: [CGPoint]) -> CGPoint? {
                guard !p.isEmpty else { return nil }
                return CGPoint(x: p.map(\.x).reduce(0, +) / Double(p.count), y: p.map(\.y).reduce(0, +) / Double(p.count))
            }
            guard let e1 = centre(pts(lm.leftPupil).isEmpty ? pts(lm.leftEye) : pts(lm.leftPupil)),
                  let e2 = centre(pts(lm.rightPupil).isEmpty ? pts(lm.rightEye) : pts(lm.rightPupil)) else { continue }
            let lips = pts(lm.outerLips)
            let nose = pts(lm.nose) + pts(lm.noseCrest)
            guard lips.count >= 2, !nose.isEmpty else { continue }
            let eyes = [e1, e2].sorted { $0.x < $1.x }
            // Facing the camera: eyes far enough apart relative to the face.
            guard (eyes[1].x - eyes[0].x) / box.width >= 0.3 else { continue }
            let mouthL = lips.min { $0.x < $1.x }!, mouthR = lips.max { $0.x < $1.x }!
            let tip = nose.max { $0.y < $1.y }!        // lowest point of the nose
            faces.append(Face(box: box, points: [eyes[0], eyes[1], tip, mouthL, mouthR]))
        }
        return faces
    }

    // MARK: Alignment to SFace's 112 × 112 template

    static let template: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014), CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655), CGPoint(x: 70.7299, y: 92.2041)
    ]

    /// Returns 112 × 112 RGB pixels, channel by channel (what the model expects), values 0…255.
    static func align(_ face: Face, in img: Pixels) -> [Float]? {
        let src = face.points, dst = template
        let n = Double(src.count)
        let ms = CGPoint(x: src.map(\.x).reduce(0, +) / n, y: src.map(\.y).reduce(0, +) / n)
        let md = CGPoint(x: dst.map(\.x).reduce(0, +) / n, y: dst.map(\.y).reduce(0, +) / n)
        var num = 0.0, numB = 0.0, den = 0.0
        for i in 0..<src.count {
            let sx = src[i].x - ms.x, sy = src[i].y - ms.y
            let dx = dst[i].x - md.x, dy = dst[i].y - md.y
            num += sx * dx + sy * dy
            numB += sx * dy - sy * dx
            den += sx * sx + sy * sy
        }
        guard den > 0 else { return nil }
        let a = num / den, b = numB / den          // dst = [[a,-b],[b,a]] * src + t
        let tx = md.x - (a * ms.x - b * ms.y), ty = md.y - (b * ms.x + a * ms.y)
        let det = a * a + b * b
        guard det > 0 else { return nil }
        var out = [Float](repeating: 0, count: 3 * 112 * 112)
        let W = img.width, H = img.height
        img.data.withUnsafeBufferPointer { px in
            for y in 0..<112 {
                for x in 0..<112 {
                    // Back from the template to the source image
                    let u = Double(x) - tx, v = Double(y) - ty
                    let sx = (a * u + b * v) / det, sy = (-b * u + a * v) / det
                    let x0 = Int(floor(sx)), y0 = Int(floor(sy))
                    let fx = sx - Double(x0), fy = sy - Double(y0)
                    for c in 0..<3 {
                        func p(_ xx: Int, _ yy: Int) -> Double {
                            guard xx >= 0, yy >= 0, xx < W, yy < H else { return 0 }
                            return Double(px[(yy * W + xx) * 4 + c])
                        }
                        let val = p(x0, y0) * (1 - fx) * (1 - fy) + p(x0 + 1, y0) * fx * (1 - fy)
                            + p(x0, y0 + 1) * (1 - fx) * fy + p(x0 + 1, y0 + 1) * fx * fy
                        out[c * 112 * 112 + y * 112 + x] = Float(val)
                    }
                }
            }
        }
        return out
    }

    // MARK: Faceprint (SFace via ONNX Runtime)

    private func embed(_ input: [Float]) throws -> [Float] {
        let s = try model()
        let data = input.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.size) }
        let tensor = try ORTValue(tensorData: data, elementType: ORTTensorElementDataType.float, shape: [1, 3, 112, 112])
        let outputs = try s.run(withInputs: ["data": tensor], outputNames: ["fc1"], runOptions: nil)
        guard let value = outputs["fc1"] else { return [] }
        let raw = try value.tensorData() as Data
        var v = [Float](repeating: 0, count: raw.count / MemoryLayout<Float>.size)
        _ = v.withUnsafeMutableBytes { raw.copyBytes(to: $0) }
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return norm > 0 ? v.map { $0 / norm } : v
    }

    // MARK: Face pictures for the naming window

    static func saveThumb(_ face: Face, in img: Pixels, name: String) {
        let side = max(face.box.width, face.box.height) * 1.5
        let rect = CGRect(x: face.box.midX - side / 2, y: face.box.midY - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        guard let crop = img.cg.cropping(to: rect) else { return }
        let size = 160
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let small = ctx.makeImage() else { return }
        try? FileManager.default.createDirectory(at: Faces.thumbsFolder, withIntermediateDirectories: true)
        let url = Faces.thumbsFolder.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, small, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}
