import Foundation
import XCTest

final class DaisyLauncherTests: XCTestCase {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    func testExportDispatchesToSiblingExporterWithoutSubcommand() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let launcher = directory.appendingPathComponent("daisy")
        let exporter = directory.appendingPathComponent(".daisy-export")
        let received = directory.appendingPathComponent("arguments.txt")
        try FileManager.default.copyItem(
            at: Self.repositoryRoot.appendingPathComponent("Resources/bin/daisy"), to: launcher)
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$DAISY_EXPORT_ARGUMENTS\"\n".write(
            to: exporter, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exporter.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [launcher.path, "export", "report.md", "--format", "docx", "--output", "report.docx"]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["DAISY_EXPORT_ARGUMENTS": received.path], uniquingKeysWith: { _, new in new })
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: received, encoding: .utf8),
                       "report.md\n--format\ndocx\n--output\nreport.docx\n")
    }
}
