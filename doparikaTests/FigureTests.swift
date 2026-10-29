import XCTest
import SwiftUI
@testable import doparika

@MainActor
final class FigureTests: XCTestCase {
    private func table(_ rows: [[String]], headers: [String] = ["a", "b"]) -> Figure {
        Figure(kind: .table, caption: nil, headers: headers, rows: rows, chartType: nil, xLabel: nil, yLabel: nil,
               xs: nil, ys: nil, categories: nil, values: nil, name: nil)
    }

    func testTableNeedsEvenRowsAndAtMostFiveColumns() {
        XCTAssertTrue(table([["1", "2"], ["3", "4"]]).isValid)
        XCTAssertFalse(table([["1", "2"], ["3"]]).isValid, "ragged rows")
        XCTAssertFalse(table([]).isValid, "no rows")
        XCTAssertFalse(table([["1", "2", "3", "4", "5", "6"]], headers: ["a", "b", "c", "d", "e", "f"]).isValid)
    }

    func testChartAndDiagramValidation() {
        let line = Figure(kind: .chart, caption: nil, headers: nil, rows: nil, chartType: .line, xLabel: "x", yLabel: "y",
                          xs: [0, 1], ys: [1, 2], categories: nil, values: nil, name: nil)
        XCTAssertTrue(line.isValid)
        let badLine = Figure(kind: .chart, caption: nil, headers: nil, rows: nil, chartType: .line, xLabel: nil, yLabel: nil,
                             xs: [0, 1, 2], ys: [1, 2], categories: nil, values: nil, name: nil)
        XCTAssertFalse(badLine.isValid, "x and y counts differ")
        let unknown = Figure(kind: .diagram, caption: nil, headers: nil, rows: nil, chartType: nil, xLabel: nil, yLabel: nil,
                             xs: nil, ys: nil, categories: nil, values: nil, name: "nope")
        XCTAssertFalse(unknown.isValid)
    }

    func testQuestionWithABrokenFigureIsInvalidButNoFigureIsFine() throws {
        func make(_ figure: String) -> String {
            """
            {"id":"99999","stage":"sea","grade":1,"subject":"physics","difficulty":1,"question":"q",
             "choices":[{"id":"A","text":"a"},{"id":"B","text":"b"}],"correctChoiceId":"A","explanation":"e"\(figure)}
            """
        }
        let broken = make(#","figure":{"kind":"table","headers":["a","b"],"rows":[["1"]]}"#)
        XCTAssertFalse(try JSONDecoder().decode(Question.self, from: Data(broken.utf8)).isValid)
        XCTAssertTrue(try JSONDecoder().decode(Question.self, from: Data(make("").utf8)).isValid, "no figure is fine")
    }

    func testEveryShippedFigureIsValidAndHasReadableAlternativeText() {
        let repo = QuestionRepository()
        let withFigure = repo.questions.filter { $0.figure != nil }
        XCTAssertGreaterThanOrEqual(withFigure.count, 20)
        for q in withFigure {
            let f = q.figure!
            XCTAssertTrue(f.isValid, q.id)
            XCTAssertGreaterThan(f.accessibilityDescription.count, 8, q.id)
            XCTAssertEqual(q.choices.count, 2)
        }
    }

    func testEveryFigureRendersToANonEmptyImage() throws {
        let repo = QuestionRepository()
        var kinds = Set<Figure.Kind>(), names = Set<String>()
        for q in repo.questions.compactMap({ $0.figure }) {
            kinds.insert(q.kind); if let n = q.name { names.insert(n) }
            let r = ImageRenderer(content: FigureView(figure: q).frame(width: 320).padding(8))
            r.scale = 1
            let img = try XCTUnwrap(r.uiImage, "figure did not render")
            XCTAssertGreaterThan(img.size.height, 60)
        }
        XCTAssertEqual(kinds, [.table, .chart, .diagram], "all three kinds are in use")
        XCTAssertEqual(names, Figure.diagramNames, "every built-in diagram is used by at least one question")
    }

    func testFigureQuestionsBelongToSeaOrSpaceAndIDsStayUnique() {
        let repo = QuestionRepository()
        XCTAssertEqual(Set(repo.questions.map(\.id)).count, repo.questions.count)
        XCTAssertTrue(repo.questions.filter { $0.figure != nil }.allSatisfy { $0.stage == .sea || $0.stage == .sky })
        XCTAssertGreaterThanOrEqual(repo.questions(for: .sea).count, 60)
        XCTAssertGreaterThanOrEqual(repo.questions(for: .sky).count, 130)
        XCTAssertGreaterThanOrEqual(repo.questions(for: .sky).filter { $0.figure != nil }.count, 20)
    }
}

@MainActor
final class FigureAccessibilityTests: XCTestCase {
    func testEveryBuiltInDiagramHasADetailedNarrationThatNamesItsLetters() {
        for name in Figure.diagramNames {
            let text = Figure.diagramNarration(name)
            XCTAssertGreaterThan(text.count, 60, "\(name) narration is too thin")
            XCTAssertTrue(text.contains("A") && text.contains("B"), "\(name) must name its letters")
            XCTAssertNotEqual(text, Figure.diagramNarration("unknown"), name)
        }
    }

    func testNarrationsStateWhereThingsAreWithoutGivingAwayTheAnswers() {
        let moon = Figure.diagramNarration("moon_phases")
        XCTAssertTrue(moon.contains("右") && moon.contains("反時計回り") && moon.contains("北極側"))
        XCTAssertFalse(moon.contains("満月") || moon.contains("新月"), "positions, not the answers")
        let orbit = Figure.diagramNarration("earth_orbit")
        XCTAssertTrue(orbit.contains("反時計回り") && orbit.contains("地軸"))
        XCTAssertFalse(orbit.contains("夏至") || orbit.contains("冬至"))
    }
}
