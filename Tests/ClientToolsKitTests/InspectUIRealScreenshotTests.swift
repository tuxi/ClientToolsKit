import ClientToolProtocol
import CoreGraphics
import ImageIO
import XCTest
@testable import ClientToolsKit

#if canImport(AppKit)
import AppKit
#endif

/// Opt-in end-to-end check with a real screenshot.
///
/// Run with:
///   INSPECT_UI_REAL_SCREENSHOT=/path/to/screenshot.png swift test \
///     --filter InspectUIRealScreenshotTests
final class InspectUIRealScreenshotTests: XCTestCase {
    func testRealScreenshotEvidenceAndAssets() async throws {
        guard let sourcePath = ProcessInfo.processInfo.environment["INSPECT_UI_REAL_SCREENSHOT"],
              !sourcePath.isEmpty else {
            throw XCTSkip("Set INSPECT_UI_REAL_SCREENSHOT to a real screenshot file")
        }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw XCTSkip("Screenshot not found at \(sourceURL.path)")
        }

        // view_image equivalent host path: decode the source pixels first.
        let data = try Data(contentsOf: sourceURL)
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return XCTFail("Source screenshot is not decodable")
        }
        print("view_image source: \(sourceURL.lastPathComponent) \(sourceImage.width)x\(sourceImage.height)")
        #if canImport(AppKit)
        XCTAssertNotNil(NSImage(contentsOf: sourceURL), "view_image-style source open failed")
        #endif

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InspectUIRealScreenshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let relativePath = "screen.\(fileExtension)"
        try data.write(to: root.appendingPathComponent(relativePath))

        let context = ClientToolExecutionContext(
            workspaceRoot: root,
            workspaceID: "ws_real_screenshot",
            sessionID: "session_real",
            turnID: "turn_real",
            callID: "call_real"
        )
        let cropBBox: JSONValue = .object([
            "x": .number(0.1),
            "y": .number(0.1),
            "width": .number(0.8),
            "height": .number(0.5)
        ])
        let args: JSONValue = .object([
            "path": .string(relativePath),
            "source_kind": .string("app_screenshot"),
            "crops": .array([
                .object([
                    "bbox": cropBBox,
                    "purpose": .string("content")
                ])
            ])
        ])

        let result = try await InspectUIImageTool().execute(args: args, context: context)
        let output = try XCTUnwrap(result.output)
        let document = try JSONDecoder().decode(
            UIEvidenceDocument.self,
            from: JSONEncoder().encode(output)
        )

        print("inspect_ui_image: elements=\(document.elements.count) repeated_groups=\(document.repeatedGroups.count) crops=\(document.crops.count)")
        print("source asset=\(document.source.assetID) \(document.source.width)x\(document.source.height) sha256=\(document.source.sha256.prefix(16))")
        let evidenceDirectory = URL(fileURLWithPath: "/tmp/real-ui-inspect-assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(document).write(to: evidenceDirectory.appendingPathComponent("ui_evidence.json"))
        try? result.content.write(
            to: evidenceDirectory.appendingPathComponent("content.txt"),
            atomically: true,
            encoding: .utf8
        )
        for element in document.elements.prefix(10) {
            print("  \(element.id) kind=\(element.kind.rawValue) evidence=\(element.evidence.rawValue) bbox=(\(element.bbox.x),\(element.bbox.y),\(element.bbox.width),\(element.bbox.height)) text=\(element.text ?? "-")")
        }

        XCTAssertEqual(document.source.width, sourceImage.width)
        XCTAssertEqual(document.source.height, sourceImage.height)
        XCTAssertEqual(document.source.sourceKind, .appScreenshot)
        XCTAssertEqual(result.assets.count, 2)
        XCTAssertEqual(result.assets[0].id, document.source.assetID)
        XCTAssertEqual(result.assets[0].metadata?["asset_role"], .string("source"))
        XCTAssertEqual(result.assets[1].metadata?["asset_role"], .string("crop"))
        XCTAssertEqual(result.assets[1].metadata?["source_asset_id"], .string(document.source.assetID))
        XCTAssertEqual(document.crops.first?.assetID, result.assets[1].id)

        // Source and crop assets must both resolve and open from the workspace.
        let artifactDirectory = URL(fileURLWithPath: "/tmp/real-ui-inspect-assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        for asset in result.assets {
            let relativePath = try XCTUnwrap(asset.workspaceRelativePath)
            let fileURL = root.appendingPathComponent(relativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "asset file missing: \(relativePath)")
            let artifactName = relativePath.replacingOccurrences(of: "/", with: "_")
            try? FileManager.default.copyItem(
                at: fileURL,
                to: artifactDirectory.appendingPathComponent(artifactName)
            )
            guard let assetSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let assetImage = CGImageSourceCreateImageAtIndex(assetSource, 0, nil) else {
                return XCTFail("asset is not decodable: \(relativePath)")
            }
            XCTAssertGreaterThan(assetImage.width, 0)
            XCTAssertGreaterThan(assetImage.height, 0)
            #if canImport(AppKit)
            XCTAssertNotNil(NSImage(contentsOf: fileURL), "asset open failed: \(relativePath)")
            #endif
            print("asset open: \(asset.metadata?["asset_role"]?.stringValue ?? "?") \(relativePath) \(assetImage.width)x\(assetImage.height)")
        }

        let bannedKeys: Set<String> = [
            "recommended_component", "layout_should_be", "use_this_view",
            "next_call", "selected_design", "recommended_layout",
            "recommended_navigation"
        ]
        XCTAssertEqual(collectKeys(in: output).intersection(bannedKeys), [])

        let content = result.content.lowercased()
        for banned in ["recommended_component", "layout_should_be", "use_this_view"] {
            XCTAssertFalse(content.contains(banned))
        }
    }

    private func collectKeys(in value: JSONValue) -> Set<String> {
        switch value {
        case .object(let dictionary):
            var keys = Set(dictionary.keys)
            for nested in dictionary.values {
                keys.formUnion(collectKeys(in: nested))
            }
            return keys
        case .array(let array):
            return array.reduce(into: Set<String>()) { $0.formUnion(collectKeys(in: $1)) }
        default:
            return []
        }
    }
}
