import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Page Size

/// Standard document page sizes in points (72 points per inch).
public enum PageSize: String, CaseIterable, Sendable {
    case a4
    case letter
    case legal

    /// Page dimensions in points at 72 DPI.
    public var rect: CGRect {
        switch self {
        case .a4:     return CGRect(x: 0, y: 0, width: 595, height: 842)
        case .letter: return CGRect(x: 0, y: 0, width: 612, height: 792)
        case .legal:  return CGRect(x: 0, y: 0, width: 612, height: 1008)
        }
    }

    public var width: CGFloat { rect.width }
    public var height: CGFloat { rect.height }
}

// MARK: - Page Layout Constants

/// Default page margins for rendered documents.
public struct PageLayout: Sendable {
    public let pageSize: PageSize
    public let topMargin: CGFloat
    public let bottomMargin: CGFloat
    public let leftMargin: CGFloat
    public let rightMargin: CGFloat

    public var textRect: CGRect {
        let page = pageSize.rect
        return CGRect(
            x: leftMargin,
            y: topMargin,
            width: page.width - leftMargin - rightMargin,
            height: page.height - topMargin - bottomMargin
        )
    }

    /// Standard 1-inch margins on all sides.
    public static func standard(_ pageSize: PageSize) -> PageLayout {
        PageLayout(
            pageSize: pageSize,
            topMargin: 72,
            bottomMargin: 72,
            leftMargin: 72,
            rightMargin: 72
        )
    }
}

// MARK: - Page Range Parsing

/// Parses a page-range string like "1-5,8,10-12" into a sorted, deduplicated array of 1-based page numbers.
///
/// Returns `nil` if the string is empty. Throws `PageRangeParseError` on invalid syntax or out-of-bounds pages.
public func parsePageRange(_ input: String, pageCount: Int) throws -> [Int] {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw PageRangeParseError.emptyRange
    }

    var pages = Set<Int>()

    let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    for part in parts {
        if part.contains("-") {
            let bounds = part.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            guard bounds.count == 2,
                  let start = Int(bounds[0]),
                  let end = Int(bounds[1]) else {
                throw PageRangeParseError.invalidSyntax(part)
            }
            guard start >= 1, end <= pageCount else {
                throw PageRangeParseError.pageOutOfBounds(part, pageCount: pageCount)
            }
            guard start <= end else {
                throw PageRangeParseError.invalidRangeOrder(start: start, end: end)
            }
            pages.formUnion(start...end)
        } else {
            guard let page = Int(part) else {
                throw PageRangeParseError.invalidSyntax(part)
            }
            guard (1...pageCount).contains(page) else {
                throw PageRangeParseError.pageOutOfBounds(part, pageCount: pageCount)
            }
            pages.insert(page)
        }
    }

    guard !pages.isEmpty else {
        throw PageRangeParseError.emptyRange
    }

    return pages.sorted()
}

public enum PageRangeParseError: LocalizedError {
    case emptyRange
    case invalidSyntax(String)
    case pageOutOfBounds(String, pageCount: Int)
    case invalidRangeOrder(start: Int, end: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyRange:
            return "Page range must not be empty."
        case .invalidSyntax(let part):
            return "Invalid page range syntax: \"\(part)\". Use numbers separated by commas, e.g. \"1-5,8,10-12\"."
        case .pageOutOfBounds(let part, let pageCount):
            return "Page number \"\(part)\" is out of bounds (document has \(pageCount) pages)."
        case .invalidRangeOrder(let start, let end):
            return "Invalid range order: start page \(start) is after end page \(end)."
        }
    }
}

// MARK: - Attributed String → PDF Rendering

/// Renders an attributed string to a multi-page PDF and returns the PDF data.
///
/// On iOS, uses `UIGraphicsPDFRenderer` (UIKit-recommended, writes to memory).
/// On macOS, uses `CGPDFContext` (writes to a temp file).
public func renderAttributedStringToPDF(
    attributedString: NSAttributedString,
    pageSize: PageSize,
    topMargin: CGFloat = 72,
    bottomMargin: CGFloat = 72,
    leftMargin: CGFloat = 72,
    rightMargin: CGFloat = 72,
    headerTitle: String? = nil,
    showPageNumbers: Bool = true,
    startingPageNumber: Int = 1
) throws -> Data {
    let pageRect = pageSize.rect
    let textRect = CGRect(
        x: leftMargin,
        y: topMargin,
        width: pageRect.width - leftMargin - rightMargin,
        height: pageRect.height - topMargin - bottomMargin
    )
    let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)

    #if canImport(UIKit)
    // iOS: UIGraphicsPDFRenderer — writes to NSMutableData in memory, no temp-file issues.
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
    let pdfData = renderer.pdfData { rendererContext in
        var currentLocation = 0
        let totalLength = attributedString.length
        var pageNumber = startingPageNumber

        // UIGraphicsPDFRenderer begins the first page automatically.
        while currentLocation < totalLength {
            if pageNumber > startingPageNumber {
                rendererContext.beginPage()
            }

            let ctx = rendererContext.cgContext

            // UIGraphicsPDFRenderer uses UIKit coordinate system (origin top-left).
            drawHeaderFlipped(
                in: ctx,
                title: headerTitle,
                pageRect: pageRect,
                leftMargin: leftMargin,
                rightMargin: rightMargin
            )

            let framePath = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: currentLocation, length: 0),
                framePath,
                nil
            )
            CTFrameDraw(frame, ctx)
            let visibleRange = CTFrameGetVisibleStringRange(frame)

            if showPageNumbers {
                drawFooterFlipped(
                    in: ctx,
                    pageNumber: pageNumber,
                    pageRect: pageRect,
                    leftMargin: leftMargin,
                    rightMargin: rightMargin
                )
            }

            currentLocation += visibleRange.length
            pageNumber += 1

            guard visibleRange.length > 0 else { break }
        }
    }
    return pdfData

    #else
    // macOS: CGPDFContext writes to a temp file.
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".pdf")

    var mediaBox = pageRect
    guard let pdfContext = CGContext(tempURL as CFURL, mediaBox: &mediaBox, nil) else {
        throw PDFRenderError.contextCreationFailed
    }

    var currentLocation = 0
    let totalLength = attributedString.length
    var pageNumber = startingPageNumber

    while currentLocation < totalLength {
        var pageMediaBox = pageRect
        pdfContext.beginPage(mediaBox: &pageMediaBox)

        // CGPDFContext origin is bottom-left — CoreText draws correctly here.
        drawHeaderStandard(
            in: pdfContext,
            title: headerTitle,
            pageRect: pageRect,
            leftMargin: leftMargin,
            rightMargin: rightMargin
        )

        let textRectStandard = CGRect(
            x: leftMargin,
            y: bottomMargin,
            width: pageRect.width - leftMargin - rightMargin,
            height: pageRect.height - topMargin - bottomMargin
        )
        let framePath = CGPath(rect: textRectStandard, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: currentLocation, length: 0),
            framePath,
            nil
        )
        CTFrameDraw(frame, pdfContext)
        let visibleRange = CTFrameGetVisibleStringRange(frame)

        if showPageNumbers {
            drawFooterStandard(
                in: pdfContext,
                pageNumber: pageNumber,
                pageRect: pageRect,
                leftMargin: leftMargin,
                rightMargin: rightMargin
            )
        }

        pdfContext.endPage()

        currentLocation += visibleRange.length
        pageNumber += 1

        guard visibleRange.length > 0 else { break }
    }

    pdfContext.closePDF()
    return try Data(contentsOf: tempURL)
    #endif
}

// MARK: - Page Decorations (UIKit / flipped coords, for UIGraphicsPDFRenderer)

/// Header for UIKit-flipped contexts (origin top-left, Y increases downward).
private func drawHeaderFlipped(
    in context: CGContext,
    title: String?,
    pageRect: CGRect,
    leftMargin: CGFloat,
    rightMargin: CGFloat
) {
    let textY: CGFloat = 36
    let lineY: CGFloat = 54

    if let title = title {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: headerFooterFont(ofSize: 9),
            .foregroundColor: headerFooterColor()
        ]
        let attrString = NSAttributedString(string: title, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString as CFAttributedString)
        context.textPosition = CGPoint(x: leftMargin, y: textY)
        CTLineDraw(line, context)
    }

    context.setStrokeColor(separatorColor().cgColor)
    context.setLineWidth(0.5)
    context.move(to: CGPoint(x: leftMargin, y: lineY))
    context.addLine(to: CGPoint(x: pageRect.width - rightMargin, y: lineY))
    context.strokePath()
}

/// Footer for UIKit-flipped contexts.
private func drawFooterFlipped(
    in context: CGContext,
    pageNumber: Int,
    pageRect: CGRect,
    leftMargin: CGFloat,
    rightMargin: CGFloat
) {
    let textY: CGFloat = pageRect.height - 36
    let lineY: CGFloat = pageRect.height - 54

    context.setStrokeColor(separatorColor().cgColor)
    context.setLineWidth(0.5)
    context.move(to: CGPoint(x: leftMargin, y: lineY))
    context.addLine(to: CGPoint(x: pageRect.width - rightMargin, y: lineY))
    context.strokePath()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: headerFooterFont(ofSize: 9),
        .foregroundColor: headerFooterColor()
    ]
    let pageString = "— \(pageNumber) —"
    let attrString = NSAttributedString(string: pageString, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString as CFAttributedString)

    let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
    let centerX = (pageRect.width - lineWidth) / 2
    context.textPosition = CGPoint(x: centerX, y: textY)
    CTLineDraw(line, context)
}

// MARK: - Page Decorations (standard / bottom-left coords, for CGPDFContext)

/// Header for standard PDF contexts (origin bottom-left, Y increases upward).
private func drawHeaderStandard(
    in context: CGContext,
    title: String?,
    pageRect: CGRect,
    leftMargin: CGFloat,
    rightMargin: CGFloat
) {
    let textY: CGFloat = pageRect.height - 36
    let lineY: CGFloat = pageRect.height - 54

    if let title = title {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: headerFooterFont(ofSize: 9),
            .foregroundColor: headerFooterColor()
        ]
        let attrString = NSAttributedString(string: title, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString as CFAttributedString)
        context.textPosition = CGPoint(x: leftMargin, y: textY)
        CTLineDraw(line, context)
    }

    context.setStrokeColor(separatorColor().cgColor)
    context.setLineWidth(0.5)
    context.move(to: CGPoint(x: leftMargin, y: lineY))
    context.addLine(to: CGPoint(x: pageRect.width - rightMargin, y: lineY))
    context.strokePath()
}

/// Footer for standard PDF contexts.
private func drawFooterStandard(
    in context: CGContext,
    pageNumber: Int,
    pageRect: CGRect,
    leftMargin: CGFloat,
    rightMargin: CGFloat
) {
    let textY: CGFloat = 36
    let lineY: CGFloat = 54

    context.setStrokeColor(separatorColor().cgColor)
    context.setLineWidth(0.5)
    context.move(to: CGPoint(x: leftMargin, y: lineY))
    context.addLine(to: CGPoint(x: pageRect.width - rightMargin, y: lineY))
    context.strokePath()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: headerFooterFont(ofSize: 9),
        .foregroundColor: headerFooterColor()
    ]
    let pageString = "— \(pageNumber) —"
    let attrString = NSAttributedString(string: pageString, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString as CFAttributedString)

    let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
    let centerX = (pageRect.width - lineWidth) / 2
    context.textPosition = CGPoint(x: centerX, y: textY)
    CTLineDraw(line, context)
}

// MARK: - Platform Helpers

#if canImport(UIKit)
private func headerFooterFont(ofSize size: CGFloat) -> UIFont {
    UIFont.systemFont(ofSize: size, weight: .regular)
}
private func headerFooterColor() -> UIColor {
    UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
}
private func separatorColor() -> UIColor {
    UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
}
#elseif canImport(AppKit)
private func headerFooterFont(ofSize size: CGFloat) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: .regular)
}
private func headerFooterColor() -> NSColor {
    NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
}
private func separatorColor() -> NSColor {
    NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
}
#endif

// MARK: - Errors

public enum PDFRenderError: LocalizedError {
    case contextCreationFailed
    case emptyContent

    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            return "Failed to create PDF rendering context."
        case .emptyContent:
            return "Cannot render PDF from empty content."
        }
    }
}
