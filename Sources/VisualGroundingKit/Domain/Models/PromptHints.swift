//
//  PromptHints.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public struct PromptHintsPayload: Sendable, Codable, Hashable {
    public let subjectRefStyle: String?
    public let subjectSceneBalance: String?
    public let motionPreference: String?

    public init(
        subjectRefStyle: String? = nil,
        subjectSceneBalance: String? = nil,
        motionPreference: String? = nil
    ) {
        self.subjectRefStyle = subjectRefStyle
        self.subjectSceneBalance = subjectSceneBalance
        self.motionPreference = motionPreference
    }
}

