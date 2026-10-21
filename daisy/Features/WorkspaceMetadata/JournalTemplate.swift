//
//  JournalTemplate.swift
//  daisy
//
//  What a new journal entry holds: the template chosen for it in Settings →
//  Extensions, from the reader's template file (Settings → General →
//  Templates); with none chosen, or the chosen one gone from the file, just
//  `# YYYY-MM-DD`.
//
//  Variables follow the slash menu's templates (`slashExpandTemplate` in
//  `scripts/editor-bundle/src/slash.js`), except that `{{date}}` and
//  `{{weekday}}` name the entry's day, which need not be today. `{{time}}`
//  is the moment the entry is created. `{{cursor}}` has no caret to place in
//  a new file and is dropped. `\{{` writes `{{`; an unknown name stays as
//  typed.
//
//  No AppKit, so it links into `tests/swift-tests`.
//

import Foundation

nonisolated enum JournalTemplate {
    /// The template called exactly `name`, or nil. Names in a file are
    /// unique: the parser numbers repeats ("Daily (2)").
    static func template(named name: String?, in templates: [MarkdownTemplate]) -> MarkdownTemplate? {
        guard let name else { return nil }
        return templates.first { $0.name == name }
    }

    /// The new entry's text, ending in one newline.
    static func contents(for day: JournalDay, template: MarkdownTemplate?, now: Date = Date(),
                         calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let template else { return "# \(day.string)\n" }
        let text = expand(template.body, day: day, now: now, calendar: calendar, locale: locale)
        let trimmed = text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        return trimmed + "\n"
    }

    static func expand(_ body: String, day: JournalDay, now: Date,
                       calendar: Calendar, locale: Locale) -> String {
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH:mm"
        let weekday = DateFormatter()
        weekday.calendar = calendar
        weekday.timeZone = calendar.timeZone
        weekday.locale = locale
        weekday.dateFormat = "EEEE"

        let values: [String: () -> String] = [
            "date": { day.string },
            "time": { time.string(from: now) },
            "datetime": { "\(day.string) \(time.string(from: now))" },
            "weekday": { weekday.string(from: day.date(in: calendar)) },
            "cursor": { "" },
        ]
        guard let pattern = try? NSRegularExpression(pattern: #"\\\{\{|\{\{\s*([A-Za-z]+)\s*\}\}"#) else {
            return body
        }
        let source = body as NSString
        var text = ""
        var last = 0
        for match in pattern.matches(in: body, range: NSRange(location: 0, length: source.length)) {
            text += source.substring(with: NSRange(location: last, length: match.range.location - last))
            last = match.range.location + match.range.length
            let nameRange = match.range(at: 1)
            if nameRange.location == NSNotFound {
                text += "{{"
            } else if let value = values[source.substring(with: nameRange).lowercased()] {
                text += value()
            } else {
                text += source.substring(with: match.range)
            }
        }
        text += source.substring(from: last)
        return text
    }
}
