import Foundation
import AVFoundation
import WhisperKit

/// On-device transcription with WhisperKit (Whisper, by Argmax; MIT licence).
/// The model downloads once into Lasso's private folder; after that nothing leaves the Mac.
actor Transcriber {
    static let shared = Transcriber()

    /// Whisper's small multilingual model ("Fast"): about 0.5 GB, handles English and French.
    static let variant = "openai_whisper-small"

    /// ~/Library/Application Support/Lasso/Models
    static var modelsBase: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Lasso/Models", isDirectory: true)
    }

    private var pipe: WhisperKit?
    private var modelFolder: URL?

    /// The downloaded model folder, if it's already on this Mac.
    static func installedModelFolder() -> URL? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: modelsBase, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in en where url.lastPathComponent == variant {
            // A complete download holds the compiled model parts.
            let parts = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
            if parts.contains(where: { $0.hasSuffix(".mlmodelc") }) { return url }
        }
        return nil
    }

    /// Downloads the model if needed. `progress` is called with 0…1.
    func ensureModel(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if let folder = modelFolder { return folder }
        if let folder = Self.installedModelFolder() { modelFolder = folder; return folder }
        try FileManager.default.createDirectory(at: Self.modelsBase, withIntermediateDirectories: true)
        let folder = try await WhisperKit.download(variant: Self.variant, downloadBase: Self.modelsBase,
                                                   progressCallback: { p in progress(p.fractionCompleted) })
        modelFolder = folder
        return folder
    }

    private func loadedPipe() async throws -> WhisperKit {
        if let pipe { return pipe }
        let folder = try await ensureModel(progress: { _ in })
        let config = WhisperKitConfig(modelFolder: folder.path, download: false)
        let made = try await WhisperKit(config)
        pipe = made
        return made
    }

    struct Line { let start: Double; let end: Double; let text: String }

    /// Transcribes a clip's audio. Returns no lines when there's no speech.
    func transcribe(_ url: URL) async throws -> [Line] {
        var samples = await Self.audioSamples(url)
        guard samples.count > 16000 else { return [] }   // under a second of audio
        Self.normalize(&samples)
        let whisper = try await loadedPipe()
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = nil          // detect the language (English, French, …)
        options.skipSpecialTokens = true
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        var lines: [Line] = []
        for result in results {
            for seg in result.segments {
                let text = Self.clean(seg.text)
                if !text.isEmpty { lines.append(Line(start: Double(seg.start), end: Double(seg.end), text: text)) }
            }
        }
        return lines
    }

    /// Raises quiet recordings (a phone across the room, a soft voice) so Whisper doesn't mistake them for silence.
    static func normalize(_ samples: inout [Float]) {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0.0005, peak < 0.5 else { return }
        let gain = min(0.9 / peak, 30)
        for i in samples.indices { samples[i] *= gain }
    }

    /// Removes Whisper's control tokens such as <|0.00|> and tidies spacing.
    static func clean(_ s: String) -> String {
        let noTokens = s.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
        return noTokens.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The clip's sound as 16 kHz mono samples, which is what Whisper expects.
    static func audioSamples(_ url: URL) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
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
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
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
        return samples
    }

    /// Writes "name.srt" next to the clip. Returns false when there was nothing to write.
    @discardableResult
    static func writeSRT(_ lines: [Line], for clip: URL) throws -> Bool {
        guard !lines.isEmpty else { return false }
        func stamp(_ t: Double) -> String {
            let ms = Int((t * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
        }
        var out = ""
        for (i, line) in lines.enumerated() {
            out += "\(i + 1)\n\(stamp(line.start)) --> \(stamp(line.end))\n\(line.text)\n\n"
        }
        let srt = clip.deletingPathExtension().appendingPathExtension("srt")
        try out.write(to: srt, atomically: true, encoding: .utf8)
        return true
    }

    /// The plain words of a clip's .srt, for search. Nil when there's no transcript.
    static func transcriptText(for clip: URL) -> String? {
        let srt = clip.deletingPathExtension().appendingPathExtension("srt")
        guard let raw = try? String(contentsOf: srt, encoding: .utf8) else { return nil }
        let words = raw.components(separatedBy: "\n").filter { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            return !l.isEmpty && Int(l) == nil && !l.contains("-->")
        }
        return words.joined(separator: " ")
    }

    /// Footage types worth transcribing: the ones with speech.
    static func wantsTranscript(_ type: FootageType) -> Bool {
        [.talk, .aroll, .vo, .offscreen].contains(type)
    }
}
