import XCTest
@testable import TextRotatorCore

final class BackupServiceTests: XCTestCase {

    var service: BackupService!

    override func setUp() {
        super.setUp()
        service = BackupService()
    }

    // MARK: - Export shape

    func testExportProducesOriginalCompatibleStructure() throws {
        let backup = service.makeBackup(
            folders: [
                ImportFolderPayload(name: "Приветки", snippets: ["aa", "bb"]),
                ImportFolderPayload(name: "DI", snippets: ["cc"])
            ],
            hotkeys: BackupHotkeys(rotation: "F3", translation: "F4", instant: "F1", cursor: "F2"),
            settings: ["provider.primary": "Yandex"],
            date: Date(timeIntervalSince1970: 1_792_316_154)
        )

        XCTAssertEqual(backup.format, "text-rotator-backup")
        XCTAssertEqual(backup.version, 1)
        XCTAssertEqual(backup.exportedAt, "1792316154")
        XCTAssertEqual(backup.folders.count, 2)
        XCTAssertEqual(backup.folders[0].name, "Приветки")
        XCTAssertEqual(backup.folders[0].snippets, ["aa", "bb"])

        // Hotkeys merged into settings map (original app stores both places)
        XCTAssertEqual(backup.settings?["hotkey.rotation"], "F3")
        XCTAssertEqual(backup.settings?["hotkey.translate"], "F4")
        XCTAssertEqual(backup.settings?["hotkey.instant_translate"], "F1")
        XCTAssertEqual(backup.settings?["hotkey.cursor_translate"], "F2")
        XCTAssertEqual(backup.settings?["provider.primary"], "Yandex")
    }

    func testEncodedJSONContainsRequiredTopLevelKeys() throws {
        let backup = service.makeBackup(
            folders: [ImportFolderPayload(name: "X", snippets: ["y"])],
            hotkeys: BackupHotkeys(rotation: "F3", translation: "F4", instant: "F1", cursor: "F2"),
            settings: [:]
        )
        let data = try service.encode(backup)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["format"] as? String, "text-rotator-backup")
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertNotNil(object["exportedAt"])
        XCTAssertNotNil(object["folders"])

        let hotkeys = try XCTUnwrap(object["hotkeys"] as? [String: Any])
        XCTAssertEqual(hotkeys["rotation"] as? String, "F3")
        XCTAssertEqual(hotkeys["translation"] as? String, "F4")
        XCTAssertEqual(hotkeys["instant"] as? String, "F1")
        XCTAssertEqual(hotkeys["cursor"] as? String, "F2")
    }

    // MARK: - Import: modern backup format

    func testParseModernBackupFormat() throws {
        let json = """
        {
          "format": "text-rotator-backup",
          "version": 1,
          "exportedAt": "1792316154",
          "hotkeys": {
            "rotation": "F3",
            "translation": "F4",
            "instant": "F1",
            "cursor": "F2"
          },
          "settings": {
            "cursor.translate_mode.enabled": "1",
            "provider.primary": "Yandex",
            "theme.active": "dark"
          },
          "folders": [
            { "name": "Приветки", "snippets": ["hello", "hi"] },
            { "name": "DI", "snippets": ["gm"] }
          ]
        }
        """
        let parsed = try service.parse(data: Data(json.utf8))

        XCTAssertEqual(parsed.folders.count, 2)
        XCTAssertEqual(parsed.folders[0].name, "Приветки")
        XCTAssertEqual(parsed.folders[0].snippets, ["hello", "hi"])
        XCTAssertEqual(parsed.folders[1].name, "DI")
        XCTAssertEqual(parsed.hotkeys?.rotation, "F3")
        XCTAssertEqual(parsed.hotkeys?.cursor, "F2")
        XCTAssertEqual(parsed.settings?["provider.primary"], "Yandex")
        XCTAssertEqual(parsed.settings?["cursor.translate_mode.enabled"], "1")
    }

    func testParseModernBackupWithoutHotkeysBlockFallsBackToSettings() throws {
        let json = """
        {
          "format": "text-rotator-backup",
          "version": 1,
          "exportedAt": "1792316154",
          "settings": {
            "hotkey.rotation": "F6",
            "hotkey.translate": "F7"
          },
          "folders": []
        }
        """
        let parsed = try service.parse(data: Data(json.utf8))
        XCTAssertEqual(parsed.hotkeys?.rotation, "F6")
        XCTAssertEqual(parsed.hotkeys?.translation, "F7")
    }

    // MARK: - Import: legacy data_popup config

    func testParseLegacyPopupConfig() throws {
        let json = """
        {
          "data_rotation": ["1123", "33445"],
          "data_popup": [
            { "type": "folder", "name": "Приветки", "items": ["aaa", "bbb", "ccc"] },
            { "type": "folder", "name": "HR TEST", "items": ["test"] }
          ],
          "hotkey": "f3",
          "use_popup": true,
          "theme_mode": "auto"
        }
        """
        let parsed = try service.parse(data: Data(json.utf8))

        XCTAssertEqual(parsed.folders.count, 2)
        XCTAssertEqual(parsed.folders[0].name, "Приветки")
        XCTAssertEqual(parsed.folders[0].snippets.count, 3)
        XCTAssertEqual(parsed.hotkeys?.rotation, "f3")
        XCTAssertNil(parsed.settings)
    }

    func testParseLegacyConfigSkipsNonFolderEntries() throws {
        let json = """
        {
          "data_popup": [
            { "type": "folder", "name": "ok", "items": ["1"] },
            { "type": "text", "name": "skip me", "items": ["2"] }
          ]
        }
        """
        let parsed = try service.parse(data: Data(json.utf8))
        XCTAssertEqual(parsed.folders.count, 1)
        XCTAssertEqual(parsed.folders[0].name, "ok")
    }

    // MARK: - Round-trip

    func testRoundTripPreservesFoldersAndHotkeys() throws {
        let original = service.makeBackup(
            folders: [
                ImportFolderPayload(name: "Рассылки", snippets: ["x\nmultiline", "emoji 😋 текст"])
            ],
            hotkeys: BackupHotkeys(rotation: "F3", translation: "F4", instant: "F1", cursor: "F2"),
            settings: ["provider.primary": "Google"]
        )

        let data = try service.encode(original)
        let parsed = try service.parse(data: data)

        XCTAssertEqual(parsed.folders, original.folders.map { ImportFolderPayload(name: $0.name, snippets: $0.snippets) })
        XCTAssertEqual(parsed.hotkeys?.rotation, "F3")
        XCTAssertEqual(parsed.hotkeys?.translation, "F4")
        XCTAssertEqual(parsed.hotkeys?.instant, "F1")
        XCTAssertEqual(parsed.hotkeys?.cursor, "F2")
        XCTAssertEqual(parsed.settings?["provider.primary"], "Google")
    }

    // MARK: - Error handling

    func testParseRejectsUnknownFormat() {
        let json = "{\"something\": \"else\"}"
        XCTAssertThrowsError(try service.parse(data: Data(json.utf8))) { error in
            guard case BackupError.unknownFormat = error else {
                return XCTFail("Expected unknownFormat, got \(error)")
            }
        }
    }

    func testParseRejectsGarbage() {
        XCTAssertThrowsError(try service.parse(data: Data("not json at all".utf8)))
    }

    // MARK: - Real-world original backup

    func testParseRealOriginalBackupShape() throws {
        // Verbatim structure of the original Windows app export (with shortened payloads)
        let json = """
        {
          "format": "text-rotator-backup",
          "version": 1,
          "exportedAt": "1792316154",
          "hotkeys": {
            "rotation": "F3",
            "translation": "F4",
            "instant": "F1",
            "cursor": "F2"
          },
          "settings": {
            "bundled.services.fingerprint": "9617f7169574c2d0",
            "cursor.translate_mode.enabled": "1",
            "hotkey.cursor_translate": "F2",
            "hotkey.instant_translate": "F1",
            "hotkey.rotation": "F3",
            "hotkey.translate": "F4",
            "provider.alias.Yandex": "Yandex",
            "provider.order": "[\\"Amazon\\",\\"Yandex\\"]",
            "provider.primary": "Yandex",
            "theme.active": "dark",
            "updater.skip.version": ""
          },
          "folders": [
            {
              "name": "Приветки",
              "snippets": [
                "Can we break the silence and get to know each other? And I'll share some interesting facts about you in return😋",
                "ntmtu! \\nMy name is Melania n I am 23 yo."
              ]
            }
          ]
        }
        """
        let parsed = try service.parse(data: Data(json.utf8))

        XCTAssertEqual(parsed.folders.count, 1)
        XCTAssertEqual(parsed.folders[0].snippets.count, 2)
        XCTAssertEqual(parsed.hotkeys?.rotation, "F3")
        XCTAssertEqual(parsed.settings?.count, 11)

        // Hotkey settings merged from dedicated block take priority
        XCTAssertEqual(parsed.settings?["hotkey.rotation"], "F3")
    }
}
