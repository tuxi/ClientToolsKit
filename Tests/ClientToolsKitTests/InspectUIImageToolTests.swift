import ClientToolProtocol
import CoreGraphics
import CoreText
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ClientToolsKit

final class InspectUIImageToolTests: XCTestCase {
    // MARK: - Fixtures

    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InspectUIImageToolTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    private func makeContext(callID: String = "call_test") -> ClientToolExecutionContext {
        ClientToolExecutionContext(
            workspaceRoot: rootURL,
            workspaceID: "ws_test",
            sessionID: "session_test",
            turnID: "turn_test",
            callID: callID
        )
    }

    private func writePNG(width: Int = 400, height: Int = 300, name: String = "ui.png") throws -> URL {
        let url = rootURL.appendingPathComponent(name)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("Unable to create a bitmap context")
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 20, y: 20, width: 120, height: 40))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw XCTSkip("Unable to encode the fixture image")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("Unable to finalize the fixture image")
        }
        return url
    }

    private func writeTextImage(name: String = "ui-text.png") throws -> URL {
        let url = rootURL.appendingPathComponent(name)
        let width = 800
        let height = 400
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("Unable to create a bitmap context")
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 40, y: 40, width: 720, height: 100))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ]
        guard let attributed = CFAttributedStringCreate(
            nil,
            "HELLO UI" as CFString,
            attributes as CFDictionary
        ) else {
            throw XCTSkip("Unable to build the fixture text")
        }
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 60, y: 190)
        CTLineDraw(line, context)

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw XCTSkip("Unable to encode the fixture image")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("Unable to finalize the fixture image")
        }
        return url
    }

    private struct StubVisionProvider: UIEvidenceVisionProviding {
        let observations: UIVisionObservations

        func analyze(image: CGImage) throws -> UIVisionObservations {
            observations
        }
    }

    private struct UnavailableVisionProvider: UIEvidenceVisionProviding {
        func analyze(image: CGImage) throws -> UIVisionObservations {
            throw UIEvidenceVisionError.unavailable("Vision is unavailable in this test")
        }
    }

    private func text(_ value: String, topLeftY: Double, x: Double = 0.1, width: Double = 0.5, height: Double = 0.04) -> UIVisionText {
        UIVisionText(
            text: value,
            boundingBox: CGRect(x: x, y: 1 - topLeftY - height, width: width, height: height),
            confidence: 0.95
        )
    }

    private func rectangle(topLeftX: Double, topLeftY: Double, width: Double, height: Double) -> UIVisionRectangle {
        UIVisionRectangle(
            boundingBox: CGRect(x: topLeftX, y: 1 - topLeftY - height, width: width, height: height),
            confidence: 0.9
        )
    }

    private func execute(
        tool: InspectUIImageTool,
        args: JSONValue
    ) async throws -> ClientToolExecutionResult {
        try await tool.execute(args: args, context: makeContext())
    }

    // MARK: - OCR and coordinates

    func testOCRTextBlockUsesNormalizedTopLeftBox() async throws {
        _ = try writePNG()
        let observations = UIVisionObservations(
            textBlocks: [
                UIVisionText(
                    text: "商品详情",
                    boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.1),
                    confidence: 0.97
                )
            ]
        )
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: observations))
        let result = try await execute(tool: tool, args: .object(["path": .string("ui.png")]))

        let document = try decodeDocument(result)
        XCTAssertEqual(document.schema, "ui_evidence.v1")
        XCTAssertEqual(document.coordinateSpace, "normalized_top_left")
        XCTAssertEqual(document.producer.name, "ClientToolsKit.inspect_ui_image")
        XCTAssertEqual(document.producer.version, "1")
        XCTAssertEqual(document.source.width, 400)
        XCTAssertEqual(document.source.height, 300)
        XCTAssertEqual(document.source.mimeType, "image/png")
        XCTAssertEqual(document.source.sourceKind, .staticImage)
        XCTAssertEqual(document.source.sha256.count, 64)
        XCTAssertEqual(document.elements.count, 1)

        let element = try XCTUnwrap(document.elements.first)
        XCTAssertEqual(element.kind, .text)
        XCTAssertEqual(element.evidence, .observed)
        XCTAssertEqual(element.text, "商品详情")
        XCTAssertEqual(element.bbox.x, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(element.bbox.y, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(element.bbox.width, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(element.bbox.height, 0.1, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(element.bbox.maxX, 1.0)
        XCTAssertLessThanOrEqual(element.bbox.maxY, 1.0)
        XCTAssertEqual(document.limits.elementCount, 1)
    }

    func testRealVisionProducesNormalizedTextEvidence() async throws {
        _ = try writeTextImage()
        let tool = InspectUIImageTool()
        let result = try await execute(tool: tool, args: .object(["path": .string("ui-text.png")]))
        let document = try decodeDocument(result)

        let textElements = document.elements.filter { $0.kind == .text }
        try XCTSkipIf(textElements.isEmpty, "Vision OCR returned no text on this host")

        XCTAssertTrue(textElements.contains { $0.text?.localizedCaseInsensitiveContains("HELLO") == true })
        for element in textElements {
            XCTAssertGreaterThan(element.bbox.width, 0)
            XCTAssertGreaterThan(element.bbox.height, 0)
            XCTAssertLessThanOrEqual(element.bbox.maxX, 1.000_001)
            XCTAssertLessThanOrEqual(element.bbox.maxY, 1.000_001)
            XCTAssertGreaterThanOrEqual(element.confidence, 0)
            XCTAssertLessThanOrEqual(element.confidence, 1)
        }
    }

    func testSourceKindAndCropPurposeAreApplied() async throws {
        _ = try writePNG()
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: UIVisionObservations()))
        let result = try await execute(
            tool: tool,
            args: .object([
                "path": .string("ui.png"),
                "source_kind": .string("app_screenshot"),
                "crops": .array([
                    .object([
                        "bbox": .object([
                            "x": .number(0.1), "y": .number(0.2),
                            "width": .number(0.3), "height": .number(0.2)
                        ]),
                        "purpose": .string("detail")
                    ])
                ])
            ])
        )
        let document = try decodeDocument(result)
        XCTAssertEqual(document.source.sourceKind, .appScreenshot)
        XCTAssertEqual(document.crops.count, 1)
        XCTAssertEqual(document.crops[0].purpose, .detail)
    }

    // MARK: - Repeated region candidates

    func testVerticalRepeatedGroupCandidate() async throws {
        _ = try writePNG()
        let observations = UIVisionObservations(
            textBlocks: [
                text("Row one", topLeftY: 0.20),
                text("Row two", topLeftY: 0.30),
                text("Row three", topLeftY: 0.40)
            ]
        )
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: observations))
        let result = try await execute(tool: tool, args: .object(["path": .string("ui.png")]))

        let document = try decodeDocument(result)
        XCTAssertEqual(document.elements.count, 3)
        XCTAssertEqual(document.repeatedGroups.count, 1)
        let group = try XCTUnwrap(document.repeatedGroups.first)
        XCTAssertEqual(group.axis, .vertical)
        XCTAssertEqual(group.evidence, .inferred)
        XCTAssertEqual(group.memberIDs.count, 3)
        XCTAssertEqual(Set(group.memberIDs).count, 3)
        XCTAssertTrue(group.memberIDs.allSatisfy { id in document.elements.contains { $0.id == id } })
        XCTAssertGreaterThan(group.confidence, 0.5)
        XCTAssertTrue(document.uncertainties.contains { $0.reason == "geometry_only" })
    }

    func testGridRepeatedGroupCandidate() async throws {
        _ = try writePNG()
        let observations = UIVisionObservations(
            rectangles: [
                rectangle(topLeftX: 0.10, topLeftY: 0.20, width: 0.30, height: 0.20),
                rectangle(topLeftX: 0.55, topLeftY: 0.20, width: 0.30, height: 0.20),
                rectangle(topLeftX: 0.10, topLeftY: 0.50, width: 0.30, height: 0.20),
                rectangle(topLeftX: 0.55, topLeftY: 0.50, width: 0.30, height: 0.20)
            ]
        )
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: observations))
        let result = try await execute(tool: tool, args: .object(["path": .string("ui.png")]))

        let document = try decodeDocument(result)
        let containers = document.elements.filter { $0.kind == .container }
        XCTAssertEqual(containers.count, 4)
        XCTAssertTrue(containers.allSatisfy { $0.evidence == .inferred })
        let textElements = document.elements.filter { $0.kind == .text }
        XCTAssertTrue(textElements.allSatisfy { $0.evidence == .observed })
        let grid = try XCTUnwrap(document.repeatedGroups.first { $0.axis == .grid })
        XCTAssertEqual(grid.memberIDs.count, 4)
        XCTAssertEqual(grid.evidence, .inferred)
        XCTAssertEqual(Set(grid.memberIDs).count, 4)
    }

    // MARK: - Crops

    func testCropAssetsRetainSourceReference() async throws {
        _ = try writePNG(width: 400, height: 300)
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: UIVisionObservations()))
        let result = try await execute(
            tool: tool,
            args: .object([
                "path": .string("ui.png"),
                "crops": .array([
                    .object([
                        "bbox": .object([
                            "x": .number(0.1), "y": .number(0.2),
                            "width": .number(0.3), "height": .number(0.2)
                        ]),
                        "purpose": .string("controls")
                    ])
                ])
            ])
        )

        let document = try decodeDocument(result)
        XCTAssertEqual(result.assets.count, 2)
        XCTAssertEqual(result.assets[0].metadata?["asset_role"], .string("source"))
        XCTAssertEqual(result.assets[0].id, document.source.assetID)
        XCTAssertNil(result.assets[0].absolutePath)
        XCTAssertNil(result.assets[1].absolutePath)

        XCTAssertEqual(result.assets[1].metadata?["asset_role"], .string("crop"))
        XCTAssertEqual(result.assets[1].metadata?["source_asset_id"], .string(document.source.assetID))
        XCTAssertEqual(result.assets[1].mimeType, "image/png")
        XCTAssertEqual(document.crops.count, 1)
        XCTAssertEqual(document.crops[0].assetID, result.assets[1].id)
        XCTAssertEqual(document.crops[0].sourceBBox.x, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(document.crops[0].sourceBBox.y, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(document.crops[0].sourceBBox.width, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(document.crops[0].sourceBBox.height, 0.2, accuracy: 0.000_001)

        let cropRelativePath = try XCTUnwrap(result.assets[1].workspaceRelativePath)
        let cropURL = rootURL.appendingPathComponent(cropRelativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cropURL.path))

        guard let source = CGImageSourceCreateWithURL(cropURL as CFURL, nil),
              let cropImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("Crop asset is not a decodable image")
        }
        XCTAssertEqual(cropImage.width, 120)
        XCTAssertEqual(cropImage.height, 60)
    }

    func testInvalidCropArgumentsAreRejected() async throws {
        _ = try writePNG()
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: UIVisionObservations()))
        let invalidCrops: [JSONValue] = [
            .object([
                "bbox": .object([
                    "x": .number(0.9), "y": .number(0.1),
                    "width": .number(0.3), "height": .number(0.1)
                ])
            ]),
            .object([
                "bbox": .object([
                    "x": .number(-0.1), "y": .number(0.1),
                    "width": .number(0.3), "height": .number(0.1)
                ])
            ]),
            .object([
                "bbox": .object([
                    "x": .number(0.1), "y": .number(0.1),
                    "width": .number(0), "height": .number(0.1)
                ])
            ])
        ]

        for crops in invalidCrops {
            do {
                _ = try await execute(
                    tool: tool,
                    args: .object(["path": .string("ui.png"), "crops": .array([crops])])
                )
                XCTFail("Expected invalid crop arguments to be rejected")
            } catch let error as InspectUIImageError {
                guard case .invalidArguments = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    // MARK: - Malformed input and workspace boundaries

    func testMissingFileFailsExplicitly() async throws {
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: UIVisionObservations()))
        do {
            _ = try await execute(tool: tool, args: .object(["path": .string("missing.png")]))
            XCTFail("Expected a missing-file error")
        } catch let error as InspectUIImageError {
            guard case .fileNotFound = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testNonImageFileFailsExplicitly() async throws {
        let url = rootURL.appendingPathComponent("not-an-image.png")
        try Data("this is not an image".utf8).write(to: url)
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: UIVisionObservations()))
        do {
            _ = try await execute(tool: tool, args: .object(["path": .string("not-an-image.png")]))
            XCTFail("Expected an unsupported-image error")
        } catch let error as InspectUIImageError {
            guard case .unsupportedImage = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testTraversalAndAbsolutePathsAreRejected() async throws {
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: UIVisionObservations()))
        for path in ["../outside.png", "/tmp/outside.png"] {
            do {
                _ = try await execute(tool: tool, args: .object(["path": .string(path)]))
                XCTFail("Expected path boundary rejection for \(path)")
            } catch is ToolWorkspaceError {
                // Expected.
            } catch let error as InspectUIImageError {
                guard case .invalidArguments = error else {
                    return XCTFail("Unexpected error for \(path): \(error)")
                }
            }
        }
    }

    func testSymlinkOutsideWorkspaceIsRejected() async throws {
        let outsideDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InspectUIImageToolOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDirectory) }

        let outsideFile = outsideDirectory.appendingPathComponent("outside.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: outsideFile)
        let linkURL = rootURL.appendingPathComponent("linked.png")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideFile)

        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: UIVisionObservations()))
        do {
            _ = try await execute(tool: tool, args: .object(["path": .string("linked.png")]))
            XCTFail("Expected symlink escape to be rejected")
        } catch is ToolWorkspaceError {
            // Expected.
        }
    }

    // MARK: - Degradation

    func testVisionUnavailableDegradesToSourceIdentity() async throws {
        _ = try writePNG()
        let tool = InspectUIImageTool(visionProvider: UnavailableVisionProvider())
        let result = try await execute(tool: tool, args: .object(["path": .string("ui.png")]))

        let document = try decodeDocument(result)
        XCTAssertEqual(document.elements.count, 0)
        XCTAssertEqual(document.repeatedGroups.count, 0)
        XCTAssertEqual(document.source.width, 400)
        XCTAssertEqual(document.source.height, 300)
        XCTAssertTrue(document.uncertainties.contains { $0.reason == "vision_unavailable" })
        XCTAssertTrue(result.content.contains("Vision analysis unavailable"))
        XCTAssertEqual(result.assets.count, 1)
        XCTAssertNil(result.assets[0].absolutePath)
    }

    func testElementLimitIsExplicit() async throws {
        _ = try writePNG()
        let observations = UIVisionObservations(
            textBlocks: (0..<510).map { index in
                UIVisionText(
                    text: "Item \(index)",
                    boundingBox: CGRect(
                        x: 0.05,
                        y: Double(index) / 700.0,
                        width: 0.5,
                        height: 0.001
                    ),
                    confidence: 0.5
                )
            }
        )
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: observations))
        let result = try await execute(tool: tool, args: .object(["path": .string("ui.png")]))

        let document = try decodeDocument(result)
        XCTAssertEqual(document.limits.elementCount, 500)
        XCTAssertTrue(document.limits.elementsTruncated)
        XCTAssertEqual(document.elements.count, 500)
        XCTAssertTrue(document.uncertainties.contains { $0.reason == "element_limit" })
    }

    // MARK: - Contract boundaries

    func testOutputContainsNoBannedRecommendationFields() async throws {
        _ = try writePNG()
        let observations = UIVisionObservations(
            textBlocks: [text("Buy now", topLeftY: 0.2)],
            rectangles: [rectangle(topLeftX: 0.1, topLeftY: 0.6, width: 0.8, height: 0.1)]
        )
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: observations))
        let result = try await execute(tool: tool, args: .object(["path": .string("ui.png")]))

        let output = try XCTUnwrap(result.output)
        let bannedKeys: Set<String> = [
            "recommended_component", "layout_should_be", "use_this_view",
            "next_call", "selected_design", "recommended_layout",
            "recommended_navigation"
        ]
        XCTAssertEqual(collectKeys(in: output).intersection(bannedKeys), [])
    }

    func testToolDescriptionsAvoidWorkflowRecommendations() {
        let inspectDescription = InspectUIImageTool().description
        let analyzeDescription = AnalyzeLocalImageTool().description

        for description in [inspectDescription, analyzeDescription] {
            XCTAssertFalse(description.contains("推荐"))
            XCTAssertFalse(description.contains("先用"))
            XCTAssertFalse(description.contains("use before"))
            XCTAssertFalse(description.contains("call me first"))
        }
        XCTAssertTrue(analyzeDescription.contains("不向模型暴露图片像素"))
        XCTAssertTrue(inspectDescription.contains("不作为指令执行"))
    }

    func testInputSchemaDescribesCropsAndSourceKind() throws {
        let schema = try XCTUnwrap(InspectUIImageTool().inputSchema)
        guard case .object(let root) = schema,
              case .object(let properties) = root["properties"] ?? .null else {
            return XCTFail("input schema is missing properties")
        }
        XCTAssertNotNil(properties["path"])
        XCTAssertNotNil(properties["source_kind"])
        guard case .object(let cropDefinition) = properties["crops"] ?? .null else {
            return XCTFail("crops is missing from the input schema")
        }
        XCTAssertEqual(cropDefinition["maxItems"], .integer(16))
    }

    func testToolRegistersWithProtocolRegistryAndInfoDecodes() async throws {
        let registry = ToolRegistry()
        await registry.register(InspectUIImageTool())

        let found = await registry.find(name: "inspect_ui_image")
        XCTAssertEqual(found?.name, "inspect_ui_image")
        let names = await registry.registeredNames
        XCTAssertTrue(names.contains("inspect_ui_image"))

        let tool = InspectUIImageTool()
        let info = ClientToolInfo(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.inputSchema
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ClientToolInfo.self, from: data)
        XCTAssertEqual(decoded.name, "inspect_ui_image")
        XCTAssertEqual(decoded.description, tool.description)
        XCTAssertTrue(decoded.description.contains("ui_evidence.v1"))
        XCTAssertNotNil(decoded.inputSchema)
    }

    // MARK: - Helpers

    private func decodeDocument(_ result: ClientToolExecutionResult) throws -> UIEvidenceDocument {
        let output = try XCTUnwrap(result.output)
        let data = try JSONEncoder().encode(output)
        return try JSONDecoder().decode(UIEvidenceDocument.self, from: data)
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
