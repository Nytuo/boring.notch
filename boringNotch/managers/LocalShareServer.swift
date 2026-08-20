//
//  LocalShareServer.swift
//  boringNotch
//
//  F-51: share links, local/LAN only — the plan's default, no-account tier.
//  A short-lived local HTTP server, one file at a time, behind a random
//  unguessable path token, on an OS-assigned port (not a fixed one — this
//  listens on every interface rather than loopback, since other devices on
//  the LAN need to reach it, so an unpredictable port is worth it where
//  AgentProgressServer's fixed loopback-only port wasn't). Auto-expires;
//  the token and the listener both go away together, whichever ends first.
//
//  "Bring your own storage" (S3/WebDAV/SCP) and "hosted" are out of scope —
//  this is the local tier only.
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Network
import UniformTypeIdentifiers

@MainActor
final class LocalShareServer: ObservableObject {
    static let shared = LocalShareServer()

    struct ActiveShare {
        let token: String
        let fileURL: URL
        let fileName: String
        let expiresAt: Date
    }

    @Published private(set) var activeShare: ActiveShare?
    @Published private(set) var shareURL: URL?

    private var listener: NWListener?
    private var expiryTask: Task<Void, Never>?
    private var securityScopedURL: URL?

    private init() {}

    /// Starts serving `fileURL` and returns the shareable URL, or `nil` if
    /// the server couldn't start (no LAN address, couldn't bind).
    func startSharing(fileURL: URL, duration: TimeInterval = 600) async -> URL? {
        stopSharing()

        guard let lanAddress = Self.currentLANAddress() else { return nil }

        let accessed = fileURL.startAccessingSecurityScopedResource()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: parameters) else {
            if accessed { fileURL.stopAccessingSecurityScopedResource() }
            return nil
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }

        let port: UInt16? = await withCheckedContinuation { continuation in
            let resumeOnce = ResumeOnce(continuation: continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce.resume(with: listener.port?.rawValue)
                case .failed, .cancelled:
                    resumeOnce.resume(with: nil)
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }

        guard let port else {
            if accessed { fileURL.stopAccessingSecurityScopedResource() }
            return nil
        }

        let token = Self.randomToken()
        let fileName = fileURL.lastPathComponent
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName

        guard let url = URL(string: "http://\(lanAddress):\(port)/\(token)/\(encodedName)") else {
            listener.cancel()
            if accessed { fileURL.stopAccessingSecurityScopedResource() }
            return nil
        }

        self.listener = listener
        if accessed { securityScopedURL = fileURL }

        let expiresAt = Date().addingTimeInterval(duration)
        activeShare = ActiveShare(token: token, fileURL: fileURL, fileName: fileName, expiresAt: expiresAt)
        shareURL = url

        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.stopSharing()
        }

        return url
    }

    func stopSharing() {
        listener?.cancel()
        listener = nil
        expiryTask?.cancel()
        expiryTask = nil
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        activeShare = nil
        shareURL = nil
    }

    // MARK: - HTTP (GET only — this only ever needs to hand back one file)

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveRequest(on: connection, buffered: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buffer = buffered
            if let data {
                buffer.append(data)
            }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
                self.handleRequest(headerData, on: connection)
                return
            }

            guard buffer.count < 8192, !(isComplete || error != nil) else {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, buffered: buffer)
        }
    }

    private func handleRequest(_ headerData: Data, on connection: NWConnection) {
        guard let headerString = String(data: headerData, encoding: .utf8),
              let requestLine = headerString.components(separatedBy: "\r\n").first,
              let path = requestLine.components(separatedBy: " ").dropFirst().first
        else {
            respond(status: "404 Not Found", body: "Not found", on: connection)
            return
        }

        guard let share = activeShare else {
            respond(status: "404 Not Found", body: "This share has ended.", on: connection)
            return
        }

        let encodedName = share.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? share.fileName
        guard path == "/\(share.token)/\(encodedName)" else {
            respond(status: "404 Not Found", body: "Not found", on: connection)
            return
        }

        guard let fileData = try? Data(contentsOf: share.fileURL) else {
            respond(status: "404 Not Found", body: "Could not read the file.", on: connection)
            return
        }

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(Self.mimeType(for: share.fileURL))\r\n"
        header += "Content-Length: \(fileData.count)\r\n"
        header += "Content-Disposition: attachment; filename=\"\(share.fileName)\"\r\n"
        header += "Connection: close\r\n\r\n"

        var response = Data(header.utf8)
        response.append(fileData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func respond(status: String, body: String, on connection: NWConnection) {
        let html = "<html><body>\(body)</body></html>"
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((header + html).utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Helpers

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    /// First `en*` interface with an IPv4 address that's up — Wi-Fi/Ethernet,
    /// not loopback or a VPN tunnel. No existing code in this codebase
    /// extracts an actual address from `getifaddrs` (the other two callers
    /// only check flags/name or link-layer stats), so this is new.
    private static func currentLANAddress() -> String? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else { return nil }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en"), (Int32(interface.ifa_flags) & IFF_UP) != 0 else { continue }
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard status == 0 else { continue }
            return String(cString: host)
        }
        return nil
    }
}

/// Guards a `CheckedContinuation` against being resumed twice — Network's
/// `stateUpdateHandler` isn't guaranteed to fire only once, and this class
/// (not a captured `var`) is what makes that safe to check from whatever
/// queue the handler runs on.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false
    private let continuation: CheckedContinuation<UInt16?, Never>

    init(continuation: CheckedContinuation<UInt16?, Never>) {
        self.continuation = continuation
    }

    func resume(with value: UInt16?) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: value)
    }
}

enum QRCodeGenerator {
    static func image(for text: String, scale: CGFloat = 8) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: transformed.extent.width, height: transformed.extent.height))
    }
}
