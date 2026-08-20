//
//  CalendarQuickAddParser.swift
//  boringNotch
//
//  F-50: natural-language calendar entry. Leans on `NSDataDetector`'s
//  `.date` type, which already understands "tomorrow 3pm", "next Tuesday",
//  "in 20 min" and similar phrasing — there's no custom date-language rules
//  layer here beyond stripping the matched substring back out of the title.
//  Falls back to "starts now, one hour" when no date phrase is found, rather
//  than refusing the whole entry.
//

import Foundation

struct ParsedEventDraft {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
}

enum CalendarQuickAddParser {
    static func parse(_ input: String, now: Date = Date()) -> ParsedEventDraft? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return ParsedEventDraft(title: trimmed, start: now, end: now.addingTimeInterval(3600), isAllDay: false)
        }

        let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = detector.matches(in: trimmed, range: fullRange).first, let date = match.date else {
            return ParsedEventDraft(title: trimmed, start: now, end: now.addingTimeInterval(3600), isAllDay: false)
        }

        var title = trimmed
        if let range = Range(match.range, in: trimmed) {
            title.removeSubrange(range)
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        while title.contains("  ") {
            title = title.replacingOccurrences(of: "  ", with: " ")
        }
        if title.isEmpty {
            title = trimmed
        }

        // `match.duration` is 0 for a bare date/time mention ("tomorrow
        // 3pm") and non-zero when the detector itself found a range ("2-3pm
        // tomorrow") — an explicit range beats the one-hour default.
        let duration = match.duration > 0 ? match.duration : 3600
        let end = date.addingTimeInterval(duration)

        return ParsedEventDraft(title: title, start: date, end: end, isAllDay: false)
    }
}
