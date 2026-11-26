import Foundation
import XCTest

@testable import MarkdownHelpers

/// The reader's own themes as reading themes: listing, applying and
/// re-reading them (unified CSS themes, P2).
final class ThemeLibraryTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func write(_ fileName: String, name: String, appearance: String? = "light",
                     extends: String? = nil, _ css: String = "") throws {
    var header = "/* @theme\nname: \(name)\n"
    if let appearance { header += "appearance: \(appearance)\n" }
    if let extends { header += "extends: \(extends)\n" }
    try (header + "*/\n" + css).write(to: folder.appendingPathComponent(fileName),
                                      atomically: true, encoding: .utf8)
  }

  private var catalog: [String: Theme] { ThemeLibrary.catalog(userDirectory: folder) }

  func testAC_1_1_menuListsEveryBuiltInAndUserThemesByName() throws {
    try write("zeta.css", name: "Zeta", ":root { --link: #111111; }")
    try write("brand.css", name: "Acme Brand", ":root { --link: #222222; }")
    let slideThemes = ["Paper Warm", "Midnight Navy"]
    XCTAssertEqual(Array(ThemePreset.all.prefix(ThemePreset.builtIn.count)), ThemePreset.builtIn)
    XCTAssertEqual(ThemePreset.all.map(\.name).suffix(2), slideThemes[...])
    XCTAssertTrue(ThemePreset.builtIn.allSatisfy { !slideThemes.contains($0.name) }, "Not in the gallery")
    XCTAssertEqual(ThemeLibrary.userThemes(in: catalog).map(\.name), ["Acme Brand", "Zeta"])
    XCTAssertEqual(ThemeLibrary.applied(id: "brand", catalog: { self.catalog }).name, "Acme Brand")
    XCTAssertEqual(ThemeLibrary.applied(id: "Paper", catalog: { self.catalog }).preset?.name, "Paper")
    XCTAssertEqual(ThemeLibrary.applied(id: "Pitch", catalog: { self.catalog }).preset?.name, "Pitch",
                   "Built-ins outside the gallery can be the reading theme")
  }

  func testAC_1_6_missingAppliedFileResolvesToOriginal() throws {
    try write("brand.css", name: "Brand", ":root { --link: #222222; }")
    guard case .user = ThemeLibrary.applied(id: "brand", catalog: { self.catalog }) else {
      return XCTFail("brand is the reading theme while its file exists")
    }
    try FileManager.default.removeItem(at: folder.appendingPathComponent("brand.css"))
    XCTAssertEqual(ThemeLibrary.applied(id: "brand", catalog: { self.catalog }), .builtIn(.defaultPreset))
    XCTAssertEqual(ThemeLibrary.refresh(appliedID: "brand", catalog: catalog,
                                        current: ThemePreset.defaultPreset.restoredLook()),
                   .original)
  }

  func testAC_2_8_themeWithoutAppearanceIsNotListed() throws {
    try write("plain.css", name: "Plain", appearance: nil, ":root { --link: #222222; }")
    XCTAssertTrue(ThemeLibrary.userThemes(in: catalog).isEmpty)
    let settings = SlideDeckSettings(markdown: "---\nslides: true\ntheme: plain\n---\n")
    XCTAssertEqual(Theme.forDeck(settings, in: catalog).slideCSS, "", "The deck uses the reading theme")
  }

  func testAC_2_9_userEmberFileIsSkipped() throws {
    try write("ember.css", name: "My Ember", ":root { --link: #000000; }")
    XCTAssertEqual(catalog["ember"], BuiltInThemes.catalog["ember"])
    XCTAssertTrue(ThemeLibrary.userThemes(in: catalog).isEmpty)
    XCTAssertEqual(ThemeLibrary.applied(id: "Ember", catalog: { self.catalog }).preset?.name, "Ember")
  }

  func testAC_2_10_refreshReportsChangeOnlyWhenValuesDiffer() throws {
    try write("brand.css", name: "Brand", appearance: "system",
              ":root { --link: #222222; } @media (prefers-color-scheme: dark) { :root { --link: #333333; } }")
    let original = try XCTUnwrap(catalog["brand"])
    var current = ThemeLibrary.look(for: original)
    XCTAssertEqual(ThemeLibrary.refresh(appliedID: "brand", catalog: catalog, current: current), .none)

    current.appearance = .dark
    XCTAssertEqual(ThemeLibrary.refresh(appliedID: "brand", catalog: catalog, current: current), .none,
                   "A system theme leaves the appearance choice to the reader")

    try write("brand.css", name: "Brand", appearance: "system",
              ":root { --link: #444444; } @media (prefers-color-scheme: dark) { :root { --link: #333333; } }")
    let changed = try XCTUnwrap(catalog["brand"])
    XCTAssertEqual(ThemeLibrary.refresh(appliedID: "brand", catalog: catalog, current: current),
                   .reapply(changed))
    XCTAssertEqual(ThemeLibrary.look(for: changed).colors.hexValue(.linkColor, .light), "#444444")

    XCTAssertEqual(ThemeLibrary.refresh(appliedID: "Paper", catalog: catalog, current: current), .none,
                   "Built-in themes are never re-read")
    XCTAssertEqual(ThemeLibrary.refresh(appliedID: nil, catalog: catalog, current: current), .none)
  }

  /// Every window draws from the shared store: what applying a user theme
  /// writes there reads back unchanged, colors and fonts included.
  func testAC_1_2_userThemeValuesRoundTripThroughTheSharedStore() throws {
    try write("brand.css", name: "Brand", appearance: "system", """
    :root { --link: #222222; --bold: #333333; --widget-accent: #444444; --font-heading: Futura, sans-serif; }
    @media (prefers-color-scheme: dark) { :root { --link: #555555; } }
    """)
    let colors = ThemeLibrary.look(for: try XCTUnwrap(catalog["brand"])).colors
    let suite = "ThemeLibraryTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    ThemeColorsSetting.write(colors, to: defaults)
    let read = ThemeColorsSetting.read(from: defaults)
    XCTAssertEqual(read, colors)
    XCTAssertEqual(read.hexValue(.linkColor, .dark), "#555555")
    XCTAssertEqual(read.headingFont, "Futura, sans-serif")
  }

  func testAC_1_3_userThemeHasNoGalleryCard() throws {
    try write("brand.css", name: "Brand", ":root { --link: #222222; }")
    let applied = ThemeLibrary.applied(id: "brand", catalog: { self.catalog })
    XCTAssertNil(applied.preset, "no preset, so no card is selected")
    XCTAssertFalse(ThemePreset.builtIn.contains { $0.name == "Brand" }, "and it isn't in the gallery")
  }
}

