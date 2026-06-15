import AVFoundation
import Foundation

enum SoundEvent: String, CaseIterable {
    case sessionStart = "session-start"
    case sessionEnd = "session-end"
    case toolUse = "tool-use"
    case completion = "completion"
    case error = "error"
    case approvalNeeded = "approval-needed"
    case approvalGranted = "approval-granted"
    case approvalDenied = "approval-denied"
}

final class SoundEngine {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var soundBuffers: [SoundEvent: AVAudioPCMBuffer] = [:]
    private var enabled = true
    private var volume: Float = 0.7
    private var disabledEvents: Set<SoundEvent> = []
    /// event.rawValue → "default" | "off" | "<library filename>".
    private var assignments: [String: String] = [:]

    init() {
        setupAudioEngine()
        loadSounds()
    }

    func play(_ event: SessionEvent) {
        guard enabled else { return }
        let soundEvent: SoundEvent? = {
            switch event {
            case .sessionStarted: return .sessionStart
            case .sessionEnded: return .sessionEnd
            case .toolStarted: return .toolUse
            case .statusChanged(_, let status) where status == .idle: return .completion
            case .statusChanged(_, let status) where status == .error: return .error
            case .permissionRequested: return .approvalNeeded
            case .permissionResponded(_, let allowed): return allowed ? .approvalGranted : .approvalDenied
            default: return nil
            }
        }()

        guard let soundEvent, !disabledEvents.contains(soundEvent),
              let buffer = soundBuffers[soundEvent] else { return }
        playBuffer(buffer)
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    func setVolume(_ volume: Float) {
        self.volume = max(0, min(1, volume))
        playerNode?.volume = self.volume
    }

    /// Apply the per-event assignment map (Default / Off / a library file) and
    /// rebuild the buffers.
    func applyAssignments(_ map: [String: String]) {
        assignments = map
        loadSounds()
    }

    /// Play an event's currently-assigned sound regardless of enabled/off state
    /// (used by the ▶ preview buttons in Settings).
    func preview(_ event: SoundEvent) {
        if let buffer = soundBuffers[event] { playBuffer(buffer) }
    }

    /// Play a specific library file (preview a "My Sounds" entry).
    func previewFile(_ filename: String) {
        let url = customSoundsDirectory().appendingPathComponent(filename)
        if let buffer = loadAudioFile(url) { playBuffer(buffer) }
    }

    // MARK: - Audio Engine

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = playerNode else { return }
        engine.attach(player)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            player.volume = volume
        } catch {
            print("[CodeIsland] Audio engine failed to start: \(error)")
        }
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let player = playerNode, audioEngine?.isRunning == true else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    // MARK: - Sound Loading

    private func loadSounds() {
        let synth = SoundSynthesizer()
        let dir = customSoundsDirectory()
        let supportedExts = ["wav", "mp3", "m4a", "aiff", "caf"]
        disabledEvents = []

        for event in SoundEvent.allCases {
            let choice = assignments[event.rawValue] ?? "default"
            if choice == "off" { disabledEvents.insert(event) }

            // 1. An explicitly-assigned library file.
            if choice != "default", choice != "off" {
                let url = dir.appendingPathComponent(choice)
                if FileManager.default.fileExists(atPath: url.path), let b = loadAudioFile(url) {
                    soundBuffers[event] = b
                    continue
                }
            }
            // 2. "default": a legacy file named after the event, else the synth.
            var buffer: AVAudioPCMBuffer?
            for ext in supportedExts {
                let url = dir.appendingPathComponent("\(event.rawValue).\(ext)")
                if FileManager.default.fileExists(atPath: url.path), let b = loadAudioFile(url) {
                    buffer = b; break
                }
            }
            soundBuffers[event] = buffer ?? synth.generateSound(for: event)
        }
    }

    /// Reload all sounds — call after the user drops new files in the sound-packs dir.
    func reloadSounds() {
        soundBuffers.removeAll()
        loadSounds()
    }

    private func customSoundsDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".code-island/sound-packs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadAudioFile(_ url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url),
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else {
            return nil
        }
        do { try file.read(into: srcBuffer) } catch {
            print("[CodeIsland] Failed to read audio file \(url.lastPathComponent): \(error)")
            return nil
        }

        // Convert to the engine's standard format (mono 44.1kHz) so it plays
        // through our existing AVAudioPlayerNode connection.
        guard let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            return srcBuffer
        }
        if srcBuffer.format.isEqual(targetFormat) { return srcBuffer }

        guard let converter = AVAudioConverter(from: srcBuffer.format, to: targetFormat) else {
            return srcBuffer
        }
        let ratio = targetFormat.sampleRate / srcBuffer.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(srcBuffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else {
            return srcBuffer
        }
        var done = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if done { status.pointee = .noDataNow; return nil }
            done = true
            status.pointee = .haveData
            return srcBuffer
        }
        var error: NSError?
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if let error {
            print("[CodeIsland] Audio convert failed: \(error.localizedDescription)")
            return srcBuffer
        }
        return outBuffer
    }
}
