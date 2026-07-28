//
//  SubjectHintAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public struct SubjectHintResult: Sendable, Codable, Hashable {
    public let subjectRefHints: [String]
    public let subjectScaleHint: String?
    public let ageLevel: SubjectAgeLevel?

    public init(
        subjectRefHints: [String] = [],
        subjectScaleHint: String? = nil,
        ageLevel: SubjectAgeLevel? = nil
    ) {
        self.subjectRefHints = subjectRefHints
        self.subjectScaleHint = subjectScaleHint
        self.ageLevel = ageLevel
    }
}

public protocol SubjectHintAnalyzing: Sendable {
    func analyze(
        subjects: [DetectedSubject],
        rawVision: RawVisionAnalysis
    ) async throws -> [SubjectHintResult]
}

public final class MockSubjectHintAnalyzer: SubjectHintAnalyzing {
    public init() {}

    public func analyze(
        subjects: [DetectedSubject],
        rawVision: RawVisionAnalysis
    ) async throws -> [SubjectHintResult] {
        _ = rawVision
        return subjects.map { subject in
            SubjectHintResult(
                subjectRefHints: subject.type == .person ? ["single_person"] : [],
                subjectScaleHint: nil,
                ageLevel: nil
            )
        }
    }
}

