//
//  File.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation
import CryptoKit
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension VisualImage {
    
    /// 生成图片内容的稳定哈希值。
    /// iOS 使用 UIImage.pngData()，macOS 使用 NSBitmapImageRep 转换。
    func contentHash() -> String? {
        guard let data = self.rawPNGData() else { return nil }
        
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// 内部辅助方法：统一获取 PNG 数据
    private func rawPNGData() -> Data? {
        #if os(macOS)
        // macOS: NSImage 不直接提供 pngData()，需要通过 Tiff 或 BitmapRep 转换
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
        
        #else
        // iOS / tvOS / watchOS
        return self.pngData()
        #endif
    }
}
