import CoreGraphics
import Foundation

// MARK: - ui_evidence.v1 models

/// Deterministic visual evidence extracted from a UI source.
///
/// This is the `ui_evidence.v1` document. It reports measurable facts and
/// uncertainty only; it never selects components, layouts, or navigation.
public struct UIEvidenceDocument: Codable, Sendable, Hashable {
    public let schema: String
    public let source: UIEvidenceSource
    public let coordinateSpace: String
    public let producer: UIEvidenceProducer
    public let elements: [UIEvidenceElement]
    public let repeatedGroups: [UIEvidenceRepeatedGroup]
    public let sourceTree: UIEvidenceSourceTree
    public let crops: [UIEvidenceCrop]
    public let uncertainties: [UIEvidenceUncertainty]
    public let limits: UIEvidenceLimits

    public init(
        source: UIEvidenceSource,
        producer: UIEvidenceProducer,
        elements: [UIEvidenceElement],
        repeatedGroups: [UIEvidenceRepeatedGroup],
        sourceTree: UIEvidenceSourceTree,
        crops: [UIEvidenceCrop],
        uncertainties: [UIEvidenceUncertainty],
        limits: UIEvidenceLimits
    ) {
        self.schema = "ui_evidence.v1"
        self.source = source
        self.coordinateSpace = "normalized_top_left"
        self.producer = producer
        self.elements = elements
        self.repeatedGroups = repeatedGroups
        self.sourceTree = sourceTree
        self.crops = crops
        self.uncertainties = uncertainties
        self.limits = limits
    }

    enum CodingKeys: String, CodingKey {
        case schema, source, producer, elements, crops, uncertainties, limits
        case coordinateSpace = "coordinate_space"
        case repeatedGroups = "repeated_groups"
        case sourceTree = "source_tree"
    }
}

public struct UIEvidenceSource: Codable, Sendable, Hashable {
    public let assetID: String
    public let sourceKind: UIEvidenceSourceKind
    public let sha256: String
    public let mimeType: String
    public let width: Int
    public let height: Int

    public init(
        assetID: String,
        sourceKind: UIEvidenceSourceKind,
        sha256: String,
        mimeType: String,
        width: Int,
        height: Int
    ) {
        self.assetID = assetID
        self.sourceKind = sourceKind
        self.sha256 = sha256
        self.mimeType = mimeType
        self.width = width
        self.height = height
    }

    enum CodingKeys: String, CodingKey {
        case sha256, width, height
        case assetID = "asset_id"
        case sourceKind = "source_kind"
        case mimeType = "mime_type"
    }
}

public enum UIEvidenceSourceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case staticImage = "static_image"
    case appScreenshot = "app_screenshot"
    case webScreenshot = "web_screenshot"
}

public struct UIEvidenceProducer: Codable, Sendable, Hashable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct UIEvidenceElement: Codable, Sendable, Hashable {
    public let id: String
    public let kind: UIEvidenceElementKind
    public let role: String?
    public let bbox: UIEvidenceBBox
    public let text: String?
    public let confidence: Double
    public let evidence: UIEvidenceLevel
    public let parentID: String?
    public let interactive: Bool?

    public init(
        id: String,
        kind: UIEvidenceElementKind,
        role: String? = nil,
        bbox: UIEvidenceBBox,
        text: String? = nil,
        confidence: Double,
        evidence: UIEvidenceLevel,
        parentID: String? = nil,
        interactive: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.role = role
        self.bbox = bbox
        self.text = text
        self.confidence = confidence
        self.evidence = evidence
        self.parentID = parentID
        self.interactive = interactive
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, role, bbox, text, confidence, evidence, interactive
        case parentID = "parent_id"
    }
}

public enum UIEvidenceElementKind: String, Codable, Sendable, Hashable, CaseIterable {
    case text
    case image
    case icon
    case control
    case container
    case separator
    case unknown
}

public enum UIEvidenceLevel: String, Codable, Sendable, Hashable, CaseIterable {
    case observed
    case inferred
    case uncertain
}

public struct UIEvidenceRepeatedGroup: Codable, Sendable, Hashable {
    public let id: String
    public let axis: UIEvidenceAxis
    public let memberIDs: [String]
    public let bbox: UIEvidenceBBox
    public let confidence: Double
    public let evidence: UIEvidenceLevel

    public init(
        id: String,
        axis: UIEvidenceAxis,
        memberIDs: [String],
        bbox: UIEvidenceBBox,
        confidence: Double,
        evidence: UIEvidenceLevel
    ) {
        self.id = id
        self.axis = axis
        self.memberIDs = memberIDs
        self.bbox = bbox
        self.confidence = confidence
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case id, axis, bbox, confidence, evidence
        case memberIDs = "member_ids"
    }
}

public enum UIEvidenceAxis: String, Codable, Sendable, Hashable, CaseIterable {
    case vertical
    case horizontal
    case grid
    case unknown
}

public struct UIEvidenceSourceTree: Codable, Sendable, Hashable {
    public let kind: UIEvidenceSourceTreeKind
    public let nodes: [UIEvidenceSourceNode]
    public let truncated: Bool

    public init(kind: UIEvidenceSourceTreeKind, nodes: [UIEvidenceSourceNode], truncated: Bool) {
        self.kind = kind
        self.nodes = nodes
        self.truncated = truncated
    }
}

public enum UIEvidenceSourceTreeKind: String, Codable, Sendable, Hashable, CaseIterable {
    case accessibility
    case dom
    case none
}

public struct UIEvidenceSourceNode: Codable, Sendable, Hashable {
    public let id: String
    public let parentID: String?
    public let role: String
    public let label: String?
    public let bbox: UIEvidenceBBox?
    public let interactive: Bool
    public let visible: Bool
    public let enabled: Bool

    public init(
        id: String,
        parentID: String?,
        role: String,
        label: String? = nil,
        bbox: UIEvidenceBBox? = nil,
        interactive: Bool,
        visible: Bool,
        enabled: Bool
    ) {
        self.id = id
        self.parentID = parentID
        self.role = role
        self.label = label
        self.bbox = bbox
        self.interactive = interactive
        self.visible = visible
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case id, role, label, bbox, interactive, visible, enabled
        case parentID = "parent_id"
    }
}

public struct UIEvidenceCrop: Codable, Sendable, Hashable {
    public let assetID: String
    public let sourceBBox: UIEvidenceBBox
    public let purpose: UIEvidenceCropPurpose

    public init(assetID: String, sourceBBox: UIEvidenceBBox, purpose: UIEvidenceCropPurpose) {
        self.assetID = assetID
        self.sourceBBox = sourceBBox
        self.purpose = purpose
    }

    enum CodingKeys: String, CodingKey {
        case purpose
        case assetID = "asset_id"
        case sourceBBox = "source_bbox"
    }
}

public enum UIEvidenceCropPurpose: String, Codable, Sendable, Hashable, CaseIterable {
    case navigation
    case content
    case controls
    case repeatedGroup = "repeated_group"
    case detail
    case unknown
}

public struct UIEvidenceUncertainty: Codable, Sendable, Hashable {
    public let description: String
    public let relatedElementIDs: [String]
    public let reason: String?

    public init(description: String, relatedElementIDs: [String], reason: String? = nil) {
        self.description = description
        self.relatedElementIDs = relatedElementIDs
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case description, reason
        case relatedElementIDs = "related_element_ids"
    }
}

public struct UIEvidenceLimits: Codable, Sendable, Hashable {
    public let elementCount: Int
    public let elementsTruncated: Bool
    public let treeNodesTruncated: Bool

    public init(elementCount: Int, elementsTruncated: Bool, treeNodesTruncated: Bool) {
        self.elementCount = elementCount
        self.elementsTruncated = elementsTruncated
        self.treeNodesTruncated = treeNodesTruncated
    }

    enum CodingKeys: String, CodingKey {
        case elementCount = "element_count"
        case elementsTruncated = "elements_truncated"
        case treeNodesTruncated = "tree_nodes_truncated"
    }
}

public struct UIEvidenceBBox: Codable, Sendable, Hashable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        let clampedX = Self.clamp(x)
        let clampedY = Self.clamp(y)
        let clampedWidth = min(max(0, width), 1 - clampedX)
        let clampedHeight = min(max(0, height), 1 - clampedY)
        let roundedX = Self.round(clampedX)
        let roundedY = Self.round(clampedY)
        var roundedWidth = Self.round(clampedWidth)
        var roundedHeight = Self.round(clampedHeight)
        if roundedX + roundedWidth > 1 {
            roundedWidth = Self.round(max(0, 1 - roundedX))
        }
        if roundedY + roundedHeight > 1 {
            roundedHeight = Self.round(max(0, 1 - roundedY))
        }
        self.x = roundedX
        self.y = roundedY
        self.width = roundedWidth
        self.height = roundedHeight
    }

    /// Converts a Vision bottom-left normalized rectangle into top-left space.
    public init(visionNormalized rect: CGRect) {
        self.init(
            x: Double(rect.minX),
            y: Double(1 - rect.maxY),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func round(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }
}

// MARK: - Repeated region detection

/// Precision-first repeated-region detection.
///
/// The detector clusters OCR text into periodic visual lines/items first, then
/// compares alignment, spacing, and item membership. It intentionally does not
/// consume Vision rectangles: those are weak geometric observations and must
/// not be promoted into repeated structure or semantic containers.
enum UIEvidenceRepeatedGroupDetector {
    static let maximumGroups = 100
    static let maximumMembers = 100
    private static let minimumScore = 0.90
    private static let minimumGap = 0.04
    private static let maximumGap = 0.40

    private struct Progression {
        let members: [UIEvidenceElement]
        let centers: [Double]
        let gap: Double
        let gapCV: Double
    }

    private struct Phase {
        let items: [[UIEvidenceElement]]
        let centers: [Double]
        let gap: Double
    }

    private struct Candidate {
        let memberIDs: [String]
        let bbox: UIEvidenceBBox
        let itemBBoxes: [UIEvidenceBBox]
        let gap: Double
        let score: Double
        let itemCount: Int
        let memberCounts: [Int]
        let phaseCount: Int
    }

    static func detect(elements: [UIEvidenceElement]) -> [UIEvidenceRepeatedGroup] {
        let textElements = elements.filter { $0.kind == .text }
        guard textElements.count >= 3 else { return [] }

        var progressions: [Progression] = []
        for cluster in xAlignedClusters(textElements) {
            progressions.append(contentsOf: findProgressions(cluster))
        }
        let candidates = combinePhases(makePhases(progressions)).filter(isHighPrecisionCandidate)
        let selected = selectCandidates(candidates)

        return selected.prefix(maximumGroups).enumerated().map { index, candidate in
            UIEvidenceRepeatedGroup(
                id: "rg_\(index + 1)",
                axis: .vertical,
                memberIDs: Array(candidate.memberIDs.prefix(maximumMembers)),
                bbox: candidate.bbox,
                confidence: min(0.98, max(0.0, candidate.score)),
                evidence: .inferred
            )
        }
    }

    // MARK: - Visual-line and item clustering

    private static func xAlignedClusters(_ elements: [UIEvidenceElement]) -> [[UIEvidenceElement]] {
        let left = alignmentClusters(elements, edge: { $0.x })
        let right = alignmentClusters(elements, edge: { 1 - $0.maxX })
        var seen = Set<String>()
        var clusters: [[UIEvidenceElement]] = []
        for cluster in left + right {
            let key = cluster.map(\.id).sorted().joined(separator: "|")
            if seen.insert(key).inserted {
                clusters.append(cluster)
            }
        }
        return clusters
    }

    private static func alignmentClusters(
        _ elements: [UIEvidenceElement],
        edge: (UIEvidenceBBox) -> Double
    ) -> [[UIEvidenceElement]] {
        let sorted = elements.sorted {
            let lhs = edge($0.bbox)
            let rhs = edge($1.bbox)
            if abs(lhs - rhs) > 0.000_001 { return lhs < rhs }
            return $0.bbox.y < $1.bbox.y
        }
        var used = Set<String>()
        var clusters: [[UIEvidenceElement]] = []
        for element in sorted where !used.contains(element.id) {
            let cluster = sorted.filter { candidate in
                candidate.id == element.id ||
                    (abs(edge(candidate.bbox) - edge(element.bbox)) <= 0.012 &&
                     ratio(candidate.bbox.height, element.bbox.height) <= 1.65)
            }
            guard cluster.count >= 3 else { continue }
            cluster.forEach { used.insert($0.id) }
            clusters.append(cluster)
        }
        return clusters
    }

    private static func findProgressions(_ elements: [UIEvidenceElement]) -> [Progression] {
        let sorted = elements.sorted { centerY($0.bbox) < centerY($1.bbox) }
        let centers = sorted.map { centerY($0.bbox) }
        var gapKeys = Set<Int>()
        var gaps: [Double] = []
        if sorted.count >= 3 {
            for first in 0..<(sorted.count - 2) {
                for second in (first + 1)..<sorted.count {
                    let gap = centers[second] - centers[first]
                    guard gap >= minimumGap, gap <= maximumGap else { continue }
                    let key = Int((gap * 1_000).rounded())
                    if gapKeys.insert(key).inserted {
                        gaps.append(gap)
                    }
                }
            }
        }

        var candidates: [Progression] = []
        for gap in gaps.sorted() {
            let tolerance = max(0.005, gap * 0.09)
            for start in sorted.indices {
                var selected = [sorted[start]]
                var selectedIDs = Set([sorted[start].id])
                var lastCenter = centers[start]
                for step in 1..<20 {
                    let target = centers[start] + Double(step) * gap
                    if target > 1.05 { break }
                    let match = sorted.indices
                        .filter { index in
                            index > start &&
                            !selectedIDs.contains(sorted[index].id) &&
                            centers[index] > lastCenter &&
                            abs(centers[index] - target) <= tolerance
                        }
                        .min { abs(centers[$0] - target) < abs(centers[$1] - target) }
                    guard let match else { continue }
                    selected.append(sorted[match])
                    selectedIDs.insert(sorted[match].id)
                    lastCenter = centers[match]
                }
                guard selected.count >= 3 else { continue }
                let selectedCenters = selected.map { centerY($0.bbox) }
                let selectedGaps = zip(selectedCenters.dropFirst(), selectedCenters).map { $0 - $1 }
                let gapCV = coefficientOfVariation(selectedGaps)
                guard gapCV <= 0.12 else { continue }
                candidates.append(Progression(
                    members: selected,
                    centers: selectedCenters,
                    gap: selectedGaps.reduce(0, +) / Double(selectedGaps.count),
                    gapCV: gapCV
                ))
            }
        }

        var deduped: [String: Progression] = [:]
        for candidate in candidates {
            let key = candidate.members.map(\.id).joined(separator: "|")
            if let existing = deduped[key], existing.gapCV <= candidate.gapCV { continue }
            deduped[key] = candidate
        }
        return Array(deduped.values)
    }

    private static func makePhases(_ progressions: [Progression]) -> [Phase] {
        var buckets: [[Progression]] = []
        for progression in progressions.sorted(by: progressionOrder) {
            if let index = buckets.firstIndex(where: { bucket in
                guard let first = bucket.first else { return false }
                return abs(first.centers.count - progression.centers.count) <= 1 &&
                    abs(first.gap - progression.gap) <= 0.006
            }) {
                buckets[index].append(progression)
            } else {
                buckets.append([progression])
            }
        }

        var phases: [Phase] = []
        for bucket in buckets {
            var phaseClusters: [[Progression]] = []
            for progression in bucket {
                if let index = phaseClusters.firstIndex(where: { cluster in
                    guard let first = cluster.first,
                          first.centers.count == progression.centers.count else { return false }
                    return zip(first.centers, progression.centers).allSatisfy { abs($0 - $1) <= 0.012 }
                }) {
                    phaseClusters[index].append(progression)
                } else {
                    phaseClusters.append([progression])
                }
            }
            for cluster in phaseClusters {
                guard let first = cluster.first else { continue }
                var items = Array(repeating: [UIEvidenceElement](), count: first.centers.count)
                for progression in cluster {
                    for index in progression.members.indices where index < items.count {
                        items[index].append(progression.members[index])
                    }
                }
                phases.append(Phase(
                    items: items.map(deduplicateElements),
                    centers: first.centers,
                    gap: cluster.map(\.gap).reduce(0, +) / Double(cluster.count)
                ))
            }
        }
        return phases
    }

    private static func combinePhases(_ phases: [Phase]) -> [Candidate] {
        var candidates: [Candidate] = []
        var signatures = Set<String>()

        for phase in phases {
            var related = [phase]
            for other in phases {
                guard other.centers.count == phase.centers.count,
                      abs(other.gap - phase.gap) <= 0.006 else { continue }
                let offsets = zip(other.centers, phase.centers).map { $0 - $1 }
                guard let offset = offsets.first,
                      abs(offset) >= 0.006,
                      abs(offset) < phase.gap * 0.95,
                      (offsets.max() ?? offset) - (offsets.min() ?? offset) <= 0.018 else { continue }
                related.append(other)
            }

            var unique: [String: Phase] = [:]
            for item in related {
                let key = item.centers.map { String(format: "%.4f", $0) }.joined(separator: "|")
                unique[key] = item
            }
            guard !unique.isEmpty else { continue }
            let ordered = unique.values.sorted { ($0.centers.first ?? 0) < ($1.centers.first ?? 0) }
            guard let first = ordered.first else { continue }
            let itemCount = first.centers.count
            var items = Array(repeating: [UIEvidenceElement](), count: itemCount)
            for item in ordered {
                for index in 0..<min(itemCount, item.items.count) {
                    items[index].append(contentsOf: item.items[index])
                }
            }
            items = items.map(deduplicateElements)
            let memberIDs = items.flatMap { $0 }.map(\.id)
            let signature = memberIDs.sorted().joined(separator: "|")
            guard signatures.insert(signature).inserted else { continue }
            let boxes = items.map(union)
            guard boxes.allSatisfy({ $0.width > 0 && $0.height > 0 }) else { continue }
            let score = candidateScore(
                items: items,
                itemBBoxes: boxes,
                gap: first.gap,
                phaseCount: ordered.count
            )
            candidates.append(Candidate(
                memberIDs: memberIDs,
                bbox: union(items.flatMap { $0 }),
                itemBBoxes: boxes,
                gap: first.gap,
                score: score,
                itemCount: itemCount,
                memberCounts: items.map(\.count),
                phaseCount: ordered.count
            ))
        }
        return candidates
    }

    private static func candidateScore(
        items: [[UIEvidenceElement]],
        itemBBoxes: [UIEvidenceBBox],
        gap: Double,
        phaseCount: Int
    ) -> Double {
        guard itemBBoxes.count >= 3 else { return 0 }
        let counts = items.map(\.count)
        let widths = itemBBoxes.map(\.width)
        let heights = itemBBoxes.map(\.height)
        let leadEdges = itemBBoxes.map(\.x)
        let itemGaps = zip(itemBBoxes.dropFirst(), itemBBoxes).map { next, previous in
            next.y - previous.maxY
        }
        let widthRatio = ratio(widths.max() ?? 0, widths.min() ?? 0)
        let heightRatio = ratio(heights.max() ?? 0, heights.min() ?? 0)
        let leadSpan = (leadEdges.max() ?? 0) - (leadEdges.min() ?? 0)
        let gapCV = coefficientOfVariation(itemGaps)
        guard gapCV <= 0.22,
              heightRatio <= 1.8,
              leadSpan <= 0.035 else { return 0 }
        if counts.max() == 1 {
            guard widthRatio <= 3.2 else { return 0 }
        } else {
            guard widthRatio <= 1.9 else { return 0 }
        }
        let spacingScore = 1 - min(gapCV, 1)
        let countScore = min(1, Double(items.count) / 6)
        let widthDenominator = counts.max() == 1 ? 2.2 : 1.0
        let widthScore = 1 - min(max(0, widthRatio - 1) / widthDenominator, 1)
        let heightScore = 1 - min(max(0, heightRatio - 1), 1)
        let leadScore = 1 - min(leadSpan / 0.035, 1)
        let phaseScore = min(1, Double(phaseCount) / 3)
        let boundedGap = min(max(gap, minimumGap), maximumGap)
        let gapScore = 1 - abs(boundedGap - 0.08) / maximumGap
        return 0.48 +
            0.18 * spacingScore +
            0.12 * countScore +
            0.08 * widthScore +
            0.06 * heightScore +
            0.06 * leadScore +
            0.05 * phaseScore -
            0.03 * (1 - gapScore)
    }

    private static func isHighPrecisionCandidate(_ candidate: Candidate) -> Bool {
        guard candidate.score >= minimumScore,
              candidate.itemCount >= 3,
              candidate.bbox.width >= 0.06 else { return false }
        if candidate.itemCount <= 4 && candidate.bbox.width < 0.20 { return false }
        if candidate.itemCount == 3 && candidate.bbox.width > 0.65 { return false }
        if candidate.itemCount <= 4 && candidate.bbox.width > 0.80 { return false }
        if candidate.bbox.width < 0.20 && candidate.memberCounts.contains(where: { $0 > 1 }) { return false }
        if candidate.itemCount <= 4,
           candidate.bbox.width < 0.32,
           candidate.memberCounts.contains(where: { $0 > 1 }) { return false }
        if candidate.itemCount >= 5 && candidate.bbox.width < 0.08 { return false }
        if candidate.itemCount >= 6 && candidate.bbox.width < 0.15 { return false }
        if candidate.memberIDs.count >= 6 && candidate.bbox.width < 0.15 { return false }
        if candidate.memberIDs.count >= 5,
           candidate.bbox.width < 0.15,
           candidate.bbox.height < 0.25 { return false }
        let averageHeight = candidate.itemBBoxes.map(\.height).reduce(0, +) / Double(candidate.itemBBoxes.count)
        if candidate.itemCount == 3 && candidate.phaseCount == 1 && averageHeight > 0.11 { return false }
        if candidate.itemCount <= 4,
           candidate.bbox.width < 0.25,
           candidate.memberCounts.contains(where: { $0 > 1 }) { return false }
        if candidate.itemCount == 3 && candidate.phaseCount == 1 && candidate.bbox.height > 0.25 { return false }
        return candidate.memberIDs.count >= candidate.itemCount
    }

    private static func selectCandidates(_ candidates: [Candidate]) -> [Candidate] {
        var selected: [Candidate] = []
        for candidate in candidates.sorted(by: {
            selectionScore($0) > selectionScore($1)
        }) {
            let memberSet = Set(candidate.memberIDs)
            let rejected = selected.contains { existing in
                let existingSet = Set(existing.memberIDs)
                let union = memberSet.union(existingSet).count
                if union > 0, Double(memberSet.intersection(existingSet).count) / Double(union) > 0.45 {
                    return true
                }
                let intersection = intersectionArea(candidate.bbox, existing.bbox)
                let minimumArea = min(area(candidate.bbox), area(existing.bbox))
                return minimumArea > 0 && intersection / minimumArea >= 0.55
            }
            if !rejected {
                selected.append(candidate)
            }
        }
        return Array(mergeAlignedCandidates(selected).prefix(6))
    }

    private static func selectionScore(_ candidate: Candidate) -> Double {
        candidate.score + min(0.10, Double(candidate.memberIDs.count) / 200)
    }

    private static func mergeAlignedCandidates(_ candidates: [Candidate]) -> [Candidate] {
        var merged = candidates
        var changed = true
        while changed {
            changed = false
            outer: for first in merged.indices {
                for second in merged.indices where second > first {
                    let lhs = merged[first]
                    let rhs = merged[second]
                    let horizontalOverlap = max(0, min(lhs.bbox.maxX, rhs.bbox.maxX) - max(lhs.bbox.x, rhs.bbox.x))
                    let minimumWidth = min(lhs.bbox.width, rhs.bbox.width)
                    let verticalGap = max(0, max(lhs.bbox.y, rhs.bbox.y) - min(lhs.bbox.maxY, rhs.bbox.maxY))
                    guard minimumWidth > 0,
                          horizontalOverlap / minimumWidth >= 0.80,
                          verticalGap <= 0.03 else { continue }
                    let members = Array(Set(lhs.memberIDs).union(rhs.memberIDs))
                    let combined = Candidate(
                        memberIDs: members,
                        bbox: union([lhs.bbox, rhs.bbox]),
                        itemBBoxes: lhs.itemBBoxes + rhs.itemBBoxes,
                        gap: min(lhs.gap, rhs.gap),
                        score: max(lhs.score, rhs.score),
                        itemCount: lhs.itemCount + rhs.itemCount,
                        memberCounts: lhs.memberCounts + rhs.memberCounts,
                        phaseCount: max(lhs.phaseCount, rhs.phaseCount)
                    )
                    merged.remove(at: second)
                    merged[first] = combined
                    changed = true
                    break outer
                }
            }
        }
        return merged.sorted { $0.score > $1.score }
    }

    // MARK: - Geometry helpers

    private static func deduplicateElements(_ elements: [UIEvidenceElement]) -> [UIEvidenceElement] {
        var output: [UIEvidenceElement] = []
        var seen = Set<String>()
        for element in elements where seen.insert(element.id).inserted {
            output.append(element)
        }
        return output
    }

    private static func union(_ elements: [UIEvidenceElement]) -> UIEvidenceBBox {
        union(elements.map(\.bbox))
    }

    private static func union(_ boxes: [UIEvidenceBBox]) -> UIEvidenceBBox {
        guard let first = boxes.first else {
            return UIEvidenceBBox(x: 0, y: 0, width: 0, height: 0)
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.maxX
        var maxY = first.maxY
        for box in boxes.dropFirst() {
            minX = min(minX, box.x)
            minY = min(minY, box.y)
            maxX = max(maxX, box.maxX)
            maxY = max(maxY, box.maxY)
        }
        return UIEvidenceBBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func centerY(_ box: UIEvidenceBBox) -> Double {
        box.y + box.height / 2
    }

    private static func ratio(_ lhs: Double, _ rhs: Double) -> Double {
        guard lhs > 0, rhs > 0 else { return .infinity }
        return max(lhs, rhs) / min(lhs, rhs)
    }

    private static func coefficientOfVariation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return .infinity }
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return sqrt(max(0, variance)) / mean
    }

    private static func progressionOrder(_ lhs: Progression, _ rhs: Progression) -> Bool {
        if lhs.centers.count != rhs.centers.count { return lhs.centers.count > rhs.centers.count }
        if abs(lhs.gap - rhs.gap) > 0.000_001 { return lhs.gap < rhs.gap }
        return (lhs.centers.first ?? 0) < (rhs.centers.first ?? 0)
    }

    private static func area(_ box: UIEvidenceBBox) -> Double {
        box.width * box.height
    }

    private static func intersectionArea(_ lhs: UIEvidenceBBox, _ rhs: UIEvidenceBBox) -> Double {
        let width = max(0, min(lhs.maxX, rhs.maxX) - max(lhs.x, rhs.x))
        let height = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.y, rhs.y))
        return width * height
    }
}
