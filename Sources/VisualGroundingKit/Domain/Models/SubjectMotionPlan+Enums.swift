//
//  SubjectMotionPlan+Enums.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/23.
//

import Foundation

public enum SubjectStartPose: String, Sendable, Hashable, Codable {
    case seated
    case standing
}

public enum SubjectPrimaryAction: String, Sendable, Hashable, Codable {
    case idle
    case standUp
    case dance
    case turn
    case walk
}

public enum SubjectSecondaryAction: String, Sendable, Hashable, Codable {
    case nod
    case wave
}

public enum SubjectInteractionMode: String, Sendable, Hashable, Codable {
    case subtleInteraction
    case holdingChild
}

public enum SubjectGazeTarget: String, Sendable, Hashable, Codable {
    case camera
    case forward
}

public enum SubjectMotionIntensity: String, Sendable, Hashable, Codable {
    case subtle
    case gentle
}

public enum SubjectMotionStyleMode: String, Sendable, Hashable, Codable {
    case safeSubtle
    case creativeSoft
}
