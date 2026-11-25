import AVFoundation
import Foundation
import SLTestKit
import TrainScene

private let audioAssetNames = ["chuff.wav", "whistle.wav", "scream.wav"]

private struct AssetError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private func requireAsset(_ name: String) throws -> URL {
    guard let url = audioAssetURL(named: name),
          FileManager.default.fileExists(atPath: url.path)
    else { throw AssetError(message: "missing audio asset: \(name)") }
    return url
}

public let audioAssetChecks: [Check] = [
    Check("when audio assets are requested the vendored directory resolves") {
        try expect(audioAssetDirectory() != nil)
    },
    Check("when each named audio asset is requested it returns an existing file") {
        for name in audioAssetNames {
            _ = try requireAsset(name)
        }
    },
    Check("when each audio asset is opened with AVAudioFile it decodes") {
        for name in audioAssetNames {
            let file = try AVAudioFile(forReading: requireAsset(name))
            try expect(file.length > 0, name)
        }
    },
    Check("when audio assets are measured their total size stays under 2 MB") {
        var total = 0
        for name in audioAssetNames {
            let size = try requireAsset(name)
                .resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            total += size
        }
        try expect(total > 0 && total < 2 * 1024 * 1024, "\(total) bytes")
    },
    Check("when LICENSES.md is sought at the repo root it exists") {
        guard let audioDir = audioAssetDirectory() else {
            throw AssetError(message: "audio directory unresolved")
        }
        let root = audioDir
            .deletingLastPathComponent()  // sl
            .deletingLastPathComponent()  // share
            .deletingLastPathComponent()  // repo root
        let licenses = root.appendingPathComponent("LICENSES.md")
        try expect(FileManager.default.fileExists(atPath: licenses.path))
    },
]
