import AVFoundation
import whisper_cpp

public struct Segment {
    let text: String
    let t0: Int64
    let t1: Int64
}

public typealias OrderedSegments = [Segment]

public extension OrderedSegments {
    var text: any StringProtocol {
        map { $0.text }.joined()
    }
}

fileprivate let WHISPER_SAMPLE_RATE: Int64 = 16000

public class WhisperStream: Thread {
    @Published public private(set) var segments = OrderedSegments()
    @Published public private(set) var alive = true
    @Published public var isMuted = false
    private var streamContext: stream_context_t?

    let waiter = DispatchGroup()
    
    let model: URL
    let device: CaptureDevice?
//    let window: TimeInterval
    let suppressNonSpeechOutput: Bool
    let language: String

    // Define a class-level lock to ensure serial execution of stream_init
    private static let streamInitLock = NSLock()

    public init(model: URL, device: CaptureDevice? = nil/*, window: TimeInterval = (60 * 5)*/, suppressNonSpeechOutput: Bool = false, language: String? = nil) {
        self.model = model
        self.device = device
//        self.window = window
        self.suppressNonSpeechOutput = suppressNonSpeechOutput
        self.language = language?.lowercased() ?? ""
        super.init()
    }

    deinit {
        if let streamContext = streamContext {
            stream_free(streamContext)
        }
    }

    public override func start() {
        waiter.enter()
        super.start()
    }

    public override func main() {
        task()
        waiter.leave()
    }

    public func join() {
        waiter.wait()
    }

    func task() {
        device?.activateVAD()
        guard let vad = device?.vad else { return }
        
        language.withCString { languageCStr in
            model.path.withCString { modelCStr in
                var params = stream_default_params()
                params.model = modelCStr
                params.language = languageCStr
                params.suppress_non_speech_tokens = false
                
                if let device = device {
                    params.capture_id = device.id
                }
                
                guard !isCancelled else {
                    alive = false
                    device?.deactivateVAD()
                    return
                }
                
                // Use the class-level lock to ensure only one instance initializes stream at a time
                WhisperStream.streamInitLock.lock()
                defer {
                    WhisperStream.streamInitLock.unlock()
                }
                
                let ctx = stream_init(params, Unmanaged.passUnretained(vad).toOpaque()) { userData, audioBuffer, length in
                    let now = stream_timestamp()
                    let vad = Unmanaged<VAD>.fromOpaque(userData!).takeUnretainedValue()
                    
                    // Process audio data in chunks
                    let chunkSize = Int32(vad.samples)
                    // Calculate the total number of samples in the input data
                    let totalSamples = length / Int32(MemoryLayout<Float32>.size)
                    let totalDurationMicroseconds = (Int64(totalSamples) * 1_000_000) / Int64(WHISPER_SAMPLE_RATE)
                    // Initialize a variable to keep track of the current position
                    var currentPosition: Int32 = 0
                    var t0 = now - totalDurationMicroseconds
                    // Process audio data with a sliding window
                    while currentPosition + chunkSize <= totalSamples {
                        // Calculate the offset into the audioBuffer
                        let bufferOffset = currentPosition * Int32(MemoryLayout<Float32>.size)
//                        let bufferPointer = audioBuffer!.advanced(by: Int(bufferOffset)).withMemoryRebound(to: Uint8.self, capacity: Int(chunkSize) * MemoryLayout<Float32>.size) { ptr in
//                            return ptr
//                        }
                        let bufferPointer = audioBuffer!.advanced(by: Int(bufferOffset)).withMemoryRebound(to: Float32.self, capacity: Int(chunkSize)) { ptr in
                            return ptr
                        }
                        // Calculate t1 and t0 in microseconds
                        // let t0 be now minus the size of the audioBuffer as measured in microseconds, knowing that the SDL audioBuffer data has sample rate WHISPER_SAMPLE_RATE; then add the currentPosition times the sample chunkSize to get the starting timestamp of the chunk of audio
                        // let t1 be t0 + the duration of this chunk of audio (expected to be 160 samples chunk size, or in other words, 10ms because the sample rate is 16000)
                        // Calculate t1 in microseconds by adding the duration of the current chunk
                        let t1 = t0 + (Int64(chunkSize) * 1_000_000) / Int64(WHISPER_SAMPLE_RATE)

                           // Do something with t0 and t1

                        //                        let t0: Int64 = now - ( Int64(chunkSize) * 1_000_000 / Int64(WHISPER_SAMPLE_RATE))
//                        let t1: Int64 = now - (Int64(bufferOffset) * 1_000_000 / Int64(WHISPER_SAMPLE_RATE))
//                        let t0: Int64 = max(0, t1 - Int64(chunkSize) * 1_000_000 / Int64(WHISPER_SAMPLE_RATE))
//                        let t1: Int64 = now - Int64(bufferOffset) * 1_000_000 / Int64(WHISPER_SAMPLE_RATE)
//                        let t0: Int64 = max(0, t1 - Int64(chunkSize) * 1_000_000 / Int64(WHISPER_SAMPLE_RATE))
//                        let t1: Int64 = now - Int64(bufferOffset) * 1000 / WHISPER_SAMPLE_RATE
//                        // Calculate t0 based on t1 and chunk size
//                        let t0: Int64 = max(0, t1 - Int64(chunkSize) * 1000 / WHISPER_SAMPLE_RATE)
                        
                        vad.callback(t0: t0, t1: t1, audioBuffer: bufferPointer, length: chunkSize * Int32(MemoryLayout<Float32>.size))
                        currentPosition += chunkSize
                        // Increment t0 for the next iteration
                        t0 = t1
                    }
                }
                streamContext = ctx
                if ctx == nil {
                    return
                }
                
                while !isCancelled {
                    let errno = stream_run(ctx, Unmanaged.passUnretained(self).toOpaque()) { text, t0, t1, startTime, myself in
                        var resultText = text
                        let stream = Unmanaged<WhisperStream>.fromOpaque(myself!).takeUnretainedValue()
                        if stream.isMuted {
                            stream.device?.vad?.removeAllSpeechDetectionRanges()
                            resultText = nil
                        } else {
                            stream.device?.vad?.removeSpeechDetectionRanges(startTime: startTime, t0: t0, t1: t1)
                            var speechCoverage: Int64 = 0
                            let speechDetectedAt = stream.device?.vad?.speechDetectedAt ?? []
                            for pair in speechDetectedAt {
                                let speech0 = max(0, pair.0 - startTime) / 1000
                                let speech1 = max(0, pair.1 - startTime) / 1000
                                let duration = max(0, min(t1, speech1) - max(t0, speech0))
                                speechCoverage += duration
                            }
                            let speechRatio = Double(speechCoverage) / max(0, Double(t1) - Double(t0))
                            if speechRatio.isNaN || speechRatio < 0.1 {
                                print("SKIPPED \(speechRatio) \(text != nil ? String(cString: text!) : nil)")
                                resultText = nil
                            } else {
                                print("NOT SKIP! \(speechRatio) \(text != nil ? String(cString: text!) : nil)")
                            }
                        }
                        return stream.callback(
                            text: resultText != nil ? String(cString: resultText!) : nil,
                            t0: t0,
                            t1: t1)
                    }
                    if errno != 0 {
                        break
                    }
                }
                
                device?.deactivateVAD()
                stream_free(ctx)
                streamContext = nil
                alive = false
            }
        }
    }

    func callback(text: String?, t0: Int64, t1: Int64) -> Int32 {
        if segments.isEmpty || text == nil {
            segments.append(Segment(text: "", t0: -1, t1: -1))
        }
        if var text = text {
            if suppressNonSpeechOutput {
                text = suppressNonSpeech(text: text)
            }
            segments[segments.count - 1] = Segment(text: text, t0: t0, t1: t1)
        }

//        var k = 0
//        for segment in segments {
//            if let last = segments.last, last.t0 - segment.t0 > Int64(window * 1000) {
//                k += 1
//            }
//        }
//        segments.removeFirst(k)

        return 0
    }
    
    public func clearAudio() {
        guard let ctx = streamContext else { return }
        stream_audio_clear(ctx)
    }
    
    public func clearSegments() {
        segments.removeAll()
    }
    
    func suppressNonSpeech(text: String) -> String {
        var text = text
        // TODO: Disallow hyphens, single quotes at start of line (only between words)
        //        symbols = list("\"#()*+/:;<=>@[\\]^_`{|}~「」『』")
        //        symbols += "<< >> <<< >>> -- --- -( -[ (' (\" (( )) ((( ))) [[ ]] {{ }} ♪♪ ♪♪♪".split()
        //                miscellaneous = set("♩♪♫♬♭♮♯")
        text = text
            .replacingOccurrences(of: bracketPairsPattern, with: " ", options: .regularExpression)
            .replacingOccurrences(of: symbolsPattern, with: " ", options: .regularExpression)
            .replacingOccurrences(of: spacesPattern, with: " ", options: .regularExpression)
        return text
    }
}

fileprivate let spacesPattern = #"\s{2,}"#
// Non-symbol chars in brackets/parens
fileprivate let bracketPairsPattern = "\\p{Ps}[^\\p{Pe}]*?\\p{Pe}|\\p{Pi}[^\\p{Pf}]*?\\p{Pf}|" + ["\\(\\)", "「」", "『』", "〔〕", "〈〉", "**", #"\(\)"#, #"\[\]"#].map { "\($0.prefix($0.count / 2))[^\($0)]*?\($0.suffix($0.count / 2))" }.joined(separator: "|")
fileprivate let symbolsPattern = #"[\[\]#*+/:;<=>^_`\(\)|~♩♪♫♬♭♮♯♪]+"#
