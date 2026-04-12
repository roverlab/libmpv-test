import Foundation
import UIKit
import Libmpv

// MARK: - MPV Error Types
public enum MPVError: Int32, Error {
    case success = 0
    case nomem = -1
    case uninitialized = -2
    case invalidParameter = -3
    case optionNotFound = -4
    case optionFormat = -5
    case optionError = -6
    case propertyNotFound = -7
    case propertyFormat = -8
    case propertyError = -9
    case propertyUnavailable = -10
    case command = -11
    
    public var localizedDescription: String {
        return String(cString: mpv_error_string(rawValue))
    }
}

// MARK: - MPV Handle Wrapper
open class MPVHandle {
    internal var handle: OpaquePointer?
    
    public init?() {
        guard let mpvHandle = mpv_create() else {
            return nil
        }
        self.handle = mpvHandle
    }
    
    deinit {
        if let handle = handle {
            mpv_terminate_destroy(handle)
        }
    }
    
    @discardableResult
    public func initialize() throws -> Bool {
        guard let handle = handle else { return false }
        let result = mpv_initialize(handle)
        if result == 0 {
            return true
        } else {
            throw MPVError(rawValue: result) ?? MPVError.command
        }
    }
    
    @discardableResult
    public func command(_ args: [String]) throws -> Bool {
        guard let handle = handle else { return false }
        
        let cArgs = args.map { $0.withCString { $0 } } + [nil]
        let result = mpv_command(handle, cArgs)
        
        if result == 0 {
            return true
        } else {
            throw MPVError(rawValue: result) ?? MPVError.command
        }
    }
    
    @discardableResult
    public func setProperty<T>(name: String, value: T, format: mpv_format = MPV_FORMAT_FLAG) throws -> Bool {
        guard let handle = handle else { return false }
        
        let result = mpv_set_property(handle, name, format, &value)
        if result == 0 {
            return true
        } else {
            throw MPVError(rawValue: result) ?? MPVError.propertyError
        }
    }
    
    public func waitEvent(timeout: Double = -1) -> UnsafePointer<mpv_event>? {
        guard let handle = handle else { return nil }
        let event = mpv_wait_event(handle, timeout)
        return event
    }
}

// MARK: - Test Player for compatibility
open class MPVTestPlayer {
    private var mpvHandle: MPVHandle?
    private var isInitialized = false
    
    public init() {
        mpvHandle = MPVHandle()
    }
    
    public func initialize() throws {
        guard let handle = mpvHandle else {
            throw MPVError.uninitialized
        }
        
        try handle.initialize()
        isInitialized = true
        
        // Basic mpv configuration
        try handle.command(["load-script=sw://mpv-interactive.lua"])
    }
    
    public func loadFile(_ path: String) throws {
        guard isInitialized else {
            throw MPVError.uninitialized
        }
        try mpvHandle?.command(["loadfile", path, "replace"])
    }
    
    public func pause() throws {
        guard isInitialized else {
            throw MPVError.uninitialized
        }
        try mpvHandle?.setProperty(name: "pause", value: true)
    }
    
    public func resume() throws {
        guard isInitialized else {
            throw MPVError.uninitialized
        }
        try mpvHandle?.setProperty(name: "pause", value: false)
    }
    
    public var isPlaying: Bool {
        return isInitialized
    }
}