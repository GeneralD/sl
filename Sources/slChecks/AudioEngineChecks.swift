import AVFoundation
import Foundation
import SLCore
import SLTestKit
import TrainScene

/// Spec sentences for the `-s` playback engine (Sources/sl/AudioEngine.swift).
/// The engine itself is app-lifecycle code in the `sl` executable —
/// unreachable from slChecks by target design — so these pin the
/// contract it consumes: the cue asset set it loads and the `RunSpec`
/// flags that gate it.
private let cueAssetNames = ["chuff.wav", "whistle.wav", "scream.wav"]

private struct SpecParseFailure: Error {
    let message: String
}

private func parsedSpec(_ args: [String]) throws -> RunSpec {
    guard case .success(let spec) = RunSpec.parse(args) else {
        throw SpecParseFailure(message: "parse failed for \(args)")
    }
    return spec
}

public let audioEngineChecks: [Check] = [
    Check("when the audio engine's cue assets are requested each resolves to a decodable file") {
        let urls = cueAssetNames
            .compactMap { audioAssetURL(named: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        try expect(urls.count == cueAssetNames.count, "unresolved cue asset")
        for url in urls {
            let file = try AVAudioFile(forReading: url)
            try expect(file.length > 0, url.lastPathComponent)
            try expect(file.processingFormat.sampleRate > 0)
            try expect(file.processingFormat.channelCount > 0)
        }
    },
    Check("when -s is absent the spec leaves sound off so the engine stays silent") {
        let spec = try parsedSpec(["sl"])
        try expect(!spec.sound)
    },
    Check("when -s is passed the spec requests sound for the engine") {
        let spec = try parsedSpec(["sl", "-s"])
        try expect(spec.sound)
    },
    Check("when -s and -a are combined the spec carries both sound and accident") {
        let spec = try parsedSpec(["sl", "-sa"])
        try expect(spec.sound && spec.accident)
    },
]
