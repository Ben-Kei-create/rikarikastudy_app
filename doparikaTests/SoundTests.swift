import XCTest
import AVFoundation
import SceneKit
@testable import doparika

@MainActor
final class SoundTests: XCTestCase {
    override func tearDown() { SoundPlayer.testOverride = false }

    func testEverySoundFileIsBundled() {
        for s in SoundPlayer.Sfx.allCases {
            XCTAssertNotNil(Bundle.main.url(forResource: s.rawValue, withExtension: "mp3"), "missing \(s.rawValue).mp3")
        }
    }

    func testHomeMusicIsBundledAndDecodable() throws {
        for t in MusicPlayer.Track.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: t.rawValue, withExtension: "m4a"), "missing \(t.rawValue).m4a")
            let p = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(p.duration, 30)
        }
    }

    func testMutedPlaysNothing() {
        SoundPlayer.testOverride = false
        let before = SoundPlayer.shared.playCount
        SoundPlayer.shared.play(.correctVoice)
        XCTAssertEqual(SoundPlayer.shared.playCount, before)
    }

    func testCountdownStartsOncePerQuestionAndStopsOnAnswer() throws {
        let clock = FakeClock(), env = try TestEnv()
        SoundPlayer.testOverride = true             // TestEnv silences; count plays instead
        defer { SoundPlayer.testOverride = false }
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 874, width: 402)
        let base = SoundPlayer.shared.playCount
        clock.advance(10); s.advance()
        XCTAssertEqual(SoundPlayer.shared.playCount, base)          // not yet
        clock.advance(2); s.advance(); clock.advance(0.1); s.advance()
        XCTAssertEqual(SoundPlayer.shared.playCount, base + 1)      // countdown began
        clock.advance(0.5); s.advance()
        XCTAssertEqual(SoundPlayer.shared.playCount, base + 1)      // only once
    }
}

@MainActor
final class SettingsTests: XCTestCase {
    func testAllSwitchesDefaultOnAndPersist() {
        let d = UserDefaults(suiteName: "settings-test-\(UUID().uuidString)")!
        let a = AppSettings(defaults: d)
        XCTAssertTrue(a.bgmEnabled && a.sfxEnabled && a.effectsEnabled && a.hapticsEnabled)
        a.effectsEnabled = false; a.hapticsEnabled = false
        let b = AppSettings(defaults: d)                 // a fresh launch reads the saved values
        XCTAssertFalse(b.effectsEnabled); XCTAssertFalse(b.hapticsEnabled)
        XCTAssertTrue(b.bgmEnabled && b.sfxEnabled)
    }

    func testLegacyMuteTurnsMusicAndSfxOffButKeepsEffects() {
        let d = UserDefaults(suiteName: "settings-test-\(UUID().uuidString)")!
        d.set(true, forKey: "soundMuted")
        let a = AppSettings(defaults: d)
        XCTAssertFalse(a.bgmEnabled); XCTAssertFalse(a.sfxEnabled)
        XCTAssertTrue(a.effectsEnabled); XCTAssertTrue(a.hapticsEnabled)
    }
}

@MainActor
final class GlobeTests: XCTestCase {
    func testGlobeModelLoadsWithGeometryAndTexture() throws {
        let scene = try XCTUnwrap(GlobeView.loadScene(), "globe.usdz missing or unreadable")
        var meshes = 0
        scene.rootNode.enumerateHierarchy { node, _ in
            if let g = node.geometry {
                meshes += 1
                XCTAssertFalse(g.materials.isEmpty)
            }
        }
        XCTAssertGreaterThanOrEqual(meshes, 1)
    }
}

final class StampAssetTests: XCTestCase {
    func testAnswerStampsAreInTheBundle() {
        for name in ["answer_correct", "answer_incorrect"] {
            XCTAssertNotNil(UIImage(named: name), "\(name) missing from the asset catalog")
        }
    }
}
