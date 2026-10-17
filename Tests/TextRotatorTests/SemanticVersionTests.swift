import XCTest
@testable import TextRotatorCore

final class SemanticVersionTests: XCTestCase {
    func testParsingValidVersions() {
        let v1 = SemanticVersion(string: "1.0.0")
        XCTAssertNotNil(v1)
        XCTAssertEqual(v1?.major, 1)
        XCTAssertEqual(v1?.minor, 0)
        XCTAssertEqual(v1?.patch, 0)
        XCTAssertNil(v1?.prerelease)

        let v2 = SemanticVersion(string: "v1.2.3")
        XCTAssertNotNil(v2)
        XCTAssertEqual(v2?.major, 1)
        XCTAssertEqual(v2?.minor, 2)
        XCTAssertEqual(v2?.patch, 3)

        let v3 = SemanticVersion(string: "2.0.1-beta.2")
        XCTAssertNotNil(v3)
        XCTAssertEqual(v3?.major, 2)
        XCTAssertEqual(v3?.minor, 0)
        XCTAssertEqual(v3?.patch, 1)
        XCTAssertEqual(v3?.prerelease, "beta.2")

        let v4 = SemanticVersion(string: "  V10.20.30  ")
        XCTAssertNotNil(v4)
        XCTAssertEqual(v4?.major, 10)
        XCTAssertEqual(v4?.minor, 20)
        XCTAssertEqual(v4?.patch, 30)
    }

    func testParsingInvalidVersions() {
        XCTAssertNil(SemanticVersion(string: ""))
        XCTAssertNil(SemanticVersion(string: "abc"))
        XCTAssertNil(SemanticVersion(string: "1"))
        XCTAssertNil(SemanticVersion(string: "invalid.version.number"))
    }

    func testVersionComparison() {
        let v100 = SemanticVersion(string: "1.0.0")!
        let v101 = SemanticVersion(string: "1.0.1")!
        let v110 = SemanticVersion(string: "1.1.0")!
        let v200 = SemanticVersion(string: "2.0.0")!

        XCTAssertTrue(v100 < v101)
        XCTAssertTrue(v101 < v110)
        XCTAssertTrue(v110 < v200)
        XCTAssertTrue(v200 > v100)
        XCTAssertEqual(v100, SemanticVersion(string: "v1.0.0"))

        let vBeta = SemanticVersion(string: "1.0.1-beta.1")!
        let vRelease = SemanticVersion(string: "1.0.1")!
        XCTAssertTrue(vBeta < vRelease)
    }
}
