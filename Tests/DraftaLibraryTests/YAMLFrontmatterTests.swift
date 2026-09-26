import XCTest
@testable import DraftaLibrary

final class YAMLFrontmatterTests: XCTestCase {
    func testParsesScalarsBoolsIntsAndArrays() {
        let src = """
        ---
        title: Hello
        count: 3
        pinned: true
        tags: [work, urgent]
        ---
        body text
        """
        let fields = YAMLFrontmatter.parse(src)
        XCTAssertEqual(fields?["title"]?.stringValue, "Hello")
        XCTAssertEqual(fields?["count"]?.intValue, 3)
        XCTAssertEqual(fields?["pinned"]?.boolValue, true)
        XCTAssertEqual(fields?["tags"]?.arrayValue, ["work", "urgent"])
    }

    func testReturnsNilWithoutFrontmatter() {
        XCTAssertNil(YAMLFrontmatter.parse("no frontmatter here"))
        XCTAssertNil(YAMLFrontmatter.parse("---\nno closing delimiter"))
    }

    func testStripFrontmatterReturnsBody() {
        let src = "---\ntitle: X\n---\nline 1\nline 2"
        XCTAssertEqual(YAMLFrontmatter.stripFrontmatter(src), "line 1\nline 2")
        XCTAssertEqual(YAMLFrontmatter.stripFrontmatter("plain"), "plain")
    }

    func testEncodePreservesOrderAndQuotesSpecials() {
        let yaml = YAMLFrontmatter.encode([
            ("title", .string("a: b")),   // contains ':' → must quote
            ("n", .int(5)),
            ("flag", .bool(false)),
            ("tags", .array(["x", "y"])),
        ])
        XCTAssertEqual(yaml, """
        ---
        title: "a: b"
        n: 5
        flag: false
        tags: [x, y]
        ---
        """)
    }

    func testRoundTripWithEscapedQuotesAndNewlines() {
        let original = "He said \"hi\"\nand left"
        let yaml = YAMLFrontmatter.encode([("note", .string(original))])
        let parsed = YAMLFrontmatter.parse(yaml + "\nbody")
        XCTAssertEqual(parsed?["note"]?.stringValue, original)
    }
}
