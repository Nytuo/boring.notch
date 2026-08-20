//
//  XPCClientValidator.swift
//  BoringNotchXPCHelper
//
//  F-01: the helper is unsandboxed and, until now, `shouldAcceptNewConnection`
//  accepted any incoming connection with no check at all. Every future
//  privileged capability (window control, keystroke posting, PTY spawn) turns
//  that into a local privilege-escalation primitive, so connections are now
//  validated before the helper exports anything to them.
//
//  The project currently builds ad-hoc (`DEVELOPMENT_TEAM = ""`,
//  `CODE_SIGN_IDENTITY = "-"` — see CLAUDE.md open decision on signing), so
//  there is no stable Team ID to hardcode into a requirement string. The
//  validator derives its requirement from the helper's own signing
//  information at runtime: if the helper is signed with a real Developer ID
//  (a future release build), it pins the connecting client to that team and
//  bundle identifier; otherwise it falls back to a bundle-identifier-only
//  check, which still blocks any process that isn't the shipped app but
//  cannot fully defend against a resigned ad-hoc copy. That gap closes when
//  the project adopts a stable signing identity.
//

import Foundation
import Security

enum XPCClientValidator {
    /// Bundle identifier of the only client allowed to use this helper.
    private static let expectedBundleIdentifier = "theboringteam.boringnotch"

    /// `true` if the connecting process is authorized to use the helper.
    static func isConnectionAuthorized(_ connection: NSXPCConnection) -> Bool {
        #if DEBUG
        // Local unsigned dev builds have no meaningful code signature to
        // check against. Accept everything so debug builds keep working.
        return true
        #else
        return validate(pid: connection.processIdentifier)
        #endif
    }

    private static func validate(pid: pid_t) -> Bool {
        var guestCode: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode) == errSecSuccess,
              let guestCode else {
            HelperLog.security("Could not resolve SecCode for pid \(pid)")
            return false
        }

        // The guest's own signature must be intact.
        guard SecCodeCheckValidity(guestCode, [], nil) == errSecSuccess else {
            HelperLog.security("Guest pid \(pid) failed base signature validity check")
            return false
        }

        guard let requirement = makeRequirement() else {
            HelperLog.security("Could not build a client requirement to validate against")
            return false
        }

        let status = SecCodeCheckValidity(guestCode, [], requirement)
        if status != errSecSuccess {
            HelperLog.security("Guest pid \(pid) did not satisfy the client requirement (status \(status))")
        }
        return status == errSecSuccess
    }

    /// Builds the requirement the connecting client must satisfy. Pins to the
    /// helper's own Team Identifier when one exists (a signed release build);
    /// otherwise falls back to matching the app's bundle identifier only.
    private static func makeRequirement() -> SecRequirement? {
        if let teamID = ownTeamIdentifier() {
            let requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(expectedBundleIdentifier)\""
            var requirement: SecRequirement?
            if SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess {
                return requirement
            }
        }

        let fallback = "identifier \"\(expectedBundleIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(fallback as CFString, [], &requirement) == errSecSuccess else {
            return nil
        }
        return requirement
    }

    private static func ownTeamIdentifier() -> String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess, let staticCode else { return nil }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo) == errSecSuccess,
              let info = signingInfo as? [String: Any] else {
            return nil
        }

        guard let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String, !teamID.isEmpty else {
            return nil
        }
        return teamID
    }
}
