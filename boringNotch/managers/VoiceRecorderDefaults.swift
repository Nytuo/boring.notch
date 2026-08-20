//
//  VoiceRecorderDefaults.swift
//  boringNotch
//

import Defaults

extension Defaults.Keys {
    static let voiceRecorderEnabled = Key<Bool>("voiceRecorderEnabled", default: false)
    static let voiceRecorderAutoTranscribe = Key<Bool>("voiceRecorderAutoTranscribe", default: true)
}
