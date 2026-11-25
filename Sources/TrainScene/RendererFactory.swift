import Foundation
import SLCore

/// Picks the renderer for a run. `SL_RENDERER=scenkit` opts into the
/// SceneKit spike renderer; anything else keeps the placeholder default.
/// Kept out of `sl/main.swift` so slChecks can exercise the selection.
@MainActor
public enum RendererFactory {
    public static func make(spec: RunSpec, stripWidth: CGFloat) -> any Renderer {
        if ProcessInfo.processInfo.environment["SL_RENDERER"] == "scenkit" {
            return SceneKitRenderer(spec: spec, stripWidth: stripWidth)
        }
        return PlaceholderRenderer(spec: spec, stripWidth: stripWidth)
    }
}
