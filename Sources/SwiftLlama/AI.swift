//
//  Model.swift
//  Mia
//
//  Created by Byron Everson on 12/25/22.
//

import Foundation
import llama_cpp_helpers

public enum ModelInference {
    case LLama_gguf
}

public actor AI {
//    var aiQueue = DispatchQueue(label: "LLMFarm-Main", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .inherit, target: nil)
    
    //var model: Model!
    public var model: LLaMa!
    public var modelPath: String
    public var modelName: String
    
    public var flagExit = false {
        didSet {
            let val = flagExit
            Task { @MainActor in
                didFlagExit = val
            }
        }
    }
    @MainActor public var didFlagExit = false
    @MainActor public var didFlagExitDueToStopWord = false
    private(set) var flagResponding = false
    
    @MainActor public var context: Int32 = 0
    
    @MainActor public var nBatch: Int32 = 0
    
    public init(_modelPath: String) {
        self.modelPath = _modelPath
        self.modelName = NSURL(fileURLWithPath: _modelPath).lastPathComponent!
    }
    
    public func stop() async {
        flagExit = true
    }
    
    public func loadModel(_ aiModel: ModelInference, contextParams: ModelAndContextParams = .default) async throws {
        await Task { @MainActor in
            context = contextParams.context
            nBatch = contextParams.n_batch
        }.value

        do {
            switch aiModel {
            case .LLama_gguf:
                model = try LLaMa(path: self.modelPath, contextParams: contextParams)
            }
        } catch {
            print(error)
            throw error
        }
    }
    
    public func reinitialize(systemPrompt: String?) throws {
        print("AI reinit system prompt: \(systemPrompt)")
        try model.reinitialize(systemPrompt: systemPrompt)
    }
    
    public func conversationHistory(allMessages messages: [(String, String)]) throws {
        print("AI conversation history: \(messages)")
        try model.preparePast(messages: messages)
    }
    
    public func conversation(_ input: String, _ tokenCallback: @escaping (String, String, Double) async -> (Bool, String)?) async throws -> String {
        print("AI new input: \(input)")
        flagResponding = true
        await Task { @MainActor in
            didFlagExitDueToStopWord = false
        }.value
        flagExit = false
        
        defer {
            flagResponding = false
        }
        
        guard let model = model else {
            throw ModelLoadError.modelLoadError
        }
        
        var output: String?
//            try ExceptionCatcher.catchException {
        output = try await model.predict(input) { str, textSoFar, time in
            if flagExit {
                flagExit = false
                return (true, textSoFar)
            }
            print("AI Predicted next: \(str)")
            guard let (check, processedTextSoFar) = await tokenCallback(str, textSoFar, time) else {
                return (true, textSoFar)
            }
            if flagExit {
                flagExit = false
                return (true, processedTextSoFar)
            }
            return (check, processedTextSoFar)
        }
//            }
        
        print("AI Predicted: \(output)")
        return output ?? "[Error]"
    }

}

private typealias _ModelProgressCallback = (_ progress: Float, _ userData: UnsafeMutableRawPointer?) -> Void

public typealias ModelProgressCallback = (_ progress: Float, _ model: LLaMa) -> Void

func get_path_by_lora_name(_ model_name:String, dest:String = "lora_adapters") -> String? {
    //#if os(iOS) || os(watchOS) || os(tvOS)
    do {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let destinationURL = documentsPath!.appendingPathComponent(dest)
        try fileManager.createDirectory (at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        let path = destinationURL.appendingPathComponent(model_name).path
        if fileManager.fileExists(atPath: path){
            return path
        }else{
            return nil
        }
        
    } catch {
        print(error)
    }
    return nil
}

//
//public func get_model_context_param_by_config(_ model_config:Dictionary<String, AnyObject>) -> ModelAndContextParams{
//    var tmp_param = ModelAndContextParams.default
//    if (model_config["context"] != nil){
//        tmp_param.context = model_config["context"] as! Int32
//    }
//    if (model_config["numberOfThreads"] != nil && model_config["numberOfThreads"] as! Int32 != 0){
//        tmp_param.n_threads = model_config["numberOfThreads"] as! Int32
//    }
//    if model_config["lora_adapters"] != nil{
//        let tmp_adapters = model_config["lora_adapters"]! as? [Dictionary<String, Any>]
//        if tmp_adapters != nil{
//            for adapter in tmp_adapters!{
//                var adapter_file: String? = nil
//                var scale: Float? = nil
//                if adapter["adapter"] != nil{
//                    adapter_file = adapter["adapter"]! as? String
//                }
//                if adapter["scale"] != nil{
//                    scale = adapter["scale"]! as? Float
//                }
//                if adapter_file != nil && scale != nil{
//                    let adapter_path = get_path_by_lora_name(adapter_file!)
//                    if adapter_path != nil{
//                        tmp_param.lora_adapters.append((adapter_path!,scale!))
//                    }
//                }
//            }
//        }            
//    }
//    return tmp_param
//}

public struct ModelAndContextParams {
    public var context: Int32 = 512    // text context
    public var parts: Int32 = -1   // -1 for default
    public var seed: UInt32 = 0xFFFFFFFF      // RNG seed, 0 for random
    public var n_threads: Int32 = 1
    public var n_batch: Int32 = 512
    public var lora_adapters: [(String,Float)] = []
    
    public var f16Kv = true         // use fp16 for KV cache
    public var logitsAll = false    // the llama_eval() call computes all logits, not just the last one
    public var vocabOnly = false    // only load the vocabulary, no weights
    public var useMlock = false     // force system to keep model in RAM
    public var useMMap = true     // if disabled dont use MMap file
    public var embedding = false    // embedding mode only
    public var processorsConunt = Int32(ProcessInfo.processInfo.processorCount)
    public var useMetal = false
    public var grammarPath: String? = nil
    
    public var warm_prompt = "\n\n\n"
    
    public static let `default` = ModelAndContextParams()
    
    public init(context: Int32 = 2048 /*512*/, parts: Int32 = -1, seed: UInt32 = 0xFFFFFFFF, numberOfThreads: Int32 = 0, n_batch: Int32 = 512, f16Kv: Bool = true, logitsAll: Bool = false, vocabOnly: Bool = false, useMlock: Bool = false, useMMap: Bool = true, useMetal: Bool = false, embedding: Bool = false) {
        self.context = context
        self.parts = parts
        self.seed = seed
        // Set numberOfThreads to processorCount, processorCount is actually thread count of cpu
        self.n_threads = Int32(numberOfThreads) == Int32(0) ? processorsConunt : numberOfThreads
        //        self.numberOfThreads = processorsConunt
        self.n_batch = n_batch
        self.f16Kv = f16Kv
        self.logitsAll = logitsAll
        self.vocabOnly = vocabOnly
        self.useMlock = useMlock
        self.useMMap = useMMap
        self.useMetal = useMetal
        self.embedding = embedding
    }
}

public struct ModelSampleParams {
    public var n_batch: Int32
    public var temp: Float
    public var top_k: Int32
    public var top_p: Float
    public var tfs_z: Float
    public var typical_p: Float
    public var repeat_penalty: Float
    public var repeat_last_n: Int32
    public var frequence_penalty: Float
    public var presence_penalty: Float
    public var mirostat: Int32
    public var mirostat_tau: Float
    public var mirostat_eta: Float
    public var penalize_nl: Bool
    
    public static let `default` = ModelSampleParams(
        n_batch: 512,
        temp: 0.9,
        top_k: 40,
        top_p: 0.95,
        tfs_z: 1.0,
        typical_p: 1.0,
        repeat_penalty: 1.1,
        repeat_last_n: 64,
        frequence_penalty: 0.0,
        presence_penalty: 0.0,
        mirostat: 0,
        mirostat_tau: 5.0,
        mirostat_eta: 0.1,
        penalize_nl: true
    )
    
    public init(n_batch: Int32 = 512,
                temp: Float = 0.8,
                top_k: Int32 = 40,
                top_p: Float = 0.95,
                tfs_z: Float = 1.0,
                typical_p: Float = 1.0,
                repeat_penalty: Float = 1.1,
                repeat_last_n: Int32 = 64,
                frequence_penalty: Float = 0.0,
                presence_penalty: Float = 0.0,
                mirostat: Int32 = 0,
                mirostat_tau: Float = 5.0,
                mirostat_eta: Float = 0.1,
                penalize_nl: Bool = true) {
        self.n_batch = n_batch
        self.temp = temp
        self.top_k = top_k
        self.top_p = top_p
        self.tfs_z = tfs_z
        self.typical_p = typical_p
        self.repeat_penalty = repeat_penalty
        self.repeat_last_n = repeat_last_n
        self.frequence_penalty = frequence_penalty
        self.presence_penalty = presence_penalty
        self.mirostat = mirostat
        self.mirostat_tau = mirostat_tau
        self.mirostat_eta = mirostat_eta
        self.penalize_nl = penalize_nl
    }
}

public enum ModelError: Error {
    case modelNotFound(String)
    case inputTooLong
    case failedToEval
    case contextLimit
}

public enum ModelPromptStyle {
    case None
    case Custom
    case ChatBase
    case OpenAssistant
    case StableLM_Tuned
    case LLaMa
    case LLaMa_QA
    case Dolly_b3
    case RedPajama_chat
}

public typealias ModelToken = Int32

//public class Model {
//
//    public var context: OpaquePointer?
//    public var grammar: OpaquePointer?
//    public var contextParams: ModelContextParams
//    public var sampleParams: ModelSampleParams = .default
//    public var promptFormat: ModelPromptStyle = .None
//    public var custom_prompt_format = ""
//    public var core_resourses = get_core_bundle_path()
//    public var reverse_prompt: [String] = []
//    public var session_tokens: [Int32] = []
//
//    // Init
//    public init(path: String = "", contextParams: ModelContextParams = .default) throws {
//        self.contextParams = contextParams
//        self.context = nil
//    }
//
//    public func llm_load_model(path: String = "", contextParams: ModelContextParams = .default, params:gpt_context_params ) throws -> Bool{
//        return false
//    }
//
//    // Predict
//    public func predict(_ input: String, _ callback: ((String, Double) -> Bool) ) throws -> String {
//        return ""
//    }
//
//    public func llm_tokenize(_ input: String, bos: Bool = false, eos: Bool = false) -> [ModelToken] {
//        return []
//    }
//
//
//
//
//    public func tokenizePrompt(_ input: String, _ style: ModelPromptStyle) -> [ModelToken] {
//        return llm_tokenize(input)
//    }
//
//}
