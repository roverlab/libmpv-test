import Libmpv

// This file verifies that `import Libmpv` resolves correctly.
// The test target will call the functions below at runtime on a simulator.

/// Test that mpv_create() returns a valid handle
public func testMPVCreate() -> Bool {
    let handle = mpv_create()
    return handle != nil
}

/// Test that mpv client API version is accessible
public func testMPVVersion() -> Int32 {
    return mpv_client_api_version()
}

/// Test mpv initialization and basic option setting
@available(iOS 13, *)
public func testMPVInitialize() -> Bool {
    guard let handle = mpv_create() else {
        return false
    }
    // Set a simple string option to verify the API is functional
    let result = mpv_set_option_string(handle, "vo", "null")
    if result < 0 {
        mpv_terminate_destroy(handle)
        return false
    }
    // Initialize the mpv instance
    let initResult = mpv_initialize(handle)
    if initResult < 0 {
        mpv_terminate_destroy(handle)
        return false
    }
    // Clean up
    mpv_terminate_destroy(handle)
    return true
}
