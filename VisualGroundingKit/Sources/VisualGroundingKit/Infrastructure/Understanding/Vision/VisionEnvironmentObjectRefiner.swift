//
//  VisionEnvironmentObjectRefiner.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public final class VisionEnvironmentObjectRefiner: EnvironmentObjectRefining {
    public init() {}

    public func refine(
        background: BackgroundDescriptor?,
        rawVision: RawVisionAnalysis
    ) async throws -> EnvironmentObjectRefineResult {
        let existing = background?.environmentObjects.map { $0.lowercased() } ?? []
        let labels = rawVision.classifications.map { $0.identifier.lowercased() }
        var objects = existing
        var sceneRefHints: [String] = background?.sceneRefHints ?? []

        if labels.contains(where: { $0.contains("tree") || $0.contains("branch") || $0.contains("foliage") }) {
            objects.append("tree")
        }
        if labels.contains(where: { $0.contains("grass") }) {
            objects.append("grass")
        }
        if labels.contains(where: { $0.contains("road") || $0.contains("street") || $0.contains("path") }) {
            objects.append("road")
            sceneRefHints.append("roadside_like")
        }
        if objects.contains("tree") && objects.contains("grass") {
            sceneRefHints.append("park_like")
        }
        if objects.contains("tree") {
            sceneRefHints.append("tree_line_like")
        }

        return EnvironmentObjectRefineResult(
            environmentObjects: dedup(objects),
            sceneRefHints: dedup(sceneRefHints)
        )
    }
}

private extension VisionEnvironmentObjectRefiner {
    func dedup(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }
}
