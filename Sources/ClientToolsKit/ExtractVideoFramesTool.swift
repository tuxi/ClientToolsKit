//
//  ExtractVideoFramesTool.swift
//  ClientToolsKit
//
//  Created by xiaoyuan on 2026/8/17.
//

import AVFoundation
import ClientToolProtocol
import Foundation
import CoreGraphics
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Extracts keyframes or periodic frames from a video file in the workspace using AVFoundation.
public struct ExtractVideoFramesTool: ClientTool {
    public let name = "extract_video_frames"
    public let description = """
从 workspace 中的视频文件提取关键帧或定时抽帧，并保存至指定的 workspace 输出目录。
参数：
  - path（必填）：视频文件在 workspace 中的相对路径
  - output_dir（可选）：帧图片保存的相对目录路径，默认 "frames"
  - mode（可选）："fps"（按每秒帧数抽帧）、"interval"（按秒间隔抽帧）、"count"（均匀提取固定张数）或 "keyframes"（仅关键帧），默认 "fps"
  - rate（可选）：抽帧速率/间隔/数量。mode=fps 时表示每秒抽取几帧（默认 1.0）；mode=interval 时表示间隔几秒抽取一帧（默认 1.0）；mode=count 时表示总共提取几张（默认 10）
  - max_dimension（可选）：输出图片的最大长边像素值，用于缩放图片（例如 1080、720），不传保持原分辨率
  - format（可选）：输出图片格式，"jpeg" 或 "png"，默认 "jpeg"
说明：
  - 本地抽帧，自动保证时间轴递增。
  - 提取成功后返回生成帧的相对路径列表及元数据。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内的视频文件相对路径")
                ]),
                "output_dir": .object([
                    "type": .string("string"),
                    "description": .string("输出图片的目录相对路径，默认 'frames'"),
                    "default": .string("frames")
                ]),
                "mode": .object([
                    "type": .string("string"),
                    "description": .string("抽帧模式：fps（按帧率）、interval（按间隔秒）、count（固定数量）、keyframes（关键帧），默认 fps"),
                    "enum": .array([.string("fps"), .string("interval"), .string("count"), .string("keyframes")]),
                    "default": .string("fps")
                ]),
                "rate": .object([
                    "type": .string("number"),
                    "description": .string("配合 mode 使用的数值（FPS/间隔秒数/总张数）")
                ]),
                "max_dimension": .object([
                    "type": .string("integer"),
                    "description": .string("输出图片最大边长像素限制（例如 1280），不填保持原始分辨率")
                ]),
                "format": .object([
                    "type": .string("string"),
                    "description": .string("图片格式：jpeg 或 png，默认 jpeg"),
                    "enum": .array([.string("jpeg"), .string("png")]),
                    "default": .string("jpeg")
                ])
            ]),
            "required": .array([.string("path")])
        ])
    }

    public init() {}

    public func execute(
        args: JSONValue?,
        context: ClientToolExecutionContext
    ) async throws -> ClientToolExecutionResult {
        guard case .object(let values) = args,
              case .string(let relativePath) = values["path"] else {
            throw ExtractVideoFramesError.invalidArguments("Missing required string parameter: path")
        }

        let outputDirRelPath: String
        if case .string(let requestedOutputDir) = values["output_dir"] {
            outputDirRelPath = requestedOutputDir
        } else {
            outputDirRelPath = "frames"
        }

        let modeString: String
        if case .string(let requestedMode) = values["mode"] {
            modeString = requestedMode
        } else {
            modeString = "fps"
        }
        guard let mode = ExtractionMode(rawValue: modeString) else {
            throw ExtractVideoFramesError.invalidArguments("mode must be fps, interval, count, or keyframes")
        }

        let rate: Double?
        if case .number(let requestedRate) = values["rate"] {
            rate = requestedRate
        } else {
            rate = nil
        }

        let maxDimension: Int?
        if case .number(let requestedDimension) = values["max_dimension"] {
            maxDimension = Int(requestedDimension)
        } else {
            maxDimension = nil
        }

        let formatString: String
        if case .string(let requestedFormat) = values["format"] {
            formatString = requestedFormat.lowercased()
        } else {
            formatString = "jpeg"
        }
        let imageFormat = OutputFormat(rawValue: formatString) ?? .jpeg

        let workspace = try ToolWorkspace(context: context)
        let videoURL = try workspace.resolve(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ExtractVideoFramesError.fileNotFound(relativePath)
        }

        let outputDirectoryURL = try workspace.resolve(relativePath: outputDirRelPath)
        try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

        let startedAt = Date()
        let asset = AVURLAsset(url: videoURL)

        // 1. 读取视频基本元数据
        let durationSeconds = try await asset.load(.duration).seconds
        guard durationSeconds > 0 else {
            throw ExtractVideoFramesError.invalidVideo("Video duration is zero or invalid.")
        }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExtractVideoFramesError.invalidVideo("Video has no video track.")
        }

        // 2. 计算需要提取的时间点列表 (CMTime)
        let sampleTimes = try await calculateSampleTimes(
            asset: asset,
            videoTrack: videoTrack,
            duration: durationSeconds,
            mode: mode,
            rate: rate
        )

        // 3. 配置 AVAssetImageGenerator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = (mode == .keyframes) ? .positiveInfinity : .zero
        generator.requestedTimeToleranceAfter = (mode == .keyframes) ? .positiveInfinity : .zero

        if let maxDim = maxDimension, maxDim > 0 {
            generator.maximumSize = CGSize(width: maxDim, height: maxDim)
        }

        // 4. 批量提取并保存帧
        let locale = Locale(identifier: "en_US_POSIX")
        var extractedFrames: [ExtractedFrameInfo] = []
        var assets: [AgentAssetRef] = []
        var failedTimes: [Double] = []
        var frameIndex = 0

        for requestedTime in sampleTimes {
            if Task.isCancelled {
                throw CancellationError()
            }
            do {
                let (cgImage, actualTime) = try await generator.image(at: requestedTime)
                let timeInSeconds = actualTime.seconds
                let fileName = String(
                    format: "frame_%04d_%.2fs.%@",
                    locale: locale,
                    arguments: [frameIndex, timeInSeconds, imageFormat.fileExtension]
                )
                let fileURL = outputDirectoryURL.appendingPathComponent(fileName)
                let frameRelPath = (outputDirRelPath as NSString).appendingPathComponent(fileName)

                try Self.save(cgImage: cgImage, to: fileURL, format: imageFormat)

                extractedFrames.append(ExtractedFrameInfo(
                    index: frameIndex,
                    relativePath: frameRelPath,
                    timestampSeconds: timeInSeconds,
                    width: cgImage.width,
                    height: cgImage.height
                ))
                assets.append(AgentAssetRef(
                    id: "\(context.callID)-video-frame-\(frameIndex)",
                    kind: "image",
                    displayName: fileName,
                    workspaceID: context.workspaceID,
                    workspaceRelativePath: frameRelPath,
                    absolutePath: fileURL.path,
                    mimeType: imageFormat.mimeType,
                    sourceTurnID: context.turnID,
                    sourceCallID: context.callID,
                    metadata: ["timestamp_seconds": .number(timeInSeconds)]
                ))
                frameIndex += 1
            } catch {
                // 单张提取失败时记录并跳过，避免中断整体工作流。
                failedTimes.append(requestedTime.seconds)
            }
        }

        guard !extractedFrames.isEmpty else {
            throw ExtractVideoFramesError.extractionFailed("No frames could be extracted from the video.")
        }

        let result = ExtractVideoFramesResult(
            success: true,
            videoPath: relativePath,
            outputDirectory: outputDirRelPath,
            totalDurationSeconds: durationSeconds,
            extractedCount: extractedFrames.count,
            failedCount: failedTimes.count,
            frames: extractedFrames,
            elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )

        return try ToolResultEncoder.executionResult(result, assets: assets)
    }

    // MARK: - Time Calculation

    private func calculateSampleTimes(
        asset: AVURLAsset,
        videoTrack: AVAssetTrack,
        duration: Double,
        mode: ExtractionMode,
        rate: Double?
    ) async throws -> [CMTime] {
        var times: [CMTime] = []
        let timescale: CMTimeScale = 600

        switch mode {
        case .fps:
            let fps = max(0.01, rate ?? 1.0)
            let step = 1.0 / fps
            try Self.ensureFrameBudget(Int(ceil(duration / step)))
            var index = 0
            while Double(index) * step < duration {
                times.append(CMTime(seconds: Double(index) * step, preferredTimescale: timescale))
                index += 1
            }

        case .interval:
            let interval = max(0.1, rate ?? 1.0)
            try Self.ensureFrameBudget(Int(ceil(duration / interval)))
            var index = 0
            while Double(index) * interval < duration {
                times.append(CMTime(seconds: Double(index) * interval, preferredTimescale: timescale))
                index += 1
            }

        case .count:
            let targetCount = max(1, Int(rate ?? 10))
            try Self.ensureFrameBudget(targetCount)
            if targetCount == 1 {
                times.append(CMTime(seconds: duration / 2.0, preferredTimescale: timescale))
            } else {
                let step = duration / Double(targetCount - 1)
                for i in 0..<targetCount {
                    let time = min(Double(i) * step, duration)
                    times.append(CMTime(seconds: time, preferredTimescale: timescale))
                }
            }

        case .keyframes:
            // 提取关键帧 (Sync Samples)。NotSync 缺省或为 false 的采样即为关键帧。
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            reader.add(output)
            guard reader.startReading() else {
                throw ExtractVideoFramesError.extractionFailed("Failed to start reading video samples.")
            }

            var seenBuckets = Set<Int64>()
            while let sampleBuffer = output.copyNextSampleBuffer() {
                let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
                let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool
                guard notSync != true else { continue }

                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let seconds = pts.seconds
                // 过滤无效/越界时间戳（压缩采样中的边界样本可能为 NaN 或等于时长）。
                guard seconds.isFinite, seconds >= 0, seconds < duration else { continue }
                let bucket = Int64((seconds * 1000).rounded())
                guard seenBuckets.insert(bucket).inserted else { continue }
                times.append(pts)
            }

            if reader.status == .failed {
                throw ExtractVideoFramesError.extractionFailed(
                    reader.error?.localizedDescription ?? "Failed to read video samples."
                )
            }
            // 如果未能提取到关键帧，兜底按照 1 秒间隔抽帧
            if times.isEmpty {
                return try await calculateSampleTimes(
                    asset: asset,
                    videoTrack: videoTrack,
                    duration: duration,
                    mode: .interval,
                    rate: 1.0
                )
            }
        }

        return times
    }

    // MARK: - Frame Budget

    private static let maxFrameCount = 10_000

    private static func ensureFrameBudget(_ count: Int) throws {
        guard count <= maxFrameCount else {
            throw ExtractVideoFramesError.frameLimitExceeded(count, maxFrameCount)
        }
    }

    // MARK: - Image Saving Helper

    private static func save(cgImage: CGImage, to url: URL, format: OutputFormat) throws {
        let uti = format.utType as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, uti, 1, nil) else {
            throw ExtractVideoFramesError.imageEncodingFailed
        }

        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = 0.85
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExtractVideoFramesError.imageEncodingFailed
        }
    }
}

// MARK: - Supporting Types

private enum ExtractionMode: String {
    case fps
    case interval
    case count
    case keyframes
}

private enum OutputFormat: String, Equatable {
    case jpeg
    case png

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }

    var utType: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        }
    }

    var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        }
    }
}

private struct ExtractedFrameInfo: Encodable {
    let index: Int
    let relativePath: String
    let timestampSeconds: Double
    let width: Int
    let height: Int

    enum CodingKeys: String, CodingKey {
        case index
        case relativePath = "relative_path"
        case timestampSeconds = "timestamp_seconds"
        case width, height
    }
}

private struct ExtractVideoFramesResult: Encodable {
    let success: Bool
    let videoPath: String
    let outputDirectory: String
    let totalDurationSeconds: Double
    let extractedCount: Int
    let failedCount: Int
    let frames: [ExtractedFrameInfo]
    let elapsedMilliseconds: Int

    enum CodingKeys: String, CodingKey {
        case success
        case videoPath = "video_path"
        case outputDirectory = "output_directory"
        case totalDurationSeconds = "total_duration_seconds"
        case extractedCount = "extracted_count"
        case failedCount = "failed_count"
        case frames
        case elapsedMilliseconds = "elapsed_ms"
    }
}

private enum ExtractVideoFramesError: LocalizedError {
    case invalidArguments(String)
    case fileNotFound(String)
    case invalidVideo(String)
    case imageEncodingFailed
    case extractionFailed(String)
    case frameLimitExceeded(Int, Int)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .fileNotFound(let path):
            return "Video not found in workspace: \(path)"
        case .invalidVideo(let reason):
            return "Invalid video file: \(reason)"
        case .imageEncodingFailed:
            return "Failed to encode frame image."
        case .extractionFailed(let reason):
            return "Frame extraction failed: \(reason)"
        case .frameLimitExceeded(let count, let maximum):
            return "Requested frame count (\(count)) exceeds the maximum of \(maximum)."
        }
    }
}
