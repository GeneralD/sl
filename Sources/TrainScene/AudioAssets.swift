import Foundation

/// Locates the vendored audio assets. Layout decision (task #34): the
/// files live in `share/sl/audio/` — outside `Sources/` so Package.swift
/// stays untouched — and `make install` copies them to
/// `$(PREFIX)/share/sl/audio/` next to `$(PREFIX)/bin/sl`.
///
/// Resolution is argv0-relative (`Bundle.main.executableURL`): an
/// ancestor walk of the executable's directory finds the installed
/// layout (`<prefix>/bin/sl` → `<prefix>/share/sl/audio`), then a walk
/// of the working directory covers SwiftPM scratch builds and
/// worktrees, where the binary lives under `.hackathon/`.
public func audioAssetDirectory() -> URL? {
    let exeDir = Bundle.main.executableURL?
        .deletingLastPathComponent()
        .resolvingSymlinksInPath()
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .resolvingSymlinksInPath()
    let candidates = [exeDir].compactMap { $0 }
        + ancestors(of: exeDir)
        + ancestors(of: cwd)
    return candidates.lazy
        .map { $0.appendingPathComponent("share/sl/audio") }
        .first { isDirectory($0) }
}

/// URL of one vendored asset (`chuff.wav`, `whistle.wav`, `scream.wav`),
/// or nil when the asset directory cannot be resolved.
public func audioAssetURL(named name: String) -> URL? {
    audioAssetDirectory()?.appendingPathComponent(name)
}

private func ancestors(of start: URL?) -> [URL] {
    guard var dir = start else { return [] }
    var result: [URL] = []
    // `.path` comparison, not `==`: URL equality keeps component
    // details that never converge at the filesystem root.
    while result.count < 64 {
        result.append(dir)
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { return result }
        dir = parent
    }
    return result
}

private func isDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        && isDir.boolValue
}
