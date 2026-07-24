//
//  VisionImageRequestPerformer.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation
import Vision
import ImageIO

public protocol VisionImageRequestPerforming: Sendable {
    func perform(
        _ requests: [VNRequest],
        on image: VisualImage
    ) throws
}

public final class VisionImageRequestPerformer: VisionImageRequestPerforming {
    public init() {}

    public func perform(
        _ requests: [VNRequest],
        on image: VisualImage
    ) throws {
        guard let cgImage = image.cgImage else {
            throw VisionAnalyzerError.invalidImage
        }
        
        // 直接使用统一的初始化器
        let orientation = CGImagePropertyOrientation(visualImage: image)
        
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: orientation,
            options: [:]
        )
        try handler.perform(requests)
    }
}
