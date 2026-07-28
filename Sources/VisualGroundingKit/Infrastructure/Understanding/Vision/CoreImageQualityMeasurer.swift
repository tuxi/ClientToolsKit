//
//  CoreImageQualityMeasurer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import CoreGraphics
import Foundation

public final class CoreImageQualityMeasurer: ImageQualityMeasuring {
    public init() {}

    public func brightness(of image: VisualImage) async throws -> ImageBrightnessLevel? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let grayscale = makeGrayscalePixels(from: cgImage, maxDimension: 64)
        guard !grayscale.pixels.isEmpty else {
            return nil
        }

        let average = grayscale.pixels.reduce(0, +) / Double(grayscale.pixels.count)

        switch average {
        case ..<0.32:
            return .dark
        case 0.68...:
            return .bright
        default:
            return .normal
        }
    }

    public func sharpness(of image: VisualImage) async throws -> ImageSharpnessLevel? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let grayscale = makeGrayscalePixels(from: cgImage, maxDimension: 96)
        let width = grayscale.width
        let height = grayscale.height
        let pixels = grayscale.pixels

        guard width >= 3, height >= 3 else {
            return nil
        }

        var laplacianEnergy = 0.0
        var sampleCount = 0

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = pixels[y * width + x]
                let up = pixels[(y - 1) * width + x]
                let down = pixels[(y + 1) * width + x]
                let left = pixels[y * width + (x - 1)]
                let right = pixels[y * width + (x + 1)]
                let laplacian = abs((4.0 * center) - up - down - left - right)
                laplacianEnergy += laplacian
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return nil
        }

        let averageEnergy = laplacianEnergy / Double(sampleCount)

        switch averageEnergy {
        case ..<0.045:
            return .blurry
        case 0.11...:
            return .sharp
        default:
            return .normal
        }
    }
}

private extension CoreImageQualityMeasurer {
    typealias GrayscaleBuffer = (pixels: [Double], width: Int, height: Int)

    func makeGrayscalePixels(
        from cgImage: CGImage,
        maxDimension: Int
    ) -> GrayscaleBuffer {
        let originalWidth = cgImage.width
        let originalHeight = cgImage.height

        guard originalWidth > 0, originalHeight > 0 else {
            return ([], 0, 0)
        }

        let scale = min(
            1.0,
            Double(maxDimension) / Double(max(originalWidth, originalHeight))
        )

        let width = max(1, Int(Double(originalWidth) * scale))
        let height = max(1, Int(Double(originalHeight) * scale))

        var raw = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ([], 0, 0)
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels = [Double]()
        pixels.reserveCapacity(width * height)

        for index in stride(from: 0, to: raw.count, by: 4) {
            let red = Double(raw[index]) / 255.0
            let green = Double(raw[index + 1]) / 255.0
            let blue = Double(raw[index + 2]) / 255.0
            let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
            pixels.append(luminance)
        }

        return (pixels, width, height)
    }
}
