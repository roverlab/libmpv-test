import XCTest
@testable import TestApp
// TestApp re-exports Libmpv, so this implicitly tests `import Libmpv`

final class LibmpvTests: XCTestCase {

    func testImportLibmpvResolves() {
        // If this test compiles and runs, `import Libmpv` works correctly.
        // This catches the "Unable to find module dependency: 'Libmpv'" error.
        print("✅ import Libmpv resolved successfully")
    }

    func testMPVClientAPIVersion() {
        let version = testMPVVersion()
        // mpv_client_api_version() should return a non-zero value
        // Format: (major << 16) | (minor << 8) | patch
        XCTAssertGreaterThan(version, 0, "mpv_client_api_version() should return > 0, got \(version)")
        print("✅ mpv client API version: \(version)")
    }

    func testMPVCreateHandle() {
        let created = testMPVCreate()
        XCTAssertTrue(created, "mpv_create() should return a non-null handle")
        print("✅ mpv_create() returned valid handle")
    }

    func testMPVInitializeAndDestroy() {
        if #available(iOS 13, *) {
            let success = testMPVInitialize()
            XCTAssertTrue(success, "mpv initialization (create + set option + initialize + destroy) should succeed")
            print("✅ mpv full lifecycle test passed")
        }
    }
}
