//
//  VAD.swift
//  Whakahua
//
//  Created by Thomas Kiddle on 5/10/21.
//

import Foundation
import libfvad
import AudioToolbox
import AVFAudio
import CoreAudio
import AVFoundation

public class VAD: ObservableObject {
    @Published public var isSpeechDetected = false
    
    let inst: OpaquePointer
    let sampleRate: Int32
    let aggressiveness: Int32
   
    var isMicrophoneActive = false
    var audioBuffers = [AudioQueueBufferRef]()
    var audioQueue: AudioQueueRef?

    var audioStreamDescription = AudioStreamBasicDescription(
      mSampleRate: 8000,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger,
      mBytesPerPacket: 2,
      mFramesPerPacket: 1,
      mBytesPerFrame: 2,
      mChannelsPerFrame: 1,
      mBitsPerChannel: 16,
      mReserved: 0)

    public init?(_ sampleRate: Int = 16000,_ agressiveness: Int = 3) {
        guard let inst = fvad_new() else { return nil }
        self.inst = inst
        
        self.sampleRate = Int32(sampleRate)
        self.aggressiveness = Int32(agressiveness)
        
        //very aggressive
        guard fvad_set_mode(self.inst, self.aggressiveness) == 0 else {
            fatalError("Invalid value")
        }
        
        //16000hz
        guard fvad_set_sample_rate(inst, self.sampleRate) == 0 else {
            assertionFailure("Invalid value, should be 8000|16000|32000|48000")
            return
        }
    }
    
    ///  Calculates a VAD decision for an audio duration.
    ///
    /// - Parameter frames:  Array of signed 16-bit samples.
    /// - Parameter count:  Specify count of frames.
    ///                  Since internal processor supports only counts of 10, 20 or 30 ms,
    ///                  so for example at 16000 kHz, `count` must be either 160, 320 or 480.
    ///
    /// - Returns:  VAD decision.
    public func isSpeech(frames: UnsafePointer<Int16>, count: Int) -> Bool {
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
    
    // From https://github.com/reedom/VoiceActivityDetector/blob/e639fc037f19f8c03ba33d1dfdfc42da914f11b4/Example/VoiceActivityDetector/ViewController.swift
    public func setupAudioRecording() {
        let callback: AudioQueueInputCallback = { (
            inUserData: UnsafeMutableRawPointer?,
            inAQ: AudioQueueRef,
            inBuffer: AudioQueueBufferRef,
            inStartTime: UnsafePointer<AudioTimeStamp>,
            inNumberPacketDescriptions: UInt32,
            inPacketDescs: UnsafePointer<AudioStreamPacketDescription>?
        ) in
            guard let inUserData = inUserData else { return }
            
            let myself = Unmanaged<VAD>.fromOpaque(inUserData).takeUnretainedValue()
            guard myself.isMicrophoneActive else { return }
            
            myself.didReceivceSampleBuffer(buffer: inBuffer.pointee)
            
            let err = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
            if (err != noErr) {
                NSLog("AudioQueueEnqueueBuffer failed with error (\(err))");
                AudioQueueFreeBuffer(inAQ, inBuffer)
            }
        }
        
        let err = AudioQueueNewInput(&audioStreamDescription,
                                     callback,
                                     Unmanaged.passUnretained(self).toOpaque(),
                                     nil, nil, 0, &audioQueue)
        if err != noErr {
            fatalError("Unable to create new output audio queue (\(err))")
        }
    }
    
    
#if os(iOS)
    public func activateMicrophone() {
        guard let audioQueue = audioQueue else { return }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSession.Category.record)
            try audioSession.setActive(true)
            try audioSession.setPreferredSampleRate(audioStreamDescription.mSampleRate)
            
            enqueueBuffers()
            
            let err = AudioQueueStart(audioQueue, nil)
            if err == noErr {
                isMicrophoneActive = true
            } else {
                NSLog("AudioQueueStart failed with error (\(err))");
            }
        } catch {
            print(error.localizedDescription)
            dequeueBuffers()
        }
    }
#else
    public func activateMicrophone(deviceID: AudioObjectID) {
        var audioQueue: AudioQueueRef? = nil
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        // Set the input device ID for the audio queue
        var inputDeviceID: AudioObjectID = deviceID
        let propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var err = AudioQueueNewInput(&audioFormat, { (inUserData, inAQ, inBuffer, inStartTime, inNumPackets, inPacketDesc) in
            // Handle audio buffer here
        }, nil, nil, nil, 0, &audioQueue)
        
        if err != noErr {
            NSLog("AudioQueueNewInput failed with error (\(err))")
            return
        }
        
        err = AudioQueueSetProperty(audioQueue!, kAudioQueueProperty_CurrentDevice, &inputDeviceID, propertySize)
        
        if err != noErr {
            NSLog("AudioQueueSetProperty for device ID \(deviceID) failed with error (\(err))")
            AudioQueueDispose(audioQueue!, true)
            return
        }
        
        for _ in 0..<3 {
            var bufferRef: AudioQueueBufferRef? = nil
            err = AudioQueueAllocateBuffer(audioQueue!, 1024, &bufferRef)
            if (err != noErr) {
                NSLog("Failed to allocate buffer for audio recording (\(err))")
                AudioQueueDispose(audioQueue!, true)
                return
            }
            err = AudioQueueEnqueueBuffer(audioQueue!, bufferRef!, 0, nil)
            if (err != noErr) {
                NSLog("Failed to enqueue buffer for audio recording (\(err))")
                AudioQueueDispose(audioQueue!, true)
                return
            }
        }
        
        let startStatus = AudioQueueStart(audioQueue!, nil)
        if startStatus == noErr {
            // Audio capture started successfully
            isMicrophoneActive = true
        } else {
            NSLog("AudioQueueStart failed with error (\(startStatus))")
            AudioQueueDispose(audioQueue!, true)
        }
    }
#endif
    
    public func deactivateMicrophone() {
        guard isMicrophoneActive else { return }
        isMicrophoneActive = false
        guard let audioQueue = audioQueue else { return }
        
        let err = AudioQueueStop(audioQueue, true)
        if err != noErr {
            NSLog("AudioQueueStop failed with error (\(err))");
        }
        
        dequeueBuffers()
    }
    
    func enqueueBuffers() {
        guard let audioQueue = audioQueue else { return }
        
        let format = audioStreamDescription
        let bufferSize = UInt32(format.mSampleRate) * UInt32(format.mBytesPerFrame) / 1000 * UInt32(30) // 30 msec
        for _ in 0 ..< 3 {
            var buffer: AudioQueueBufferRef?
            var err = AudioQueueAllocateBuffer(audioQueue, bufferSize, &buffer)
            if (err != noErr) {
                NSLog("Failed to allocate buffer for audio recording (\(err))")
                continue
            }
            
            err = AudioQueueEnqueueBuffer(audioQueue, buffer!, 0, nil)
            if (err != noErr) {
                NSLog("Failed to enqueue buffer for audio recording (\(err))")
            }
            
            audioBuffers.append(buffer!)
        }
    }
    
    func dequeueBuffers() {
        guard let audioQueue = audioQueue else { return }
        while let buffer = audioBuffers.popLast() {
            AudioQueueFreeBuffer(audioQueue, buffer)
        }
    }
    
    func didReceivceSampleBuffer(buffer: AudioQueueBuffer) {
        let frames = buffer.mAudioData.assumingMemoryBound(to: Int16.self)
        var count = Int(buffer.mAudioDataByteSize) / MemoryLayout<Int16>.size
        let detectorFrameUnit = Int(audioStreamDescription.mSampleRate) * 10 / 1000 // 10ms
        count = count - (count % detectorFrameUnit)
        guard 0 < count else { return }
        
        let voiceActivity = isSpeech(frames: frames, count: count)
        Task { @MainActor in
            isSpeechDetected = voiceActivity
        }
    }
}

