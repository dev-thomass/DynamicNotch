//
//  MediaKeyRouterTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

@MainActor
private final class FakeVolume: VolumeControl {
    var isSettable = true
    var isMuteSettable = true
    var level = 0.5
    var isMuted = false
    var onVolumeChange: (() -> Void)?
    var onDeviceChange: (() -> Void)?
    func setLevel(_ level: Double) { self.level = level }
    func setMuted(_ muted: Bool) { isMuted = muted }
}

@MainActor
private final class FakeBrightness: BrightnessControl {
    var isAvailable = true
    var level = 0.5
    func setLevel(_ level: Double) { self.level = level }
}

@MainActor
final class MediaKeyRouterTests: XCTestCase {
    private var volume: FakeVolume!
    private var brightness: FakeBrightness!
    private var hud: HUDController!
    private var feedbacks = 0
    private var router: MediaKeyRouter!

    override func setUp() async throws {
        volume = FakeVolume()
        brightness = FakeBrightness()
        hud = HUDController(scheduler: ManualScheduler())
        feedbacks = 0
        router = MediaKeyRouter(volume: volume, brightness: brightness, hud: hud, policy: MediaKeyPolicy()) { [unowned self] in
            feedbacks += 1
        }
        router.replaceEnabled = true
        router.trusted = true
        router.refreshPolicy()
    }

    private func press(_ key: MediaKey, fine: Bool = false) {
        router.apply(MediaKeyEvent(key: key, isDown: true, isRepeat: false, fine: fine))
    }

    func test_volumeUp_stepsAndShowsHUD_withFeedback() {
        press(.volumeUp)
        XCTAssertEqual(volume.level, 0.5625)
        XCTAssertEqual(hud.current, HUDState(kind: .volume, level: 0.5625, isMuted: false))
        XCTAssertEqual(feedbacks, 1)
    }

    func test_fineStep() {
        press(.volumeDown, fine: true)
        XCTAssertEqual(volume.level, 0.484375)
    }

    func test_volumeUp_unmutes() {
        volume.isMuted = true
        press(.volumeUp)
        XCTAssertFalse(volume.isMuted)
    }

    func test_mute_toggles() {
        press(.mute)
        XCTAssertTrue(volume.isMuted)
        XCTAssertEqual(hud.current?.isMuted, true)
        press(.mute)
        XCTAssertFalse(volume.isMuted)
    }

    func test_brightness_steps_withoutFeedback() {
        press(.brightnessDown)
        XCTAssertEqual(brightness.level, 0.4375)
        XCTAssertEqual(hud.current, HUDState(kind: .brightness, level: 0.4375, isMuted: false))
        XCTAssertEqual(feedbacks, 0)
    }

    func test_keyUp_doesNothing() {
        router.apply(MediaKeyEvent(key: .volumeUp, isDown: false, isRepeat: false, fine: false))
        XCTAssertEqual(volume.level, 0.5)
        XCTAssertNil(hud.current)
    }

    func test_policy() {
        XCTAssertTrue(router.policy.shouldConsume(.volumeUp))
        XCTAssertTrue(router.policy.shouldConsume(.brightnessUp))

        volume.isSettable = false
        router.refreshPolicy()
        XCTAssertFalse(router.policy.shouldConsume(.volumeUp))
        XCTAssertFalse(router.policy.shouldConsume(.volumeDown))
        // Le muet suit `isMuteSettable`, pas `isSettable`.
        XCTAssertTrue(router.policy.shouldConsume(.mute))
        XCTAssertTrue(router.policy.shouldConsume(.brightnessDown))

        brightness.isAvailable = false
        router.refreshPolicy()
        XCTAssertFalse(router.policy.shouldConsume(.brightnessDown))

        volume.isSettable = true
        router.trusted = false
        router.refreshPolicy()
        XCTAssertFalse(router.policy.shouldConsume(.volumeUp))

        router.trusted = true
        router.replaceEnabled = false
        router.refreshPolicy()
        XCTAssertFalse(router.policy.shouldConsume(.volumeUp))
    }

    func test_policy_releasesMute_whenMuteNotSettable() {
        volume.isMuteSettable = false
        router.refreshPolicy()
        XCTAssertFalse(router.policy.shouldConsume(.mute))
        XCTAssertTrue(router.policy.shouldConsume(.volumeUp))
        XCTAssertTrue(router.policy.shouldConsume(.volumeDown))
    }

    func test_policy_consumesMute_whenVolumeAndMuteSettable() {
        XCTAssertTrue(router.policy.shouldConsume(.mute))
    }

    func test_externalVolumeChange_showsHUD() {
        volume.level = 0.25
        router.volumeChangedExternally()
        XCTAssertEqual(hud.current, HUDState(kind: .volume, level: 0.25, isMuted: false))
    }
}
