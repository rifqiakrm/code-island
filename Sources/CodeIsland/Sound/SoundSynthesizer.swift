import AVFoundation
import Foundation

/// Generates 8-bit style sounds programmatically using square/triangle waves.
struct SoundSynthesizer {
    private let sampleRate: Double = 44100
    private let amplitude: Float = 0.3

    func generateSound(for event: SoundEvent) -> AVAudioPCMBuffer? {
        switch event {
        case .sessionStart:
            // Rising arpeggio: C5 → E5 → G5
            return arpeggio(frequencies: [523.25, 659.25, 783.99], noteDuration: 0.08, waveform: .square)

        case .sessionEnd:
            // Soft descending: G4 → E4 → C4
            return arpeggio(frequencies: [392.0, 329.63, 261.63], noteDuration: 0.1, waveform: .triangle)

        case .toolUse:
            // Quick blip
            return tone(frequency: 880, duration: 0.05, waveform: .square)

        case .completion:
            // Triumphant celebration: C5 → E5 → G5 → C6 (longer, more satisfying)
            return arpeggio(frequencies: [523.25, 659.25, 783.99, 1046.5], noteDuration: 0.12, waveform: .square)

        case .error:
            // Descending buzz: A4 → F4 → D4
            return arpeggio(frequencies: [440, 349.23, 293.66], noteDuration: 0.1, waveform: .sawtooth)

        case .approvalNeeded:
            // Question tone: rising two notes
            return arpeggio(frequencies: [440, 554.37], noteDuration: 0.12, waveform: .square)

        case .approvalGranted:
            // Happy confirmation: two quick ascending notes
            return arpeggio(frequencies: [523.25, 783.99], noteDuration: 0.06, waveform: .square)

        case .approvalDenied:
            // Low rejection buzz
            return tone(frequency: 220, duration: 0.15, waveform: .sawtooth)
        }
    }

    // MARK: - Waveform Generation

    enum Waveform {
        case square
        case triangle
        case sawtooth
    }

    private func tone(frequency: Double, duration: Double, waveform: Waveform) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let floatData = buffer.floatChannelData?[0] else { return nil }

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let phase = t * frequency
            let raw: Float

            switch waveform {
            case .square:
                raw = sin(2 * .pi * phase) >= 0 ? 1.0 : -1.0
            case .triangle:
                let p = phase.truncatingRemainder(dividingBy: 1.0)
                raw = Float(4 * abs(p - 0.5) - 1.0)
            case .sawtooth:
                let p = phase.truncatingRemainder(dividingBy: 1.0)
                raw = Float(2 * p - 1.0)
            }

            // Apply envelope (quick attack, sustain, quick release)
            let envelope = Self.envelope(sample: i, totalSamples: Int(frameCount))
            floatData[i] = raw * amplitude * envelope
        }

        return buffer
    }

    private func arpeggio(frequencies: [Double], noteDuration: Double, waveform: Waveform) -> AVAudioPCMBuffer? {
        let totalDuration = Double(frequencies.count) * noteDuration
        let totalFrames = AVAudioFrameCount(sampleRate * totalDuration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            return nil
        }
        buffer.frameLength = totalFrames

        guard let floatData = buffer.floatChannelData?[0] else { return nil }

        let framesPerNote = Int(sampleRate * noteDuration)

        for (noteIndex, freq) in frequencies.enumerated() {
            let startFrame = noteIndex * framesPerNote
            for i in 0..<framesPerNote {
                let globalIndex = startFrame + i
                guard globalIndex < Int(totalFrames) else { break }

                let t = Double(i) / sampleRate
                let phase = t * freq
                let raw: Float

                switch waveform {
                case .square:
                    raw = sin(2 * .pi * phase) >= 0 ? 1.0 : -1.0
                case .triangle:
                    let p = phase.truncatingRemainder(dividingBy: 1.0)
                    raw = Float(4 * abs(p - 0.5) - 1.0)
                case .sawtooth:
                    let p = phase.truncatingRemainder(dividingBy: 1.0)
                    raw = Float(2 * p - 1.0)
                }

                let envelope = Self.envelope(sample: i, totalSamples: framesPerNote)
                floatData[globalIndex] = raw * amplitude * envelope
            }
        }

        return buffer
    }

    /// Quick attack, sustain, quick release envelope.
    private static func envelope(sample: Int, totalSamples: Int) -> Float {
        let attackSamples = min(totalSamples / 10, 200)
        let releaseSamples = min(totalSamples / 5, 400)
        let sustainEnd = totalSamples - releaseSamples

        if sample < attackSamples {
            return Float(sample) / Float(attackSamples)
        } else if sample < sustainEnd {
            return 1.0
        } else {
            let releasePos = Float(sample - sustainEnd) / Float(releaseSamples)
            return max(0, 1.0 - releasePos)
        }
    }
}
