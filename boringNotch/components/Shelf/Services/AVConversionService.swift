//
//  AVConversionService.swift
//  boringNotch
//
//  F-42: audio/video conversion, the half of F-42 `ImageProcessingService`
//  doesn't cover (that file already ships image format conversion,
//  background removal and PDF creation — F-41 and half of F-42 shipped
//  earlier). Uses `AVAssetExportSession` presets, never ffmpeg, per
//  CLAUDE.md's licensing rule.
//

import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct MediaConversionOptions {
    enum OutputFormat: String, CaseIterable {
        case mp4
        case mov
        case m4a

        var fileExtension: String { rawValue }

        var fileType: AVFileType {
            switch self {
            case .mp4: return .mp4
            case .mov: return .mov
            case .m4a: return .m4a
            }
        }

        var isAudioOnly: Bool { self == .m4a }
    }

    /// Label shown in the picker, paired with the `AVAssetExportSession`
    /// preset name it maps to.
    struct QualityOption {
        let label: String
        let preset: String
    }

    static let videoQualities: [QualityOption] = [
        QualityOption(label: "High Quality", preset: AVAssetExportPresetHighestQuality),
        QualityOption(label: "Medium Quality (720p)", preset: AVAssetExportPreset1280x720),
        QualityOption(label: "Low Quality (480p)", preset: AVAssetExportPreset640x480)
    ]

    static let audioQualities: [QualityOption] = [
        QualityOption(label: "High Quality", preset: AVAssetExportPresetAppleM4A)
    ]

    let format: OutputFormat
    let preset: String
}

@MainActor
final class AVConversionService {
    static let shared = AVConversionService()

    private init() {}

    func isAudioOrVideoFile(_ url: URL) -> Bool {
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return contentType.conforms(to: .audiovisualContent)
    }

    func isVideoFile(_ url: URL) -> Bool {
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return contentType.conforms(to: .movie)
    }

    func convertMedia(from url: URL, options: MediaConversionOptions) async throws -> URL? {
        let asset = AVURLAsset(url: url)

        guard let isReadable = try? await asset.load(.isReadable), isReadable else {
            throw MediaConversionError.invalidAsset
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: options.preset) else {
            throw MediaConversionError.unsupportedPreset
        }

        guard exportSession.supportedFileTypes.contains(options.format.fileType) else {
            throw MediaConversionError.unsupportedFormat
        }

        let originalName = url.deletingPathExtension().lastPathComponent
        let newName = "\(originalName)_converted.\(options.format.fileExtension)"

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let outputURL = tempDir.appendingPathComponent(newName)

        try await Self.runExport(exportSession, outputURL: outputURL, fileType: options.format.fileType)

        return outputURL
    }

    /// `export(to:as:)` replaces `export()`/`status`/`error` on macOS 15+;
    /// the deprecated trio is still fully functional and is the only path
    /// available on this project's macOS 14 minimum, so both are kept
    /// rather than taking an unsilenceable deprecation warning on the
    /// import target.
    private static func runExport(_ session: AVAssetExportSession, outputURL: URL, fileType: AVFileType) async throws {
        if #available(macOS 15.0, *) {
            do {
                try await session.export(to: outputURL, as: fileType)
            } catch {
                throw MediaConversionError.exportFailed(error.localizedDescription)
            }
        } else {
            session.outputURL = outputURL
            session.outputFileType = fileType
            await session.export()
            guard session.status == .completed else {
                let message = session.error?.localizedDescription ?? "Export did not complete"
                throw MediaConversionError.exportFailed(message)
            }
        }
    }
}

enum MediaConversionError: LocalizedError {
    case invalidAsset
    case unsupportedPreset
    case unsupportedFormat
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAsset:
            return NSLocalizedString("media_convert_error_invalid", comment: "Media conversion: source file could not be read")
        case .unsupportedPreset:
            return NSLocalizedString("media_convert_error_preset", comment: "Media conversion: preset not supported for this asset")
        case .unsupportedFormat:
            return NSLocalizedString("media_convert_error_format", comment: "Media conversion: output format not supported for this asset")
        case .exportFailed(let message):
            return message
        }
    }
}
