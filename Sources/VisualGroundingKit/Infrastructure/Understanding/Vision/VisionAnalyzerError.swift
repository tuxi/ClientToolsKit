//
//  VisionAnalyzerError.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public enum VisionAnalyzerError: Error, LocalizedError {
    case invalidImage
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image for Vision analysis."
        case .requestFailed(let message):
            return "Vision request failed: \(message)"
        }
    }
}
