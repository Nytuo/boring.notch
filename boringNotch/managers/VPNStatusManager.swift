//
//  VPNStatusManager.swift
//  boringNotch
//
//  F-22: VPN connection status.
//
//  `NEVPNManager` is not usable here — reading another app's VPN connection
//  state through it requires the app itself to be a Personal VPN / Network
//  Extension provider, an entitlement Apple grants under separate review and
//  not available to a plain sandboxed app (CLAUDE.md: don't claim a
//  capability the platform doesn't support here). This uses the plan's own
//  stated fallback instead, promoted to the only path: `SCDynamicStore`
//  watching `State:/Network/Global/IPv4` for change notifications, cross-
//  checked against active `utun`/`ppp`/`ipsec` interfaces. That heuristic
//  can't identify *which* VPN app or provider is connected — only that a
//  VPN-shaped interface is up — so the UI shows the interface name, not a
//  provider name, and never guesses one.
//

import Combine
import Defaults
import Foundation
import SystemConfiguration

@MainActor
final class VPNStatusManager: NSObject, ObservableObject {
    static let shared = VPNStatusManager()

    @Published private(set) var isConnected = false
    @Published private(set) var interfaceName: String?
    @Published private(set) var connectedSince: Date?

    private var dynamicStore: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        Defaults.publisher(.vpnStatusEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    change.newValue ? self?.start() : self?.stop()
                }
            }
            .store(in: &cancellables)

        if Defaults[.vpnStatusEnabled] {
            start()
        }
    }

    func start() {
        stop()
        refresh()
        setupDynamicStore()
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        dynamicStore = nil
        isConnected = false
        interfaceName = nil
        connectedSince = nil
    }

    private func setupDynamicStore() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let store = SCDynamicStoreCreate(nil, "BoringNotchVPNStatus" as CFString, { _, _, info in
            guard let info else { return }
            let manager = Unmanaged<VPNStatusManager>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in manager.refresh() }
        }, &context) else { return }

        dynamicStore = store
        SCDynamicStoreSetNotificationKeys(store, ["State:/Network/Global/IPv4"] as CFArray, nil)

        guard let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func refresh() {
        let wasConnected = isConnected
        let (connected, name) = Self.currentVPNInterface()
        isConnected = connected
        interfaceName = name

        if connected {
            if !wasConnected {
                connectedSince = Date()
                BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .vpn)
            }
        } else {
            connectedSince = nil
        }
    }

    private static let vpnInterfacePrefixes = ["utun", "ppp", "ipsec"]

    private static func currentVPNInterface() -> (Bool, String?) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (false, nil) }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let name = String(cString: current.pointee.ifa_name)
            let isUp = (Int32(current.pointee.ifa_flags) & IFF_UP) != 0
            if isUp && vpnInterfacePrefixes.contains(where: { name.hasPrefix($0) }) {
                return (true, name)
            }
            pointer = current.pointee.ifa_next
        }
        return (false, nil)
    }
}
