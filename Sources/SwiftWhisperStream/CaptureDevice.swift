import LibWhisper
import SDL
import CoreAudio
import AVFoundation

public enum CaptureDeviceError: Error {
    case sdlErrorCode(Int32)
}

public struct CaptureDevice: Identifiable {
    public let id: Int32
    public let name: String
    
    public func audioDeviceID() -> AudioDeviceID {
        var audioDeviceID: AudioDeviceID = AudioDeviceID(kAudioDeviceUnknown)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        
        var deviceList: [AudioDeviceID] = []
        var dataSize: UInt32 = 0
        
        // Get the list of available audio devices
        let err = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        if err != noErr {
            NSLog("AudioObjectGetPropertyDataSize failed with error (\(err))")
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        deviceList = [AudioDeviceID](repeating: AudioDeviceID(kAudioDeviceUnknown), count: deviceCount)
        
        let listErr = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceList)
        if listErr != noErr {
            NSLog("AudioObjectGetPropertyData failed with error (\(listErr))")
        }
        
        // Find the matching AudioDeviceID based on the device name
        for deviceID in deviceList {
            var namePropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var nameSize: UInt32 = 0
            var deviceName = ""
            
            let nameErr = AudioObjectGetPropertyDataSize(deviceID, &namePropertyAddress, 0, nil, &nameSize)
            if nameErr != noErr {
                NSLog("AudioObjectGetPropertyDataSize for device name failed with error (\(nameErr))")
            }
            
            var nameData = [CChar](repeating: 0, count: Int(nameSize))
            let nameDataErr = AudioObjectGetPropertyData(deviceID, &namePropertyAddress, 0, nil, &nameSize, &nameData)
            if nameDataErr != noErr {
                NSLog("AudioObjectGetPropertyData for device name failed with error (\(nameDataErr))")
            }
            
            deviceName = String(cString: nameData)
            
            if name == deviceName {
                audioDeviceID = deviceID
                break
            }
        }
        
        return audioDeviceID
    }
    
    public init(id: Int32, name: String) {
        self.id = id
        self.name = name
    }
    
    public static var devices: [CaptureDevice] {
        get throws {
            var devices = [CaptureDevice]()
            
            SDL_SetMainReady()
            let result = SDL_Init(SDL_INIT_AUDIO)
            if result < 0 {
                print("SDL could not initialize! SDL_Error: \(String(cString: SDL_GetError()))")
                throw CaptureDeviceError.sdlErrorCode(result)
            }
            
            for i in 0..<SDL_GetNumAudioDevices(1) {
                let name = String(cString: SDL_GetAudioDeviceName(i, 1))
                devices.append(CaptureDevice(id: i, name: name))
            }
            
            return devices
        }
    }
    
    public func close() {
        SDL_CloseAudioDevice(SDL_AudioDeviceID(id))
    }
}

extension CaptureDevice: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }
}

extension CaptureDevice: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
