import XCTest
@testable import doparika

@MainActor
final class AdTests: XCTestCase {
    private func scheduler() -> AdScheduler {
        AdScheduler(defaults: UserDefaults(suiteName: "ads-test-\(UUID().uuidString)")!)
    }

    private final class FakeAds: AdManaging {
        var shows = 0
        var willShow = true
        func showRewarded(completion: @escaping (Bool) -> Void) { completion(false) }
        func showInterstitial(completion: @escaping (Bool) -> Void) { shows += 1; completion(willShow) }
    }

    private func envWithAds(_ ads: FakeAds) throws -> TestEnv {
        let env = try TestEnv()
        env.model.ads = ads
        env.model.adScheduler = scheduler()
        return env
    }

    private func finishPlays(_ n: Int, _ env: TestEnv) { for _ in 0..<n { env.model.finishSession() } }

    func testDueExactlyEveryTenPlays() {
        let s = scheduler()
        XCTAssertFalse(s.isDue(playsCompleted: 0))
        XCTAssertFalse(s.isDue(playsCompleted: 9))
        XCTAssertTrue(s.isDue(playsCompleted: 10))
        s.markShown(playsCompleted: 10)
        XCTAssertFalse(s.isDue(playsCompleted: 10))
        XCTAssertFalse(s.isDue(playsCompleted: 19))
        XCTAssertTrue(s.isDue(playsCompleted: 20))
    }

    func testNoAdBeforeTenPlaysAndNextRunsImmediately() throws {
        let ads = FakeAds(), env = try envWithAds(ads)
        finishPlays(9, env)
        var continued = 0
        env.model.presentAdIfDue { continued += 1 }
        XCTAssertEqual(ads.shows, 0)
        XCTAssertEqual(continued, 1)
    }

    func testTenthPlayShowsOneAdThenContinues() throws {
        let ads = FakeAds(), env = try envWithAds(ads)
        finishPlays(10, env)
        var continued = 0
        env.model.presentAdIfDue { continued += 1 }
        XCTAssertEqual(ads.shows, 1)
        XCTAssertEqual(continued, 1)
        env.model.presentAdIfDue { continued += 1 }           // same break again: no second ad
        XCTAssertEqual(ads.shows, 1)
        XCTAssertEqual(continued, 2)
        finishPlays(10, env)                                   // 20th play: the next one
        env.model.presentAdIfDue { continued += 1 }
        XCTAssertEqual(ads.shows, 2)
    }

    func testAdThatCouldNotBeShownStaysDueButNeverBlocksPlay() throws {
        let ads = FakeAds(), env = try envWithAds(ads)
        ads.willShow = false
        finishPlays(10, env)
        var continued = 0
        env.model.presentAdIfDue { continued += 1 }
        XCTAssertEqual(continued, 1, "no ad must never trap the player")
        ads.willShow = true
        env.model.presentAdIfDue { continued += 1 }
        XCTAssertEqual(ads.shows, 2, "still due, so it is tried again at the next break")
    }

    func testNoopManagerShowsNothingAndContinues() throws {
        let env = try TestEnv()
        env.model.adScheduler = scheduler()
        finishPlays(10, env)
        var continued = 0
        env.model.presentAdIfDue { continued += 1 }
        XCTAssertEqual(continued, 1)
    }

    func testResetStartsTheCountAgain() throws {
        let ads = FakeAds(), env = try envWithAds(ads)
        finishPlays(10, env)
        env.model.presentAdIfDue {}
        env.model.resetProgress()
        finishPlays(9, env)
        env.model.presentAdIfDue {}
        XCTAssertEqual(ads.shows, 1, "nine plays after a reset: not due yet")
        finishPlays(1, env)
        env.model.presentAdIfDue {}
        XCTAssertEqual(ads.shows, 2)
    }
}
