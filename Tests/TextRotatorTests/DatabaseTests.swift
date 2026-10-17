import XCTest
@testable import TextRotatorCore

final class DatabaseTests: XCTestCase {
    var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService.inMemory()
    }

    override func tearDownWithError() throws {
        db = nil
        try super.tearDownWithError()
    }

    // MARK: - Folders Tests

    func testCreateAndListFolders() throws {
        let f1 = try db.createFolder(name: "Work")
        XCTAssertEqual(f1.name, "Work")
        XCTAssertEqual(f1.position, 0)
        XCTAssertEqual(f1.snippetCount, 0)

        let f2 = try db.createFolder(name: "Personal")
        XCTAssertEqual(f2.name, "Personal")
        XCTAssertEqual(f2.position, 1)

        let folders = try db.listFolders()
        XCTAssertEqual(folders.count, 2)
        XCTAssertEqual(folders[0].name, "Work")
        XCTAssertEqual(folders[1].name, "Personal")
    }

    func testUpdateFolder() throws {
        let f = try db.createFolder(name: "Old Name")
        try db.updateFolder(id: f.id, name: "New Name")

        let folders = try db.listFolders()
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0].name, "New Name")

        XCTAssertThrowsError(try db.updateFolder(id: 9999, name: "Non-existent"))
    }

    func testDeleteFolderCascadesSnippets() throws {
        let folder = try db.createFolder(name: "Temp Folder")
        let s1 = try db.createSnippet(folderId: folder.id, content: "Snippet 1")
        let s2 = try db.createSnippet(folderId: folder.id, content: "Snippet 2")

        var snippets = try db.listSnippets(folderId: folder.id)
        XCTAssertEqual(snippets.count, 2)

        try db.deleteFolder(id: folder.id)

        let folders = try db.listFolders()
        XCTAssertTrue(folders.isEmpty)

        snippets = try db.listSnippets(folderId: folder.id)
        XCTAssertTrue(snippets.isEmpty)

        // Verify FTS virtual table also cleaned up
        let searchResults = try db.searchSnippets(query: "Snippet", limit: 10)
        XCTAssertTrue(searchResults.isEmpty)
    }

    func testReorderFolders() throws {
        let f1 = try db.createFolder(name: "First")
        let f2 = try db.createFolder(name: "Second")
        let f3 = try db.createFolder(name: "Third")

        try db.reorderFolders(order: [f3.id, f1.id, f2.id])

        let folders = try db.listFolders()
        XCTAssertEqual(folders.count, 3)
        XCTAssertEqual(folders[0].id, f3.id)
        XCTAssertEqual(folders[0].position, 0)
        XCTAssertEqual(folders[1].id, f1.id)
        XCTAssertEqual(folders[1].position, 1)
        XCTAssertEqual(folders[2].id, f2.id)
        XCTAssertEqual(folders[2].position, 2)
    }

    // MARK: - Snippets Tests

    func testCreateAndListSnippets() throws {
        let folder = try db.createFolder(name: "General")
        let s1 = try db.createSnippet(folderId: folder.id, content: "Hello World")
        XCTAssertEqual(s1.position, 0)
        XCTAssertEqual(s1.content, "Hello World")
        XCTAssertNotNil(s1.createdAt)

        let s2 = try db.createSnippet(folderId: folder.id, content: "Second Item")
        XCTAssertEqual(s2.position, 1)

        let list = try db.listSnippets(folderId: folder.id)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].id, s1.id)
        XCTAssertEqual(list[1].id, s2.id)

        // Verify snippet count in folder summary
        let folders = try db.listFolders()
        XCTAssertEqual(folders[0].snippetCount, 2)
    }

    func testListFoldersWithSnippets() throws {
        let f1 = try db.createFolder(name: "Folder 1")
        let f2 = try db.createFolder(name: "Folder 2")

        _ = try db.createSnippet(folderId: f1.id, content: "S1")
        _ = try db.createSnippet(folderId: f1.id, content: "S2")
        _ = try db.createSnippet(folderId: f2.id, content: "S3")

        let combined = try db.listFoldersWithSnippets()
        XCTAssertEqual(combined.count, 2)
        XCTAssertEqual(combined[0].id, f1.id)
        XCTAssertEqual(combined[0].snippets.count, 2)
        XCTAssertEqual(combined[0].snippets[0].content, "S1")
        XCTAssertEqual(combined[0].snippets[1].content, "S2")

        XCTAssertEqual(combined[1].id, f2.id)
        XCTAssertEqual(combined[1].snippets.count, 1)
        XCTAssertEqual(combined[1].snippets[0].content, "S3")
    }

    func testUpdateSnippet() throws {
        let folder = try db.createFolder(name: "Notes")
        let s = try db.createSnippet(folderId: folder.id, content: "Initial content")

        try db.updateSnippet(id: s.id, content: "Updated content")

        let snippets = try db.listSnippets(folderId: folder.id)
        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets[0].content, "Updated content")

        XCTAssertThrowsError(try db.updateSnippet(id: 99999, content: "Nothing"))
    }

    func testDeleteSnippet() throws {
        let folder = try db.createFolder(name: "Notes")
        let s = try db.createSnippet(folderId: folder.id, content: "To be deleted")

        try db.deleteSnippet(id: s.id)

        let snippets = try db.listSnippets(folderId: folder.id)
        XCTAssertTrue(snippets.isEmpty)

        XCTAssertThrowsError(try db.deleteSnippet(id: s.id))
    }

    func testMoveSnippet() throws {
        let f1 = try db.createFolder(name: "Folder A")
        let f2 = try db.createFolder(name: "Folder B")

        _ = try db.createSnippet(folderId: f2.id, content: "Existing B1")
        let sToMove = try db.createSnippet(folderId: f1.id, content: "Moving snippet")

        try db.moveSnippet(id: sToMove.id, targetFolderId: f2.id)

        let f1Snippets = try db.listSnippets(folderId: f1.id)
        XCTAssertTrue(f1Snippets.isEmpty)

        let f2Snippets = try db.listSnippets(folderId: f2.id)
        XCTAssertEqual(f2Snippets.count, 2)
        XCTAssertEqual(f2Snippets[1].id, sToMove.id)
        XCTAssertEqual(f2Snippets[1].folderId, f2.id)
        XCTAssertEqual(f2Snippets[1].position, 1)

        XCTAssertThrowsError(try db.moveSnippet(id: sToMove.id, targetFolderId: 99999))
    }

    func testReorderSnippets() throws {
        let folder = try db.createFolder(name: "Reorder Test")
        let s1 = try db.createSnippet(folderId: folder.id, content: "Item 1")
        let s2 = try db.createSnippet(folderId: folder.id, content: "Item 2")
        let s3 = try db.createSnippet(folderId: folder.id, content: "Item 3")

        try db.reorderSnippets(folderId: folder.id, order: [s3.id, s1.id, s2.id])

        let snippets = try db.listSnippets(folderId: folder.id)
        XCTAssertEqual(snippets.count, 3)
        XCTAssertEqual(snippets[0].id, s3.id)
        XCTAssertEqual(snippets[0].position, 0)
        XCTAssertEqual(snippets[1].id, s1.id)
        XCTAssertEqual(snippets[1].position, 1)
        XCTAssertEqual(snippets[2].id, s2.id)
        XCTAssertEqual(snippets[2].position, 2)
    }

    // MARK: - Search Tests (FTS5 + LIKE)

    func testSearchSnippets() throws {
        let f1 = try db.createFolder(name: "Emails")
        let f2 = try db.createFolder(name: "Code")

        _ = try db.createSnippet(folderId: f1.id, content: "Dear John, please find the attached report.")
        _ = try db.createSnippet(folderId: f1.id, content: "Quick brown fox jumps over the lazy dog.")
        _ = try db.createSnippet(folderId: f2.id, content: "function sendReport() { return true; }")

        let reportResults = try db.searchSnippets(query: "report", limit: 10)
        XCTAssertEqual(reportResults.count, 2)
        XCTAssertTrue(reportResults.contains { $0.folderName == "Emails" })
        XCTAssertTrue(reportResults.contains { $0.folderName == "Code" })

        let foxResults = try db.searchSnippets(query: "fox", limit: 10)
        XCTAssertEqual(foxResults.count, 1)
        XCTAssertEqual(foxResults.first?.folderName, "Emails")

        let emptyResults = try db.searchSnippets(query: "nonexistentkeywordxyz", limit: 10)
        XCTAssertTrue(emptyResults.isEmpty)

        let whitespaceResults = try db.searchSnippets(query: "   ", limit: 10)
        XCTAssertTrue(whitespaceResults.isEmpty)
    }

    func testSearchAfterSnippetUpdate() throws {
        let folder = try db.createFolder(name: "Testing")
        let snippet = try db.createSnippet(folderId: folder.id, content: "Original alpha beta")

        var results = try db.searchSnippets(query: "alpha", limit: 10)
        XCTAssertEqual(results.count, 1)

        try db.updateSnippet(id: snippet.id, content: "Updated gamma delta")

        results = try db.searchSnippets(query: "alpha", limit: 10)
        XCTAssertTrue(results.isEmpty)

        results = try db.searchSnippets(query: "gamma", limit: 10)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Settings Tests

    func testSettingsGetAndSet() throws {
        let initial = try db.getSetting(key: "primary_provider")
        XCTAssertNil(initial)

        try db.setSetting(key: "primary_provider", value: "Google")
        let updated = try db.getSetting(key: "primary_provider")
        XCTAssertEqual(updated, "Google")

        try db.setSetting(key: "primary_provider", value: "Yandex")
        let overridden = try db.getSetting(key: "primary_provider")
        XCTAssertEqual(overridden, "Yandex")
    }
}
