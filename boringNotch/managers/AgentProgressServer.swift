//
//  AgentProgressServer.swift
//  boringNotch
//
//  F-25: shows AI coding agent (Claude Code, etc.) progress in the notch.
//  A local loopback HTTP listener, fed by shell hooks the user adds to their
//  agent's own hook config — see `AgentInstallSnippet.swift` for the exact
//  command.
//
//  Scoping note vs the plan: the plan's default design was a Unix domain
//  socket at `~/Library/Application Support/BoringNotch/agent.sock`. That
//  path is unreachable as written — the app is sandboxed, so that literal
//  path resolves inside `~/Library/Containers/<bundle-id>/...`, which an
//  external, unsandboxed `claude` CLI process has no standing access to.
//  Making the real path reachable needs either a one-time folder-access
//  grant (an `NSOpenPanel` + security-scoped bookmark, the same pattern
//  `ScreenshotManager.needsFolderAccess` already uses) or writing outside the
//  container via the always-unsandboxed XPC helper — both real, but more
//  work than fits this pass. A **fixed** loopback TCP port sidesteps the
//  whole container boundary: neither side needs to discover anything on
//  disk, `com.apple.security.network.server` is already granted, and the
//  well-known-file design in the plan turns out to be solving a problem this
//  approach doesn't have. The tradeoff is a fixed port can collide with
//  something else on the machine — acceptable for a v1, worth reconsidering
//  if it turns out to matter in practice.
//
//  Nothing here has been exercised against a live Claude Code hook firing —
//  there was no way to do that in this environment. The HTTP parsing is
//  deliberately minimal and defensive (any malformed request just drops the
//  connection), but treat this as needing a real end-to-end check before
//  relying on it.
//

import Combine
import Defaults
import Foundation
import Network

struct AgentStatus: Identifiable, Equatable {
    let id: String
    var agentName: String
    var state: String
    var toolName: String?
    var updatedAt: Date
}

@MainActor
final class AgentProgressServer: ObservableObject {
    static let shared = AgentProgressServer()

    /// Fixed rather than discovered — see the file header. High enough to
    /// be unlikely to collide with anything else already listening locally.
    static let port: UInt16 = 47921

    @Published private(set) var activeAgents: [AgentStatus] = []
    @Published private(set) var isListening = false

    private var listener: NWListener?
    private var cancellables = Set<AnyCancellable>()
    private var heartbeatTask: Task<Void, Never>?
    private static let staleAfter: TimeInterval = 30

    private init() {
        Defaults.publisher(.agentProgressEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    change.newValue ? self?.start() : self?.stop()
                }
            }
            .store(in: &cancellables)

        if Defaults[.agentProgressEnabled] {
            start()
        }
    }

    func start() {
        stop()

        guard let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        parameters.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: parameters, on: port) else {
            NSLog("⚠️ AgentProgressServer: could not bind 127.0.0.1:\(Self.port)")
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.isListening = (state == .ready)
            }
        }
        listener.start(queue: .main)
        self.listener = listener

        startHeartbeat()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        activeAgents = []
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffered: Data())
    }

    /// Reads until it can find a `Content-Length` header and that many body
    /// bytes, or gives up. No chunked transfer support — hook commands post
    /// a single small JSON body, not a stream.
    private func receive(on connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buffer = buffered
            if let data {
                buffer.append(data)
            }

            if let bodyRange = Self.completeBodyRange(in: buffer) {
                self.handleBody(buffer.subdata(in: bodyRange))
                Self.respondOK(on: connection)
                connection.cancel()
                return
            }

            guard buffer.count < 64 * 1024 else {
                connection.cancel()
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            self.receive(on: connection, buffered: buffer)
        }
    }

    /// Finds the JSON body's byte range once the full `Content-Length` worth
    /// of it has arrived, or `nil` if the headers or body aren't complete yet.
    private static func completeBodyRange(in buffer: Data) -> Range<Data.Index>? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        var contentLength = 0
        for line in headerString.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            guard lower.hasPrefix("content-length:") else { continue }
            let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            contentLength = Int(value) ?? 0
        }

        let bodyStart = headerEnd.upperBound
        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength, limitedBy: buffer.endIndex) ?? buffer.endIndex
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= contentLength else { return nil }
        return bodyStart..<bodyEnd
    }

    private static func respondOK(on connection: NWConnection) {
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
    }

    // MARK: - Payload handling

    /// Deliberately tolerant field names: hook payload shape varies by tool
    /// and event type, and this has not been checked against a live hook
    /// firing (see file header) — every field but the two used as an
    /// identity key is optional, and an unparseable body is silently
    /// dropped rather than crashing the connection handler.
    private func handleBody(_ body: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return }

        let sessionID = (json["session_id"] as? String) ?? (json["session"] as? String) ?? "unknown"
        let agentName = (json["agent"] as? String) ?? "Agent"
        let eventName = (json["hook_event_name"] as? String) ?? (json["state"] as? String) ?? "update"
        let toolName = json["tool_name"] as? String

        if eventName == "Stop" || eventName == "SubagentStop" {
            activeAgents.removeAll { $0.id == sessionID }
            return
        }

        let status = AgentStatus(
            id: sessionID,
            agentName: agentName,
            state: Self.friendlyState(for: eventName),
            toolName: toolName,
            updatedAt: Date()
        )

        if let index = activeAgents.firstIndex(where: { $0.id == sessionID }) {
            activeAgents[index] = status
        } else {
            activeAgents.append(status)
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .agentProgress)
        }
    }

    private static func friendlyState(for eventName: String) -> String {
        switch eventName {
        case "PreToolUse": return NSLocalizedString("agent_state_running_tool", comment: "Agent is running a tool")
        case "PostToolUse": return NSLocalizedString("agent_state_thinking", comment: "Agent is thinking")
        case "Notification": return NSLocalizedString("agent_state_waiting", comment: "Agent is waiting on the user")
        default: return NSLocalizedString("agent_state_active", comment: "Agent is active")
        }
    }

    // MARK: - Heartbeat expiry

    /// A killed agent's session never sends `Stop` — this clears it a
    /// heartbeat-timeout after the last event instead.
    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                let cutoff = Date().addingTimeInterval(-Self.staleAfter)
                self.activeAgents.removeAll { $0.updatedAt < cutoff }
            }
        }
    }
}
