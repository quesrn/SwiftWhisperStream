import Foundation
import libfvad
import SDL2
import LibWhisper

public class VAD: ObservableObject {
    @Published public var isSpeechDetected = false
    
    var speechDetectedAt = [(Int64, Int64)]()
    private let speechDetectedAtQueue = DispatchQueue(label: "VAD-SpeechDetectedAtQueue")

    let inst: OpaquePointer
    let sampleRate: Int32
    let aggressiveness: Int32
    let samples: UInt16 = 160
   
    var isMicrophoneActive = false
    
    private let audioDataQueue = DispatchQueue(label: "VAD-AudioDataQueue")
    private var audioFrameBuffer: [Int16] = []

    init?(_ sampleRate: Int = 16000, _ aggressiveness: Int = 2) {
        guard let inst = fvad_new() else { return nil }
        self.inst = inst
        
        self.sampleRate = Int32(sampleRate)
        self.aggressiveness = Int32(aggressiveness)
        
        // Very aggressive
        guard fvad_set_mode(self.inst, self.aggressiveness) == 0 else {
            fatalError("Invalid value")
        }
        
        // 16000 Hz
        guard fvad_set_sample_rate(inst, self.sampleRate) == 0 else {
            assertionFailure("Invalid value, should be 8000|16000|32000|48000")
            return
        }
    }
    
    /// Calculates a VAD decision for an audio duration.
    ///
    /// - Parameter frames: Array of signed 16-bit samples.
    /// - Parameter count: Specify the count of frames.
    ///                   Since the internal processor supports only counts of 10, 20, or 30 ms,
    ///                   for example, at 16000 kHz, `count` must be either 160, 320, or 480.
    ///
    /// - Returns: VAD decision.
    func isSpeech(frames: UnsafePointer<Int16>, count: Int) -> Bool {
        switch fvad_process(inst, frames, count) {
        case 0:
            return false
        case 1:
            return true
        default:
            assertionFailure("Defaulted on fvad_process")
            return false
        }
    }
    
    deinit {
        // Frees the dynamic memory of a specified VAD instance.
        fvad_free(inst)
    }
    
    func callback(t0: Int64, t1: Int64, audioBuffer: UnsafeMutablePointer<Float32>?, length: Int32) {
        let samples = samples
        audioDataQueue.sync {
            guard isMicrophoneActive else { return }
            
            let bufferPointer = audioBuffer!.withMemoryRebound(to: Int16.self, capacity: Int(length)) {
                $0
            }
            let frames = UnsafePointer(bufferPointer)
            let count = Int(length) / MemoryLayout<Int16>.size
            
            // Accumulate audio frames in the buffer
            audioFrameBuffer.append(contentsOf: Array(UnsafeBufferPointer(start: frames, count: count)))
            
            // Check if we have accumulated 30ms of audio data (480 frames)
            if audioFrameBuffer.count >= samples {
                // Take the first 480 frames for processing
                let framesToProcess = Array(audioFrameBuffer.prefix(Int(samples)))
                
                // Make the VAD decision using 30 ms of audio data (480 frames)
                let voiceActivity = isSpeech(frames: framesToProcess, count: Int(samples))
                
                // Remove all frames from the buffer after processing
                audioFrameBuffer.removeAll()
                
                // After processing audio and running inference
//                let t1 = getCurrentTimestamp() // timestamp in microseconds
                // Calculate t0 based on the logic from stream.cpp
//                let durationMicroseconds = Int64(framesToProcess.count) * 1_000_000 / Int64(sampleRate)
//                let t0 = max(0, t1 - durationMicroseconds)
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    isSpeechDetected = voiceActivity
                    if voiceActivity {
                        addSpeechDetectionRange(range: (t0, t1))
                    }
                }
            }
        }
    }
    
    func activateMicrophone() {
        isMicrophoneActive = true
    }
    
    func deactivateMicrophone() {
        guard isMicrophoneActive else { return }
        removeAllSpeechDetectionRanges()
        isMicrophoneActive = false
//        SDL_Quit()
    }
    
    func removeAllSpeechDetectionRanges() {
        speechDetectedAtQueue.sync {
            speechDetectedAt.removeAll()
        }
    }
    
    private func addSpeechDetectionRange(range: (Int64, Int64)) {
        speechDetectedAtQueue.sync {
            speechDetectedAt.append(range)
        }
    }

    func removeSpeechDetectionRanges(startTime: Int64, t0: Int64, t1: Int64) {
        speechDetectedAtQueue.sync {
            speechDetectedAt.removeAll { $0.1 < (startTime + (t0 * 1000)) || $0.0 > (startTime + (t1 * 1000)) }
        }
    }
}
