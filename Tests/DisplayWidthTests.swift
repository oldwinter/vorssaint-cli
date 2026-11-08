// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import vorssaint

final class DisplayWidthTests: XCTestCase {
    func testASCII() {
        XCTAssertEqual("abc".displayWidth, 3)
        XCTAssertEqual("".displayWidth, 0)
    }

    func testCJKCountsTwoCells() {
        XCTAssertEqual("UU远程".displayWidth, 6)
        XCTAssertEqual("日本語".displayWidth, 6)
        XCTAssertEqual("한국어".displayWidth, 6)
    }

    func testMixedAndFullWidth() {
        XCTAssertEqual("名前 name".displayWidth, 9)
        XCTAssertEqual("ｆｕｌｌ".displayWidth, 8) // fullwidth latin
    }

    func testCombiningAndControlCountZero() {
        XCTAssertEqual("e\u{0301}".displayWidth, 1)      // e + combining acute
        XCTAssertEqual("​zero​width".displayWidth, 9) // zero-width spaces
    }

    func testANSIEscapesCountZero() {
        XCTAssertEqual("\u{1B}[36mfoo\u{1B}[0m".displayWidth, 3)
        XCTAssertEqual("\u{1B}[2mnot installed\u{1B}[0m".displayWidth, 13)
    }
}
