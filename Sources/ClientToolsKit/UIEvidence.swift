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

/// Geometric repetition detection. It reports candidates only: identical
/// geometry does not establish that elements form a list, grid, or any other
/// semantic group, so every group is marked `inferred`.
enum UIEvidenceRepeatedGroupDetector {
    static let maximumGroups = 100
    static let maximumMembers = 100

    static func detect(elements: [UIEvidenceElement]) -> [UIEvidenceRepeatedGroup] {
        let textElements = elements.filter { $0.kind == .text }
        let containerElements = elements.filter { $0.kind == .container }

        var candidates: [CandidateGroup] = []
        candidates.append(contentsOf: alignedGroups(elements: textElements, axis: .vertical))
        candidates.append(contentsOf: alignedGroups(elements: textElements, axis: .horizontal))
        candidates.append(contentsOf: gridGroups(elements: containerElements))

        let deduped = deduplicate(candidates)
            .sorted {
                if $0.bbox.y != $1.bbox.y { return $0.bbox.y < $1.bbox.y }
                if $0.bbox.x != $1.bbox.x { return $0.bbox.x < $1.bbox.x }
                if $0.axis != $1.axis { return $0.axis.rawValue < $1.axis.rawValue }
                return $0.memberIDs.count > $1.memberIDs.count
            }
            .prefix(maximumGroups)

        return deduped.enumerated().map { index, candidate in
            UIEvidenceRepeatedGroup(
                id: "rg_\(index + 1)",
                axis: candidate.axis,
                memberIDs: Array(candidate.memberIDs.prefix(maximumMembers)),
                bbox: candidate.bbox,
                confidence: candidate.confidence,
                evidence: .inferred
            )
        }
    }

    private struct CandidateGroup {
        let axis: UIEvidenceAxis
        let memberIDs: [String]
        let bbox: UIEvidenceBBox
        let confidence: Double
    }

    private static func alignedGroups(
        elements: [UIEvidenceElement],
        axis: UIEvidenceAxis
    ) -> [CandidateGroup] {
        let leadingTolerance = 0.02
        let sizeRatioTolerance = 1.8
        var used = Set<String>()
        var groups: [CandidateGroup] = []

        for element in elements where !used.contains(element.id) {
            guard let lead = leadingEdge(element.bbox, axis: axis) else { continue }
            let extent = extentSize(element.bbox, axis: axis)
            guard extent > 0 else { continue }

            var members = [element]
            for other in elements where other.id != element.id && !used.contains(other.id) {
                guard let otherLead = leadingEdge(other.bbox, axis: axis) else { continue }
                let otherExtent = extentSize(other.bbox, axis: axis)
                guard otherExtent > 0 else { continue }
                let leadDistance = abs(otherLead - lead)
                let extentRatio = max(extent, otherExtent) / min(extent, otherExtent)
                let crossRatio = max(crossSize(element.bbox, axis: axis), crossSize(other.bbox, axis: axis))
                    / min(crossSize(element.bbox, axis: axis), crossSize(other.bbox, axis: axis))
                guard leadDistance <= leadingTolerance,
                      extentRatio <= sizeRatioTolerance,
                      crossRatio <= sizeRatioTolerance else { continue }
                members.append(other)
            }

            guard members.count >= 3 else { continue }

            let sorted = members.sorted { position($0.bbox, axis: axis) < position($1.bbox, axis: axis) }
            let crossSizes = sorted.map { crossSize($0.bbox, axis: axis) }
            let crossMean = crossSizes.reduce(0, +) / Double(crossSizes.count)
            guard crossMean > 0 else { continue }

            let gaps = zip(sorted.dropFirst(), sorted).map { next, previous in
                position(next.bbox, axis: axis)
                    - (position(previous.bbox, axis: axis) + crossSize(previous.bbox, axis: axis))
            }
            guard let statistics = spacingStatistics(gaps) else { continue }
            guard statistics.mean >= 0.002,
                  statistics.mean <= crossMean * 2.0,
                  statistics.coefficientOfVariation <= 0.45 else { continue }

            let leadingSize = sorted.map { extentSize($0.bbox, axis: axis) }
            let leadingMean = leadingSize.reduce(0, +) / Double(leadingSize.count)
            guard leadingMean > 0 else { continue }

            let leadingDeviation = leadingSize.map { abs($0 - leadingMean) / leadingMean }.reduce(0, +) / Double(leadingSize.count)
            let crossDeviation = crossSizes.map { abs($0 - crossMean) / crossMean }.reduce(0, +) / Double(crossSizes.count)
            let sizeScore = max(0, 1 - (leadingDeviation + crossDeviation))
            let spacingScore = max(0, 1 - statistics.coefficientOfVariation)
            let countScore = min(1, Double(sorted.count) / 6)
            let confidence = min(0.95, 0.35 + 0.3 * sizeScore + 0.2 * spacingScore + 0.15 * countScore)

            let memberIDs = sorted.map(\.id)
            memberIDs.forEach { used.insert($0) }
            groups.append(CandidateGroup(
                axis: axis,
                memberIDs: memberIDs,
                bbox: union(sorted.map(\.bbox)),
                confidence: confidence
            ))
        }
        return groups
    }

    private static func gridGroups(elements: [UIEvidenceElement]) -> [CandidateGroup] {
        guard elements.count >= 4 else { return [] }
        var used = Set<String>()
        var groups: [CandidateGroup] = []

        for element in elements where !used.contains(element.id) {
            var sizeCluster = [element]
            for other in elements where other.id != element.id && !used.contains(other.id) {
                let widthRatio = max(element.bbox.width, other.bbox.width) / max(min(element.bbox.width, other.bbox.width), 0.000_001)
                let heightRatio = max(element.bbox.height, other.bbox.height) / max(min(element.bbox.height, other.bbox.height), 0.000_001)
                guard widthRatio <= 1.4, heightRatio <= 1.4 else { continue }
                sizeCluster.append(other)
            }
            guard sizeCluster.count >= 4 else { continue }

            let meanWidth = sizeCluster.map(\.bbox.width).reduce(0, +) / Double(sizeCluster.count)
            let meanHeight = sizeCluster.map(\.bbox.height).reduce(0, +) / Double(sizeCluster.count)

            var rows: [[UIEvidenceElement]] = []
            for candidate in sizeCluster.sorted(by: { $0.bbox.y < $1.bbox.y }) {
                if let lastIndex = rows.indices.last {
                    let rowCenter = rows[lastIndex].map { $0.bbox.y + $0.bbox.height / 2 }.reduce(0, +) / Double(rows[lastIndex].count)
                    let candidateCenter = candidate.bbox.y + candidate.bbox.height / 2
                    if abs(candidateCenter - rowCenter) <= max(0.015, meanHeight * 0.6) {
                        rows[lastIndex].append(candidate)
                        continue
                    }
                }
                rows.append([candidate])
            }
            guard rows.count >= 2 else { continue }

            let counts = Set(rows.map(\.count))
            guard counts.count == 1, let rowCount = counts.first, rowCount >= 2 else { continue }
            guard rows.count * rowCount >= 4 else { continue }

            for index in rows.indices {
                rows[index].sort { $0.bbox.x < $1.bbox.x }
            }
            let columnTolerance = max(0.02, meanWidth * 0.4)
            var columnsAligned = true
            for column in 0..<rowCount {
                let centers = rows.map { $0[column].bbox.x + $0[column].bbox.width / 2 }
                if let first = centers.first {
                    columnsAligned = centers.allSatisfy { abs($0 - first) <= columnTolerance }
                }
                if !columnsAligned { break }
            }
            guard columnsAligned else { continue }

            let members = rows.flatMap { $0 }
            let memberIDs = members.map(\.id)
            memberIDs.forEach { used.insert($0) }
            let confidence = min(0.9, 0.6 + min(0.2, 0.03 * Double(members.count)))
            groups.append(CandidateGroup(
                axis: .grid,
                memberIDs: memberIDs,
                bbox: union(members.map(\.bbox)),
                confidence: confidence
            ))
        }
        return groups
    }

    private static func deduplicate(_ candidates: [CandidateGroup]) -> [CandidateGroup] {
        let ranked = candidates.sorted { $0.confidence > $1.confidence }
        var kept: [CandidateGroup] = []
        for candidate in ranked {
            let candidateSet = Set(candidate.memberIDs)
            let overlaps = kept.contains { existing in
                let existingSet = Set(existing.memberIDs)
                let intersection = candidateSet.intersection(existingSet).count
                let union = candidateSet.union(existingSet).count
                return union > 0 && Double(intersection) / Double(union) >= 0.8
            }
            if !overlaps {
                kept.append(candidate)
            }
        }
        return kept
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

    private static func spacingStatistics(_ gaps: [Double]) -> (mean: Double, coefficientOfVariation: Double)? {
        guard !gaps.isEmpty else { return nil }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        guard mean.isFinite else { return nil }
        let variance = gaps.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(gaps.count)
        let standardDeviation = sqrt(max(0, variance))
        let coefficientOfVariation = mean > 0 ? standardDeviation / mean : .infinity
        return (mean, coefficientOfVariation)
    }

    private static func leadingEdge(_ box: UIEvidenceBBox, axis: UIEvidenceAxis) -> Double? {
        switch axis {
        case .vertical: return box.x
        case .horizontal: return box.y
        default: return nil
        }
    }

    private static func extentSize(_ box: UIEvidenceBBox, axis: UIEvidenceAxis) -> Double {
        switch axis {
        case .vertical: return box.width
        case .horizontal: return box.height
        default: return 0
        }
    }

    private static func crossSize(_ box: UIEvidenceBBox, axis: UIEvidenceAxis) -> Double {
        switch axis {
        case .vertical: return box.height
        case .horizontal: return box.width
        default: return 0
        }
    }

    private static func position(_ box: UIEvidenceBBox, axis: UIEvidenceAxis) -> Double {
        switch axis {
        case .vertical: return box.y
        case .horizontal: return box.x
        default: return 0
        }
    }
}
