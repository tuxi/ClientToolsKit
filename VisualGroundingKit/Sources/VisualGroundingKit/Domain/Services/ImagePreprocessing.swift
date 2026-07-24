//
//  ImagePreprocessing.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public protocol ImagePreprocessing: Sendable {
    func normalize(_ image: VisualImage) async throws -> VisualImage
    func resizedForAnalysis(_ image: VisualImage) async throws -> VisualImage
}
