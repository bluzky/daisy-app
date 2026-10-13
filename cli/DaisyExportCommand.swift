//
//  DaisyExportCommand.swift
//  daisy-export
//

import Foundation

@MainActor
enum DaisyExportCommand {
    private enum ExitCode: Int32 {
        case success = 0
        case usage = 64
        case input = 66
        case render = 69
        case output = 73
    }

    private struct Request {
        let input: URL
        let output: URL
        let themeID: String?
        let themeFile: URL?
        let mermaid: MermaidMode
    }

    private enum MermaidMode: String {
        case auto, off, strict
    }

    static func run(
        arguments: [String], executableURL: URL,
        writeStandardOutput: (String) -> Void = { print($0) },
        writeStandardError: (String) -> Void = { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    ) async -> Int32 {
        if arguments == ["--help"] || arguments == ["-h"] {
            writeStandardOutput(help)
            return ExitCode.success.rawValue
        }
        switch parse(arguments: arguments) {
        case .failure(let error):
            writeStandardError(error.message)
            return error.exitCode.rawValue
        case .success(let request):
            return await export(request, executableURL: executableURL,
                                writeStandardError: writeStandardError)
        }
    }

    private struct CommandError: Error {
        let exitCode: ExitCode
        let message: String
    }

    private static func parse(arguments: [String]) -> Result<Request, CommandError> {
        var input: String?
        var output: String?
        var format: String?
        var themeID: String?
        var themeFile: String?
        var mermaid = MermaidMode.auto
        var index = 0

        func value(for option: String) -> String? {
            guard index + 1 < arguments.count else { return nil }
            index += 1
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--format", "-f":
                guard let value = value(for: argument) else {
                    return .failure(usageError("Missing value for \(argument)."))
                }
                format = value
            case "--output", "-o":
                guard let value = value(for: argument) else {
                    return .failure(usageError("Missing value for \(argument)."))
                }
                output = value
            case "--theme":
                guard let value = value(for: argument) else {
                    return .failure(usageError("Missing value for --theme."))
                }
                themeID = value
            case "--theme-file":
                guard let value = value(for: argument) else {
                    return .failure(usageError("Missing value for --theme-file."))
                }
                themeFile = value
            case "--mermaid":
                guard let value = value(for: argument), let mode = MermaidMode(rawValue: value) else {
                    return .failure(usageError("--mermaid must be auto, off, or strict."))
                }
                mermaid = mode
            case "--help", "-h":
                return .failure(usageError("--help cannot be combined with export options."))
            default:
                if argument.hasPrefix("-") {
                    return .failure(usageError("Unknown option: \(argument)"))
                }
                guard input == nil else {
                    return .failure(usageError("Only one input file is supported."))
                }
                input = argument
            }
            index += 1
        }

        guard format?.lowercased() == "docx" else {
            return .failure(usageError("--format docx is required."))
        }
        guard let input else { return .failure(usageError("Input Markdown file is required.")) }
        guard let output else { return .failure(usageError("--output is required.")) }
        guard themeID == nil || themeFile == nil else {
            return .failure(usageError("Use either --theme or --theme-file, not both."))
        }
        return .success(Request(
            input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output),
            themeID: themeID, themeFile: themeFile.map(URL.init(fileURLWithPath:)), mermaid: mermaid))
    }

    private static func export(
        _ request: Request, executableURL: URL, writeStandardError: (String) -> Void
    ) async -> Int32 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.input.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let markdown = try? String(contentsOf: request.input, encoding: .utf8)
        else {
            writeStandardError("Cannot read input Markdown file: \(request.input.path)")
            return ExitCode.input.rawValue
        }

        let resourceDirectory = executableURL.deletingLastPathComponent()
            .appendingPathComponent(".daisy-resources", isDirectory: true)
        VendorResource.configure(directory: resourceDirectory)

        let theme: DocxTheme
        if let themeFile = request.themeFile {
            guard let data = try? Data(contentsOf: themeFile),
                  let decoded = try? JSONDecoder().decode(DocxTheme.self, from: data) else {
                writeStandardError("Cannot load DOCX theme: \(themeFile.path)")
                return ExitCode.input.rawValue
            }
            theme = decoded
        } else if let themeID = request.themeID {
            guard let selected = DocxThemeStore.themes(inDirectory: resourceDirectory)
                .first(where: { $0.id == themeID }) else {
                writeStandardError("Unknown DOCX theme: \(themeID)")
                return ExitCode.usage.rawValue
            }
            theme = selected
        } else {
            theme = DocxThemeStore.themes(inDirectory: resourceDirectory)
                .first(where: { $0.id == "github" }) ?? .github
        }

        let mermaidSources = DocxExporter.mermaidSources(in: markdown)
        let diagrams: [String: DocxImage]
        switch request.mermaid {
        case .off:
            diagrams = [:]
        case .auto, .strict:
            diagrams = await MermaidRasterizer.render(mermaidSources)
            if request.mermaid == .strict,
               diagrams.count != Set(mermaidSources).count {
                writeStandardError("Failed to render one or more Mermaid diagrams.")
                return ExitCode.render.rawValue
            }
        }

        do {
            try DocxExporter.write(markdown: markdown,
                                   assetBaseURL: request.input.deletingLastPathComponent(),
                                   theme: theme, mermaidDiagrams: diagrams, to: request.output)
            return ExitCode.success.rawValue
        } catch {
            writeStandardError("Cannot write DOCX file: \(error.localizedDescription)")
            return ExitCode.output.rawValue
        }
    }

    private static func usageError(_ message: String) -> CommandError {
        CommandError(exitCode: .usage, message: "\(message)\n\n\(help)")
    }

    private static let help = """
    Usage: daisy export INPUT --format docx --output OUTPUT.docx [options]

    Options:
      -f, --format docx             Export format (required; DOCX only)
      -o, --output PATH             Output DOCX path (required)
          --theme ID                Bundled theme: document, github, minimal, or serif
          --theme-file PATH         Custom DOCX theme JSON file
          --mermaid MODE            auto (default), off, or strict
      -h, --help                    Show this help
    """
}
