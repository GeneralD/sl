import AppKit
import Foundation
import OverlayKit
import SLCore

/// Picks the renderer for a run. SceneKit is the committed renderer
/// (spike B); `SL_RENDERER=placeholder` keeps the skeleton view around
/// for A/B debugging. Kept out of `sl/main.swift` so slChecks can
/// exercise the selection.
@MainActor
public enum RendererFactory {
    public static func make(spec: RunSpec, stripWidth: CGFloat,
                            model: ModelAsset.Loaded? = nil,
                            dock: [DockZone] = [],
                            laneHeight: CGFloat = OverlayGeometry
                                .referenceLaneHeight) -> any Renderer {
        if ProcessInfo.processInfo.environment["SL_RENDERER"] == "placeholder" {
            return PlaceholderRenderer(
                spec: spec, stripWidth: stripWidth, dock: dock,
                laneHeight: laneHeight)
        }
        return SceneKitRenderer(
            spec: spec, stripWidth: stripWidth, model: model, dock: dock,
            laneHeight: laneHeight)
    }
}
