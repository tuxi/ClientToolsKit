//
//  ImageUnderstandingService.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public protocol ImageUnderstandingService: Sendable {
    func analyze(image: InputImageAsset) async throws -> ImageDescriptor
}
