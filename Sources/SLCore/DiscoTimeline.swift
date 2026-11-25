import Foundation

/// The `-d` disco timeline — pure timing math, no AppKit/SceneKit.
/// Three effects share one clock: the loco body hue cycles continuously,
/// the scene lights alternate between two colors, and the train scale
/// pulses on the beat. All rates are seizure-safe by construction:
/// color changes never exceed `maxFlashRate` per second and the scale
/// pulse amplitude stays small.
public struct DiscoTimeline: Sendable {
    /// Hard ceiling on color changes per second (WCAG/photosensitivity
    /// guidance for flashing content).
    public static let maxFlashRate: Double = 3

    /// Color alternations per second; clamped to `maxFlashRate`.
    public var flashRate: Double
    /// Seconds for one full hue cycle of the loco body.
    public var huePeriod: Double
    /// Scale pulse amplitude as a fraction of base scale (0.08 = ±8%).
    public var pulseAmplitude: Double

    public init(flashRate: Double = 2, huePeriod: Double = 4,
                pulseAmplitude: Double = 0.08) {
        precondition(huePeriod > 0)
        precondition(pulseAmplitude >= 0 && pulseAmplitude <= 0.25)
        self.flashRate = min(max(flashRate, 0), Self.maxFlashRate)
        self.huePeriod = huePeriod
        self.pulseAmplitude = pulseAmplitude
    }

    /// Body hue in `[0, 1)` for `NSColor(hue:…)`-style consumers; wraps
    /// every `huePeriod` seconds so consecutive shots differ.
    public func hue(at t: TimeInterval) -> Double {
        let p = (t / huePeriod).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }

    /// Which of the two light colors is active: flips every
    /// `1 / flashRate` seconds, so the flash rate is bounded by
    /// `maxFlashRate` regardless of the requested rate.
    public func lightIndex(at t: TimeInterval) -> Int {
        guard flashRate > 0 else { return 0 }
        return Int((t * flashRate).rounded(.down)) % 2
    }

    /// Beat-synced scale factor: `1 ± pulseAmplitude`, sinusoidal at the
    /// flash rate so each flash lands on a pulse peak.
    public func scale(at t: TimeInterval) -> Double {
        1 + pulseAmplitude * sin(2 * .pi * flashRate * t)
    }
}
