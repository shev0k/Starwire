import XCTest
@testable import StarwireKit

/// Quick Launch, as Android's QuickLaunchManager and QuickLaunchView behave.
final class GameScreenQuickLaunchTests: XCTestCase {
    private let pcA = "11111111-aaaa-bbbb-cccc-000000000001"
    private let pcB = "22222222-aaaa-bbbb-cccc-000000000002"

    private var storage: MemorySettingsStorage!
    private var millis: Int64 = 1_700_000_000_000
    private var store: QuickLaunchStore!

    override func setUp() {
        super.setUp()
        storage = MemorySettingsStorage()
        millis = 1_700_000_000_000
        store = makeStore(storage)
    }

    private func makeStore(_ storage: SettingsStorage) -> QuickLaunchStore {
        QuickLaunchStore(storage: storage, nowMillis: { [unowned self] in
            self.millis += 5
            return self.millis
        })
    }

    @discardableResult
    private func add(_ app: String, id: Int, on pc: String? = nil, computer: String = "Desk") -> QuickLaunchEntry {
        store.add(computerUUID: pc ?? pcA, computerName: computer, appID: id, appName: app)!
    }

    // MARK: Adding

    func testAddingFollowsAndroidsKeyAndValueFormat() {
        let entry = add("Forza Horizon", id: 101)
        XCTAssertEqual(entry.key, "\(pcA):101:1700000000005")
        XCTAssertEqual(storage.object(forKey: entry.key) as? String, "Desk|Forza Horizon|Forza Horizon")
        XCTAssertEqual(storage.object(forKey: "_sort_order") as? String, entry.key)
        XCTAssertEqual(entry.customName, "Forza Horizon")
        XCTAssertEqual(entry.displayName, "Forza Horizon")
        XCTAssertEqual(entry.displayNameLong, "Forza Horizon")
    }

    func testAddedEntriesGoToTheEndInOrder() {
        let first = add("One", id: 1)
        let second = add("Two", id: 2, on: pcB, computer: "Laptop")
        let third = add("Three", id: 3)
        XCTAssertEqual(store.entries().map(\.key), [first.key, second.key, third.key])
        XCTAssertEqual(store.entries()[1].computerName, "Laptop")
        XCTAssertEqual(store.entries()[1].computerUUID, pcB)
        XCTAssertEqual(store.entries()[1].appID, 2)
    }

    func testTheSameGameCanBePinnedTwice() {
        let first = add("Game", id: 7)
        let second = add("Game", id: 7)
        XCTAssertNotEqual(first.key, second.key)
        XCTAssertEqual(store.entries().count, 2)
    }

    func testTwoAddsInTheSameMillisecondStayApart() {
        let frozen = QuickLaunchStore(storage: storage, nowMillis: { 1_700_000_000_000 })
        let first = frozen.add(computerUUID: pcA, computerName: "Desk", appID: 1, appName: "Game")!
        let second = frozen.add(computerUUID: pcA, computerName: "Desk", appID: 1, appName: "Game")!
        XCTAssertNotEqual(first.key, second.key)
        XCTAssertEqual(frozen.entries().count, 2)
    }

    func testThereIsNoLimit() {
        for index in 1...60 {
            add("Game \(index)", id: index)
        }
        XCTAssertEqual(store.entries().count, 60)
    }

    func testAGameWithoutANameIsNotAdded() {
        XCTAssertNil(store.add(computerUUID: pcA, computerName: "Desk", appID: 1, appName: ""))
        XCTAssertTrue(store.entries().isEmpty)
    }

    func testAPipeInANameIsKeptOutOfTheSavedText() {
        let entry = add("A|B", id: 3, computer: "My|PC")
        XCTAssertEqual(entry.originalAppName, "A/B")
        XCTAssertEqual(storage.object(forKey: entry.key) as? String, "My/PC|A/B|A/B")
        XCTAssertEqual(store.entries().first?.originalAppName, "A/B")
    }

    // MARK: Renaming

    func testRenameKeepsTheOriginalNameAndShowsItInTheLongName() {
        let entry = add("Forza Horizon", id: 101)
        XCTAssertTrue(store.rename(key: entry.key, to: "  Fast  "))
        let renamed = store.entry(forKey: entry.key)!
        XCTAssertEqual(renamed.displayName, "Fast")
        XCTAssertEqual(renamed.originalAppName, "Forza Horizon")
        XCTAssertEqual(renamed.displayNameLong, "Fast (Forza Horizon)")
        XCTAssertEqual(storage.object(forKey: entry.key) as? String, "Desk|Forza Horizon|Fast")
    }

    func testRenameToNothingOrOfAMissingEntryChangesNothing() {
        let entry = add("Game", id: 1)
        XCTAssertFalse(store.rename(key: entry.key, to: "   "))
        XCTAssertFalse(store.rename(key: "nope:1:2", to: "Name"))
        XCTAssertEqual(store.entry(forKey: entry.key)?.customName, "Game")
    }

    func testRenameBackToTheOriginalHidesTheLongName() {
        let entry = add("Game", id: 1)
        store.rename(key: entry.key, to: "Other")
        store.rename(key: entry.key, to: "Game")
        XCTAssertEqual(store.entry(forKey: entry.key)?.displayNameLong, "Game")
    }

    func testFindingAnEntryByNameIgnoresCase() {
        let entry = add("Forza Horizon", id: 101)
        store.rename(key: entry.key, to: "Fast")
        XCTAssertEqual(store.entry(named: "fAST")?.key, entry.key)
        XCTAssertNil(store.entry(named: "Forza Horizon"))
        XCTAssertNil(store.entry(named: ""))
        XCTAssertNil(store.entry(named: nil))
    }

    // MARK: Removing and moving

    func testRemoveTakesTheEntryOutOfTheListAndTheStorage() {
        let first = add("One", id: 1)
        let second = add("Two", id: 2)
        store.remove(key: first.key)
        XCTAssertEqual(store.entries().map(\.key), [second.key])
        XCTAssertNil(storage.object(forKey: first.key))
        XCTAssertEqual(storage.object(forKey: "_sort_order") as? String, second.key)
        store.remove(key: second.key)
        XCTAssertEqual(storage.object(forKey: "_sort_order") as? String, "")
        XCTAssertTrue(store.entries().isEmpty)
    }

    func testMovingSwapsWithTheNeighbour() {
        let a = add("A", id: 1), b = add("B", id: 2), c = add("C", id: 3)
        XCTAssertTrue(store.moveLeft(key: c.key))
        XCTAssertEqual(store.entries().map(\.key), [a.key, c.key, b.key])
        XCTAssertTrue(store.moveRight(key: a.key))
        XCTAssertEqual(store.entries().map(\.key), [c.key, a.key, b.key])
        XCTAssertEqual(storage.object(forKey: "_sort_order") as? String, [c.key, a.key, b.key].joined(separator: ","))
    }

    func testMovingPastTheEndsOrOfAnUnknownEntryFails() {
        let a = add("A", id: 1), b = add("B", id: 2)
        XCTAssertFalse(store.moveLeft(key: a.key))
        XCTAssertFalse(store.moveRight(key: b.key))
        XCTAssertFalse(store.moveLeft(key: "nope:1:2"))
        XCTAssertFalse(store.moveRight(key: "nope:1:2"))
        XCTAssertEqual(store.entries().map(\.key), [a.key, b.key])
    }

    // MARK: Android's saved data

    func testReadsDataAndroidWrote() {
        let key1 = "\(pcA):12:1690000000000", key2 = "\(pcB):5:1690000000001"
        let android = MemorySettingsStorage([
            key1: "Desk|Steam Big Picture|Steam",
            key2: "Laptop|Desktop|Desktop",
            "_sort_order": "\(key2),\(key1)",
        ])
        let read = makeStore(android).entries()
        XCTAssertEqual(read.map(\.key), [key2, key1])
        XCTAssertEqual(read[1], QuickLaunchEntry(key: key1, computerUUID: pcA, appID: 12, computerName: "Desk",
                                                 originalAppName: "Steam Big Picture", customName: "Steam"))
    }

    func testEntriesMissingFromTheOrderGoToTheEndAndTheOrderIsSaved() {
        let first = add("One", id: 1)
        let old1 = "\(pcA):9:1600000000002", old2 = "\(pcA):8:1600000000001"
        storage.set("Desk|Old Two|Old Two", forKey: old1)
        storage.set("Desk|Old One|Old One", forKey: old2)
        XCTAssertEqual(store.entries().map(\.key), [first.key, old2, old1])
        XCTAssertEqual(storage.object(forKey: "_sort_order") as? String, [first.key, old2, old1].joined(separator: ","))
    }

    func testBrokenEntriesAreSkipped() {
        let good = add("Good", id: 1)
        storage.set("Desk|Name", forKey: "\(pcA):2:1600000000000")      // two parts only
        storage.set("Desk|Name|Name", forKey: "\(pcA):x:1600000000000") // app ID isn't a number
        storage.set("Desk|Name|Name", forKey: "\(pcA):3")               // key has two parts
        storage.set("Desk|Name|", forKey: "\(pcA):4:1600000000000")     // empty last part, as Java's split
        storage.set(42, forKey: "\(pcA):5:1600000000000")               // not text
        XCTAssertEqual(store.entries().map(\.key), [good.key])
    }

    func testAKeyInTheOrderWithNoEntryIsIgnored() {
        let a = add("A", id: 1)
        storage.set("ghost:1:2,\(a.key)", forKey: "_sort_order")
        XCTAssertEqual(store.entries().map(\.key), [a.key])
    }

    func testAnEmptyNameOnTheMiddleOfTheTextIsKept() {
        storage.set("|Game|Game", forKey: "\(pcA):1:1")
        XCTAssertEqual(store.entries().first?.computerName, "")
    }

    func testTheJSONExportRoundTripsToAnotherStorage() {
        let a = add("Forza", id: 101)
        let b = add("Steam", id: 5, on: pcB, computer: "Laptop")
        let c = add("Desktop", id: 6)
        store.rename(key: b.key, to: "Big Picture")
        store.moveLeft(key: c.key)
        store.markStarted(key: a.key)

        let exported = store.exportValues()
        XCTAssertEqual(exported["_sort_order"], [a.key, c.key, b.key].joined(separator: ","))
        XCTAssertEqual(exported[b.key], "Laptop|Steam|Big Picture")
        XCTAssertNil(exported["_last_started_\(pcA)"])

        // through JSON text and back, like a settings export
        let data = try! JSONSerialization.data(withJSONObject: exported, options: [.sortedKeys])
        let decoded = try! JSONSerialization.jsonObject(with: data) as! [String: String]
        let other = makeStore(MemorySettingsStorage(["stale:1:1": "Old|Old|Old", "_sort_order": "stale:1:1"]))
        other.importValues(decoded)
        XCTAssertEqual(other.entries(), store.entries())
        XCTAssertNil(other.entry(forKey: "stale:1:1"))
    }

    func testImportSkipsEntriesAndroidCouldNotRead() {
        let key = "\(pcA):1:1"
        store.importValues([key: "Desk|Game|Game", "\(pcA):2:2": "bad", "_sort_order": "\(key),missing:1:1"])
        XCTAssertEqual(store.entries().map(\.key), [key])
    }

    func testListingStorageFindsOrphansButAPlainStorageOnlyFollowsTheOrder() {
        final class PlainStorage: SettingsStorage {
            var values: [String: Any] = [:]
            func object(forKey key: String) -> Any? { values[key] }
            func set(_ value: Any?, forKey key: String) { values[key] = value }
            func removeObject(forKey key: String) { values[key] = nil }
        }
        let plain = PlainStorage()
        plain.values["\(pcA):1:1"] = "Desk|Game|Game"
        XCTAssertTrue(makeStore(plain).entries().isEmpty)
        plain.values["_sort_order"] = "\(pcA):1:1"
        XCTAssertEqual(makeStore(plain).entries().count, 1)
    }

    // MARK: Running

    func testAnEntryRunsWhenItWasStartedAndItsGameIsRunning() {
        let entry = add("Game", id: 7)
        XCTAssertFalse(store.isRunning(key: entry.key))
        store.markStarted(key: entry.key)
        XCTAssertTrue(store.isRunning(key: entry.key))
        XCTAssertEqual(storage.object(forKey: "_last_started_\(pcA)") as? String, entry.key)
        XCTAssertFalse(store.isRunning(key: nil))
        XCTAssertFalse(store.isRunning(key: "nope:1:2"))
    }

    func testOnlyTheEntryStartedLastLightsUpWhenAGameIsPinnedTwice() {
        let first = add("Game", id: 7)
        let second = add("Game", id: 7)
        store.markStarted(key: second.key)
        XCTAssertFalse(store.isRunning(key: first.key))
        XCTAssertTrue(store.isRunning(key: second.key))
        XCTAssertEqual(store.runningKeys(runningAppIDs: [pcA: [7]]), [second.key])
    }

    func testAGameStartedElsewhereLightsTheFirstMatchingEntry() {
        let first = add("Game", id: 7)
        add("Game", id: 7)
        let other = add("Other", id: 8)
        store.updateRunningAppID(7, onPC: pcA, now: 0)
        XCTAssertTrue(store.isRunning(key: first.key))
        XCTAssertFalse(store.isRunning(key: other.key))
        XCTAssertEqual(storage.object(forKey: "_last_started_\(pcA)") as? String, first.key)
        store.updateRunningAppID(8, onPC: pcA, now: 1)
        XCTAssertTrue(store.isRunning(key: other.key))
        XCTAssertFalse(store.isRunning(key: first.key))
    }

    func testAGameThatIsNotPinnedClearsTheLastStarted() {
        let entry = add("Game", id: 7)
        store.markStarted(key: entry.key)
        store.updateRunningAppID(99, onPC: pcA, now: 0)
        XCTAssertFalse(store.isRunning(key: entry.key))
        XCTAssertNil(storage.object(forKey: "_last_started_\(pcA)"))
    }

    func testRunningStateIsPerPC() {
        let onA = add("Game", id: 7, on: pcA)
        let onB = add("Game", id: 7, on: pcB)
        store.updateRunningAppID(7, onPC: pcB, now: 0)
        XCTAssertFalse(store.isRunning(key: onA.key))
        XCTAssertTrue(store.isRunning(key: onB.key))
        XCTAssertEqual(store.runningKeys(runningAppIDs: [pcB: [7], pcA: [0]]), [onB.key])
        XCTAssertEqual(store.runningKeys(runningAppIDs: [:]), [])
    }

    func testRunningKeysWithSeveralGamesOnOnePC() {
        let one = add("One", id: 1)
        let two = add("Two", id: 2)
        add("Three", id: 3)
        XCTAssertEqual(store.runningKeys(runningAppIDs: [pcA: [1, 2]]), [one.key, two.key])
    }

    func testNothingRunningIsHeldForASecondBeforeItCounts() {
        let entry = add("Game", id: 7)
        store.markStarted(key: entry.key)
        var changes = 0
        store.onRunningStatusChanged = { changes += 1 }

        store.updateRunningAppID(0, onPC: pcA, now: 100)
        XCTAssertEqual(store.nextDeadline, 101)
        store.tick(now: 100.9)
        XCTAssertTrue(store.isRunning(key: entry.key))
        XCTAssertEqual(changes, 0)

        store.tick(now: 101)
        XCTAssertFalse(store.isRunning(key: entry.key))
        XCTAssertEqual(changes, 1)
        XCTAssertNil(store.nextDeadline)
        // the entry is kept as the last started, so it lights up again when its game returns
        XCTAssertEqual(storage.object(forKey: "_last_started_\(pcA)") as? String, entry.key)
        store.updateRunningAppID(7, onPC: pcA, now: 200)
        XCTAssertTrue(store.isRunning(key: entry.key))
    }

    func testAGameAppearingCancelsTheHeldStop() {
        let entry = add("Game", id: 7)
        store.markStarted(key: entry.key)
        store.updateRunningAppID(0, onPC: pcA, now: 100)
        store.updateRunningAppID(7, onPC: pcA, now: 100.5)
        XCTAssertNil(store.nextDeadline)
        store.tick(now: 200)
        XCTAssertTrue(store.isRunning(key: entry.key))
    }

    func testASecondStopReportRestartsTheWait() {
        let entry = add("Game", id: 7)
        store.markStarted(key: entry.key)
        store.updateRunningAppID(0, onPC: pcA, now: 100)
        store.updateRunningAppID(0, onPC: pcA, now: 100.8)
        store.tick(now: 101.5)
        XCTAssertTrue(store.isRunning(key: entry.key))
        store.tick(now: 101.8)
        XCTAssertFalse(store.isRunning(key: entry.key))
    }

    func testTheLastStartedEntrySurvivesARestart() {
        let entry = add("Game", id: 7)
        store.markStarted(key: entry.key)
        let afterRestart = makeStore(storage)
        afterRestart.updateRunningAppID(7, onPC: pcA, now: 0)
        XCTAssertTrue(afterRestart.isRunning(key: entry.key))
    }

    func testTheLabelsUseAndroidsResourceNames() {
        XCTAssertEqual(QuickLaunchText.sectionTitle.resourceName, "quick_launch_section_title")
        XCTAssertEqual(QuickLaunchText.quit.resourceName, "applist_menu_quit")
        XCTAssertEqual(QuickLaunchText.moveLeft.english, "Move Left")
        XCTAssertTrue(QuickLaunchText.renamed.isAndroidResource)
        XCTAssertFalse(QuickLaunchText.cannotMoveLeft.isAndroidResource)
        XCTAssertEqual(Set(QuickLaunchText.allCases.map(\.resourceName)).count, QuickLaunchText.allCases.count)
    }
}

/// The overrides bar and how it combines with the other settings.
final class GameScreenOverridesTests: XCTestCase {
    private var storage: MemorySettingsStorage!
    private var overrides: StreamOverridesStore!

    override func setUp() {
        super.setUp()
        storage = MemorySettingsStorage()
        overrides = StreamOverridesStore(storage: storage)
    }

    // MARK: Defaults and keys

    func testNothingIsOnOrSetByDefault() {
        XCTAssertEqual(overrides.overrides, StreamOverrides())
        XCTAssertFalse(overrides.isEnabled)
        XCTAssertEqual(overrides.bitrateKbps, 0)
        XCTAssertEqual(overrides.statsOverlay, .useDefault)
        XCTAssertEqual(overrides.codec, .useDefault)
        XCTAssertEqual(overrides.sliderPosition, 0)
        XCTAssertEqual(overrides.bitrateInputText, "")
    }

    func testAndroidsKeysAndTypes() {
        overrides.toggleEnabled()
        overrides.setSliderPosition(4)
        overrides.cycleStatsOverlay()
        overrides.cycleCodec()
        XCTAssertEqual(storage.object(forKey: "overrides_enabled") as? Bool, true)
        XCTAssertEqual(storage.object(forKey: "bitrate_override") as? Int, 0)
        XCTAssertEqual(storage.object(forKey: "perf_overlay_override") as? Int, 1)
        XCTAssertEqual(storage.object(forKey: "codec_override") as? Int, 1)
        XCTAssertEqual(storage.object(forKey: "bitrate_override_codec_0") as? Int, 40_000)
    }

    func testTheEnabledToggleFlips() {
        XCTAssertTrue(overrides.toggleEnabled())
        XCTAssertTrue(overrides.isEnabled)
        XCTAssertFalse(overrides.toggleEnabled())
        XCTAssertFalse(overrides.isEnabled)
    }

    // MARK: Bitrate slider and box

    func testTheSliderSavesTenMbpsSteps() {
        overrides.setSliderPosition(1)
        XCTAssertEqual(overrides.bitrateKbps, 10_000)
        overrides.setSliderPosition(50)
        XCTAssertEqual(overrides.bitrateKbps, 500_000)
        overrides.setSliderPosition(0)
        XCTAssertEqual(overrides.bitrateKbps, 0)
        overrides.setSliderPosition(99)
        XCTAssertEqual(overrides.bitrateKbps, 500_000)
        overrides.setSliderPosition(-3)
        XCTAssertEqual(overrides.bitrateKbps, 0)
    }

    func testKeysStepTheSliderAndStopAtTheEnds() {
        XCTAssertEqual(overrides.stepSlider(by: -1), 0)
        XCTAssertEqual(overrides.stepSlider(by: 1), 1)
        XCTAssertEqual(overrides.stepSlider(by: 1), 2)
        XCTAssertEqual(overrides.bitrateKbps, 20_000)
        XCTAssertEqual(overrides.stepSlider(by: -2), 0)
        XCTAssertEqual(overrides.bitrateKbps, 0)
        overrides.setSliderPosition(50)
        XCTAssertEqual(overrides.stepSlider(by: 1), 50)
        XCTAssertEqual(overrides.bitrateKbps, 500_000)
    }

    func testSteppingKeepsATypedBitrateWhenNothingMoves() {
        overrides.setBitrate(fromText: "800")
        XCTAssertEqual(overrides.sliderPosition, 50)
        XCTAssertEqual(overrides.stepSlider(by: 1), 50)
        XCTAssertEqual(overrides.bitrateKbps, 800_000)
    }

    func testTypedBitrateIsInMbps() {
        XCTAssertEqual(overrides.setBitrate(fromText: " 45 "), .saved(kbps: 45_000))
        XCTAssertEqual(overrides.bitrateKbps, 45_000)
        XCTAssertEqual(overrides.bitrateInputText, "45")
        XCTAssertEqual(overrides.sliderPosition, 4)
        XCTAssertEqual(overrides.setBitrate(fromText: "0"), .saved(kbps: 0))
        XCTAssertEqual(overrides.bitrateKbps, 0)
    }

    func testTypedBitrateBeyondTheSliderIsKeptUpToTheMaximum() {
        XCTAssertEqual(overrides.setBitrate(fromText: "2500"), .saved(kbps: 2_500_000))
        XCTAssertEqual(overrides.sliderPosition, 50)
        XCTAssertEqual(overrides.setBitrate(fromText: "2501"), .clamped(kbps: 2_500_000))
        XCTAssertEqual(overrides.bitrateKbps, 2_500_000)
        XCTAssertEqual(overrides.setBitrate(fromText: "2147483647"), .clamped(kbps: 2_500_000))
    }

    func testNegativeTypedBitrateBecomesTheDefault() {
        overrides.setBitrate(fromText: "30")
        XCTAssertEqual(overrides.setBitrate(fromText: "-5"), .saved(kbps: 0))
        XCTAssertEqual(overrides.bitrateKbps, 0)
    }

    func testAnEmptyOrBadBoxChangesNothing() {
        overrides.setBitrate(fromText: "30")
        XCTAssertEqual(overrides.setBitrate(fromText: "   "), .ignored)
        XCTAssertEqual(overrides.setBitrate(fromText: "abc"), .invalid)
        XCTAssertEqual(overrides.setBitrate(fromText: "12.5"), .invalid)
        XCTAssertEqual(overrides.setBitrate(fromText: "99999999999"), .invalid)
        XCTAssertEqual(overrides.bitrateKbps, 30_000)
    }

    func testTheSliderPositionOfABitrateBetweenSteps() {
        XCTAssertEqual(StreamOverridesStore.sliderPosition(forKbps: 25_000), 2)
        XCTAssertEqual(StreamOverridesStore.sliderPosition(forKbps: 9_999), 0)
        XCTAssertEqual(StreamOverridesStore.sliderPosition(forKbps: -1), 0)
        XCTAssertEqual(StreamOverridesStore.sliderPosition(forKbps: 900_000), 50)
    }

    // MARK: Stats overlay and codec

    func testTheStatsButtonCyclesDefaultOnOffDefault() {
        XCTAssertEqual(overrides.cycleStatsOverlay(), .forceOn)
        XCTAssertEqual(overrides.cycleStatsOverlay(), .forceOff)
        XCTAssertEqual(overrides.cycleStatsOverlay(), .useDefault)
        XCTAssertEqual(storage.object(forKey: "perf_overlay_override") as? Int, 0)
    }

    func testAnUnknownSavedStatsNumberShowsAsDefaultAndCyclesLikeJava() {
        storage.set(7, forKey: "perf_overlay_override")
        XCTAssertEqual(overrides.statsOverlay, .useDefault)
        XCTAssertEqual(overrides.overrides.statsOverlayLabel.text, .statsDefault)
        XCTAssertEqual(overrides.cycleStatsOverlay(), .forceOff) // (7 + 1) % 3 = 2
        storage.set(-5, forKey: "perf_overlay_override")
        overrides.cycleStatsOverlay()
        XCTAssertEqual(storage.object(forKey: "perf_overlay_override") as? Int, -1, "Java's remainder keeps the sign")
        XCTAssertEqual(overrides.statsOverlay, .useDefault)
    }

    func testTheCodecButtonCyclesDefaultHEVCAV1PyroWaveDefault() {
        XCTAssertEqual(overrides.cycleCodec(), .hevc)
        XCTAssertEqual(overrides.cycleCodec(), .av1)
        XCTAssertEqual(overrides.cycleCodec(), .pyroWave)
        XCTAssertEqual(overrides.cycleCodec(), .useDefault)
        XCTAssertEqual(overrides.codec, .useDefault)
    }

    func testEachCodecRemembersItsOwnBitrate() {
        overrides.setSliderPosition(3)              // 30 Mbps on Default
        overrides.cycleCodec()                      // HEVC
        XCTAssertEqual(overrides.bitrateKbps, 0, "a codec with nothing remembered starts at the default")
        overrides.setBitrate(fromText: "80")
        overrides.cycleCodec()                      // AV1
        XCTAssertEqual(overrides.bitrateKbps, 0)
        overrides.setSliderPosition(5)
        overrides.cycleCodec()                      // PyroWave
        overrides.cycleCodec()                      // back to Default
        XCTAssertEqual(overrides.bitrateKbps, 30_000)
        overrides.cycleCodec()                      // HEVC again
        XCTAssertEqual(overrides.bitrateKbps, 80_000)
        overrides.cycleCodec()                      // AV1 again
        XCTAssertEqual(overrides.bitrateKbps, 50_000)
        XCTAssertEqual(storage.object(forKey: "bitrate_override_codec_1") as? Int, 80_000)
        XCTAssertEqual(storage.object(forKey: "bitrate_override_codec_0") as? Int, 30_000)
    }

    func testAnUnknownSavedCodecShowsAsDefaultAndIsFiledUnderItsOwnNumber() {
        storage.set(9, forKey: "codec_override")
        storage.set(20_000, forKey: "bitrate_override")
        XCTAssertEqual(overrides.codec, .useDefault)
        XCTAssertEqual(overrides.cycleCodec(), .av1) // (9 + 1) % 4 = 2
        XCTAssertEqual(storage.object(forKey: "bitrate_override_codec_9") as? Int, 20_000)
        XCTAssertEqual(overrides.bitrateKbps, 0)
    }

    // MARK: Applying on top of a stream's settings

    private func base() -> [String: SettingValue] {
        [
            "seekbar_bitrate_kbps": .int(20_000),
            "checkbox_enable_perf_overlay": .bool(false),
            "video_format": .string("auto"),
            "list_fps": .string("60"),
        ]
    }

    func testOffMeansNoChange() {
        let off = StreamOverrides(enabled: false, bitrateKbps: 90_000, statsOverlayRaw: 1, codecRaw: 2)
        XCTAssertEqual(off.applied(to: base()), base())
    }

    func testOnWithDefaultsMeansNoChange() {
        XCTAssertEqual(StreamOverrides(enabled: true).applied(to: base()), base())
    }

    func testBitrateOverridesTheStreamsBitrate() {
        let result = StreamOverrides(enabled: true, bitrateKbps: 90_000).applied(to: base())
        XCTAssertEqual(result["seekbar_bitrate_kbps"], .int(90_000))
        XCTAssertEqual(result["list_fps"], .string("60"))
    }

    func testStatsOverlayForcedOnOrOff() {
        var on = base()
        on["checkbox_enable_perf_overlay"] = .bool(false)
        XCTAssertEqual(StreamOverrides(enabled: true, statsOverlayRaw: 1).applied(to: on)["checkbox_enable_perf_overlay"],
                       .bool(true))
        var off = base()
        off["checkbox_enable_perf_overlay"] = .bool(true)
        XCTAssertEqual(StreamOverrides(enabled: true, statsOverlayRaw: 2).applied(to: off)["checkbox_enable_perf_overlay"],
                       .bool(false))
        XCTAssertEqual(StreamOverrides(enabled: true, statsOverlayRaw: 0).applied(to: off)["checkbox_enable_perf_overlay"],
                       .bool(true))
        XCTAssertEqual(StreamOverrides(enabled: true, statsOverlayRaw: 5).applied(to: off)["checkbox_enable_perf_overlay"],
                       .bool(true))
    }

    func testCodecForcesTheVideoFormat() {
        let expected: [Int: String] = [1: "forceh265", 2: "forceav1", 3: "forcepyrowave"]
        for (raw, format) in expected {
            XCTAssertEqual(StreamOverrides(enabled: true, codecRaw: raw).applied(to: base())["video_format"],
                           .string(format), "codec \(raw)")
        }
        var neverHEVC = base()
        neverHEVC["video_format"] = .string("neverh265")
        XCTAssertEqual(StreamOverrides(enabled: true, codecRaw: 0).applied(to: neverHEVC)["video_format"],
                       .string("neverh265"))
        XCTAssertEqual(StreamOverrides(enabled: true, codecRaw: 4).applied(to: neverHEVC)["video_format"],
                       .string("neverh265"))
    }

    func testTheForcedFormatsAreValuesTheSettingAccepts() throws {
        for codec in CodecOverride.allCases {
            if let format = codec.videoFormat {
                XCTAssertTrue(SettingsCatalog.videoFormats.contains(format), format)
            }
        }
    }

    func testTheOverridesBeatEveryOtherSource() throws {
        let settings = SettingsStore(storage: MemorySettingsStorage([
            "seekbar_bitrate_kbps": 15_000, "video_format": "forceav1", "checkbox_enable_perf_overlay": false,
        ]))
        let game = GameSettings(fps: 120, bitrate: 40_000, enablePerfOverlay: "false", useGlobalSettings: false,
                                gameOptions: ["video_format": "forceh265"])
        let quick = GameSettings(bitrate: 60_000, enablePerfOverlay: "false", useGlobalSettings: false)
        let bar = StreamOverrides(enabled: true, bitrateKbps: 90_000, statsOverlayRaw: 1, codecRaw: 3)

        let values = settings.launchValues(game: game, quickLaunch: quick, overrides: bar)
        XCTAssertEqual(values["seekbar_bitrate_kbps"], .int(90_000))
        XCTAssertEqual(values["checkbox_enable_perf_overlay"], .bool(true))
        XCTAssertEqual(values["video_format"], .string("forcepyrowave"))
        XCTAssertEqual(values["list_fps"], .string("120"), "what the bar leaves alone comes from the game")
    }

    func testWithTheBarOffTheEntryBeatsTheGameBeatsTheGlobalSetting() throws {
        let settings = SettingsStore(storage: MemorySettingsStorage(["seekbar_bitrate_kbps": 15_000]))
        let game = GameSettings(fps: 120, bitrate: 40_000, useGlobalSettings: false)
        let quick = GameSettings(bitrate: 60_000, useGlobalSettings: false)

        XCTAssertEqual(settings.launchValues(game: game, quickLaunch: quick)["seekbar_bitrate_kbps"], .int(60_000))
        XCTAssertEqual(settings.launchValues(game: game)["seekbar_bitrate_kbps"], .int(40_000))
        XCTAssertEqual(settings.launchValues(game: game, quickLaunch: quick)["list_fps"], .string("120"))
        XCTAssertEqual(settings.launchValues(game: GameSettings())["seekbar_bitrate_kbps"], .int(15_000))
        XCTAssertEqual(settings.launchValues(game: game, quickLaunch: quick,
                                             overrides: StreamOverrides(enabled: false, bitrateKbps: 90_000))["seekbar_bitrate_kbps"],
                       .int(60_000))
    }

    func testTheBarAlsoAppliesWhenEverythingUsesTheGlobalSettings() {
        let settings = SettingsStore(storage: MemorySettingsStorage(["seekbar_bitrate_kbps": 15_000]))
        let bar = StreamOverrides(enabled: true, bitrateKbps: 90_000)
        XCTAssertEqual(settings.launchValues(game: GameSettings(), overrides: bar)["seekbar_bitrate_kbps"], .int(90_000))
        XCTAssertEqual(settings.launchValues(game: GameSettings(), quickLaunch: GameSettings(),
                                             overrides: bar)["seekbar_bitrate_kbps"], .int(90_000))
    }

    func testShortcutsAndResumedSessionsSkipTheBar() {
        let settings = SettingsStore(storage: MemorySettingsStorage(["seekbar_bitrate_kbps": 15_000]))
        let bar = StreamOverrides(enabled: true, bitrateKbps: 90_000, codecRaw: 2)
        let values = settings.launchValues(game: GameSettings(), overrides: bar, applyOverrides: false)
        XCTAssertEqual(values["seekbar_bitrate_kbps"], .int(15_000))
        XCTAssertEqual(values["video_format"], .string("auto"))
    }

    func testAnEntrySettingWinsEvenWhenTheEntryUsesGlobalSettingsButTheGameDoesNot() {
        // Android checks the entry's "use global settings" only when the game uses them too
        let settings = SettingsStore(storage: MemorySettingsStorage())
        let game = GameSettings(fps: 120, bitrate: 40_000, useGlobalSettings: false)
        let quick = GameSettings(bitrate: 60_000, useGlobalSettings: true)
        let values = settings.launchValues(game: game, quickLaunch: quick)
        XCTAssertEqual(values["seekbar_bitrate_kbps"], .int(60_000))
        XCTAssertEqual(values["list_fps"], .string("120"))
    }

    func testAnEntrySettingIsUsedEvenWhenTheGameUsesGlobalSettings() {
        let settings = SettingsStore(storage: MemorySettingsStorage(["seekbar_bitrate_kbps": 15_000]))
        let game = GameSettings(fps: 120, bitrate: 40_000, useGlobalSettings: true)
        let quick = GameSettings(bitrate: 60_000, useGlobalSettings: false)
        let values = settings.launchValues(game: game, quickLaunch: quick)
        XCTAssertEqual(values["seekbar_bitrate_kbps"], .int(60_000))
        XCTAssertEqual(values["list_fps"], .string("60"), "the game's own settings are off, so fps stays global")
    }

    func testTheEntrysGameOptionWinsOverTheGamesOption() {
        let settings = SettingsStore(storage: MemorySettingsStorage())
        let game = GameSettings(useGlobalSettings: false, gameOptions: ["video_format": "forceav1"])
        let quick = GameSettings(useGlobalSettings: false, gameOptions: ["video_format": "forceh265"])
        XCTAssertEqual(settings.launchValues(game: game, quickLaunch: quick)["video_format"], .string("forceh265"))
        XCTAssertEqual(settings.launchValues(game: game)["video_format"], .string("forceav1"))
    }

    // MARK: Saved data

    func testSavedOverridesReadBackIntoAStruct() {
        let android = MemorySettingsStorage([
            "overrides_enabled": true, "bitrate_override": 70_000, "perf_overlay_override": 2, "codec_override": 3,
        ])
        XCTAssertEqual(StreamOverridesStore(storage: android).overrides,
                       StreamOverrides(enabled: true, bitrateKbps: 70_000, statsOverlayRaw: 2, codecRaw: 3))
    }

    func testTheExportRoundTrips() {
        overrides.toggleEnabled()
        overrides.setSliderPosition(4)
        overrides.cycleCodec()
        overrides.setBitrate(fromText: "75")
        overrides.cycleStatsOverlay()
        let exported = overrides.exportValues()
        XCTAssertEqual(exported["overrides_enabled"], .bool(true))
        XCTAssertEqual(exported["bitrate_override"], .int(75_000))
        XCTAssertEqual(exported["bitrate_override_codec_0"], .int(40_000))
        XCTAssertEqual(exported["codec_override"], .int(1))

        let other = StreamOverridesStore(storage: MemorySettingsStorage())
        other.importValues(exported)
        XCTAssertEqual(other.overrides, overrides.overrides)
        XCTAssertEqual(other.exportValues(), exported)
        // and a switch to another codec brings the remembered bitrate back
        other.cycleCodec()
        other.cycleCodec()
        other.cycleCodec()
        XCTAssertEqual(other.bitrateKbps, 40_000)
    }

    func testImportSkipsWrongKeysAndTypes() {
        overrides.importValues(["bitrate_override": .string("5"), "overrides_enabled": .int(1), "other": .int(3),
                                "codec_override": .int(2)])
        XCTAssertEqual(overrides.overrides, StreamOverrides(codecRaw: 2))
        XCTAssertNil(storage.object(forKey: "other"))
    }

    // MARK: Labels

    func testLabelsUseAndroidsWordingAndResourceNames() {
        var state = StreamOverrides()
        XCTAssertEqual(state.bitrateLabel.english, "Bitrate: (Default)")
        XCTAssertEqual(state.bitrateLabel.resourceName, "bitrate_use_default")
        state.bitrateKbps = 800_000
        XCTAssertEqual(state.bitrateLabel.english, "Bitrate: 800 Mbps")
        XCTAssertEqual(state.bitrateLabel.number, 800)
        XCTAssertEqual(StreamOverrides.sliderLabel(position: 0).english, "Bitrate: (Default)")
        XCTAssertEqual(StreamOverrides.sliderLabel(position: 7).english, "Bitrate: 70 Mbps")

        state.statsOverlayRaw = 1
        XCTAssertEqual(state.statsOverlayLabel.english, "Stats overlay: Enabled")
        state.statsOverlayRaw = 2
        XCTAssertEqual(state.statsOverlayLabel.english, "Stats overlay: Disabled")
        state.statsOverlayRaw = 0
        XCTAssertEqual(state.statsOverlayLabel.english, "Stats overlay: Default")

        let codecs = [0: "Codec: Default", 1: "Codec: HEVC", 2: "Codec: AV1", 3: "Codec: PyroWave", 9: "Codec: Default"]
        for (raw, text) in codecs {
            state.codecRaw = raw
            XCTAssertEqual(state.codecLabel.english, text)
        }
        XCTAssertEqual(OverrideText.sectionTitle.resourceName, "overrides_section_title")
        XCTAssertEqual(OverrideText.toggleDescription.resourceName, "cg_a11y_overrides")
        XCTAssertTrue(OverrideText.bitrateDefault.isAndroidResource)
        XCTAssertFalse(OverrideText.statsEnabled.isAndroidResource)
        XCTAssertEqual(OverrideLabel(.bitrateDialogMessage, number: 2500).english,
                       "Enter bitrate in Mbps (0 for default, max 2500)")
        XCTAssertEqual(Set(OverrideText.allCases.map(\.resourceName)).count, OverrideText.allCases.count)
    }
}
