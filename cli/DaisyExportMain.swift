//
//  DaisyExportMain.swift
//  daisy-export
//

import AppKit
import Foundation

@main
struct DaisyExportMain {
    static func main() async {
        // WebKit needs an application instance when Mermaid rasterization is
        // requested. No window is created.
        _ = NSApplication.shared
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let exitCode = await DaisyExportCommand.run(
            arguments: Array(CommandLine.arguments.dropFirst()), executableURL: executableURL)
        Foundation.exit(exitCode)
    }
}
