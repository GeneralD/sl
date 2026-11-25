import AVFoundation
import Foundation
import SLCore
import TrainScene

/// Playback engine for `-s` (issue #35): a chuff loop paced to wheel
/// speed, a whistle on entry and exit, and `-a` layers screams over the
/// run. Silent unless `spec.sound`; every asset miss degrades to a
/// no-op rather than a crash — the gag is the train, not the speaker.
///
/// Driven by `update(t:finished:)` from the run loop's frame timer, so
/// cue timing is a pure function of run time — the same `t` the
/// trajectory consumes. Freeze/shot mode never constructs an engine.
@MainActor
final class AudioEngine {
    /// Vendored cue files under `share/sl/audio/` (resolved by
    /// `audioAssetURL` — argv0-relative, install- and worktree-aware).
    private enum Cue {
        static let chuff = "chuff.wav"
        static let whistle = "whistle.wav"
        static let scream = "scream.wav"
    }

    /// Chuff loop pacing: one chuff file per wheel revolution at calm
    /// speed; `speedFactor` (`-w`) spins the wheels faster, so the loop
    /// interval divides by it. Floored so `-w` can't machine-gun.
    private static let minChuffInterval: TimeInterval = 0.4

    private let spec: RunSpec
    private let duration: TimeInterval
    private let chuffInterval: TimeInterval
    /// Scream cue times as fractions of the crossing — the accident
    /// reads mid-run and again on the way out.
    private static let screamFractions: [Double] = [0.55, 0.8]

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    /// Format the player node was connected with — `scheduleBuffer`
    /// stalls on a mismatch, so `play` drops foreign-format buffers.
    private var nodeFormat: AVAudioFormat?
    private var buffers: [String: AVAudioPCMBuffer] = [:]

    private var started = false
    private var exited = false
    /// Run time at which the exit whistle has finished ringing — the
    /// run loop holds the process open until then so the whistle is
    /// actually heard instead of clipped by `exit(0)`.
    private var exitAt: TimeInterval = 0
    private var nextChuff: TimeInterval = 0
    private var nextScream = 0

    /// `nil` = silent run: `-s` absent, non-positive duration, or no
    /// cue asset resolvable. Never throws — audio must not crash a run.
    init?(spec: RunSpec, duration: TimeInterval) {
        guard spec.sound, duration > 0 else { return nil }
        self.spec = spec
        self.duration = duration

        var loaded: [String: AVAudioPCMBuffer] = [:]
        for name in [Cue.chuff, Cue.whistle, Cue.scream] {
            if let buffer = Self.loadBuffer(named: name) {
                loaded[name] = buffer
            }
        }
        guard !loaded.isEmpty else { return nil }
        buffers = loaded

        let chuffSeconds = loaded[Cue.chuff].map(Self.seconds(of:))
            ?? Self.minChuffInterval
        chuffInterval = max(
            Self.minChuffInterval,
            chuffSeconds / max(spec.speedFactor, 0.25))

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        // Connect in the buffers' own format: a nil format lets the
        // node negotiate the mixer's rate, and scheduleBuffer then
        // stalls on the format mismatch instead of playing.
        if let format = loaded.values.first?.format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            nodeFormat = format
        } else {
            engine.connect(player, to: engine.mainMixerNode, format: nil)
        }
        do {
            try engine.start()
        } catch {
            FileHandle.standardError.write(
                Data("sl: audio unavailable — \(error.localizedDescription)\n".utf8))
            return nil
        }
        self.engine = engine
        self.player = player
    }

    /// Advance cues to run time `t`. The first call plays the entry
    /// whistle; `finished` plays the exit whistle once and stops the
    /// engine. Chuffs fire whenever `t` crosses the next paced slot.
    func update(t: TimeInterval, finished: Bool) {
        guard let engine, engine.isRunning else { return }
        if !started {
            started = true
            play(Cue.whistle)
        }
        guard !finished else {
            guard !exited else { return }
            exited = true
            play(Cue.whistle)
            // Hold the run loop for the whistle's tail. AVAudioEngine
            // stop calls can block on the render thread, and the frame
            // timer lives on the main actor — so nothing here ever
            // calls stop(); `exit(0)` tears the engine down instead.
            exitAt = t + (buffers[Cue.whistle].map(Self.seconds(of:)) ?? 0) + 0.25
            return
        }
        while t >= nextChuff {
            play(Cue.chuff)
            nextChuff += chuffInterval
        }
        while spec.accident, nextScream < Self.screamFractions.count,
              t >= Self.screamFractions[nextScream] * duration {
            play(Cue.scream)
            nextScream += 1
        }
    }

    /// Seconds of run-loop time still needed after the train finished —
    /// the exit whistle's tail. 0 for a silent engine or once it rang.
    func tailRemaining(t: TimeInterval) -> TimeInterval {
        guard exited else { return 0 }
        return max(0, exitAt - t)
    }

    private func play(_ name: String) {
        guard let buffer = buffers[name],
              nodeFormat == nil || buffer.format.isEqual(nodeFormat!)
        else { return }
        player?.scheduleBuffer(buffer, at: nil, options: [])
        player?.play()
    }

    private static func loadBuffer(named name: String) -> AVAudioPCMBuffer? {
        guard let url = audioAssetURL(named: name),
              FileManager.default.fileExists(atPath: url.path),
              let file = try? AVAudioFile(forReading: url)
        else { return nil }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        guard (try? file.read(into: buffer)) != nil else { return nil }
        return buffer
    }

    private static func seconds(of buffer: AVAudioPCMBuffer) -> TimeInterval {
        TimeInterval(buffer.frameLength) / buffer.format.sampleRate
    }
}
