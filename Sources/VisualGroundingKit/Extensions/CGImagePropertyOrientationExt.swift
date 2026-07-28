//
//  CGImagePropertyOrientationExt.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension CGImagePropertyOrientation {
    /// 统一初始化方法，自动根据平台处理 VisualImage 的方向
    init(visualImage: VisualImage) {
        #if canImport(UIKit)
        // iOS: 从 UIImage.Orientation 映射
        switch visualImage.cgImageOrientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
        #else
        // macOS: NSImage 通常已经处理好方向，或者不暴露该属性
        self = .up
        #endif
    }
}

