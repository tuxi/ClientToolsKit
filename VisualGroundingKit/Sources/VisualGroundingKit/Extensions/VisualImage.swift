//
//  VisualImage.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/29.
//

import Foundation


#if canImport(AppKit)
import AppKit
public typealias VisualImage = NSImage
#else
import UIKit
public typealias VisualImage = UIImage
#endif

#if canImport(AppKit)
import AppKit

extension NSImage {
    /// macOS 下获取 CGImage 的标准方式
    public var cgImage: CGImage? {
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    /// macOS 图片通常已在内存中校正，或者通过 metadata 处理
    /// 这里返回 .up 以保持与 Vision 默认行为一致
    public var cgImageOrientation: CGImagePropertyOrientation {
        return .up
    }
}
#endif

#if canImport(UIKit)
import UIKit

extension UIImage {
    /// 转换 UIImage.Orientation 到 CGImagePropertyOrientation
    public var cgImageOrientation: CGImagePropertyOrientation {
        switch self.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
#endif
