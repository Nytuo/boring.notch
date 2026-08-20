//
//  HelperLog.swift
//  BoringNotchXPCHelper
//
//  Minimal logging for the XPC helper target. `utils/Logger.swift` lives in
//  the main app target and isn't visible here, so the helper gets its own
//  tiny shim. Never pass argument values containing user content — operation
//  names only (F-01).
//

import Foundation

enum HelperLog {
    static func call(_ operation: String) {
        NSLog("[BoringNotchXPCHelper] call: \(operation)")
    }

    static func security(_ message: String) {
        NSLog("[BoringNotchXPCHelper][security] \(message)")
    }
}
