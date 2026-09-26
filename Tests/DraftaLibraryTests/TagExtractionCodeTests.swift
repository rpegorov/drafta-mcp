import XCTest
@testable import DraftaLibrary

/// Tags must come from prose, not from code. Users hit the opposite: CSS colour
/// literals inside ``` blocks became tags (`#f7f7f7`, `#c0caf5`), and the tag
/// list in the app filled with hex values, each used once.
final class TagExtractionCodeTests: XCTestCase {

    // MARK: - Fenced blocks

    func testIgnoresHexColoursInFencedCodeBlock() {
        let content = """
        Тема: тёмная

        ```css
        .sidebar { background: #f7f7f7; color: #c0caf5; }
        ```

        #тема и #drafta/export
        """
        XCTAssertEqual(TagExtraction.tags(in: content), ["тема", "export"])
    }

    func testIgnoresTagsInTildeFence() {
        let content = """
        ~~~
        #скрытый
        ~~~
        #видимый
        """
        XCTAssertEqual(TagExtraction.tags(in: content), ["видимый"])
    }

    func testFenceInsideFenceKeepsOnlyTheOuterOne() {
        let content = """
        ````
        ```css
        #fff
        ```
        ````
        #после
        """
        XCTAssertEqual(TagExtraction.tags(in: content), ["после"])
    }

    func testUnterminatedFenceMasksTheRestOfTheNote() {
        let content = """
        До блока #до

        ```swift
        let color = "#abc"
        #внутри
        """
        XCTAssertEqual(TagExtraction.tags(in: content), ["до"])
    }

    func testFenceWithLanguageAndTrailingSpaces() {
        let content = """
        ``` bash
        echo "#нет"
        ```    
        #есть
        """
        XCTAssertEqual(TagExtraction.tags(in: content), ["есть"])
    }

    // MARK: - Inline spans

    func testIgnoresTagsInInlineCode() {
        let content = "Цвет `#ff0000` в теме, а тег #настоящий"
        XCTAssertEqual(TagExtraction.tags(in: content), ["настоящий"])
    }

    func testDoubleBacktickSpanContainingBacktickIsMasked() {
        let content = "``код с ` и #нет`` и #да"
        XCTAssertEqual(TagExtraction.tags(in: content), ["да"])
    }

    func testUnmatchedBacktickKeepsText() {
        let content = "Один ` бэктик без пары, но #тег здесь"
        XCTAssertEqual(TagExtraction.tags(in: content), ["тег"])
    }

    // MARK: - Regressions of the old behaviour

    func testTagOutsideCodeStillFound() {
        let content = "#работа и #личное/Питер"
        let result = TagExtraction.parse(content)
        XCTAssertEqual(result.simpleTags, ["работа"])
        XCTAssertEqual(result.pathTags.count, 1)
        XCTAssertEqual(result.pathTags.first?.leaf, "питер")
    }

    func testFrontmatterIsNotSpecial() {
        // Tags are derived from the body; a '#' in a URL or anchor stays out.
        let content = "[ссылка](https://example.com/#group/181) и #тег"
        XCTAssertEqual(TagExtraction.tags(in: content), ["тег"])
    }

    func testIndentedCodeBlocksAreStillScanned() {
        // Documented limitation: only fences and inline spans are masked.
        // The tag is written without hyphens on purpose — the pattern is
        // `[letter][letter/digit/_//]{1,}`, so a hyphenated word is not a tag
        // here and never was.
        let content = """
        обычный абзац

            #отступэтокодномыегонезнаем
        """
        XCTAssertEqual(TagExtraction.tags(in: content), ["отступэтокодномыегонезнаем"])
    }
}
