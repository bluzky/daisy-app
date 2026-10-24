//
//  WorkspaceQueryParser.swift
//  daisy
//
//  Reads the body of a ```tasks or ```notes block into a `WorkspaceQuery`.
//  The syntax is a flat list of terms, the way tasks are written: `#tag`,
//  `key:value`, `key:<=value`, `a,b` for either value, a leading `-` for
//  not, and `OR` between groups that are each ANDed. There is no other
//  keyword, no parentheses and no separate syntax tree: each term becomes
//  one `WorkspacePredicate`. A term with a problem is left out, and the
//  rest still runs. No AppKit, so it links into `tests/swift-tests`.
//

import Foundation

nonisolated struct WorkspaceQueryParser {
    nonisolated enum Problem: Equatable, Sendable {
        /// A word that is no term; `text:` searches text.
        case bareWord(String)
        /// `key:` with nothing after it.
        case missingValue(String)
        /// A value for `due`, `scheduled` or a date comparison that is no date.
        case badDate(String)
        case badPriority(String)
        case badOperator(String)
        /// `-`, a comparison or commas where the term takes none.
        case unsupported(String)
        case badLimit(String)
        /// `is:` takes `open` or `done`.
        case badState(String)
        case badName(String)
        /// `OR` with no term on one side.
        case emptyGroup
        /// A frontmatter key no file uses, with the closest one that is used.
        case unknownKey(String, suggestion: String?)

        var message: String {
            switch self {
            case let .bareWord(word):
                String(format: NSLocalizedString("“%@” is not a term. Use text:%@ to search text.",
                                                 comment: "Query block problem"), word, word)
            case let .missingValue(term):
                String(format: NSLocalizedString("“%@” has no value.", comment: "Query block problem"), term)
            case let .badDate(term):
                String(format: NSLocalizedString("“%@” is not a date. Use today, 7d, -2w or YYYY-MM-DD.",
                                                 comment: "Query block problem"), term)
            case let .badPriority(term):
                String(format: NSLocalizedString("“%@”: priority is high, medium or low.",
                                                 comment: "Query block problem"), term)
            case let .badOperator(term):
                String(format: NSLocalizedString("“%@” has an unknown comparison. Use <, <=, > or >=.",
                                                 comment: "Query block problem"), term)
            case let .unsupported(term):
                String(format: NSLocalizedString("“%@” can’t be negated, compared or given several values.",
                                                 comment: "Query block problem"), term)
            case let .badLimit(term):
                String(format: NSLocalizedString("“%@”: limit takes a whole number.", comment: "Query block problem"),
                       term)
            case let .badState(term):
                String(format: NSLocalizedString("“%@”: use is:open or is:done.", comment: "Query block problem"),
                       term)
            case let .badName(term):
                String(format: NSLocalizedString("“%@” is not a tag, context or project.",
                                                 comment: "Query block problem"), term)
            case .emptyGroup:
                NSLocalizedString("OR needs a term on each side.", comment: "Query block problem")
            case let .unknownKey(key, suggestion?):
                String(format: NSLocalizedString("No file has “%@”. Did you mean “%@”?",
                                                 comment: "Query block problem"), key, suggestion)
            case let .unknownKey(key, nil):
                String(format: NSLocalizedString("No file has “%@”.", comment: "Query block problem"), key)
            }
        }
    }

    nonisolated struct Result: Equatable, Sendable {
        let query: WorkspaceQuery
        let problems: [Problem]
    }

    /// Frontmatter keys some file uses, normalized; nil checks none.
    var knownKeys: Set<String>?
    /// What `today` and day offsets count from.
    var today: JournalDay

    init(knownKeys: Set<String>? = nil, today: JournalDay = JournalDay(date: Date())) {
        self.knownKeys = knownKeys
        self.today = today
    }

    /// Keys that are not frontmatter attributes.
    private static let reserved: Set<String> = ["is", "due", "scheduled", "p", "in", "links", "text", "sort",
                                                "limit", "has"]

    func parse(_ text: String, source: WorkspaceQuery.Source) -> Result {
        var problems: [Problem] = []
        var sort: [WorkspaceSortKey] = []
        var limit: Int?
        var groups: [[WorkspacePredicate]] = [[]]
        /// `sort:` and `limit:` are options of the whole query, not terms.
        var groupHadTerms = [false]

        for word in Self.words(text) {
            if word.text == "OR", !word.quoted {
                groups.append([])
                groupHadTerms.append(false)
                continue
            }
            let last = groups.count - 1
            switch term(word.text, source: source, sort: &sort, limit: &limit) {
            case let .predicate(predicate):
                groups[last].append(predicate)
                groupHadTerms[last] = true
            case let .problem(problem):
                problems.append(problem)
                groupHadTerms[last] = true
            case .option:
                break
            }
        }

        var kept: [[WorkspacePredicate]] = []
        var hasTerms = false
        for (index, group) in groups.enumerated() {
            if !groupHadTerms[index] {
                if groups.count > 1 { problems.append(.emptyGroup) }
                continue
            }
            hasTerms = true
            // A group whose every term had a problem would match everything.
            if !group.isEmpty { kept.append(group) }
        }
        // A block with no terms lists everything; one whose terms all had
        // problems lists nothing.
        let filter: WorkspacePredicate = switch kept.count {
        case 0: hasTerms ? .or([]) : .and([])
        case 1: .and(kept[0])
        default: .or(kept.map { .and($0) })
        }
        return Result(query: WorkspaceQuery(source: source, filter: filter, sort: sort, limit: limit),
                      problems: problems)
    }

    // MARK: - Words

    /// Splits on whitespace; double quotes keep spaces and are dropped.
    static func words(_ text: String) -> [(text: String, quoted: Bool)] {
        var words: [(text: String, quoted: Bool)] = []
        var current = ""
        var quoted = false
        var inQuotes = false
        var hasWord = false
        for character in text {
            if character == "\"" {
                inQuotes.toggle()
                quoted = true
                hasWord = true
            } else if character.isWhitespace, !inQuotes {
                if hasWord { words.append((current, quoted)) }
                current = ""
                quoted = false
                hasWord = false
            } else {
                current.append(character)
                hasWord = true
            }
        }
        if hasWord { words.append((current, quoted)) }
        return words
    }

    // MARK: - Terms

    private enum Term {
        case predicate(WorkspacePredicate)
        case problem(Problem)
        /// `sort:` or `limit:`, which apply to the whole query.
        case option
    }

    private func term(_ word: String, source: WorkspaceQuery.Source, sort: inout [WorkspaceSortKey],
                      limit: inout Int?) -> Term {
        var body = Substring(word)
        let negated = body.count > 1 && body.hasPrefix("-")
        if negated { body = body.dropFirst() }

        if let marker = body.first, let kind = Self.kind(marker) {
            var names: [WorkspacePredicate] = []
            for name in body.dropFirst().split(separator: ",", omittingEmptySubsequences: false) {
                guard WorkspaceIndexStore.isName(String(name)) else { return .problem(.badName(word)) }
                names.append(.hasToken(kind, key: WorkspacePage.key(String(name)), includingDescendants: true))
            }
            return .predicate(Self.negate(Self.anyOf(names), negated))
        }

        guard let colon = body.firstIndex(of: ":") else { return .problem(.bareWord(word)) }
        let key = WorkspacePage.key(String(body[..<colon]))
        var value = Substring(body[body.index(after: colon)...])
        guard !key.isEmpty else { return .problem(.bareWord(word)) }
        guard !value.isEmpty else { return .problem(.missingValue(word)) }

        // The comparison, if any.
        var comparison = WorkspaceComparison.equal
        for (prefix, operation) in [("<=", WorkspaceComparison.lessOrEqual), (">=", .greaterOrEqual),
                                    ("<", .less), (">", .greater)] where value.hasPrefix(prefix) {
            comparison = operation
            value = value.dropFirst(prefix.count)
            break
        }
        if let first = value.first, "<>=!".contains(first) { return .problem(.badOperator(word)) }
        guard !value.isEmpty else { return .problem(.missingValue(word)) }
        let values = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard !values.contains(where: \.isEmpty) else { return .problem(.missingValue(word)) }
        let isPlain = comparison == .equal && values.count == 1

        switch key {
        case "sort":
            guard !negated, comparison == .equal else { return .problem(.unsupported(word)) }
            for value in values {
                let descending = value.hasPrefix("-")
                let name = WorkspacePage.key(descending ? String(value.dropFirst()) : value)
                guard !name.isEmpty else { return .problem(.missingValue(word)) }
                sort.append(WorkspaceSortKey(key: name == "p" ? "priority" : name, descending: descending))
            }
            return .option
        case "limit":
            guard !negated, isPlain else { return .problem(.unsupported(word)) }
            guard let number = Int(values[0]), number >= 0 else { return .problem(.badLimit(word)) }
            limit = number
            return .option
        case "is":
            guard comparison == .equal else { return .problem(.unsupported(word)) }
            var states: [WorkspacePredicate] = []
            for value in values {
                switch WorkspacePage.key(value) {
                case "open": states.append(.checked(false))
                case "done": states.append(.checked(true))
                default: return .problem(.badState(word))
                }
            }
            return .predicate(Self.negate(Self.anyOf(states), negated))
        case "due", "scheduled":
            var days: [WorkspacePredicate] = []
            for value in values {
                guard let day = date(value) else { return .problem(.badDate(word)) }
                days.append(.attribute(key, comparison, .date(day)))
            }
            return .predicate(Self.negate(Self.anyOf(days), negated))
        case "p":
            let levels = ["high", "medium", "low"]
            for value in values where !levels.contains(WorkspacePage.key(value)) {
                return .problem(.badPriority(word))
            }
            return .predicate(Self.negate(Self.anyOf(values.map {
                .attribute("priority", comparison, .text(WorkspacePage.key($0)))
            }), negated))
        case "in", "links", "text", "has":
            guard comparison == .equal else { return .problem(.unsupported(word)) }
            return .predicate(Self.negate(Self.anyOf(values.map { value in
                switch key {
                case "in": .inFolder(value)
                case "links": .linksTo(path: value)
                case "text": .textContains(value)
                default:
                    .hasAttribute(WorkspacePage.key(value) == "p" ? "priority" : WorkspacePage.key(value))
                }
            }), negated))
        default:
            if let knownKeys, !knownKeys.contains(key), !key.hasPrefix("file.") {
                return .problem(.unknownKey(String(body[..<colon]), suggestion: Self.closest(to: key, in: knownKeys)))
            }
            return .predicate(Self.negate(Self.anyOf(values.map { value in
                .attribute(key, comparison, date(value).map(WorkspaceAttributeValue.date) ?? .text(value))
            }), negated))
        }
    }

    /// `today`, a signed offset in days or weeks (`7d`, `-2w`), or `YYYY-MM-DD`.
    func date(_ value: String) -> JournalDay? {
        let lowered = value.lowercased()
        if lowered == "today" { return today }
        if let day = JournalDay(string: value) { return day }
        guard let unit = lowered.last, unit == "d" || unit == "w",
              let count = Int(lowered.dropLast()) else { return nil }
        return today.adding(days: unit == "w" ? count * 7 : count)
    }

    private static func kind(_ marker: Character) -> WorkspaceMetadataKind? {
        switch marker {
        case "#": .tag
        case "@": .context
        case "+": .project
        default: nil
        }
    }

    private static func anyOf(_ predicates: [WorkspacePredicate]) -> WorkspacePredicate {
        predicates.count == 1 ? predicates[0] : .or(predicates)
    }

    private static func negate(_ predicate: WorkspacePredicate, _ negated: Bool) -> WorkspacePredicate {
        negated ? .not(predicate) : predicate
    }

    /// The known key fewest edits away, if it is close enough to be a typo.
    static func closest(to key: String, in keys: Set<String>) -> String? {
        let candidates = keys.subtracting(reserved).sorted()
        guard let best = candidates.min(by: { distance(key, $0) < distance(key, $1) }) else { return nil }
        return distance(key, best) <= max(2, key.count / 3) ? best : nil
    }

    private static func distance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs), right = Array(rhs)
        var previous = Array(0...right.count)
        for (i, l) in left.enumerated() {
            var current = [i + 1]
            for (j, r) in right.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (l == r ? 0 : 1)))
            }
            previous = current
        }
        return previous[right.count]
    }
}
