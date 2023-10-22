import Foundation
import libfvad
import SDL2

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
    
    func activateMicrophone(deviceID: SDL_AudioDeviceID) {
        guard SDL_Init(SDL_INIT_AUDIO) >= 0 else {
            print("SDL_Init failed: \(SDL_GetError()!)")
            return
        }
        
        var desiredSpec = SDL_AudioSpec()
        var obtainedSpec = SDL_AudioSpec()
        
        desiredSpec.freq = sampleRate
        desiredSpec.format = SDL_AudioFormat(AUDIO_S16) // 16-bit signed, little-endian
        desiredSpec.channels = 1
        desiredSpec.samples = samples
        desiredSpec.callback = { userData, audioBuffer, length in
            guard let userData = userData else { return }
            let myself = Unmanaged<VAD>.fromOpaque(userData).takeUnretainedValue()
            let samples = myself.samples
            myself.audioDataQueue.sync {
                guard myself.isMicrophoneActive else { return }
                
                let bufferPointer = audioBuffer!.withMemoryRebound(to: Int16.self, capacity: Int(length)) {
                    $0
                }
                let frames = UnsafePointer(bufferPointer)
                let count = Int(length) / MemoryLayout<Int16>.size
                
                // Accumulate audio frames in the buffer
                myself.audioFrameBuffer.append(contentsOf: Array(UnsafeBufferPointer(start: frames, count: count)))
                
                // Check if we have accumulated 30ms of audio data (480 frames)
                if myself.audioFrameBuffer.count >= samples {
                    // Take the first 480 frames for processing
                    let framesToProcess = Array(myself.audioFrameBuffer.prefix(Int(samples)))
                    
                    // Make the VAD decision using 30 ms of audio data (480 frames)
                    let voiceActivity = myself.isSpeech(frames: framesToProcess, count: Int(samples))
                    
                    // Remove all frames from the buffer after processing
                    myself.audioFrameBuffer.removeAll()
                    
                    // After processing audio and running inference
                    let t1 = myself.getCurrentTimestamp() // timestamp in microseconds

                    // Calculate t0 based on the logic from stream.cpp
                    let durationMicroseconds = Int64(framesToProcess.count) * 1_000_000 / Int64(myself.sampleRate)
                    let t0 = max(0, t1 - durationMicroseconds)
                    
                    Task { @MainActor [weak myself] in
                        myself?.isSpeechDetected = voiceActivity
                        if voiceActivity {
                            myself?.addSpeechDetectionRange(range: (t0, t1))
                        }
                    }
                }
            }
        }
        desiredSpec.userdata = Unmanaged.passUnretained(self).toOpaque()
        
        let audioDeviceID = deviceID // Use the provided SDL device ID
        if audioDeviceID == 0 {
            print("SDL_OpenAudioDevice failed: \(SDL_GetError()!)")
            SDL_Quit()
            return
        }
        
        let audioDeviceStatus = SDL_OpenAudioDevice(nil, 1, &desiredSpec, &obtainedSpec, 0)
        if audioDeviceStatus == 0 {
            print("SDL_OpenAudioDevice failed: \(SDL_GetError()!)")
            SDL_Quit()
            return
        }
        
        SDL_PauseAudioDevice(audioDeviceStatus, 0)
        isMicrophoneActive = true
    }
    
    func deactivateMicrophone() {
        guard isMicrophoneActive else { return }
        removeAllSpeechDetectionRanges()
        isMicrophoneActive = false
        SDL_Quit()
    }
    
    private func getCurrentTimestamp() -> Int64 {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        let old = Int64(ts.tv_sec) * 1_000_000 + Int64(ts.tv_nsec) / 1_000
        let int64Time = Int64(DispatchTime.now().uptimeNanoseconds / 1000)
        print("old: \(old)")
        print("new: \(int64Time)")
        return int64Time
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
        print("cpp time \(startTime)")
        speechDetectedAtQueue.sync {
            speechDetectedAt.removeAll { $0.1 < (startTime + (t0 * 1000)) || $0.0 > (startTime + (t1 * 1000)) }
        }
    }
}
