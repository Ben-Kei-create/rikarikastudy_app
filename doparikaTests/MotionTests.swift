import XCTest
@testable import doparika

final class MotionTests: XCTestCase {
    private func controller(width: Double = 402, height: Double = 874, fraction: Double) -> WorldMotionController {
        let m = WorldMotionController()
        m.setViewport(height, width: width)
        m.restProvider = { [unowned m] in m.permanentPosition(fraction: fraction) }
        m.jump(to: m.permanentPosition(fraction: fraction))
        return m
    }
    private func run(_ m: WorldMotionController, seconds: Double) {
        for _ in 0..<Int(seconds * 60) { m.step(1.0 / 60) }
    }

    func testTimeoutFallAtZeroXP() {
        let m = controller(fraction: 0)
        m.startThinking(duration: 15); run(m, seconds: 15)
        let before = m.position
        m.fall(distance: 440); run(m, seconds: 5)
        XCTAssertGreaterThanOrEqual(before - m.position, 430)
    }

    /// Codex P2: landscape -> portrait during thinking used to shrink the fall to ~62pt.
    func testTimeoutFallSurvivesRotationWhileThinking() {
        let m = controller(width: 874, height: 402, fraction: 0)
        m.startThinking(duration: 15); run(m, seconds: 5)
        m.setViewport(874, width: 402)
        run(m, seconds: 10)
        let before = m.position
        m.fall(distance: 440); run(m, seconds: 5)
        XCTAssertGreaterThanOrEqual(before - m.position, 430)
    }

    /// Codex P2: rotating right after the next question starts (still settling) lost headroom.
    func testRotationDuringSettleAfterNextQuestionKeepsFall() {
        let m = controller(width: 874, height: 402, fraction: 0)
        let rest = { m.permanentPosition(fraction: 0) }
        m.startThinking(duration: 15); run(m, seconds: 15)
        m.fall(distance: 440); run(m, seconds: 5)
        m.settle(to: rest()); m.startThinking(duration: 15)   // next question begins mid-return
        run(m, seconds: 0.1)
        m.setViewport(874, width: 402)
        run(m, seconds: 15)
        let before = m.position
        m.fall(distance: 440); run(m, seconds: 5)
        XCTAssertGreaterThanOrEqual(before - m.position, 430)
    }

    func testThinkingNeverDriftsBelowReserve() {
        let m = controller(fraction: 0)
        m.startThinking(duration: 15)
        for _ in 0..<(60 * 40) { m.step(1.0 / 60); XCTAssertGreaterThanOrEqual(m.position, WorldMotionController.fallReserve - 0.5) }
    }

    func testBoostAtMaxLevelStillTravels() {
        let m = controller(fraction: 1)
        let rest = m.position
        m.startThinking(duration: 15)
        var peak = rest
        m.boost(to: rest)
        for _ in 0..<300 { m.step(1.0 / 60); peak = max(peak, m.position) }
        XCTAssertGreaterThanOrEqual(peak - rest, 500)
        XCTAssertEqual(m.position, rest, accuracy: 1)
    }

    func testRotationMidBoostIsContinuousAndInRange() {
        let m = controller(fraction: 0.5)
        m.boost(to: m.permanentPosition(fraction: 0.55))
        run(m, seconds: 0.5)
        m.setViewport(874, width: 874)
        var last = m.position, maxStep = 0.0
        for _ in 0..<300 {
            m.step(1.0 / 60)
            maxStep = max(maxStep, abs(m.position - last)); last = m.position
            XCTAssertGreaterThanOrEqual(m.position, 0); XCTAssertLessThanOrEqual(m.position, m.maxPosition + 0.001)
        }
        XCTAssertLessThan(maxStep, 120)
    }

    func testPermanentPositionIsMonotonicAndInsideWorld() {
        let m = controller(fraction: 0)
        var last = -1.0
        for i in 0...30 {
            let p = m.permanentPosition(fraction: Double(i) / 30)
            XCTAssertGreaterThanOrEqual(p, last); XCTAssertLessThanOrEqual(p, m.maxPosition); last = p
        }
    }
}
