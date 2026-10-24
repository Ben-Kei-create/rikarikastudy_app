import XCTest
@testable import doparika

final class MotionTests: XCTestCase {
    private func controller(questions: Int = 10, width: Double = 402, height: Double = 874) -> WorldMotionController {
        let m = WorldMotionController()
        m.configure(questionCount: questions)
        m.setViewport(height, width: width)
        m.jump(to: 0)
        return m
    }
    private func run(_ m: WorldMotionController, seconds: Double) {
        for _ in 0..<Int(seconds * 60) { m.step(1.0 / 60) }
    }

    func testReduceMotionJumpsWithoutSurgingOrShaking() {
        let m = controller()
        m.reduceMotion = true
        let target = m.restingDepth(afterCorrect: 3)
        m.boost(to: target)
        XCTAssertEqual(m.depth, target, accuracy: 0.001, "lands at once, no surge")
        m.startThinking(duration: 15)
        run(m, seconds: 5)
        XCTAssertEqual(m.depth, target, accuracy: 0.001, "no drift while thinking")
        XCTAssertEqual(m.shake, 0)
        m.fall(distance: 300)
        XCTAssertEqual(m.depth, max(target - 300, 0), accuracy: 0.001)
        XCTAssertEqual(m.velocity, 0)
    }

    func testReduceMotionSwitchedOnWhileThinkingStopsTheDrift() {
        let m = controller()
        m.jump(to: 2000)
        m.startThinking(duration: 15)
        run(m, seconds: 12)
        let held = m.depth
        XCTAssertGreaterThan(m.shake, 0, "precondition: it was drifting and shaking")
        m.reduceMotion = true
        run(m, seconds: 1)
        XCTAssertEqual(m.depth, held, accuracy: 0.001, "drift must stop immediately")
        XCTAssertEqual(m.shake, 0)
        XCTAssertEqual(m.velocity, 0)
    }

    func testReduceMotionSwitchedOnMidSurgeLandsOnTheTarget() {
        let m = controller()
        let target = m.restingDepth(afterCorrect: 4)
        m.boost(to: target)
        run(m, seconds: 0.4)
        XCTAssertNotEqual(m.depth, target, accuracy: 1, "precondition: still travelling")
        m.reduceMotion = true
        XCTAssertEqual(m.depth, target, accuracy: 0.001)
        run(m, seconds: 1)
        XCTAssertEqual(m.depth, target, accuracy: 0.001)
        XCTAssertEqual(m.shake, 0)
        XCTAssertEqual(m.velocity, 0)
    }

    func testStartsOnSurfaceAtTopOfFirstImage() {
        let m = controller()
        XCTAssertEqual(m.depth, 0)
        XCTAssertEqual(m.restingDepth(afterCorrect: 0), 0)
    }

    func testRestingDepthIsTopOfNextImageAndGoalIsBottomOfLast() {
        for n in [10, 20] {
            let m = controller(questions: n)
            for k in 1..<n { XCTAssertEqual(m.restingDepth(afterCorrect: k), Double(k) * m.sectionStep, accuracy: 0.001) }
            // Goal: the bottom edge of image N (index N-1) sits at the bottom of the screen.
            let bottomOfLast = Double(n - 1) * m.sectionStep + m.sectionHeight
            XCTAssertEqual(m.restingDepth(afterCorrect: n) + 874, bottomOfLast, accuracy: 0.001)
            XCTAssertEqual(m.goalDepth, m.restingDepth(afterCorrect: n))
        }
    }

    func testTwentyQuestionRunUsesTwentyImagesAndNothingBeyond() {
        let m = controller(questions: 20)
        XCTAssertLessThanOrEqual(m.goalDepth + 874, Double(WorldMotionController.imageCount - 1) * m.sectionStep + m.sectionHeight + 0.001)
    }

    /// Correct answer: dive straight down onto the next image's top - no overshoot, no trip back up.
    func testBoostDivesToNextImageTopMonotonically() {
        let m = controller()
        let target = m.restingDepth(afterCorrect: 1)
        m.boost(to: target)
        var last = m.depth
        for frame in 0..<400 {
            m.step(1.0 / 60)
            if frame >= 12 { XCTAssertGreaterThanOrEqual(m.depth, last - 0.001, "must not move up during a dive") }
            XCTAssertLessThanOrEqual(m.depth, target + 0.001, "must not overshoot")
            last = m.depth
        }
        XCTAssertEqual(m.depth, target, accuracy: 1)
    }

    func testBoostIsFastNotAGlide() {
        let m = controller()
        m.boost(to: m.restingDepth(afterCorrect: 1))
        run(m, seconds: 1.8)
        XCTAssertEqual(m.depth, m.restingDepth(afterCorrect: 1), accuracy: 1, "should have landed within ~1.8s")
    }

    func testFinalCorrectReachesBottomOfLastImage() {
        let m = controller()
        m.jump(to: m.restingDepth(afterCorrect: 9))
        m.boost(to: m.restingDepth(afterCorrect: 10))
        run(m, seconds: 3)
        XCTAssertEqual(m.depth, m.goalDepth, accuracy: 1)
    }

    /// Thinking drifts back toward the surface, slowly at first, and never leaves the artwork.
    func testThinkingDriftsTowardSurfaceBounded() {
        let m = controller()
        m.jump(to: m.restingDepth(afterCorrect: 4))
        let start = m.depth
        m.startThinking(duration: 15)
        run(m, seconds: 2)
        XCTAssertLessThan(start - m.depth, 40, "starts very slowly")
        run(m, seconds: 40)
        XCTAssertLessThan(m.depth, start)
        XCTAssertGreaterThanOrEqual(start - m.depth, 250)
        XCTAssertLessThanOrEqual(start - m.depth, WorldMotionController.maxThinkingDrift + 1)
    }

    /// First question: bob slowly up and down within the top of image 001 (not just vibrate in place).
    func testSurfaceBobsUpAndDownButNeverAboveTheTop() {
        let m = controller()
        m.startThinking(duration: 15)
        var lo = Double.infinity, hi = -Double.infinity, ups = 0, downs = 0, last = m.depth
        for _ in 0..<(60 * 14) {
            m.step(1.0 / 60)
            XCTAssertGreaterThanOrEqual(m.depth, -0.001)
            lo = min(lo, m.depth); hi = max(hi, m.depth)
            if m.depth > last + 1e-6 { downs += 1 } else if m.depth < last - 1e-6 { ups += 1 }
            last = m.depth
        }
        XCTAssertLessThan(lo, 1)
        XCTAssertGreaterThan(hi, WorldMotionController.surfaceBobRange * 0.9)
        XCTAssertLessThanOrEqual(hi, WorldMotionController.surfaceBobRange + 0.5)
        XCTAssertGreaterThan(ups, 100); XCTAssertGreaterThan(downs, 100)   // goes both ways
        XCTAssertLessThan(abs(m.depth - 0), 170)
    }

    func testWrongAnswerOnTheFirstQuestionReturnsToTheTop() {
        let m = controller()
        m.startThinking(duration: 15); run(m, seconds: 3)       // bobbed part-way down
        XCTAssertGreaterThan(m.depth, 20)
        m.fall(distance: WorldMotionController.wrongFall); run(m, seconds: 3)
        XCTAssertEqual(m.depth, 0, accuracy: 0.5)
    }

    func testBobContinuesOnTheNextQuestionStartedMidReturn() {
        let m = controller()
        m.startThinking(duration: 15); run(m, seconds: 3)
        m.fall(distance: WorldMotionController.wrongFall)       // heading back to the top
        run(m, seconds: 0.2)
        m.startThinking(duration: 15)                           // next question begins mid-return
        run(m, seconds: 5)
        XCTAssertGreaterThan(m.depth, 10)                       // bobbing again, not frozen at 0
    }

    func testWrongAnswerFallsTowardSurfaceAndStopsAtZero() {
        let m = controller()
        m.jump(to: m.restingDepth(afterCorrect: 3))
        let before = m.depth
        m.fall(distance: WorldMotionController.wrongFall); run(m, seconds: 4)
        XCTAssertEqual(before - m.depth, WorldMotionController.wrongFall, accuracy: 1)
        m.fall(distance: 100_000); run(m, seconds: 5)
        XCTAssertEqual(m.depth, 0, accuracy: 0.001)
    }

    func testNextQuestionDoesNotReturnToTheAnchor() {
        // After a wrong answer the next question simply continues from where the world is.
        let m = controller()
        m.jump(to: m.restingDepth(afterCorrect: 3))
        m.fall(distance: 380); run(m, seconds: 4)
        let after = m.depth
        m.startThinking(duration: 15); run(m, seconds: 1)
        XCTAssertLessThanOrEqual(m.depth, after)
        XCTAssertGreaterThan(m.depth, after - 20)
    }

    func testWidthChangeKeepsTheSamePlaceInTheWorld() {
        let m = controller(width: 375)
        m.jump(to: m.restingDepth(afterCorrect: 3))
        let before = m.depth / m.sectionStep
        m.setViewport(874, width: 430)
        XCTAssertEqual(m.depth / m.sectionStep, before, accuracy: 0.001)
        XCTAssertLessThanOrEqual(m.depth, m.maxDepth)
    }

    func testSettleRisesBackToSurfaceForARetry() {
        let m = controller()
        m.jump(to: m.goalDepth)
        m.settle(to: 0); run(m, seconds: 6)
        XCTAssertEqual(m.depth, 0, accuracy: 1)
    }
}
