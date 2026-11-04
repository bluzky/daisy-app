import XCTest

@testable import MarkdownHelpers

@MainActor
final class PresentationSessionTests: XCTestCase {
  func testNavigationStaysInsideTheDeck() {
    let session = PresentationSession(slideCount: 3)
    session.perform(.previous)
    XCTAssertEqual(session.index, 0)
    session.perform(.next)
    session.perform(.next)
    session.perform(.next)
    XCTAssertEqual(session.index, 2)
    session.perform(.first)
    XCTAssertEqual(session.index, 0)
    session.perform(.last)
    XCTAssertEqual(session.index, 2)
  }

  func testTypedNumberJumpsOnReturn() {
    let session = PresentationSession(slideCount: 20)
    session.perform(.digit(1))
    session.perform(.digit(2))
    XCTAssertEqual(session.index, 0)
    session.perform(.confirm)
    XCTAssertEqual(session.index, 11)
    XCTAssertEqual(session.typedNumber, "")
    session.perform(.confirm)
    XCTAssertEqual(session.index, 12, "Return without a number advances")
    session.perform(.digit(9))
    session.perform(.digit(9))
    session.perform(.confirm)
    XCTAssertEqual(session.index, 19, "a number past the end goes to the last slide")
  }

  func testBlankTogglesAndNavigationClearsIt() {
    let session = PresentationSession(slideCount: 3)
    session.perform(.blankBlack)
    XCTAssertEqual(session.blank, .black)
    session.perform(.blankWhite)
    XCTAssertEqual(session.blank, .white)
    session.perform(.blankWhite)
    XCTAssertNil(session.blank)
    session.perform(.blankBlack)
    session.perform(.next)
    XCTAssertNil(session.blank)
    XCTAssertEqual(session.index, 1)
  }

  func testShrinkingDeckClampsTheCurrentSlide() {
    let session = PresentationSession(slideCount: 5, index: 4)
    var changes = 0
    session.onChange = { changes += 1 }
    session.updateSlideCount(3)
    XCTAssertEqual(session.index, 2)
    XCTAssertEqual(changes, 1)
    session.updateSlideCount(0)
    XCTAssertEqual(session.slideCount, 1)
    XCTAssertEqual(session.index, 0)
  }

  func testEndAsksTheOwner() {
    let session = PresentationSession(slideCount: 2)
    var ended = false
    session.onEnd = { ended = true }
    session.perform(.end)
    XCTAssertTrue(ended)
  }

  func testKeysMapToCommands() {
    XCTAssertEqual(PresentationCommand(keyCode: 124, characters: nil), .next)
    XCTAssertEqual(PresentationCommand(keyCode: 121, characters: nil), .next, "clicker Page Down")
    XCTAssertEqual(PresentationCommand(keyCode: 49, characters: " "), .next)
    XCTAssertEqual(PresentationCommand(keyCode: 116, characters: nil), .previous, "clicker Page Up")
    XCTAssertEqual(PresentationCommand(keyCode: 123, characters: nil), .previous)
    XCTAssertEqual(PresentationCommand(keyCode: 115, characters: nil), .first)
    XCTAssertEqual(PresentationCommand(keyCode: 119, characters: nil), .last)
    XCTAssertEqual(PresentationCommand(keyCode: 36, characters: "\r"), .confirm)
    XCTAssertEqual(PresentationCommand(keyCode: 53, characters: nil), .end)
    XCTAssertEqual(PresentationCommand(keyCode: 11, characters: "b"), .blankBlack)
    XCTAssertEqual(PresentationCommand(keyCode: 13, characters: "W"), .blankWhite)
    XCTAssertEqual(PresentationCommand(keyCode: 20, characters: "3"), .digit(3))
    XCTAssertNil(PresentationCommand(keyCode: 0, characters: "a"))
    XCTAssertNil(PresentationCommand(keyCode: 124, characters: nil, hasCommandOrControl: true))
  }
}
