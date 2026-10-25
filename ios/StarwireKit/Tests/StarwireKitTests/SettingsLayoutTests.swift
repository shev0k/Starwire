import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import StarwireKit

// MARK: - Reading the repo's Android files

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

private func read(_ path: String) throws -> String {
    try String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)
}

/// The capture groups of every match ("" for a group that didn't take part).
private func matches(_ pattern: String, in text: String) -> [[String]] {
    let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    let whole = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: whole).map { match in
        (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

private func withoutComments(_ xml: String) -> String {
    let regex = try! NSRegularExpression(pattern: "<!--.*?-->", options: [.dotMatchesLineSeparators])
    return regex.stringByReplacingMatches(in: xml, range: NSRange(xml.startIndex..., in: xml), withTemplate: "")
}

private struct StringResources {
    let android: Set<String>
    let ios: Set<String>
    let arrays: [String: [String]]

    static func load() throws -> StringResources {
        let strings = withoutComments(try read("app/src/main/res/values/strings.xml"))
        let arrays = withoutComments(try read("app/src/main/res/values/arrays.xml"))
        let ios = withoutComments(try read("ios/Strings/strings-ios.xml"))
        var arrayItems: [String: [String]] = [:]
        for group in matches("<string-array name=\"([^\"]+)\"[^>]*>(.*?)</string-array>", in: arrays) {
            arrayItems[group[0]] = matches("<item>(.*?)</item>", in: group[1]).map { $0[0] }
        }
        return StringResources(
            android: Set(matches("<string name=\"([^\"]+)\"", in: strings).map { $0[0] }),
            ios: Set(matches("<string name=\"([^\"]+)\"", in: ios).map { $0[0] }),
            arrays: arrayItems)
    }

    /// A string name, or `arrayname.N` for item N of a string array.
    func resolves(_ key: String) -> Bool {
        if let dot = key.lastIndex(of: "."), let index = Int(key[key.index(after: dot)...]) {
            guard let items = arrays[String(key[..<dot])] else { return false }
            return index < items.count
        }
        return android.contains(key) || ios.contains(key)
    }
}

// MARK: - Reading Android's preference screens

private struct XMLPref {
    let tag: String
    let attributes: [String: String]
    var key: String? { attributes["android:key"] }
    /// `@string/name` as name.
    func resource(_ attribute: String) -> String? {
        attributes[attribute].map { value in
            value.hasPrefix("@") ? String(value.split(separator: "/", maxSplits: 1).last ?? "") : value
        }
    }
}

private struct XMLCategory {
    let attributes: [String: String]
    var prefs: [XMLPref] = []
}

private final class PreferenceTreeReader: NSObject, XMLParserDelegate {
    var top: [XMLPref] = []
    var categories: [XMLCategory] = []
    private var inCategory = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "PreferenceScreen":
            break
        case "PreferenceCategory":
            categories.append(XMLCategory(attributes: attributes))
            inCategory = true
        default:
            let pref = XMLPref(tag: elementName, attributes: attributes)
            if inCategory {
                categories[categories.count - 1].prefs.append(pref)
            } else {
                top.append(pref)
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "PreferenceCategory" { inCategory = false }
    }

    static func read(_ path: String) throws -> PreferenceTreeReader {
        let reader = PreferenceTreeReader()
        let parser = XMLParser(data: try Data(contentsOf: repo.appendingPathComponent(path)))
        parser.delegate = reader
        XCTAssertTrue(parser.parse(), "\(path) didn't parse")
        return reader
    }
}

private final class NameCollector: NSObject, XMLParserDelegate {
    var names: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if elementName == "string", let name = attributes["name"] { names.append(name) }
    }
}

// MARK: - Layout

final class SettingsLayoutTests: XCTestCase {
    /// Rows Android shows for a button or a link have no catalog entry: they save nothing.
    private let rowsThatSaveNothing: Set<String> = [
        "microphone_host_info", "vban_setup_info", "mic_pairing", "overlay_custom_commands", "import_shortcuts_file",
        "clear_imported_shortcuts", "reset_osc_layout", "text_custom_vulkan_driver_path", "remove_custom_vulkan_driver",
        "about_version", "about_github", "about_issues", "about_source", "about_credits", "about_licences",
    ]

    /// Android sets these summaries in code, so the XML has none.
    private let summariesSetInCode: Set<String> = ["about_version", "about_source"]

    func testSectionsAreAndroidsPillsInOrder() throws {
        XCTAssertEqual(SettingsLayout.sections.map(\.id),
                       ["stream", "sound", "controllers", "menu", "touch", "onscreen", "pc", "app", "advanced", "about"])
        XCTAssertEqual(SettingsLayout.sections.map(\.titleKey), [
            "cg_section_stream", "cg_section_sound", "cg_section_controllers", "cg_section_menu", "cg_section_touch",
            "cg_section_onscreen", "cg_section_pc", "cg_section_app", "cg_section_advanced", "category_about",
        ])

        // Each Android category is the first group of one section, named the way CoverGlowSettings renames it
        let java = try read("app/src/main/java/com/limelight/ui/CoverGlowSettings.java")
        var friendly: [String: String] = [:]
        for pair in matches("\\{R\\.string\\.(\\w+), R\\.string\\.(cg_section_\\w+)\\}", in: java) {
            friendly[pair[0]] = pair[1]
        }
        XCTAssertEqual(friendly.count, 9)

        let tree = try PreferenceTreeReader.read("app/src/main/res/xml/preferences.xml")
        XCTAssertEqual(tree.categories.count, SettingsLayout.sections.count)
        for (category, section) in zip(tree.categories, SettingsLayout.sections) {
            let title = try XCTUnwrap(XMLPref(tag: "", attributes: category.attributes).resource("android:title"))
            XCTAssertEqual(section.titleKey, friendly[title] ?? title, section.id)
            XCTAssertEqual(section.groups[0].id, category.attributes["android:key"] ?? title, section.id)
            XCTAssertNil(section.groups[0].titleKey, "Android's group takes the section's title")
            for group in section.groups.dropFirst() {
                XCTAssertTrue(group.id.hasPrefix("ios_"), group.id)
                XCTAssertNotNil(group.titleKey, group.id)
            }
        }
    }

    func testEveryCatalogKeyIsInTheLayoutOnce() {
        var counts: [String: Int] = [:]
        for item in SettingsLayout.items { counts[item.id, default: 0] += 1 }

        for definition in SettingsCatalog.all {
            if let reason = SettingsLayout.settingsWithoutRow[definition.key] {
                XCTAssertNil(counts[definition.key], "\(definition.key) is listed as having no row (\(reason))")
                XCTAssertEqual(definition.availability, .supported, definition.key)
                continue
            }
            XCTAssertEqual(counts[definition.key], 1, "\(definition.key) should have one row")
            guard let item = SettingsLayout.item(definition.key) else { continue }
            switch definition.availability {
            case .supported, .iosOnly:
                XCTAssertEqual(item.presence, .shown, definition.key)
            case .notPossible, .hostLacks:
                XCTAssertEqual(item.presence, .hidden(definition.availability), definition.key)
            }
        }
        // A reason is only given for a key that exists
        for key in SettingsLayout.settingsWithoutRow.keys {
            XCTAssertNotNil(SettingsCatalog.definition(key), key)
        }
    }

    func testRowsThatAreNotInTheCatalogSaveNothing() {
        XCTAssertEqual(Set(SettingsLayout.items.map(\.id)).count, SettingsLayout.items.count, "ids repeat")
        for item in SettingsLayout.items where SettingsCatalog.definition(item.id) == nil {
            XCTAssertTrue(rowsThatSaveNothing.contains(item.id), "\(item.id) has no catalog entry")
            switch item.control {
            case .action, .link: break
            default: XCTFail("\(item.id) saves nothing, so it should be an action or a link")
            }
        }
        for id in rowsThatSaveNothing {
            XCTAssertNotNil(SettingsLayout.item(id), id)
            XCTAssertNil(SettingsCatalog.definition(id), id)
        }
    }

    func testIOSOnlySettingsSitInGroupsOfTheirOwn() {
        for section in SettingsLayout.sections {
            for group in section.groups {
                for item in group.items {
                    let iosOnly = SettingsCatalog.definition(item.id)?.availability == .iosOnly
                    XCTAssertEqual(group.id.hasPrefix("ios_"), iosOnly, "\(item.id) in \(group.id)")
                }
            }
        }
    }

    func testAndroidRowsMatchPreferencesXMLInOrder() throws {
        let tree = try PreferenceTreeReader.read("app/src/main/res/xml/preferences.xml")
        XCTAssertTrue(tree.top.isEmpty)
        let resources = try StringResources.load()

        for (category, section) in zip(tree.categories, SettingsLayout.sections) {
            let group = section.groups[0]
            // The layout has one row the XML gives no key (the reset button)
            XCTAssertEqual(group.items.map(\.id).filter { $0 != "reset_osc_layout" },
                           category.prefs.compactMap(\.key), group.id)
            for pref in category.prefs {
                guard let key = pref.key else { continue }
                guard let item = group.items.first(where: { $0.id == key }) else { continue }
                checkRow(item, against: pref, resources: resources)
            }
        }
        // The reset button's dialog
        let reset = try XCTUnwrap(SettingsLayout.item("reset_osc_layout"))
        let osc = try XCTUnwrap(tree.categories.first { $0.attributes["android:key"] == "category_onscreen_controls" })
        let resetPref = try XCTUnwrap(osc.prefs.first { $0.key == nil })
        XCTAssertEqual(reset.titleKey, resetPref.resource("android:title"))
        XCTAssertEqual(reset.summaryKey, resetPref.resource("android:summary"))
        XCTAssertEqual(reset.confirmation?.titleKey, resetPref.resource("android:dialogTitle"))
        XCTAssertEqual(reset.confirmation?.messageKey, resetPref.resource("android:dialogMessage"))
    }

    /// One layout row against the XML element it came from.
    private func checkRow(_ item: SettingsItem, against pref: XMLPref, resources: StringResources,
                          file: StaticString = #filePath, line: UInt = #line) {
        let id = item.id
        XCTAssertEqual(item.titleKey, pref.resource("android:title"), "\(id) title", file: file, line: line)
        let xmlSummary = pref.attributes["android:summary"]
        if xmlSummary == "%s" {
            XCTAssertTrue(item.summaryShowsChoice, "\(id) shows the chosen entry", file: file, line: line)
            XCTAssertNil(item.summaryKey, id, file: file, line: line)
        } else if id == "video_renderer" {
            // Android's text is about Vulkan and the direct renderer
            XCTAssertEqual(item.summaryKey, "ios_summary_video_renderer", file: file, line: line)
        } else if id == "jitter_buffer" {
            // Android's says it only works with host-timed pacing; on iOS it works with every mode
            XCTAssertEqual(item.summaryKey, "ios_summary_jitter_buffer", file: file, line: line)
            XCTAssertNil(item.enabledWhen, file: file, line: line)
        } else if xmlSummary == nil, summariesSetInCode.contains(id) {
            XCTAssertNotNil(item.summaryKey, id, file: file, line: line)
        } else {
            XCTAssertEqual(item.summaryKey, pref.resource("android:summary"), "\(id) summary", file: file, line: line)
            XCTAssertFalse(item.summaryShowsChoice, id, file: file, line: line)
        }
        XCTAssertEqual(item.dependency, pref.attributes["android:dependency"], "\(id) dependency", file: file, line: line)

        let tag = pref.tag
        switch item.control {
        case .toggle:
            XCTAssertTrue(tag == "CheckBoxPreference" || tag.hasSuffix("SmallIconCheckboxPreference"), "\(id) is a \(tag)",
                          file: file, line: line)
        case .list(let entries, let values, let custom):
            XCTAssertTrue(tag == "ListPreference" || tag.hasSuffix("ListPreference") || tag.hasSuffix("LanguagePreference"),
                          "\(id) is a \(tag)", file: file, line: line)
            XCTAssertEqual(custom, tag.hasSuffix("ResolutionListPreference") || tag.hasSuffix("FpsListPreference"), id,
                           file: file, line: line)
            XCTAssertEqual(entries.count, values.count, id, file: file, line: line)
            if entries.allSatisfy({ !$0.hasPrefix("ios_") }) {
                // Android's own list: the same arrays, entry for entry
                let names = pref.resource("android:entries") ?? ""
                let valuesName = pref.resource("android:entryValues") ?? ""
                XCTAssertEqual(entries, (0..<(resources.arrays[names]?.count ?? 0)).map { "\(names).\($0)" }, id,
                               file: file, line: line)
                XCTAssertEqual(values, resources.arrays[valuesName], id, file: file, line: line)
            } else {
                XCTAssertEqual(id, "video_renderer", "only the video renderer has iOS's own choices", file: file, line: line)
            }
        case .dynamicList:
            XCTAssertNil(pref.attributes["android:entries"], id, file: file, line: line)
        case .slider(let range, let step, let divisor, let unit, let custom):
            XCTAssertTrue(tag.hasSuffix("SeekBarPreference"), id, file: file, line: line)
            XCTAssertEqual(range.lowerBound, Int(pref.attributes["seekbar:min"] ?? "1"), "\(id) min", file: file, line: line)
            XCTAssertEqual(range.upperBound, Int(pref.attributes["android:max"] ?? "100"), "\(id) max", file: file, line: line)
            XCTAssertEqual(step, Int(pref.attributes["seekbar:step"] ?? "1"), "\(id) step", file: file, line: line)
            XCTAssertEqual(divisor, Int(pref.attributes["seekbar:divisor"] ?? "1"), "\(id) divisor", file: file, line: line)
            XCTAssertEqual(custom, pref.attributes["seekbar:custom"] == "true", id, file: file, line: line)
            XCTAssertEqual(unit, pref.resource("android:text"), "\(id) unit", file: file, line: line)
        case .text(let input, let maxLength):
            XCTAssertEqual(tag, "EditTextPreference", id, file: file, line: line)
            let xmlInput = pref.attributes["android:inputType"]
            XCTAssertEqual(input, xmlInput == "number" ? .number : xmlInput == "numberDecimal" ? .decimal : .plain, id,
                           file: file, line: line)
            XCTAssertEqual(maxLength, pref.attributes["android:maxLength"].flatMap { Int($0) }, id, file: file, line: line)
        case .link(let url):
            XCTAssertTrue(tag.hasSuffix("WebLauncherPreference"), id, file: file, line: line)
            XCTAssertEqual(url, pref.attributes["url"], id, file: file, line: line)
        case .action:
            XCTAssertTrue(tag == "Preference" || tag.hasSuffix("ConfirmDeleteOscPreference"), "\(id) is a \(tag)",
                          file: file, line: line)
        }
    }

    func testControlsMatchTheCatalog() {
        for item in SettingsLayout.items {
            guard let definition = SettingsCatalog.definition(item.id) else { continue }
            switch item.control {
            case .toggle:
                XCTAssertEqual(definition.kind, .bool, item.id)
            case .list(_, let values, _):
                XCTAssertEqual(definition.kind, .string, item.id)
                XCTAssertEqual(Set(values).count, values.count, "\(item.id) repeats a value")
                if let allowed = definition.allowedValues {
                    XCTAssertTrue(Set(values).isSubset(of: Set(allowed)), "\(item.id): \(values) vs \(allowed)")
                    // Android's lists offer every value the catalog accepts; only the renderer is different
                    if item.id != "video_renderer" {
                        XCTAssertEqual(values, allowed, item.id)
                    }
                }
                if let defaultValue = definition.defaultValue, case .string(let text) = defaultValue {
                    XCTAssertTrue(values.contains(text), "\(item.id) default \(text) isn't offered")
                }
            case .dynamicList:
                XCTAssertEqual(definition.kind, .string, item.id)
            case .slider(let range, let step, let divisor, _, let custom):
                XCTAssertEqual(definition.kind, .int, item.id)
                XCTAssertGreaterThan(step, 0, item.id)
                XCTAssertGreaterThan(divisor, 0, item.id)
                let allowed = definition.range
                if custom {
                    XCTAssertTrue(allowed.map { $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound } ?? true,
                                  "\(item.id) slider \(range) vs \(String(describing: allowed))")
                } else {
                    XCTAssertEqual(range, allowed, item.id)
                }
                if case .int(let value)? = definition.defaultValue {
                    XCTAssertTrue(range.contains(value), "\(item.id) default \(value)")
                    XCTAssertEqual((value - range.lowerBound) % step, 0, "\(item.id) default is on a step")
                }
            case .text:
                XCTAssertEqual(definition.kind, .string, item.id)
            case .action, .link:
                XCTFail("\(item.id) saves a value, so it isn't a button or a link")
            }
        }
    }

    func testDependenciesAndConditionsPointAtRealSettings() {
        for item in SettingsLayout.items + GameSettingsLayout.items {
            if let dependency = item.dependency {
                XCTAssertEqual(SettingsLayout.item(dependency)?.control, .toggle, "\(item.id) depends on \(dependency)")
            }
            for requirement in [item.showWhen, item.enabledWhen].compactMap({ $0 }) {
                if case .value(let key, let values) = requirement {
                    let allowed = SettingsCatalog.definition(key)?.allowedValues ?? []
                    XCTAssertTrue(Set(values).isSubset(of: Set(allowed)), "\(item.id) waits for \(key) in \(values)")
                }
            }
        }
    }

    func testTheMicrophoneRowsShowForTheChosenDestination() {
        // StreamSettings.showMicrophoneTarget: the PC receiver (starwire), another VBAN receiver, or the host
        func rows(for target: String) -> [String] {
            let section = SettingsLayout.sections.first { $0.id == "sound" }!
            return section.groups[0].items.filter { item in
                guard case .value("list_microphone_target", let values)? = item.showWhen else { return false }
                return values.contains(target)
            }.map(\.id)
        }
        XCTAssertEqual(rows(for: "starwire"), ["vban_setup_info", "mic_pairing", "text_vban_port"])
        XCTAssertEqual(rows(for: "vban"), ["vban_setup_info", "text_vban_stream_name", "text_vban_port"])
        XCTAssertEqual(rows(for: "host"), ["microphone_host_info"])
    }

    func testRowsAndroidRemovesAtRuntimeAreMarked() throws {
        let java = try read("app/src/main/java/com/limelight/preferences/StreamSettings.java")
        let removed = Set(matches("removePreference\\(findPreference\\(\"(\\w+)\"\\)\\)", in: java).map { $0[0] })
        XCTAssertGreaterThan(removed.count, 8)

        // Rows Android removes only because of an old Android version or the SHIELD, which don't
        // apply on iOS, or that iOS can't show at all
        let notAboutTheDevice: Set<String> = [
            "checkbox_absolute_mouse_mode", "checkbox_gamepad_motion_sensors", "checkbox_usb_bind_all",
            "checkbox_usb_driver",
        ]
        for key in removed where !notAboutTheDevice.contains(key) {
            XCTAssertNotNil(SettingsLayout.item(key)?.showWhen, "\(key) is removed on some devices, so it needs a showWhen")
        }
        for key in notAboutTheDevice {
            XCTAssertTrue(removed.contains(key), "\(key) is no longer removed by StreamSettings")
        }
        // And nothing is marked that Android keeps (the microphone rows are the other kind of showWhen)
        for item in SettingsLayout.items {
            if case .device(let feature)? = item.showWhen {
                XCTAssertTrue(removed.contains(item.id), "\(item.id) needs \(feature), which Android doesn't ask for")
            }
        }
        // The on-screen controls group goes whole, on a device with no touchscreen
        XCTAssertTrue(java.contains("FEATURE_TOUCHSCREEN"))
        XCTAssertEqual(SettingsLayout.sections.first { $0.id == "onscreen" }?.groups[0].showWhen, .device(.touchscreen))
    }

    func testSavedValueAliasesPointAtOfferedValues() {
        XCTAssertEqual(SettingsLayout.normalizedValue("system", for: "video_renderer"), "auto")
        XCTAssertEqual(SettingsLayout.normalizedValue("loop", for: "video_renderer"), "loop")
        XCTAssertEqual(SettingsLayout.normalizedValue("system", for: "list_fps"), "system")
        for (key, aliases) in SettingsLayout.valueAliases {
            let allowed = SettingsCatalog.definition(key)?.allowedValues ?? []
            guard case .list(_, let values, _)? = SettingsLayout.item(key)?.control else { return XCTFail(key) }
            for (from, to) in aliases {
                XCTAssertTrue(allowed.contains(from), "\(key) accepts \(from)")
                XCTAssertTrue(values.contains(to), "\(key) offers \(to)")
                XCTAssertFalse(values.contains(from), "\(key) offers \(from) as well")
            }
        }
    }

    // MARK: - Per-game screen

    func testPerGameRowsMatchAppPreferencesXML() throws {
        let tree = try PreferenceTreeReader.read("app/src/main/res/xml/app_preferences.xml")
        let resources = try StringResources.load()
        XCTAssertEqual(tree.top.compactMap(\.key), [GameSettingsLayout.useGlobalKey])
        XCTAssertEqual(tree.categories.count, 1)
        XCTAssertEqual(GameSettingsLayout.groups.map(\.id), ["game_use_global", tree.categories[0].attributes["android:key"] ?? ""])

        XCTAssertEqual(GameSettingsLayout.groups[1].items.map(\.id), tree.categories[0].prefs.compactMap(\.key))
        for pref in tree.categories[0].prefs {
            let item = try XCTUnwrap(GameSettingsLayout.item(pref.key!))
            XCTAssertEqual(item.titleKey, pref.resource("android:title"), item.id)
            XCTAssertEqual(item.summaryKey, pref.resource("android:summary"), item.id)
            XCTAssertNil(item.dependency, item.id)
            XCTAssertNil(item.credit, "Android shows credits on the main screen only: \(item.id)")
            let global = try XCTUnwrap(item.overrides, item.id)
            let definition = try XCTUnwrap(SettingsCatalog.definition(global), global)

            switch item.control {
            case .list(let entries, let values, let custom):
                // The "game_" options have their arrays set in code (AppStreamSettings.GAME_OPTIONS)
                if let names = pref.resource("android:entries") {
                    XCTAssertEqual(entries, (0..<(resources.arrays[names]?.count ?? 0)).map { "\(names).\($0)" }, item.id)
                    XCTAssertEqual(values, resources.arrays[pref.resource("android:entryValues") ?? ""], item.id)
                }
                XCTAssertEqual(custom, pref.tag.hasSuffix("ResolutionListPreference") || pref.tag.hasSuffix("FpsListPreference"))
                // A per-game choice is one of the global setting's values, or a true/false for a switch
                if definition.kind == .bool {
                    XCTAssertEqual(values, ["true", "false"], item.id)
                } else if let allowed = definition.allowedValues {
                    XCTAssertEqual(values, allowed, item.id)
                }
            case .text(let input, _):
                XCTAssertEqual(pref.tag, "EditTextPreference", item.id)
                XCTAssertEqual(input, pref.attributes["android:inputType"] == "number" ? .number : .decimal, item.id)
            default:
                XCTFail("\(item.id) should be a list or a text field")
            }
            // Android gives the same impact line to the per-game copy
            XCTAssertEqual(item.impactKey, SettingsImpact.impactKey(for: global), item.id)
        }

        // The top switch is written in code on Android, so it has iOS strings
        let useGlobal = try XCTUnwrap(GameSettingsLayout.item(GameSettingsLayout.useGlobalKey))
        XCTAssertEqual(useGlobal.control, .toggle)
        XCTAssertTrue(useGlobal.titleKey.hasPrefix("ios_"))
    }

    func testPerGameOptionsAreTheCatalogsGameOptions() {
        let optionRows = GameSettingsLayout.items.filter { $0.id.hasPrefix("game_") }
        XCTAssertEqual(Set(optionRows.compactMap(\.overrides)), Set(SettingsCatalog.gameOptionKeys))
        for row in optionRows {
            XCTAssertEqual(row.id, "game_" + row.overrides!)
            XCTAssertEqual(SettingsCatalog.definition(row.overrides!)?.gameOption, true, row.id)
        }
        // The rest of the per-game fields are the ones GameSettings has
        XCTAssertEqual(Set(GameSettingsLayout.items.filter { !$0.id.hasPrefix("game_") }.map(\.id)), [
            "checkbox_use_global_settings", "list_app_resolution", "list_app_fps", "text_app_bitrate_kbps",
            "list_app_frame_pacing", "text_app_actual_display_refresh_rate", "list_app_enable_hdr",
            "list_app_enable_perf_overlay",
        ])
    }

    // MARK: - Strings

    private func stringKeys(of item: SettingsItem) -> [String] {
        var keys = [item.titleKey]
        keys += [item.summaryKey, item.impactKey].compactMap { $0 }
        switch item.control {
        case .list(let entries, _, _): keys += entries
        case .dynamicList(let defaultEntry): keys.append(defaultEntry)
        case .slider(_, _, _, let unit, _): keys += [unit].compactMap { $0 }
        default: break
        }
        if let confirmation = item.confirmation {
            keys += [confirmation.titleKey, confirmation.messageKey, SettingConfirmation.yesKey, SettingConfirmation.noKey]
        }
        return keys
    }

    private func feelKeys() -> [String] {
        var keys = [SettingsFeel.titleKey, SettingsFeel.fastestKey, SettingsFeel.smoothestKey, SettingsFeel.delayKey,
                    SettingsFeel.batteryKey, SettingsFeel.movingItKey, SettingsFeel.factorRowKey]
        for pacing in SettingsCatalog.framePacing + ["something-new"] {
            for vsync in ["off", "vsync", "fast"] {
                for lfr in [false, true] {
                    let feel = SettingsFeel.describe(pacing: pacing, vsync: vsync, asyncLfr: lfr)
                    keys += [feel.descriptionKey, feel.delay.nameKey, feel.battery.nameKey]
                    for factor in feel.factors {
                        keys += [factor.titleKey, factor.effect.nameKey]
                        if case .label(let label) = factor.value { keys.append(label) }
                    }
                }
            }
        }
        return keys
    }

    private func allReferencedKeys() -> Set<String> {
        var keys: [String] = []
        for section in SettingsLayout.sections {
            keys.append(section.titleKey)
            for group in section.groups {
                keys += [group.titleKey].compactMap { $0 }
                keys += group.items.flatMap(stringKeys)
            }
        }
        for group in GameSettingsLayout.groups {
            keys += [group.titleKey].compactMap { $0 }
            keys += group.items.flatMap(stringKeys)
        }
        keys += [GameSettingsLayout.defaultEntryKey, GameSettingsLayout.quickLaunchDefaultEntryKey,
                 GameSettingsLayout.quickLaunchUseGlobalTitleKey, GameSettingsLayout.quickLaunchUseGlobalSummaryKey]
        keys.append(SettingsImpact.labelKey)
        keys += SettingsImpact.lines.values
        keys += feelKeys()
        keys += SettingsCredits.sectionKeys
        keys += SettingsCredits.projects.map(\.usedForKey)
        return Set(keys)
    }

    func testEveryStringTheLayoutNamesExists() throws {
        let resources = try StringResources.load()
        for key in allReferencedKeys().sorted() {
            XCTAssertTrue(resources.resolves(key), "\(key) isn't in strings.xml, arrays.xml or strings-ios.xml")
            if !key.contains(".") {
                // iOS names only live in the iOS file, and Android's only in Android's
                XCTAssertEqual(key.hasPrefix("ios_"), resources.ios.contains(key), key)
            }
        }
    }

    func testTheIOSStringsFileIsWellFormedAndEveryStringIsUsed() throws {
        let collector = NameCollector()
        let parser = XMLParser(data: try Data(contentsOf: repo.appendingPathComponent("ios/Strings/strings-ios.xml")))
        parser.delegate = collector
        XCTAssertTrue(parser.parse(), "strings-ios.xml didn't parse")
        XCTAssertEqual(Set(collector.names).count, collector.names.count, "a name is repeated")
        // Used by the layouts, or by the app's screens (L("name") in their Swift code, and the
        // game screen's texts that Android writes in its code, which keep the names it would use)
        var used = allReferencedKeys()
        var gameScreenTexts = Set(OverrideText.allCases.map(\.rawValue))
        gameScreenTexts.formUnion(QuickLaunchText.allCases.map(\.rawValue))
        used.formUnion(gameScreenTexts)
        used.formUnion(SettingsCredits.projects.map(\.usedForKey))
        let app = repo.appendingPathComponent("ios/Limelight")
        for case let file as URL in FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)!
            where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in matches(#"\bL\("([A-Za-z0-9_.]+)""#, in: source) { used.insert(match[0]) }
            for match in matches("return \"(ios_[a-z_]+)\"", in: source) { used.insert(match[0]) }
        }
        let resources = try StringResources.load()
        for name in collector.names {
            XCTAssertTrue(name.hasPrefix("ios_") || gameScreenTexts.contains(name), name)
            XCTAssertTrue(used.contains(name), "\(name) is not used by the layout or the app")
            XCTAssertFalse(resources.android.contains(name), "\(name) is also in strings.xml")
        }
        // Plain English, no em dashes
        let text = try read("ios/Strings/strings-ios.xml")
        XCTAssertFalse(text.contains("\u{2014}"))
    }

    // MARK: - Impact lines

    func testImpactLinesAreAndroidsTable() throws {
        let java = try read("app/src/main/java/com/limelight/ui/SettingsImpact.java")
        var lines: [String: String] = [:]
        for pair in matches("IMPACT\\.put\\(\"(\\w+)\", R\\.string\\.(\\w+)\\)", in: java) { lines[pair[0]] = pair[1] }
        var aliases: [String: String] = [:]
        for pair in matches("ALIASES\\.put\\(\"(\\w+)\", \"(\\w+)\"\\)", in: java) { aliases[pair[0]] = pair[1] }
        XCTAssertEqual(SettingsImpact.lines, lines)
        XCTAssertEqual(SettingsImpact.aliases, aliases)
        XCTAssertEqual(lines.count, 28)

        // Every key with a line is a real setting; every alias is a row of the per-game screen
        for key in lines.keys { XCTAssertNotNil(SettingsLayout.item(key), key) }
        for (alias, target) in aliases {
            XCTAssertNotNil(GameSettingsLayout.item(alias), alias)
            XCTAssertNotNil(lines[target], alias)
        }
    }

    // The same cases as Android's SettingsImpactKeysTest
    func testImpactKeysFollowAndroidsRules() {
        for key in ["list_resolution", "list_fps", "seekbar_bitrate_kbps", "frame_pacing", "vsync_mode",
                    "checkbox_async_decode", "checkbox_async_lfr", "video_format", "video_renderer"] {
            XCTAssertNotNil(SettingsImpact.impactKey(for: key), key)
        }
        XCTAssertEqual(SettingsImpact.impactKey(for: "list_app_frame_pacing"), SettingsImpact.impactKey(for: "frame_pacing"))
        XCTAssertEqual(SettingsImpact.impactKey(for: "game_vsync_mode"), SettingsImpact.impactKey(for: "vsync_mode"))
        XCTAssertEqual(SettingsImpact.impactKey(for: "list_app_fps"), SettingsImpact.impactKey(for: "list_fps"))
        XCTAssertNil(SettingsImpact.impactKey(for: "list_languages"))
        XCTAssertNil(SettingsImpact.impactKey(for: nil))

        // Only the start of a key is taken as the per-game prefix, and only once
        XCTAssertEqual(SettingsImpact.impactKey(for: "game_list_audio_haptics"), SettingsImpact.impactKey(for: "list_audio_haptics"))
        XCTAssertNotNil(SettingsImpact.impactKey(for: "list_audio_haptics"))
        XCTAssertNil(SettingsImpact.impactKey(for: "game_"))
        XCTAssertNil(SettingsImpact.impactKey(for: "x_game_vsync_mode"))
        XCTAssertNil(SettingsImpact.impactKey(for: "game_game_vsync_mode"))

        XCTAssertEqual(SettingsImpact.impactKey(for: "checkbox_stretch_video"), "impact_none")
        XCTAssertEqual(SettingsImpact.impactKey(for: "checkbox_full_range"), "impact_none")
    }

    func testRowsCarryTheirImpactLine() {
        for item in SettingsLayout.items {
            if item.id == "video_renderer" {
                // Android's line is about Vulkan, which iOS doesn't have
                XCTAssertNil(item.impactKey)
                continue
            }
            XCTAssertEqual(item.impactKey, SettingsImpact.impactKey(for: item.id), item.id)
        }
        XCTAssertEqual(SettingsLayout.item("list_resolution")?.impactKey, "impact_resolution")
        XCTAssertNil(SettingsLayout.item("list_languages")?.impactKey)
    }

    // MARK: - Predicted impact

    func testDefaultsAreBalanced() {
        let feel = SettingsFeel.describe(SettingsStore(storage: MemorySettingsStorage()))
        XCTAssertEqual(feel.position, 0.45, accuracy: 0.0001)
        XCTAssertEqual(feel.descriptionKey, "feel_balanced")
        XCTAssertEqual(feel.delay, .medium)
        XCTAssertEqual(feel.battery, .medium)
        XCTAssertEqual(feel.factors, [
            SettingsFeel.Factor(titleKey: "feel_factor_pacing", value: .label("video_frame_pacing_names.1"), effect: .balanced),
            SettingsFeel.Factor(titleKey: "feel_factor_vsync", value: .label("vsync_mode_names.0"), effect: .noEffect),
            SettingsFeel.Factor(titleKey: "feel_factor_async_lfr", value: .label("feel_off"), effect: .noEffect),
        ])
    }

    func testLowestLatencyAndSmoothest() {
        let fastest = SettingsFeel.describe(pacing: "warp2", vsync: "off", asyncLfr: false)
        XCTAssertEqual(fastest.position, 0.02, accuracy: 0.0001)
        XCTAssertEqual(fastest.descriptionKey, "feel_warp2")
        XCTAssertEqual(fastest.delay, .lower)
        XCTAssertEqual(fastest.battery, .higher)
        XCTAssertEqual(fastest.factors[0].effect, .faster)

        let smoothest = SettingsFeel.describe(pacing: "smoothness", vsync: "off", asyncLfr: false)
        XCTAssertEqual(smoothest.position, 0.92, accuracy: 0.0001)
        XCTAssertEqual(smoothest.delay, .higher)
        XCTAssertEqual(smoothest.battery, .medium)
        XCTAssertEqual(smoothest.factors[0].effect, .smoother)
        XCTAssertEqual(smoothest.descriptionKey, "feel_smoothness")

        // Android's androidTest: warp2 < latency < balanced < smoothness
        let latency = SettingsFeel.describe(pacing: "latency", vsync: "off", asyncLfr: false)
        let balanced = SettingsFeel.describe(pacing: "balanced", vsync: "off", asyncLfr: false)
        XCTAssertLessThan(fastest.position, latency.position)
        XCTAssertLessThan(latency.position, balanced.position)
        XCTAssertLessThan(balanced.position, smoothest.position)
        XCTAssertEqual(latency.position, 0.15, accuracy: 0.0001)
        XCTAssertEqual(latency.delay, .lower)
        XCTAssertEqual(SettingsFeel.describe(pacing: "warp", vsync: "off", asyncLfr: false).position, 0.06, accuracy: 0.0001)
        XCTAssertEqual(SettingsFeel.describe(pacing: "warp", vsync: "off", asyncLfr: false).battery, .higher)
        XCTAssertEqual(SettingsFeel.describe(pacing: "cap-fps", vsync: "off", asyncLfr: false).position, 0.5, accuracy: 0.0001)
        XCTAssertEqual(SettingsFeel.describe(pacing: "cap-fps", vsync: "off", asyncLfr: false).factors[0].effect, .balanced)
    }

    func testVSyncMovesTowardsSmoothAndAddsDelay() {
        // Android's androidTest: V-Sync moves towards smooth and adds delay
        let latency = SettingsFeel.describe(pacing: "latency", vsync: "off", asyncLfr: false)
        let vsync = SettingsFeel.describe(pacing: "latency", vsync: "vsync", asyncLfr: false)
        XCTAssertGreaterThan(vsync.position, latency.position)
        XCTAssertEqual(vsync.position, 0.30, accuracy: 0.0001)
        XCTAssertEqual(vsync.delay, .medium)
        XCTAssertEqual(vsync.factors[1].effect, .smoother)
        XCTAssertEqual(vsync.factors[1].value, .label("vsync_mode_names.1"))

        // Fast V-Sync moves a little and adds no delay
        let fast = SettingsFeel.describe(pacing: "balanced", vsync: "fast", asyncLfr: false)
        XCTAssertEqual(fast.position, 0.50, accuracy: 0.0001)
        XCTAssertEqual(fast.delay, .medium)
        XCTAssertEqual(fast.factors[1].value, .label("vsync_mode_names.2"))

        // The position stops at 1 and the delay at Higher
        let capped = SettingsFeel.describe(pacing: "smoothness", vsync: "vsync", asyncLfr: false)
        XCTAssertEqual(capped.position, 1)
        XCTAssertEqual(capped.delay, .higher)
        // ... and the position at 0
        XCTAssertEqual(SettingsFeel.describe(pacing: "warp2", vsync: "off", asyncLfr: true).position, 0)
    }

    func testAsyncLfrAndHostTimedPacing() {
        // Android's androidTest: Warp Drive with V-Sync and Async LFR
        let warp = SettingsFeel.describe(pacing: "warp", vsync: "vsync", asyncLfr: true)
        XCTAssertEqual(warp.factors.count, 3)
        XCTAssertEqual(warp.factors.map(\.effect), [.faster, .smoother, .faster])
        XCTAssertEqual(warp.factors[0].value, .label("video_frame_pacing_names.5"))
        XCTAssertEqual(warp.factors[2].value, .label("feel_on"))
        XCTAssertEqual(warp.position, 0.16, accuracy: 0.0001)
        XCTAssertEqual(warp.delay, .medium)
        XCTAssertEqual(warp.battery, .higher)

        // Host frame timing ignores V-Sync and Async LFR
        let host = SettingsFeel.describe(pacing: "host-timed", vsync: "vsync", asyncLfr: true)
        XCTAssertEqual(host.factors.map(\.effect), [.smoother, .notUsed, .notUsed])
        XCTAssertEqual(host.position, SettingsFeel.describe(pacing: "host-timed", vsync: "off", asyncLfr: false).position, accuracy: 0.001)
        XCTAssertEqual(host.position, 0.65, accuracy: 0.0001)
        XCTAssertEqual(host.delay, .medium)
        XCTAssertEqual(host.descriptionKey, "feel_host_timed")
    }

    func testUnknownChoicesFallBackTheWayAndroidDoes() {
        // An unknown pacing is Balanced
        let unknown = SettingsFeel.describe(pacing: "something-new", vsync: "off", asyncLfr: false)
        XCTAssertEqual(unknown, SettingsFeel.describe(pacing: "balanced", vsync: "off", asyncLfr: false))
        // An unknown V-Sync does nothing and is shown as it was saved
        let odd = SettingsFeel.describe(pacing: "balanced", vsync: "weird", asyncLfr: false)
        XCTAssertEqual(odd.factors[1], SettingsFeel.Factor(titleKey: "feel_factor_vsync", value: .literal("weird"), effect: .noEffect))
        XCTAssertEqual(odd.position, 0.45, accuracy: 0.0001)
    }

    func testThePanelReadsTheStore() throws {
        let storage = MemorySettingsStorage()
        let store = SettingsStore(storage: storage)
        try store.set(.string("warp"), for: "frame_pacing")
        try store.set(.string("vsync"), for: "vsync_mode")
        // Async LFR only counts with async decode on
        try store.set(.bool(true), for: "checkbox_async_lfr")
        XCTAssertEqual(SettingsFeel.describe(store), SettingsFeel.describe(pacing: "warp", vsync: "vsync", asyncLfr: false))
        try store.set(.bool(true), for: "checkbox_async_decode")
        XCTAssertEqual(SettingsFeel.describe(store), SettingsFeel.describe(pacing: "warp", vsync: "vsync", asyncLfr: true))

        // A saved value the list doesn't have is ignored, so the default is used
        storage.set("nonsense", forKey: "frame_pacing")
        XCTAssertEqual(SettingsFeel.describe(store).descriptionKey, "feel_balanced")

        XCTAssertEqual(SettingsFeel.inputKeys, ["frame_pacing", "vsync_mode", "checkbox_async_decode", "checkbox_async_lfr"])
        for key in SettingsFeel.inputKeys { XCTAssertNotNil(SettingsCatalog.definition(key), key) }
        XCTAssertEqual(SettingsFeel.panelMinWidth, 840)
    }

    func testFeelMatchesTheJavaConstants() throws {
        // Positions and the keys of the sentences are the ones in SettingsFeel.java
        let java = try read("app/src/main/java/com/limelight/ui/SettingsFeel.java")
        let cases = matches("case \"([\\w-]+)\":\\s*position = ([\\d.]+)f;\\s*textRes = R\\.string\\.(\\w+);", in: java)
        XCTAssertEqual(cases.count, 6)
        for found in cases {
            let feel = SettingsFeel.describe(pacing: found[0], vsync: "off", asyncLfr: false)
            XCTAssertEqual(feel.position, Float(found[1])!, accuracy: 0.0001, found[0])
            XCTAssertEqual(feel.descriptionKey, found[2], found[0])
        }
        XCTAssertTrue(java.contains("position < 0.35f ? EFFECT_FASTER : position > 0.6f ? EFFECT_SMOOTHER"))
        XCTAssertTrue(java.contains("position += 0.15f"))
        XCTAssertTrue(java.contains("position += 0.05f"))
        XCTAssertTrue(java.contains("position -= 0.05f"))
        let layout = try read("app/src/main/java/com/limelight/ui/CoverGlowSettings.java")
        XCTAssertTrue(layout.contains("FEEL_PANEL_MIN_WIDTH_DP = 840"))
        XCTAssertTrue(layout.contains("\"frame_pacing\", \"vsync_mode\", \"checkbox_async_decode\", \"checkbox_async_lfr\""))
    }

    // MARK: - Credits

    func testSettingCreditsAreAndroidsTable() throws {
        let java = try read("app/src/main/java/com/limelight/ui/CoverGlowSettings.java")
        let start = try XCTUnwrap(java.range(of: "private static final java.util.Map<String, String> CREDITS"))
        let end = try XCTUnwrap(java.range(of: "static String creditFor"))
        let source = String(java[start.lowerBound..<end.lowerBound])

        var variables: [String: String] = [:]
        for pair in matches("String (\\w+) = \"([^\"]*)\";", in: source) { variables[pair[0]] = pair[1] }
        var expected: [String: String] = [:]
        for put in matches("CREDITS\\.put\\(\"(\\w+)\",\\s*(?:\"([^\"]*)\"|(\\w+))\\)", in: source) {
            if put[1].isEmpty {
                expected[put[0]] = try XCTUnwrap(variables[put[2]], put[2])
            } else {
                expected[put[0]] = put[1]
            }
        }
        for loop in matches("for \\(String key : new String\\[\\] \\{([^}]*)\\}\\) \\{\\s*CREDITS\\.put\\(key, (\\w+)\\);", in: source) {
            let text = try XCTUnwrap(variables[loop[1]], loop[1])
            for key in matches("\"(\\w+)\"", in: loop[0]) { expected[key[0]] = text }
        }
        XCTAssertGreaterThan(expected.count, 30)
        XCTAssertEqual(SettingsCredits.androidSettingCredits.mapValues(\.text), expected)

        // Android's own checks (CoverGlowTest.borrowedSettingsAreCredited)
        XCTAssertTrue(SettingsCredits.credit(for: "checkbox_async_decode")!.text.contains("derflacco"))
        XCTAssertTrue(SettingsCredits.credit(for: "list_audio_haptics")!.text.contains("Moonlight V+"))
        XCTAssertTrue(SettingsCredits.credit(for: "checkbox_custom_vulkan_driver")!.text.contains("NoCrypt"))
        XCTAssertTrue(SettingsCredits.credit(for: "list_resolution")!.text.contains("Moonlight X"))
        XCTAssertTrue(SettingsCredits.credit(for: "list_fps")!.text.contains("MoreOrLessSoftware"))
        XCTAssertNil(SettingsCredits.credit(for: "seekbar_bitrate_kbps"))
        XCTAssertNil(SettingsCredits.credit(for: "hide_cursor_mode"))
        XCTAssertNil(SettingsCredits.credit(for: nil))
    }

    func testEveryCreditNamesAProjectInTheList() {
        let credits = SettingsCredits.androidSettingCredits.merging(SettingsCredits.iosSettingCredits) { a, _ in a }
        for (key, credit) in credits.sorted(by: { $0.key < $1.key }) {
            XCTAssertNotNil(SettingsLayout.item(key), "\(key) has a credit but no row")
            XCTAssertFalse(credit.projects.isEmpty, key)
            for name in credit.projects {
                guard let project = SettingsCredits.project(named: name) else {
                    XCTFail("\(key) names \(name), which isn't in the credits list")
                    continue
                }
                // The line names the project, or its author by a short name ("NoCrypt", "logabell")
                let words = project.author.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 }
                XCTAssertTrue(credit.text.contains(name) || words.contains { credit.text.contains($0) },
                              "\(key): \(credit.text) doesn't name \(name) or its author")
            }
        }
        XCTAssertEqual(Set(SettingsCredits.iosSettingCredits.keys).intersection(SettingsCredits.androidSettingCredits.keys), [])
        for key in SettingsCredits.iosSettingCredits.keys {
            XCTAssertEqual(SettingsCatalog.definition(key)?.availability, .iosOnly, key)
        }
    }

    func testRowsCarryTheirCredit() {
        for item in SettingsLayout.items {
            XCTAssertEqual(item.credit, SettingsCredits.credit(for: item.id), item.id)
        }
        XCTAssertEqual(SettingsLayout.item("vsync_mode")?.credit?.text, "Fast V-Sync from Artemide by derflacco")
        XCTAssertNil(SettingsLayout.item("hide_cursor_mode")?.credit)
        XCTAssertNil(GameSettingsLayout.item("game_vsync_mode")?.credit)
    }

    func testTheProjectListIsAndroidsAndTheReadmes() throws {
        let java = try read("app/src/main/java/com/limelight/ui/AboutCredits.java")
        var sections: [String: String] = [:]
        for pair in matches("private static final int (\\w+) = R\\.string\\.(credits_section_\\w+);", in: java) {
            sections[pair[0]] = pair[1]
        }
        let parsed = matches("new Credit\\((\\w+),\\s*\"([^\"]+)\",\\s*\"([^\"]+)\",\\s*R\\.string\\.(\\w+),\\s*\"([^\"]+)\"\\)", in: java)
            .map { ProjectCredit(sectionKey: sections[$0[0]] ?? "?", project: $0[1], author: $0[2], usedForKey: $0[3],
                                 url: $0[4], iosOnly: false) }
        XCTAssertEqual(parsed.count, 18)
        XCTAssertEqual(SettingsCredits.androidProjects, parsed)
        XCTAssertEqual(SettingsCredits.sectionKeys, ["credits_section_moonlight", "credits_section_microphone",
                                                     "credits_section_video", "credits_section_hosts", "credits_section_tools"])
        let headings = SettingsCredits.androidProjects.map { SettingsCredits.sectionKeys.firstIndex(of: $0.sectionKey) ?? -1 }
        XCTAssertEqual(headings, headings.sorted(), "projects follow their headings")
        XCTAssertFalse(headings.contains(-1))

        // The README's Credits table lists every Android project
        let readme = try read("README.md")
        for project in SettingsCredits.androidProjects {
            XCTAssertTrue(readme.contains("[\(project.project)](\(project.url))"), project.project)
        }

        // The iOS-only ones sit at the end of their heading
        XCTAssertEqual(SettingsCredits.projects.count, SettingsCredits.androidProjects.count + SettingsCredits.iosProjects.count)
        let iosMoonlight = SettingsCredits.iosProjects.filter { $0.sectionKey == "credits_section_moonlight" }.map(\.project)
        XCTAssertEqual(iosMoonlight, ["Moonlight iOS", "Moonlight iOS (Metal renderer)", "VoidLink", "Artemis iOS"])
        let moonlight = SettingsCredits.projects(inSection: "credits_section_moonlight")
        XCTAssertEqual(Array(moonlight.suffix(iosMoonlight.count)).map(\.project), iosMoonlight)
        XCTAssertEqual(moonlight.dropLast(iosMoonlight.count).map(\.project), SettingsCredits.androidProjects.prefix(9).map(\.project))
        XCTAssertEqual(SettingsCredits.projects.filter(\.iosOnly).map(\.project), SettingsCredits.iosProjects.map(\.project))
        XCTAssertEqual(Set(SettingsCredits.projects.map(\.project)).count, SettingsCredits.projects.count)
    }
}
