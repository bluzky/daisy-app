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
//  rest still runs. `$group:`, `$view:` and `$columns:` set how the
//  results show (`WorkspaceQueryDisplay`), never which rows match; the `$`
//  keeps them apart from filters and from frontmatter keys of those names. No AppKit, so it
//  links into `tests/swift-tests`.
//

import Foundation

/// How a block shows its results. Grouping and a table change only the
/// rendering; the query returns the same rows.
nonisolated struct WorkspaceQueryDisplay: Equatable, Sendable {
    enum View: String, Equatable, Sendable { case list, table }

    /// A table column, or the key rows are grouped by.
    nonisolated struct Field: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            /// A task's checkbox; columns of `tasks` blocks only.
            case done
            /// The task text or note title; columns only.
            case text
            /// The file's title, linking to it.
            case file
            case names(WorkspaceMetadataKind)
            /// `due`, `scheduled`, `priority`, a `file.` built-in or a
            /// frontmatter key.
            case attribute(String)
        }

        let kind: Kind
        /// As written in the block: a frontmatter key's header.
        let spelling: String

        /// What the query reads for it; nil for what the row already has.
        var queryField: WorkspaceQueryField? {
            switch kind {
            case .done, .text, .file: nil
            case let .names(kind): .names(kind)
            case let .attribute(key): .attribute(key)
            }
        }
    }

    var view: View = .list
    var group: Field?
    /// A table's columns, in order; the defaults when the block lists none.
    var columns: [Field] = []

    static func defaultColumns(_ source: WorkspaceQuery.Source) -> [Field] {
        switch source {
        case .tasks:
            [Field(kind: .done, spelling: "done"), Field(kind: .text, spelling: "text"),
             Field(kind: .attribute("due"), spelling: "due"), Field(kind: .attribute("priority"), spelling: "p"),
             Field(kind: .file, spelling: "file")]
        case .files:
            [Field(kind: .text, spelling: "text"), Field(kind: .attribute("file.folder"), spelling: "folder")]
        }
    }
}

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
        /// `$view:` takes `list` or `table`.
        case badView(String)
        /// A second `$group:` or `$view:`.
        case repeated(String)
        /// `$columns:` with `$view:list`.
        case columnsNeedTable(String)
        /// `done` in a `notes` block.
        case tasksOnly(String)
        /// `$group:` by `done` or `text`.
        case badGroup(String)
        /// A `$` term that is no display option.
        case unknownOption(String)

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
            case let .badView(term):
                String(format: NSLocalizedString("“%@”: use $view:list or $view:table.",
                                                 comment: "Query block problem"), term)
            case let .repeated(term):
                String(format: NSLocalizedString("“%@”: a block takes this option once.",
                                                 comment: "Query block problem"), term)
            case let .columnsNeedTable(term):
                String(format: NSLocalizedString("“%@”: columns show with $view:table.",
                                                 comment: "Query block problem"), term)
            case let .tasksOnly(term):
                String(format: NSLocalizedString("“%@” is for tasks blocks.", comment: "Query block problem"), term)
            case let .badGroup(term):
                String(format: NSLocalizedString("“%@”: done and text are columns, not groups.",
                                                 comment: "Query block problem"), term)
            case let .unknownOption(term):
                String(format: NSLocalizedString("“%@” is not a display option. Use $group:, $view: or $columns:.",
                                                 comment: "Query block problem"), term)
            }
        }
    }

    nonisolated struct Result: Equatable, Sendable {
        let query: WorkspaceQuery
        let problems: [Problem]
        var display = WorkspaceQueryDisplay()
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

    /// What applies to the whole block rather than filtering it.
    private struct Options {
        var sort: [WorkspaceSortKey] = []
        var limit: Int?
        var view: WorkspaceQueryDisplay.View?
        var group: WorkspaceQueryDisplay.Field?
        /// With the term that listed them, for a problem.
        var columns: (fields: [WorkspaceQueryDisplay.Field], term: String)?
    }

    func parse(_ text: String, source: WorkspaceQuery.Source) -> Result {
        var problems: [Problem] = []
        var options = Options()
        var groups: [[WorkspacePredicate]] = [[]]
        /// `sort:`, `limit:` and the display options apply to the whole
        /// query; they are not terms.
        var groupHadTerms = [false]

        for word in Self.words(text) {
            if word.text == "OR", !word.quoted {
                groups.append([])
                groupHadTerms.append(false)
                continue
            }
            let last = groups.count - 1
            switch term(word.text, source: source, options: &options) {
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
        var display = WorkspaceQueryDisplay()
        display.group = options.group
        if let columns = options.columns, options.view == .list {
            problems.append(.columnsNeedTable(columns.term))
        }
        display.view = options.view ?? (options.columns == nil ? .list : .table)
        if display.view == .table {
            let listed = options.columns?.fields ?? []
            display.columns = listed.isEmpty ? WorkspaceQueryDisplay.defaultColumns(source) : listed
        }
        return Result(query: WorkspaceQuery(source: source, filter: filter, sort: options.sort,
                                            limit: options.limit),
                      problems: problems, display: display)
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
        /// `sort:`, `limit:` or a display option, which apply to the whole
        /// query.
        case option
    }

    private func term(_ word: String, source: WorkspaceQuery.Source, options: inout Options) -> Term {
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

        let isOption = body.hasPrefix("$")
        guard let colon = body.firstIndex(of: ":") else {
            return .problem(isOption ? .unknownOption(word) : .bareWord(word))
        }
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
                options.sort.append(WorkspaceSortKey(key: name == "p" ? "priority" : name, descending: descending))
            }
            return .option
        case "limit":
            guard !negated, isPlain else { return .problem(.unsupported(word)) }
            guard let number = Int(values[0]), number >= 0 else { return .problem(.badLimit(word)) }
            options.limit = number
            return .option
        case "$view":
            guard !negated, isPlain else { return .problem(.unsupported(word)) }
            guard options.view == nil else { return .problem(.repeated(word)) }
            guard let view = WorkspaceQueryDisplay.View(rawValue: WorkspacePage.key(values[0])) else {
                return .problem(.badView(word))
            }
            options.view = view
            return .option
        case "$group":
            guard !negated, isPlain else { return .problem(.unsupported(word)) }
            guard options.group == nil else { return .problem(.repeated(word)) }
            switch field(values[0], source: source, term: word) {
            case let .success(field):
                if field.kind == .done || field.kind == .text { return .problem(.badGroup(word)) }
                options.group = field
                return .option
            case let .failure(problem):
                return .problem(problem.problem)
            }
        case "$columns":
            guard !negated, comparison == .equal else { return .problem(.unsupported(word)) }
            var fields = options.columns?.fields ?? []
            for value in values {
                switch field(value, source: source, term: word) {
                case let .success(field): fields.append(field)
                case let .failure(problem): return .problem(problem.problem)
                }
            }
            options.columns = (fields, word)
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
            if isOption { return .problem(.unknownOption(word)) }
            if let knownKeys, !knownKeys.contains(key), !Self.isBuiltIn(key) {
                return .problem(.unknownKey(String(body[..<colon]), suggestion: Self.closest(to: key, in: knownKeys)))
            }
            return .predicate(Self.negate(Self.anyOf(values.map { value in
                .attribute(key, comparison, date(value).map(WorkspaceAttributeValue.date) ?? .text(value))
            }), negated))
        }
    }

    private struct FieldProblem: Error { let problem: Problem }

    /// A `group:` or `columns:` key.
    private func field(_ name: String, source: WorkspaceQuery.Source,
                       term: String) -> Swift.Result<WorkspaceQueryDisplay.Field, FieldProblem> {
        let key = WorkspacePage.key(name)
        let kind: WorkspaceQueryDisplay.Field.Kind
        switch key {
        case "done":
            guard source == .tasks else { return .failure(FieldProblem(problem: .tasksOnly(term))) }
            kind = .done
        case "text": kind = .text
        case "file": kind = .file
        case "folder": kind = .attribute("file.folder")
        case "path": kind = .attribute("file.path")
        case "#", "tag", "tags": kind = .names(.tag)
        case "@", "context", "contexts": kind = .names(.context)
        case "+", "project", "projects": kind = .names(.project)
        case "due", "scheduled": kind = .attribute(key)
        case "p", "priority": kind = .attribute("priority")
        default:
            if let knownKeys, !knownKeys.contains(key), !Self.isBuiltIn(key) {
                return .failure(FieldProblem(problem: .unknownKey(name, suggestion: Self.closest(to: key,
                                                                                                in: knownKeys))))
            }
            kind = .attribute(key)
        }
        return .success(WorkspaceQueryDisplay.Field(kind: kind, spelling: name))
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

    /// Keys every file has, so never unknown: `title` and the `file.` ones.
    private static func isBuiltIn(_ key: String) -> Bool { key == "title" || key.hasPrefix("file.") }

    /// The known key fewest edits away, if it is close enough to be a typo.
    static func closest(to key: String, in keys: Set<String>) -> String? {
        let candidates = keys.union(["title"]).subtracting(reserved).sorted()
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
