import Foundation
import libfvad
import SDL2

public class VAD: ObservableObject {
    @Published public var isSpeechDetected = false
    
    let inst: OpaquePointer
    let sampleRate: Int32
    let aggressiveness: Int32
   
    var isMicrophoneActive = false
    
    private let audioDataQueue = DispatchQueue(label: "VAD-AudioDataQueue")
    private var audioFrameBuffer: [Int16] = []

    init?(_ sampleRate: Int = 16000, _ aggressiveness: Int = 3) {
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
        desiredSpec.samples = 480
        desiredSpec.callback = { userData, audioBuffer, length in
            guard let userData = userData else { return }
            let myself = Unmanaged<VAD>.fromOpaque(userData).takeUnretainedValue()
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
                if myself.audioFrameBuffer.count >= 480 {
                    // Take the first 480 frames for processing
                    let framesToProcess = Array(myself.audioFrameBuffer.prefix(480))
                    
                    // Make the VAD decision using 30 ms of audio data (480 frames)
                    let voiceActivity = myself.isSpeech(frames: framesToProcess, count: 480)
                    print("Voice activity? \(voiceActivity.description) for count \(myself.audioFrameBuffer.count)")
                    // Remove all frames from the buffer after processing
                    myself.audioFrameBuffer.removeAll()
                    
                    Task { @MainActor in
                        myself.isSpeechDetected = voiceActivity
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
        isMicrophoneActive = false
        SDL_Quit()
    }
}
