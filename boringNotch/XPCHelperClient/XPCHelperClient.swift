import Foundation
import Cocoa
import Combine
import Defaults
import AsyncXPCConnection

/// Receives `keystrokeDidOccur`'s pitch bucket. Kept separate from
/// `BoringNotchXPCHelperLunarListener` so a keystroke-sounds consumer
/// doesn't need to also implement Lunar's methods.
protocol KeystrokeEventReceiver: AnyObject {
    func keystrokeDidOccur(pitchIndex: Int)
}

/// The one object actually exported on the connection's listener interface
/// — see the doc comment on `BoringNotchXPCHelperLunarListener` for why.
/// Fans each callback out to whichever real delegate is registered, so
/// Lunar and keystroke sounds can both be active without either silently
/// overwriting the other's registration.
final class CombinedHelperListener: NSObject, BoringNotchXPCHelperLunarListener {
    weak var lunarDelegate: BoringNotchXPCHelperLunarListener?
    weak var keystrokeDelegate: KeystrokeEventReceiver?

    func lunarEventDidUpdate(_ event: BNLunarBrightnessEvent) {
        lunarDelegate?.lunarEventDidUpdate(event)
    }

    func lunarStreamDidStop(_ reason: String?) {
        lunarDelegate?.lunarStreamDidStop(reason)
    }

    func keystrokeDidOccur(_ pitchIndex: Int32) {
        keystrokeDelegate?.keystrokeDidOccur(pitchIndex: Int(pitchIndex))
    }
}

final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()

    private let serviceName = "theboringteam.boringnotch.BoringNotchXPCHelper"

    private var remoteService: RemoteXPCService<BoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    /// `BoringNotchXPCHelperLunarListener` is the connection's one callback
    /// interface — `NSXPCConnection` only supports a single
    /// `exportedObject`/`remoteObjectInterface` pair, so F-32's keystroke
    /// callback rides the same channel rather than fighting for it. This
    /// object is always the one actually exported; it fans each callback out
    /// to whichever real delegate (Lunar, keystroke sounds) is currently
    /// registered, so the two features don't silently steal the channel from
    /// each other by both calling `ensureRemoteService(needsListener: true)`.
    private let combinedListener = CombinedHelperListener()
    private var hasListener: Bool = false
    private var capabilityObservers: Set<AnyCancellable> = []

    override init() {
        super.init()
        Task { @MainActor [weak self] in
            self?.observeCapabilityChanges()
        }
    }

    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }

    // MARK: - Capability gating (F-01)

    /// Pushes the current capability toggles to the helper. Called on every
    /// fresh connection and whenever a toggle changes, since the unsandboxed
    /// helper can't read the sandboxed app's `Defaults` store itself.
    nonisolated private func pushCapabilities() {
        Task {
            let service = await MainActor.run { ensureRemoteService() }
            let settings = HelperCapabilitySettings.current
            _ = try? await service.withContinuation { service, continuation in
                service.updateCapabilities(settings) { ok in
                    continuation.resume(returning: ok)
                }
            }
        }
    }

    @MainActor
    private func observeCapabilityChanges() {
        Defaults.publisher(keys: .capabilityAxWindowsEnabled, .capabilityAxNotificationsEnabled, .capabilityInputEnabled, .capabilityPtyEnabled, .capabilityPowerEnabled)
            .sink { [weak self] _ in
                self?.pushCapabilities()
            }
            .store(in: &capabilityObservers)
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService(needsListener: Bool = false) -> RemoteXPCService<BoringNotchXPCHelperProtocol> {
        if let existing = remoteService, (!needsListener || hasListener) {
            return existing
        }

        if let connection {
            connection.invalidate()
            self.connection = nil
            self.remoteService = nil
        }

        let conn = NSXPCConnection(serviceName: serviceName)

        if needsListener {
            let listenerInterface = makeLunarListenerInterface()
            conn.exportedInterface = listenerInterface
            conn.exportedObject = combinedListener
            hasListener = true
        } else {
            hasListener = false
        }

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
                self?.hasListener = false
            }
        }

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
                self?.hasListener = false
            }
        }
        
        conn.resume()
        
        let service = RemoteXPCService<BoringNotchXPCHelperProtocol>(
            connection: conn,
            remoteInterface: BoringNotchXPCHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        pushCapabilities()
        return service
    }
    
    @MainActor
    private func getRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol>? {
        remoteService
    }

    private func makeLunarListenerInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: (any BoringNotchXPCHelperLunarListener).self)
        interface.setClasses(
            NSSet(array: [BNLunarBrightnessEvent.self]) as! Set<AnyHashable>,
            for: #selector(BoringNotchXPCHelperLunarListener.lunarEventDidUpdate(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        return interface
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            try? await service.withService { service in
                service.requestAccessibilityAuthorization()
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }

    nonisolated func displayIDForBrightness() async -> CGDirectDisplayID? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.displayIDForBrightness(with: { value in
                    continuation.resume(returning: value)
                })
            }
            guard let num = result else { return nil }
            return CGDirectDisplayID(num.uint32Value)
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    nonisolated func adjustScreenBrightness(by value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.adjustScreenBrightness(by: value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }

    // MARK: - Lunar Events

    nonisolated func isLunarAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isLunarAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func startLunarEventStream(listener: BoringNotchXPCHelperLunarListener) async -> Bool {
        await MainActor.run {
            combinedListener.lunarDelegate = listener
        }
        do {
            let service = await MainActor.run {
                ensureRemoteService(needsListener: true)
            }
            return try await service.withContinuation { service, continuation in
                service.startLunarEventStream { started in
                    continuation.resume(returning: started)
                }
            }
        } catch {
            return false
        }
    }

    // MARK: - Keystroke observer (F-32)

    nonisolated func startKeystrokeObserver(receiver: KeystrokeEventReceiver) async -> Bool {
        await MainActor.run {
            combinedListener.keystrokeDelegate = receiver
        }
        do {
            let service = await MainActor.run {
                ensureRemoteService(needsListener: true)
            }
            return try await service.withContinuation { service, continuation in
                service.startKeystrokeObserver { started in
                    continuation.resume(returning: started)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func setKeystrokeExcludedApps(_ bundleIDs: [String]) async {
        do {
            let service = await MainActor.run {
                ensureRemoteService(needsListener: true)
            }
            try await service.withService { service in
                service.setKeystrokeExcludedApps(bundleIDs)
            }
        } catch {
            return
        }
    }

    nonisolated func stopKeystrokeObserver() async {
        await MainActor.run {
            combinedListener.keystrokeDelegate = nil
        }
        do {
            let service = await MainActor.run {
                ensureRemoteService(needsListener: true)
            }
            try await service.withService { service in
                service.stopKeystrokeObserver()
            }
        } catch {
            return
        }
    }

    nonisolated func stopLunarEventStream() async {
        do {
            let service = await MainActor.run {
                ensureRemoteService(needsListener: true)
            }
            try await service.withService { service in
                service.stopLunarEventStream()
            }
        } catch {
            return
        }
    }

    // MARK: - Window snapping (F-30)

    struct WindowSnapResult {
        let success: Bool
        /// The window's frame before this call changed it, in Quartz
        /// (top-left-origin) coordinates — re-send this to restore it.
        let previousFrame: CGRect
    }

    nonisolated func setFocusedWindowFrame(_ frame: CGRect) async -> WindowSnapResult? {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.setFocusedWindowFrame(frame.origin.x, frame.origin.y, frame.width, frame.height) { success, px, py, pw, ph in
                    continuation.resume(returning: WindowSnapResult(
                        success: success,
                        previousFrame: CGRect(x: px, y: py, width: pw, height: ph)
                    ))
                }
            }
        } catch {
            return nil
        }
    }

    // MARK: - Power (F-23)

    nonisolated func setLowPowerMode(_ enabled: Bool) async -> Bool {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.setLowPowerMode(enabled) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func setLunarOSDHidden(_ hide: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setLunarOSDHidden(hide) { ok in
                    continuation.resume(returning: ok)
                }
            }
        } catch {
            return false
        }
    }
}

