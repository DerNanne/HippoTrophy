import SwiftUI
import UIKit

/// Turns a workout into a shareable PDF.
///
/// SwiftUI has no page break of its own, so pagination is done here: every block
/// is measured once at the printed width, blocks are packed into pages greedily,
/// and each page is drawn into the PDF context through `ImageRenderer`, which
/// keeps text as text rather than baking it into a bitmap.
@MainActor
enum WorkoutReportRenderer {
    /// Height a page has for blocks, once margins and the footer are taken out.
    /// The notice about skipped exercises only prints on the last page,
    /// but its height is held back on every one: getting that wrong would push
    /// the notice off the paper, and a page ending an inch early costs nothing.
    private static func availableHeight(skippedCount: Int) -> CGFloat {
        let notice: CGFloat = skippedCount > 0 ? noticeHeight : 0
        return ReportStyle.pageSize.height - 2 * ReportStyle.margin - footerHeight - notice
    }

    /// Footer rule, its 30pt gap and the one line of text below it.
    private static let footerHeight: CGFloat = 59
    /// One line of notice text and the gap under it.
    private static let noticeHeight: CGFloat = 24

    static func pdfData(for session: WorkoutSession, unit: WeightUnit = .current) -> Data {
        let data = WorkoutReportData(session: session, unit: unit)
        let pages = paginate(
            blocks: WorkoutReportBuilder.blocks(for: data),
            skippedCount: data.skippedCount
        )

        let bounds = CGRect(origin: .zero, size: ReportStyle.pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(data.title) — Workout Report",
            kCGPDFContextCreator as String: "HippoTrophy"
        ]

        return UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            for (index, blocks) in pages.enumerated() {
                let page = ReportPage(
                    blocks: blocks,
                    pageNumber: index + 1,
                    pageCount: pages.count,
                    skippedCount: data.skippedCount
                )
                let renderer = ImageRenderer(content: page)
                renderer.proposedSize = ProposedViewSize(ReportStyle.pageSize)
                renderer.render { _, draw in
                    context.beginPage()
                    // The PDF context comes flipped into UIKit's top-left origin,
                    // while `render` draws in Core Graphics' bottom-left one.
                    // Without undoing that, the page arrives upside down.
                    let cgContext = context.cgContext
                    cgContext.saveGState()
                    cgContext.translateBy(x: 0, y: ReportStyle.pageSize.height)
                    cgContext.scaleBy(x: 1, y: -1)
                    draw(cgContext)
                    cgContext.restoreGState()
                }
            }
        }
    }

    /// Writes the PDF to a temporary file, because the share sheet wants a URL if
    /// the result is to arrive with a readable filename rather than "Document".
    static func pdfFile(for session: WorkoutSession, unit: WeightUnit = .current) throws -> URL {
        let data = pdfData(for: session, unit: unit)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename(for: session))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The date is the day the workout was trained, in `timeZone` — a session
    /// at one in the morning belongs to that night, not to the day before,
    /// which is what UTC would have made of it.
    static func filename(for session: WorkoutSession, timeZone: TimeZone = .current) -> String {
        let name = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = session.date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().dateSeparator(.dash))
        let stem = name.isEmpty ? "Workout \(date)" : "\(name) \(date)"
        // Slashes and colons would be read as path separators; everything else a
        // user types is fine in a filename.
        let safe = stem.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        return "\(safe).pdf"
    }

    private static func paginate(
        blocks: [ReportBlock],
        skippedCount: Int
    ) -> [[ReportBlock]] {
        let pages = pack(heights: blocks.map(measure), limit: availableHeight(skippedCount: skippedCount))
        return pages.map { range in Array(blocks[range]) }
    }

    /// Greedy packing: a block moves to the next page rather than being split, so
    /// an exercise always stays together. A block taller than a whole page — a
    /// very long note, or an exercise with dozens of sets — gets a page of its own
    /// and is allowed to overflow, which is still better than losing it.
    ///
    /// Works on the measured heights alone, so the rule is testable without
    /// drawing anything. Always at least one page, empty when there is nothing.
    nonisolated static func pack(heights: [CGFloat], limit: CGFloat) -> [Range<Int>] {
        var pages: [Range<Int>] = []
        var start = 0
        var used: CGFloat = 0

        for (index, height) in heights.enumerated() {
            if index > start, used + height > limit {
                pages.append(start..<index)
                start = index
                used = 0
            }
            used += height
        }
        if start < heights.count {
            pages.append(start..<heights.count)
        }
        return pages.isEmpty ? [0..<0] : pages
    }

    private static func measure(_ block: ReportBlock) -> CGFloat {
        let controller = UIHostingController(
            rootView: block.content
                .frame(width: ReportStyle.contentWidth)
                .dynamicTypeSize(.large)
        )
        controller.view.backgroundColor = .clear
        // Without this the measurement carries the device's safe-area insets,
        // and every block reads a little taller than it prints — enough to push
        // a block onto the next page that would still have fitted on this one.
        controller.safeAreaRegions = []
        let size = controller.sizeThatFits(
            in: CGSize(width: ReportStyle.contentWidth, height: .greatestFiniteMagnitude)
        )
        return size.height
    }
}
