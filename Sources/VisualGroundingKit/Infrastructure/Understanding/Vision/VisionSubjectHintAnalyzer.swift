//
//  VisionSubjectHintAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public final class VisionSubjectHintAnalyzer: SubjectHintAnalyzing {
    public init() {}

    public func analyze(
        subjects: [DetectedSubject],
        rawVision: RawVisionAnalysis
    ) async throws -> [SubjectHintResult] {
        let labels = rawVision.classifications.map { $0.identifier.lowercased() }

        return subjects.enumerated().map { index, subject in
            let count = max(subject.attributes.subjectCount ?? subjects.count, 1)
            var refHints: [String] = []

            switch subject.type {
            case .person:
                if count >= 2 {
                    refHints.append("multi_person")
                } else {
                    refHints.append("single_person")
                }

                let hasChildHint = labels.contains(where: { $0.contains("child") || $0.contains("kid") || $0.contains("baby") })
                let hasAdultHint = labels.contains(where: { $0.contains("adult") })

                if count == 1, hasChildHint {
                    refHints.append("single_person_child_like")
                } else if count == 1, hasAdultHint {
                    refHints.append("single_person_adult_like")
                } else if count >= 2, hasChildHint && hasAdultHint, index == 0 {
                    refHints.append("adult_child_pair")
                }

            case .animal:
                refHints.append("single_animal")
            case .object, .unknown:
                break
            }

            return SubjectHintResult(
                subjectRefHints: dedup(refHints),
                subjectScaleHint: inferScaleHint(from: subject.boundingBox),
                ageLevel: inferAgeLevel(
                    subject: subject,
                    labels: labels,
                    subjectCount: count
                )
            )
        }
    }
}

private extension VisionSubjectHintAnalyzer {
    func inferScaleHint(from box: CGRect?) -> String? {
        guard let box else { return nil }
        let area = box.width * box.height

        switch area {
        case 0.35...:
            return "dominant"
        case 0.14...:
            return "medium"
        default:
            return "small"
        }
    }

    func inferAgeLevel(
        subject: DetectedSubject,
        labels: [String],
        subjectCount: Int
    ) -> SubjectAgeLevel? {
        guard subject.type == .person else { return nil }
        guard subjectCount == 1 else { return nil }

        if labels.contains(where: { $0.contains("child") || $0.contains("kid") || $0.contains("baby") }) {
            return .child
        }
        if labels.contains(where: { $0.contains("adult") }) {
            return .adult
        }
        return nil
    }

    func dedup(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }

        return result
    }
}

