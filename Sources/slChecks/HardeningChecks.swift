import AppKit
import OverlayKit
import SLTestKit

/// Unique scratch root per check run so slot claims never touch the
/// real `/tmp/sl-<uid>-slots` or a concurrently running `sl`.
private func scratchRoot(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("sl-check-\(name)-\(getpid())", isDirectory: true)
}

public let hardeningChecks: [Check] = [
    Check("when five trains hold slots a sixth request returns too many trains") {
        let root = scratchRoot("slots-cap")
        var slots: [Hardening.TrainSlot] = []
        defer {
            for slot in slots { slot.release() }
            try? FileManager.default.removeItem(at: root)
        }
        for i in 0..<Hardening.maxConcurrentTrains {
            guard case .success(let slot) = Hardening.acquireSlot(root: root) else {
                try expect(false, "slot \(i) refused before the cap")
                return
            }
            slots.append(slot)
        }
        guard case .failure(let refusal) = Hardening.acquireSlot(root: root) else {
            try expect(false, "a sixth concurrent train was granted a slot")
            return
        }
        try expect(refusal.message.contains("too many trains"),
                   "refusal was '\(refusal.message)', not 'too many trains'")
        try expectEqual(Hardening.maxConcurrentTrains, 5)
    },
    Check("when a train releases its slot the directory is removed") {
        let root = scratchRoot("slots-release")
        defer { try? FileManager.default.removeItem(at: root) }
        guard case .success(let slot) = Hardening.acquireSlot(root: root) else {
            try expect(false, "could not claim a slot")
            return
        }
        try expect(FileManager.default.fileExists(atPath: slot.directory.path))
        slot.release()
        try expect(!FileManager.default.fileExists(atPath: slot.directory.path))
    },
    Check("when a slot holder's pid is dead the slot is reclaimed") {
        let root = scratchRoot("slots-stale")
        defer { try? FileManager.default.removeItem(at: root) }
        // slot-0: unparseable pid; slot-1: a pid that cannot exist
        // (above macOS pid_max) — both must read as stale.
        let garbage = root.appendingPathComponent("slot-0/pid")
        let dead = root.appendingPathComponent("slot-1/pid")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("slot-0"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("slot-1"), withIntermediateDirectories: true)
        try "not-a-pid\n".write(to: garbage, atomically: false, encoding: .utf8)
        try "999999\n".write(to: dead, atomically: false, encoding: .utf8)
        // Age slot-0 past the claim grace period so its unreadable pid
        // reads as stale rather than a claim in flight.
        let past = Date().addingTimeInterval(-60)
        try FileManager.default.setAttributes(
            [.modificationDate: past],
            ofItemAtPath: root.appendingPathComponent("slot-0").path)

        var slots: [Hardening.TrainSlot] = []
        defer { for slot in slots { slot.release() } }
        for expected in ["slot-0", "slot-1"] {
            guard case .success(let slot) = Hardening.acquireSlot(root: root) else {
                try expect(false, "stale \(expected) was not reclaimed")
                return
            }
            try expectEqual(slot.directory.lastPathComponent, expected)
            slots.append(slot)
        }
    },
    Check("when no window server session exists headless refusal names it") {
        let reason = Hardening.headlessRefusal(hasWindowServerSession: false, screenCount: 1)
        try expect(reason != nil && reason!.contains("window server"),
                   "refusal was '\(reason ?? "nil")'")
    },
    Check("when no usable screen exists headless refusal names it") {
        let reason = Hardening.headlessRefusal(hasWindowServerSession: true, screenCount: 0)
        try expect(reason != nil && reason!.contains("screen"),
                   "refusal was '\(reason ?? "nil")'")
    },
    Check("when a session and a screen exist headless refusal returns nil") {
        try expect(Hardening.headlessRefusal(hasWindowServerSession: true, screenCount: 1) == nil)
        // Exercise the live probe too — its verdict is host-dependent,
        // only that it answers (nil or a reason) is contractual here.
        _ = Hardening.liveHeadlessRefusal()
    },
    Check("when stealth is enabled the overlay window is excluded from capture") {
        try MainActor.assumeIsolated {
            let window = OverlayWindow(frame: .zero)
            defer { window.orderOut(nil) }
            window.setStealth(true)
            try expectEqual(window.sharingType, .none)
        }
    },
    Check("when stealth is disabled the overlay window keeps read-only sharing") {
        try MainActor.assumeIsolated {
            let window = OverlayWindow(frame: .zero)
            defer { window.orderOut(nil) }
            window.setStealth(false)
            try expectEqual(window.sharingType, .readOnly)
        }
    },
    Check("when the slot root is asked for it resolves under the shared temp dir") {
        let root = Hardening.slotRoot(uid: 501)
        try expect(root.path.hasPrefix("/tmp/sl-501-slots"),
                   "unexpected slot root: \(root.path)")
    },
    Check("when a slot refusal is described it prints its message") {
        let refusal = Hardening.SlotRefusal("too many trains")
        try expectEqual(refusal.description, "too many trains")
    },
    Check("when the fade advances alpha falls from 1 to 0 across its duration") {
        var fade = Hardening.FadeOut()
        try expectEqual(fade.duration, Hardening.fadeOutDuration)
        try expectEqual(Double(fade.advance(by: 0)), 1.0)
        try expect(!fade.isFinished)
        try expectEqual(Double(fade.advance(by: 0.1)), 0.5)
        try expect(!fade.isFinished)
        try expectEqual(Double(fade.advance(by: 0.1)), 0.0)
        try expect(fade.isFinished)
        try expectEqual(Double(fade.advance(by: 5)), 0.0) // clamped, never negative
    },
]
