import ClientToolProtocol
import Foundation
import XCTest
@testable import ClientToolsKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

final class ToolWorkspaceTests: XCTestCase {
    func testWorkspaceResolvesRelativePaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = ToolWorkspace(rootURL: root)

        let result = try workspace.resolve(
            relativePath: "captures/photo.jpg",
            createParentDirectory: true
        )

        XCTAssertEqual(result.path, root.appendingPathComponent("captures/photo.jpg").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.deletingLastPathComponent().path))
    }

    func testWorkspaceRejectsTraversalAndAbsolutePaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = ToolWorkspace(rootURL: root)

        XCTAssertThrowsError(try workspace.resolve(relativePath: "../outside.jpg"))
        XCTAssertThrowsError(try workspace.resolve(relativePath: "/tmp/outside.jpg"))
    }

    func testBasicImageAnalysisReturnsWorkspacePathAndMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let imageURL = root.appendingPathComponent("sample.png")
        // A 1x1 transparent PNG.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL5WQAAAABJRU5ErkJggg==")!
        try png.write(to: imageURL)

        let tool = AnalyzeLocalImageTool()
        let response = try await tool.execute(
            args: .object([
                "path": .string("sample.png"),
                "mode": .string("basic")
            ]),
            context: executionContext(workspaceRoot: root)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(response.content.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["success"] as? Bool, true)
        XCTAssertEqual(object["relative_path"] as? String, "sample.png")
        XCTAssertEqual(object["width"] as? Int, 1)
        XCTAssertEqual(object["height"] as? Int, 1)
        XCTAssertEqual(object["local_only"] as? Bool, true)
        XCTAssertNotNil(response.output)
    }

    func testImageAnalysisRejectsMissingExecutionWorkspace() async throws {
        let tool = AnalyzeLocalImageTool()
        let context = executionContext(workspaceRoot: nil)

        do {
            _ = try await tool.execute(
                args: .object([
                    "path": .string("sample.png"),
                    "mode": .string("basic")
                ]),
                context: context
            )
            XCTFail("Expected a missing workspace error")
        } catch let error as ToolWorkspaceError {
            guard case .workspaceUnavailable = error else {
                return XCTFail("Unexpected workspace error: \(error)")
            }
        }
    }

    func testReadPDFExtractsWorkspaceTextAndHonorsCharacterLimit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeTextPDF().write(to: root.appendingPathComponent("sample.pdf"))

        let response = try await ReadPDFTool().execute(
            args: .object([
                "path": .string("sample.pdf"),
                "start_page": .integer(1),
                "end_page": .integer(1),
                "max_characters": .integer(5)
            ]),
            context: executionContext(workspaceRoot: root)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(response.content.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["success"] as? Bool, true)
        XCTAssertEqual(object["relative_path"] as? String, "sample.pdf")
        XCTAssertEqual(object["page_count"] as? Int, 1)
        XCTAssertEqual(object["text"] as? String, "Hello")
        XCTAssertEqual(object["truncated"] as? Bool, true)
        let pages = try XCTUnwrap(object["pages"] as? [[String: Any]])
        XCTAssertEqual(pages.first?["page_number"] as? Int, 1)
        XCTAssertEqual(pages.first?["text"] as? String, "Hello")
    }

    func testRenderPDFPagesCreatesImageAsset() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeTextPDF().write(to: root.appendingPathComponent("sample.pdf"))

        let response = try await RenderPDFPagesTool().execute(
            args: .object([
                "path": .string("sample.pdf"),
                "scale": .number(1),
                "format": .string("png")
            ]),
            context: executionContext(workspaceRoot: root)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(response.content.utf8)) as? [String: Any]
        )
        let pages = try XCTUnwrap(object["pages"] as? [[String: Any]])
        let page = try XCTUnwrap(pages.first)
        let relativePath = try XCTUnwrap(page["relative_path"] as? String)

        XCTAssertEqual(object["page_count"] as? Int, 1)
        XCTAssertEqual(page["width"] as? Int, 612)
        XCTAssertEqual(page["height"] as? Int, 792)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path))
        XCTAssertEqual(response.assets.first?.kind, "image")
        XCTAssertEqual(response.assets.first?.workspaceRelativePath, relativePath)
    }

    func testExtractArchiveExtractsStoredAndDeflatedEntries() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let hello = Data("hello".utf8)
        try makeZIP(
            path: "notes/hello.txt",
            contents: hello,
            compressed: hello,
            method: 0,
            crc32: 0x3610_A686
        ).write(to: root.appendingPathComponent("stored.zip"))
        // Raw DEFLATE representation of "hello".
        try makeZIP(
            path: "hello.txt",
            contents: hello,
            compressed: Data([0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00]),
            method: 8,
            crc32: 0x3610_A686
        ).write(to: root.appendingPathComponent("deflated.zip"))

        let tool = ExtractArchiveTool()
        let stored = try await tool.execute(
            args: .object(["path": .string("stored.zip")]),
            context: executionContext(workspaceRoot: root)
        )
        let deflated = try await tool.execute(
            args: .object(["path": .string("deflated.zip")]),
            context: executionContext(workspaceRoot: root)
        )

        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("extracted/stored/notes/hello.txt"), encoding: .utf8),
            "hello"
        )
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("extracted/deflated/hello.txt"), encoding: .utf8),
            "hello"
        )
        XCTAssertEqual(stored.assets.first?.kind, "directory")
        XCTAssertEqual(deflated.assets.first?.workspaceRelativePath, "extracted/deflated")
    }

    func testExtractArchiveRejectsPathTraversal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let contents = Data("bad".utf8)
        try makeZIP(
            path: "../outside.txt",
            contents: contents,
            compressed: contents,
            method: 0,
            crc32: 0x822b_39fb
        ).write(to: root.appendingPathComponent("unsafe.zip"))

        do {
            _ = try await ExtractArchiveTool().execute(
                args: .object(["path": .string("unsafe.zip")]),
                context: executionContext(workspaceRoot: root)
            )
            XCTFail("Expected unsafe ZIP path to be rejected")
        } catch let error as ExtractArchiveError {
            guard case .unsafeEntryPath("../outside.txt") = error else {
                return XCTFail("Unexpected extraction error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("outside.txt").path))
    }

    func testDeviceInfoCanReturnStructuredStaticInformation() async throws {
        let response = try await DeviceInfoTool().execute(
            args: .object([
                "include_status": .bool(false),
                "include_permissions": .bool(false)
            ]),
            context: executionContext(workspaceRoot: nil)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(response.content.utf8)) as? [String: Any]
        )
        let device = try XCTUnwrap(object["device"] as? [String: Any])
        let hardware = try XCTUnwrap(object["hardware"] as? [String: Any])

        XCTAssertEqual(object["success"] as? Bool, true)
        XCTAssertEqual(device["platform"] as? String, "macOS")
        XCTAssertNotNil(device["system_version"])
        XCTAssertNotNil(hardware["processor_count"])
        XCTAssertNil(object["status"])
        XCTAssertNotNil(response.output)
    }

    func testAutoImageAnalysisReturnsStructuredGroundingPayload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let imageURL = root.appendingPathComponent("grounding.png")
        try makeGroundingTestPNG().write(to: imageURL)

        // Auto mode with default profile (agentCompact): compact payload, grounding is nil.
        let response = try await AnalyzeLocalImageTool().execute(
            args: .object([
                "path": .string("grounding.png"),
                "mode": .string("auto")
            ]),
            context: executionContext(workspaceRoot: root)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(response.content.utf8)) as? [String: Any]
        )
        // Default profile is agentCompact — grounding is nil, compact is present.
        XCTAssertNil(object["grounding"])
        let compact = try XCTUnwrap(object["compact"] as? [String: Any])
        let summary = try XCTUnwrap(compact["summary"] as? [String: Any])
        XCTAssertNotNil(summary["content_type"])
        XCTAssertTrue(
            (object["engine"] as? String)?.contains("VisualGroundingKit") == true
        )

        // Generation grounding mode: full payload with debug.
        let debugResponse = try await AnalyzeLocalImageTool().execute(
            args: .object([
                "path": .string("grounding.png"),
                "mode": .string("grounding"),
                "profile": .string("generation_grounding"),
                "include_debug": .bool(true)
            ]),
            context: executionContext(workspaceRoot: root)
        )
        let debugObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(debugResponse.content.utf8)) as? [String: Any]
        )
        let debugGrounding = try XCTUnwrap(debugObject["grounding"] as? [String: Any])
        XCTAssertEqual(debugGrounding["schemaVersion"] as? String, "visual_grounding.v1")
        let contentType = try XCTUnwrap(debugGrounding["contentType"] as? [String: Any])
        XCTAssertNotNil(contentType["primaryType"])
        XCTAssertNotNil(debugGrounding["debug"] as? [String: Any])
        // Full grounding includes motion and preservation hints.
        XCTAssertNotNil(debugGrounding["motionHints"])
        XCTAssertNotNil(debugGrounding["preservationHints"])
    }

    private func executionContext(workspaceRoot: URL?) -> ClientToolExecutionContext {
        ClientToolExecutionContext(
            workspaceRoot: workspaceRoot,
            workspaceID: "test-workspace",
            sessionID: "test-session",
            turnID: "test-turn",
            callID: "test-call"
        )
    }

    private func makeGroundingTestPNG() throws -> Data {
        #if canImport(AppKit)
        let image = NSImage(size: NSSize(width: 256, height: 256))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 256, height: 256).fill()
        NSColor.systemBlue.setFill()
        NSRect(x: 64, y: 64, width: 128, height: 128).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw TestImageError.encodingFailed
        }
        return data
        #elseif canImport(UIKit)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 64, y: 64, width: 128, height: 128))
        }
        guard let data = image.pngData() else {
            throw TestImageError.encodingFailed
        }
        return data
        #else
        throw TestImageError.encodingFailed
        #endif
    }

    private func makeTextPDF() -> Data {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length 41 >>\nstream\nBT /F1 24 Tf 72 720 Td (Hello PDF) Tj ET\nendstream"
        ]
        var pdf = "%PDF-1.4\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xrefOffset = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        return Data(pdf.utf8)
    }

    private func makeZIP(
        path: String,
        contents: Data,
        compressed: Data,
        method: UInt16,
        crc32: UInt32
    ) -> Data {
        let name = Data(path.utf8)
        var archive = Data()
        archive.appendLittleEndian(UInt32(0x0403_4b50))
        archive.appendLittleEndian(UInt16(20))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(method)
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(crc32)
        archive.appendLittleEndian(UInt32(compressed.count))
        archive.appendLittleEndian(UInt32(contents.count))
        archive.appendLittleEndian(UInt16(name.count))
        archive.appendLittleEndian(UInt16(0))
        archive.append(name)
        archive.append(compressed)

        let centralOffset = archive.count
        archive.appendLittleEndian(UInt32(0x0201_4b50))
        archive.appendLittleEndian(UInt16(20))
        archive.appendLittleEndian(UInt16(20))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(method)
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(crc32)
        archive.appendLittleEndian(UInt32(compressed.count))
        archive.appendLittleEndian(UInt32(contents.count))
        archive.appendLittleEndian(UInt16(name.count))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt32(0))
        archive.appendLittleEndian(UInt32(0))
        archive.append(name)
        let centralSize = archive.count - centralOffset

        archive.appendLittleEndian(UInt32(0x0605_4b50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(1))
        archive.appendLittleEndian(UInt16(1))
        archive.appendLittleEndian(UInt32(centralSize))
        archive.appendLittleEndian(UInt32(centralOffset))
        archive.appendLittleEndian(UInt16(0))
        return archive
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private enum TestImageError: Error {
    case encodingFailed
}
