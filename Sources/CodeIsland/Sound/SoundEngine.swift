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

    func setEventEnabled(_ event: SoundEvent, enabled: Bool) {
        if enabled {
            disabledEvents.remove(event)
        } else {
            disabledEvents.insert(event)
        }
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
        for event in SoundEvent.allCases {
            soundBuffers[event] = synth.generateSound(for: event)
        }
    }
}
