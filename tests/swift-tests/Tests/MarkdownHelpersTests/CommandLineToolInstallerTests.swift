import Foundation
import XCTest
@testable import MarkdownHelpers

final class CommandLineToolInstallerTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func runScript(_ script: String, in directory: URL, environment: [String: String]) throws -> Process {
        let url = directory.appendingPathComponent("install.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [url.path]
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        return process
    }

    func testInstallerCopiesPayloadAndReplacesStaleResources() throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source", isDirectory: true)
        let home = directory.appendingPathComponent("home", isDirectory: true)
        let installDirectory = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        let launcher = source.appendingPathComponent("daisy")
        let exporter = source.appendingPathComponent("daisy-export")
        let ordinaryResource = source.appendingPathComponent("theme.json")
        let newlineResource = source.appendingPathComponent("diagram\nrenderer.js")
        try "#!/bin/sh\n# Managed by Markdown Preview CLI\n".write(
            to: launcher, atomically: true, encoding: .utf8)
        try "exporter".write(to: exporter, atomically: true, encoding: .utf8)
        try "theme".write(to: ordinaryResource, atomically: true, encoding: .utf8)
        try "diagram".write(to: newlineResource, atomically: true, encoding: .utf8)

        let tools = CommandLineTools(
            launcher: launcher, exporter: exporter, resources: [ordinaryResource, newlineResource])
        let environment = ["HOME": home.path, "PATH": "\(installDirectory.path):/usr/bin:/bin"]
        let first = try runScript(CommandLineToolInstaller.script(tools: tools),
                                  in: directory, environment: environment)
        XCTAssertEqual(first.terminationStatus, 0)

        let installedResources = installDirectory.appendingPathComponent(".daisy-resources")
        XCTAssertEqual(try String(contentsOf: installDirectory.appendingPathComponent("daisy"), encoding: .utf8),
                       try String(contentsOf: launcher, encoding: .utf8))
        XCTAssertEqual(try String(contentsOf: installDirectory.appendingPathComponent(".daisy-export"), encoding: .utf8), "exporter")
        XCTAssertEqual(try String(contentsOf: installedResources.appendingPathComponent("theme.json"), encoding: .utf8), "theme")
        XCTAssertEqual(try String(contentsOf: installedResources.appendingPathComponent("diagram\nrenderer.js"), encoding: .utf8), "diagram")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(
            atPath: installDirectory.appendingPathComponent("mdp").path), "daisy")

        let stale = installedResources.appendingPathComponent("removed.json")
        try "stale".write(to: stale, atomically: true, encoding: .utf8)
        let second = try runScript(CommandLineToolInstaller.script(tools: tools),
                                   in: directory, environment: environment)
        XCTAssertEqual(second.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }
}
