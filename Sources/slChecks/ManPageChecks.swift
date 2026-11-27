import Foundation
import SLTestKit

/// `sl.1` is the shipped documentation; these checks pin the contract
/// that every flag in `RunSpec.usage` (plus `--stealth`) is documented,
/// along with the required sections.
public let manPageChecks: [Check] = [
    Check("when the man page is read it documents every classic flag") {
        let text = try manPageText()
        for flag in ["a", "d", "e", "F", "l", "s", "w", "v"] {
            try expect(text.contains("Fl \(flag)"), "missing -\(flag)")
        }
        try expect(text.contains("Ns Ar n"), "missing -<number-of-cars>")
    },
    Check("when the man page is read it documents every long flag") {
        let text = try manPageText()
        for flag in ["help", "version", "model", "all", "freeze", "duration",
                     "scale", "stealth", "cars", "angle"] {
            try expect(text.contains("Fl -\(flag)"), "missing --\(flag)")
        }
    },
    Check("when the man page is read it has FILES EXAMPLES and HISTORY sections") {
        let text = try manPageText()
        for section in ["FILES", "EXAMPLES", "HISTORY"] {
            try expect(text.contains(".Sh \(section)"), "missing .Sh \(section)")
        }
    },
    Check("when the man page is read it credits mtoyoda and notes macOS") {
        let text = try manPageText()
        try expect(text.contains("mtoyoda"), "missing mtoyoda credit")
        try expect(text.contains("macOS"), "missing macOS note")
    },
]

private func manPageText() throws -> String {
    // #filePath is <root>/Sources/slChecks/ManPageChecks.swift at compile
    // time; sl.1 sits at the repository root.
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // slChecks
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // root
    let url = root.appendingPathComponent("sl.1")
    return try String(contentsOf: url, encoding: .utf8)
}
