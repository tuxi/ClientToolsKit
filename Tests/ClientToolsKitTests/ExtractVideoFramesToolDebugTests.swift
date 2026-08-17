import AVFoundation
import ClientToolProtocol
import Foundation
import XCTest
@testable import ClientToolsKit

/// Local debug tests that exercise `ExtractVideoFramesTool` keyframes mode against a
/// real video in ~/Downloads. Skipped when the file is not present, so it is safe to
/// leave in the tree — but it is primarily a debugging harness (run from Xcode with
/// breakpoints set inside `ExtractVideoFramesTool.swift`).
final class ExtractVideoFramesToolDebugTests: XCTestCase {

    /// Absolute path to the real video used for local debugging.
    private var videoPath: String {
        NSString(string: "~/Downloads/composite_1780312758922186763.mp4").expandingTildeInPath
    }

    private func makeContext(workspaceRoot: URL) -> ClientToolExecutionContext {
        ClientToolExecutionContext(
            workspaceRoot: workspaceRoot,
            workspaceID: "debug-workspace",
            sessionID: "debug-session",
            turnID: "debug-turn",
            callID: "debug-call"
        )
    }

    // MARK: - Attachment-scan diagnostics (mirrors the tool's keyframe detection)

    /// Scans the sample buffers like the tool does and counts keyframes under both
    /// the current (buggy) detection and the correct semantics.
    func testKeyframeDetectionDiagnostics() async throws {
        let url = URL(fileURLWithPath: videoPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Video not found at \(url.path)")
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw XCTSkip("No video track in \(url.lastPathComponent)")
        }
        let fps = try await videoTrack.load(.nominalFrameRate)
        print("video=\(url.lastPathComponent) duration=\(duration)s nominalFPS=\(fps)")

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        reader.add(output)
        reader.startReading()

        var totalSamples = 0
        var keyframesByDefaultSemantics = 0        // NotSync != true  → sync sample
        var keyframesByCurrentToolLogic = 0        // NotSync binding to false
        var notSyncExplicitlyTrue = 0
        var attachmentArrayNil = 0
        var notSyncKeyAbsent = 0
        var correctKeyframeTimes: [Double] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            totalSamples += 1
            let category = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            let attachments = category as? [[CFString: Any]]

            if attachments == nil {
                attachmentArrayNil += 1
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                correctKeyframeTimes.append(pts)
                keyframesByDefaultSemantics += 1
                continue
            }
            guard let first = attachments?.first else { continue }
            if let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
                if notSync {
                    notSyncExplicitlyTrue += 1
                } else {
                    // Current tool logic: requires an explicit false binding.
                    keyframesByCurrentToolLogic += 1
                    correctKeyframeTimes.append(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
                    keyframesByDefaultSemantics += 1
                }
            } else {
                notSyncKeyAbsent += 1
                correctKeyframeTimes.append(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
                keyframesByDefaultSemantics += 1
            }
        }

        print("totalSamples=\(totalSamples)")
        print("attachmentArrayNil=\(attachmentArrayNil) notSyncKeyAbsent=\(notSyncKeyAbsent) notSyncExplicitlyTrue=\(notSyncExplicitlyTrue)")
        print("keyframesByDefaultSemantics=\(keyframesByDefaultSemantics)")
        print("keyframesByCurrentToolLogic=\(keyframesByCurrentToolLogic)")
        print("correctKeyframeTimes(count=\(correctKeyframeTimes.count))=\(correctKeyframeTimes)")

        // The current tool logic should under-count badly; this documents the gap.
        XCTAssertLessThan(keyframesByCurrentToolLogic, keyframesByDefaultSemantics)
    }

    // MARK: - End-to-end tool run in keyframes mode

    func testKeyframesModeEndToEnd() async throws {
        let root = URL(fileURLWithPath: videoPath).deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: videoPath) else {
            throw XCTSkip("Video not found at \(videoPath)")
        }

        let tool = ExtractVideoFramesTool()
        let response = try await tool.execute(
            args: .object([
                "path": .string(URL(fileURLWithPath: videoPath).lastPathComponent),
                "mode": .string("keyframes"),
                "output_dir": .string("frames_keyframes_debug"),
                "format": .string("jpeg")
            ]),
            context: makeContext(workspaceRoot: root)
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(response.content.utf8)) as? [String: Any]
        )
        let frames = try XCTUnwrap(object["frames"] as? [[String: Any]])
        let timestamps = frames.compactMap { $0["timestamp_seconds"] as? Double }
        let unique = Set(timestamps)
        print("extractedCount=\(frames.count)")
        print("timestamps=\(timestamps)")
        print("uniqueTimestamps=\(unique.count) of \(timestamps.count)")
        print("duplicateTimestamps=\(timestamps.count - unique.count)")

        XCTAssertEqual(object["success"] as? Bool, true)
        XCTAssertEqual(object["failed_count"] as? Int, 0)
        XCTAssertGreaterThan(frames.count, 0)
        XCTAssertEqual(
            timestamps.count, unique.count,
            "Keyframes mode must not emit duplicate timestamps"
        )
        XCTAssertGreaterThan(response.assets.count, 0, "Extracted frames should be registered as assets")
        XCTAssertEqual(response.assets.first?.kind, "image")
    }
}
