// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import vorssaint

final class URLCleanTests: XCTestCase {
    func clean(_ s: String) -> String { URLGroup.Clean.clean(s) }

    func testStripsUtm() {
        XCTAssertEqual(
            clean("https://example.com/?a=1&utm_source=x&utm_medium=y&b=2"),
            "https://example.com/?a=1&b=2")
    }
    func testStripsFbclid() {
        XCTAssertEqual(clean("https://x.com/p?fbclid=abc"), "https://x.com/p")
    }
    func testKeepsContentParams() {
        XCTAssertEqual(clean("https://example.com/search?q=test&v=2"), "https://example.com/search?q=test&v=2")
    }
    func testYoutubeSiRemovedKeepsV() {
        let out = clean("https://www.youtube.com/watch?v=abc&si=tracker")
        XCTAssertEqual(out, "https://www.youtube.com/watch?v=abc")
    }
    func testEmptyQueryRemoved() {
        XCTAssertEqual(clean("https://x.com/?utm_a=1"), "https://x.com/")
    }
    func testInvalidUrlPassesThrough() {
        XCTAssertEqual(clean("not a url"), "not a url")
    }
}
