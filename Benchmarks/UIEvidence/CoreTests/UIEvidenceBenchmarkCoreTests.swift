import ClientToolProtocol
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import UIEvidenceBenchmarkCore

final class UIEvidenceBenchmarkCoreTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UIEvidenceBenchmarkCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    private func makeContext() -> ClientToolExecutionContext {
        ClientToolExecutionContext(
            workspaceRoot: rootURL,
            workspaceID: "benchmark",
            sessionID: "benchmark",
            turnID: "turn",
            callID: "call"
        )
    }

    private func writePNG() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = repository
            .appendingPathComponent("Benchmarks/UIEvidence/dataset-v2/images/settings_general_light.png")
        try FileManager.default.copyItem(at: source, to: rootURL.appendingPathComponent("ui.png"))
    }

    private func execute(
        tool: InspectUIImageTool,
        args: JSONValue
    ) async throws -> ClientToolExecutionResult {
        try await tool.execute(args: args, context: makeContext())
    }

    private func decodeDocument(_ result: ClientToolExecutionResult) throws -> UIEvidenceDocument {
        let data = try JSONEncoder().encode(XCTUnwrap(result.output))
        return try JSONDecoder().decode(UIEvidenceDocument.self, from: data)
    }

    private func text(
        _ value: String,
        topLeftY: Double,
        x: Double = 0.1,
        width: Double = 0.5,
        height: Double = 0.04
    ) -> UIVisionText {
        UIVisionText(
            text: value,
            boundingBox: CGRect(x: x, y: 1 - topLeftY - height, width: width, height: height),
            confidence: 0.95
        )
    }

    private func rectangle(
        topLeftX: Double,
        topLeftY: Double,
        width: Double,
        height: Double
    ) -> UIVisionRectangle {
        UIVisionRectangle(
            boundingBox: CGRect(x: topLeftX, y: 1 - topLeftY - height, width: width, height: height),
            confidence: 0.9
        )
    }

    private struct StubVisionProvider: UIEvidenceVisionProviding {
        let observations: UIVisionObservations

        func analyze(image: CGImage) throws -> UIVisionObservations {
            observations
        }
    }

    func testProducerVersionIsV2() async throws {
        try writePNG()
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: UIVisionObservations()))
        let document = try decodeDocument(try await execute(tool: tool, args: .object(["path": .string("ui.png")])))
        XCTAssertEqual(document.producer.version, "2")
    }

    func testVisionRectanglesAreWeakGeometryAndDoNotCreateGroups() async throws {
        try writePNG()
        let observations = UIVisionObservations(rectangles: [
            rectangle(topLeftX: 0.10, topLeftY: 0.20, width: 0.30, height: 0.20),
            rectangle(topLeftX: 0.55, topLeftY: 0.20, width: 0.30, height: 0.20),
            rectangle(topLeftX: 0.10, topLeftY: 0.50, width: 0.30, height: 0.20),
            rectangle(topLeftX: 0.55, topLeftY: 0.50, width: 0.30, height: 0.20),
        ])
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: observations))
        let document = try decodeDocument(try await execute(tool: tool, args: .object(["path": .string("ui.png")])))
        let rectangles = document.elements.filter { $0.role == "vision_rectangle" }
        XCTAssertEqual(rectangles.count, 4)
        XCTAssertTrue(rectangles.allSatisfy { $0.evidence == .inferred })
        XCTAssertTrue(document.repeatedGroups.isEmpty)
        XCTAssertTrue(document.uncertainties.contains { $0.reason == "weak_geometry" })
    }

    func testRepeatedRowsTolerateDifferentTextWidths() async throws {
        try writePNG()
        let observations = UIVisionObservations(textBlocks: [
            text("Short", topLeftY: 0.20, x: 0.2, width: 0.08),
            text("A much longer setting label", topLeftY: 0.30, x: 0.2, width: 0.24),
            text("Medium label", topLeftY: 0.40, x: 0.2, width: 0.14),
            text("Another label", topLeftY: 0.50, x: 0.2, width: 0.16),
        ])
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: observations))
        let document = try decodeDocument(try await execute(tool: tool, args: .object(["path": .string("ui.png")])))
        XCTAssertEqual(document.repeatedGroups.count, 1)
        let group = try XCTUnwrap(document.repeatedGroups.first)
        XCTAssertGreaterThanOrEqual(group.memberIDs.count, 3)
    }

    func testAmbiguousTextDoesNotEmitRepeatedGroup() async throws {
        try writePNG()
        let observations = UIVisionObservations(textBlocks: [
            text("One", topLeftY: 0.10, x: 0.1, width: 0.05),
            text("Two", topLeftY: 0.37, x: 0.3, width: 0.22),
            text("Three", topLeftY: 0.78, x: 0.55, width: 0.11),
        ])
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: observations))
        let document = try decodeDocument(try await execute(tool: tool, args: .object(["path": .string("ui.png")])))
        XCTAssertTrue(document.repeatedGroups.isEmpty)
    }

    func testCropPathsAreDeterministicAcrossRepeatedCalls() async throws {
        try writePNG()
        let tool = InspectUIImageTool(visionProvider: StubVisionProvider(observations: UIVisionObservations()))
        let args: JSONValue = .object([
            "path": .string("ui.png"),
            "crops": .array([
                .object([
                    "bbox": .object([
                        "x": .number(0.1), "y": .number(0.2),
                        "width": .number(0.3), "height": .number(0.2),
                    ]),
                    "purpose": .string("controls"),
                ]),
            ]),
        ])
        let first = try await execute(tool: tool, args: args)
        let second = try await execute(tool: tool, args: args)
        XCTAssertEqual(first.assets.map(\.id), second.assets.map(\.id))
        XCTAssertEqual(
            first.assets.compactMap(\.workspaceRelativePath),
            second.assets.compactMap(\.workspaceRelativePath)
        )
        let evidenceDirectory = rootURL.appendingPathComponent("ui-evidence", isDirectory: true)
        let files = FileManager.default.enumerator(at: evidenceDirectory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { !$0.hasDirectoryPath } ?? []
        XCTAssertEqual(files.filter { $0.pathExtension == "png" }.count, 1)
    }
}
