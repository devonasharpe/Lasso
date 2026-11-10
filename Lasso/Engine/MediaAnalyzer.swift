import AVFoundation
import Vision
import SoundAnalysis
import CoreGraphics
import ImageIO

struct VideoMeta {
    var duration: Double
    var fps: Double
    var size: CGSize
    var created: Date?
    var hasAudio: Bool
    var model: String?
}

/// Everything Lasso learns from a file, using only Apple's built-in frameworks.
enum MediaAnalyzer {

    // MARK: Metadata

    static func videoMeta(_ url: URL) async -> VideoMeta? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            var created: Date? = nil
            if let item = try await asset.load(.creationDate) {
                created = try? await item.load(.dateValue)
            }
            var fps = 30.0
            var size = CGSize.zero
            if let v = try await asset.loadTracks(withMediaType: .video).first {
                fps = Double(try await v.load(.nominalFrameRate))
                let (natural, transform) = try await v.load(.naturalSize, .preferredTransform)
                let rect = CGRect(origin: .zero, size: natural).applying(transform)
                size = CGSize(width: abs(rect.width), height: abs(rect.height))
            }
            let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
            var model: String? = nil
            if let common = try? await asset.load(.commonMetadata),
               let item = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierModel).first {
                model = try? await item.load(.stringValue)
            }
            return VideoMeta(duration: duration, fps: fps, size: size, created: created, hasAudio: hasAudio, model: model)
        } catch {
            return nil
        }
    }

    static func photoMeta(_ url: URL) -> (created: Date?, size: CGSize, model: String?) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return (nil, .zero, nil) }
        var w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        var h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if orientation >= 5 { swap(&w, &h) }
        var created: Date? = nil
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter()
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            created = f.date(from: s)
        }
        let model = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String
        return (created, CGSize(width: w, height: h), model)
    }

    // MARK: Speech (Apple SoundAnalysis)

    final class SpeechObserver: NSObject, SNResultsObserving {
        var windows: [(time: Double, confidence: Double)] = []
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult else { return }
            let c = r.classification(forIdentifier: "speech")?.confidence ?? 0
            windows.append((r.timeRange.start.seconds, c))
        }
        func request(_ request: SNRequest, didFailWithError error: Error) {}
        func requestDidComplete(_ request: SNRequest) {}
    }

    struct AudioResult {
        var speechWindows: [(time: Double, confidence: Double)] = []
        var windowStep = 0.4875
        var rmsDB: [Double] = []      // loudness every 0.25 s
        let rmsStep = 0.25
    }

    static func audio(_ url: URL) async -> AudioResult {
        var result = AudioResult()
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return result }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return result }
        reader.add(output)
        guard reader.startReading() else { return result }

        var samples: [Float] = []
        while let sb = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress {
                    _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
                }
            }
            samples.append(contentsOf: chunk)
        }
        guard samples.count > 8000 else { return result }

        // Loudness every 0.25 s
        let block = 4000
        var i = 0
        while i + block <= samples.count {
            var sum: Float = 0
            for j in i..<(i + block) { sum += samples[j] * samples[j] }
            result.rmsDB.append(20 * log10(Double(sqrt(sum / Float(block))) + 1e-9))
            i += block
        }

        // Apple's built-in sound classifier, which includes a "speech" class
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return result }
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let observer = SpeechObserver()
        do { try analyzer.add(request, withObserver: observer) } catch { return result }
        let chunkSize = 16000
        var pos = 0
        while pos < samples.count {
            let n = min(chunkSize, samples.count - pos)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { break }
            buffer.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { src in
                if let dst = buffer.floatChannelData?[0], let base = src.baseAddress {
                    dst.update(from: base + pos, count: n)
                }
            }
            analyzer.analyze(buffer, atAudioFramePosition: AVAudioFramePosition(pos))
            pos += n
        }
        analyzer.completeAnalysis()
        result.speechWindows = observer.windows.sorted { $0.time < $1.time }
        if result.speechWindows.count > 1 {
            result.windowStep = max(0.1, result.speechWindows[1].time - result.speechWindows[0].time)
        }
        return result
    }

    static func speechStats(_ a: AudioResult) -> (share: Double, longest: Double) {
        guard !a.speechWindows.isEmpty else { return (0, 0) }
        let on = a.speechWindows.map { $0.confidence >= 0.5 }
        var longest = 0, run = 0
        for v in on { run = v ? run + 1 : 0; longest = max(longest, run) }
        let share = Double(on.filter { $0 }.count) / Double(on.count)
        return (share, longest == 0 ? 0 : Double(longest) * a.windowStep + 0.5)
    }

    // MARK: Faces and people (Apple Vision)

    static func people(_ url: URL, duration: Double) async -> (faceShare: Double, faceSize: Double, personShare: Double) {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let n = 6
        var faceFrames = 0, personFrames = 0
        var sizes: [Double] = []
        for k in 0..<n {
            let t = CMTime(seconds: duration * (Double(k) + 0.5) / Double(n), preferredTimescale: 600)
            guard let frame = try? await gen.image(at: t) else { continue }
            let faceRequest = VNDetectFaceRectanglesRequest()
            let humanRequest = VNDetectHumanRectanglesRequest()
            humanRequest.upperBodyOnly = false
            let handler = VNImageRequestHandler(cgImage: frame.image, options: [:])
            try? handler.perform([faceRequest, humanRequest])
            // faces smaller than 1% of the frame are ignored
            let faces = (faceRequest.results ?? []).map { Double($0.boundingBox.width * $0.boundingBox.height) }.filter { $0 >= 0.01 }
            if let biggest = faces.max() {
                faceFrames += 1; personFrames += 1; sizes.append(biggest)
            } else if let humans = humanRequest.results, humans.contains(where: { $0.confidence >= 0.5 }) {
                personFrames += 1
            }
        }
        let median = sizes.isEmpty ? 0 : sizes.sorted()[sizes.count / 2]
        return (Double(faceFrames) / Double(n), median, Double(personFrames) / Double(n))
    }

    // MARK: Shot cuts

    static func cuts(_ url: URL, duration: Double) async -> [Double] {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 64, height: 64)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        let step = 0.25
        let count = min(Int(duration / step), 600)
        guard count > 2 else { return [] }
        var previous: [Float]? = nil
        var cuts: [Double] = []
        var lastCut = -10.0
        for k in 0..<count {
            let seconds = Double(k) * step
            guard let frame = try? await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) else { continue }
            let pixels = gray32(frame.image)
            if let prev = previous {
                var diff: Float = 0
                for j in 0..<pixels.count { diff += abs(pixels[j] - prev[j]) }
                diff /= Float(pixels.count)
                // a picture change of more than 15% between frames a quarter-second apart is a cut
                if diff > 0.15 && seconds - lastCut > 0.5 {
                    cuts.append(seconds); lastCut = seconds
                }
            }
            previous = pixels
        }
        return cuts
    }

    private static func gray32(_ image: CGImage) -> [Float] {
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side * side)
        bytes.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                   bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                ctx.interpolationQuality = .low
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            }
        }
        return bytes.map { Float($0) / 255 }
    }

    /// Narration recorded separately keeps going, at the same level, when the picture cuts.
    /// Location audio changes with the place being filmed.
    static func narrationCarriesOverCuts(_ cuts: [Double], audio a: AudioResult) -> Bool {
        guard cuts.count >= 3, a.rmsDB.count > 8 else { return false }
        func median(_ xs: ArraySlice<Double>) -> Double {
            let s = xs.sorted(); return s.isEmpty ? 0 : s[s.count / 2]
        }
        func jump(at i: Int) -> Double {
            abs(median(a.rmsDB[(i - 2)..<i]) - median(a.rmsDB[i..<(i + 2)]))
        }
        let idx = cuts.map { Int($0 / a.rmsStep) }.filter { $0 >= 2 && $0 + 2 <= a.rmsDB.count }
        guard !idx.isEmpty else { return false }
        let atCuts = median(ArraySlice(idx.map(jump)))
        let refs = stride(from: 2, to: a.rmsDB.count - 2, by: max(1, (a.rmsDB.count - 4) / 60)).map { $0 }
        let elsewhere = median(ArraySlice(refs.map(jump)))
        let through = cuts.filter { c in
            guard let w = a.speechWindows.min(by: { abs($0.time - c) < abs($1.time - c) }) else { return false }
            return w.confidence >= 0.5
        }.count
        return atCuts <= elsewhere + 3 && Double(through) / Double(cuts.count) >= 0.5
    }
}
