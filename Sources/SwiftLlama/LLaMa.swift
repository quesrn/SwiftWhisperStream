//
//  LLaMa.swift
//  Mia
//
//  Created by Byron Everson on 4/15/23.
//

import Foundation
//import whisper_cpp
import llama
import llama_cpp_helpers

public enum ModelLoadError: Error {
    // Throw when an invalid password is entered
    case modelLoadError
    
    // Throw when an expected resource is not found
    case contextLoadError
    
    case grammarLoadError
    
    //        // Throw in all other cases
    //        case unexpected(code: Int)
}

public class LLaMa {
    public var model: OpaquePointer?
    public var hardware_arch = ""
 
    public var context: OpaquePointer?
    public var grammar: OpaquePointer?
    public var contextParams: ModelAndContextParams
    public var sampleParams: ModelSampleParams = .default
    public var systemFormat = ""
    public var promptFormat = ""
//    public var core_resourses = get_core_bundle_path()
//    public var session_tokens: [Int32] = []
    
    private var batch: llama_batch
    // Used to keep old context until it needs to be rotated or purge out for new tokens
    var past: [[ModelToken]] = [] // Will house both queries and responses in order
    //var n_history: Int32 = 0
    var nPast: Int32 = 0
    
    public init(path: String, contextParams: ModelAndContextParams = .default) throws {
        self.contextParams = contextParams
        self.batch = llama_batch_init(512, 0, 1)

        var load_res: Bool? = false
        do {
            try ExceptionCatcher.catchException {
                load_res = try? llm_load_model(path: path, contextParams: contextParams)
            }
            if load_res != true{
                throw ModelLoadError.modelLoadError
            }
            if contextParams.grammarPath != nil && contextParams.grammarPath! != "" {
                try? self.load_grammar(contextParams.grammarPath!)
            }
            print(String(cString: print_system_info()))
            
            llm_init_logits()
//            try ExceptionCatcher.catchException {
//                _ = try? self.llm_init_logits()
//            }
            //        if exception != nil{
            //            throw ModelError.failedToEval
            //        }
            print("Logits inited.")
        } catch {
            print(error)
            throw error
        }
    }
    
    deinit {
        llama_free(context)
        llama_batch_free(batch)
        llama_free_model(model)
        llama_backend_free()
    }
    
    public func load_grammar(_ path: String) throws -> Void {
        do {
            try ExceptionCatcher.catchException {
                self.grammar = llama_load_grammar(path)
            }
        } catch {
            print(error)
            throw error
        }
    }
    
    func llm_init_logits() -> Bool {
        var inputs = [llama_token_bos(self.model), llama_token_eos(self.model)]
        return llama_eval(self.context, inputs.mutPtr, Int32(inputs.count), min(self.contextParams.context, self.nPast)) == 0
    }
    
//    func llm_init_logits() throws -> Bool {
//        do {
//            //            if self.contextParams.warm_prompt.count<1{
//            //                self.contextParams.warm_prompt = "\n\n\n"
//            //            }
//            let inputs = [llama_token_bos(self.model), llama_token_eos(self.model)]
//            try ExceptionCatcher.catchException {
//                _ = try? llm_eval(inputBatch: inputs)
//            }
//            return true
//        } catch {
//            print(error)
//            throw error
//        }
//    }
    
    public func llm_load_model(path: String = "", contextParams: ModelAndContextParams = .default) throws -> Bool {
        llama_backend_init(false)
        
        var context_params = llama_context_default_params()
        var model_params = llama_model_default_params()
        context_params.n_ctx = UInt32(contextParams.context)
        context_params.seed = UInt32(contextParams.seed)
        context_params.f16_kv = contextParams.f16Kv
        context_params.n_threads = UInt32(contextParams.n_threads)
        context_params.logits_all = contextParams.logitsAll
        context_params.n_batch = UInt32(contextParams.n_batch)
        model_params.vocab_only = contextParams.vocabOnly
        model_params.use_mlock = contextParams.useMlock
        model_params.use_mmap = contextParams.useMMap
//        context_params.rope_freq_base = 10000.0
//        context_params.rope_freq_scale = 1
        
        model_params.n_gpu_layers = contextParams.useMetal ? 1 : 0
        
        // Disable Metal on intel Mac
        hardware_arch = Get_Machine_Hardware_Name()
        if hardware_arch == "x86_64" {
            model_params.n_gpu_layers = 0
        }
        
        if contextParams.lora_adapters.count > 0 {
            model_params.use_mmap = false
        }
                        
        model = llama_load_model_from_file(path, model_params)
        if model == nil{
            return false
        }
        
        for lora in contextParams.lora_adapters {
            llama_model_apply_lora_from_file(model,lora.0,lora.1,nil,6)
        }
        
        context = llama_new_context_with_model(model, context_params)
        if self.context == nil {
            return false
        }
//        var tokens_tmp: [llama_token] = [Int32](repeating: 0, count: 100000)
//        var tokens_count:Int = 0
//        llama_load_session_file(self.context,"/Users/guinmoon/Library/Containers/com.guinmoon.LLMFarm/Data/Documents/models/dump_state.bin",tokens_tmp.mutPtr, 100000,&tokens_count)
//        self.session_tokens.append(contentsOf: tokens_tmp[0..<tokens_count])
//        try? llm_eval(inputBatch:self.session_tokens)
//        llama_load_state(self.context,"/Users/guinmoon/Library/Containers/com.guinmoon.LLMFarm/Data/Documents/models/dump_state_.bin")

        return true
    }
    
    public func predict(_ input: String, _ callback: ((String, String, Double) async -> (Bool, String)) ) async throws -> String {
        let params = sampleParams
        let contextLength = Int32(contextParams.context)
        //        print("Past token count: \(nPast)/\(contextLength) (\(past.count))")
        
        // Tokenize with prompt format
        var inputTokens = Array(past.joined())
        let promptTokens = tokenizePrompt(input, format: promptFormat)
        if promptTokens.count == 0 {
            return ""
        }
        inputTokens.append(contentsOf: promptTokens)
        //        self.session_tokens.append(contentsOf: inputTokens)
        let inputTokensCount = inputTokens.count
        
        past.append(promptTokens)
        //        var totalLength = nPast + Int32(inputTokensCount)
        
        // Create space in context if needed
        if inputTokensCount > contextLength {
            throw ModelError.inputTooLong
        }
        
        // Input
        var inputBatch: [ModelToken] = []
        do {
            while inputTokens.count > 0 {
                inputBatch.removeAll()
                // See how many to eval (up to batch size??? or can we feed the entire input)
                // Move tokens to batch
                let evalCount = min(inputTokens.count, Int(params.n_batch))
                inputBatch.append(contentsOf: inputTokens[0 ..< evalCount])
                
                inputTokens.removeFirst(evalCount)
                if nPast + Int32(inputBatch.count) >= contextParams.context {
                    self.nPast = 0
                    //                    try ExceptionCatcher.catchException {
                    //                        _ = try? self.llm_eval(inputBatch: [self.llama_token_eos(self.model)])
                    //                    }
                    throw ModelError.contextLimit
                }
                
//                batch.n_tokens = Int32(inputBatch.count)
//                for i1 in 0...batch.n_tokens - 1 {
//                    let i = Int(i1)
//                    batch.token[i] = inputBatch[i]
//                    batch.pos[i] = i1
//                    batch.n_seq_id[Int(i)] = 1
//                    batch.seq_id[Int(i)]![0] = 0
//                    batch.logits[i] = 0
//                }
//                batch.logits[Int(batch.n_tokens) - 1] = 1 // true
//                
//                if llama_decode(context, batch) != 0 {
//                    throw ModelError.failedToEval
//                }
                
                if llama_eval(self.context, inputBatch.mutPtr, Int32(inputBatch.count), min(self.contextParams.context, self.nPast)) != 0 {
                    throw ModelError.failedToEval
                }
//                }
//                var eval_res: Bool? = nil
//                try ExceptionCatcher.catchException {
//                    eval_res = try? self.llm_eval(inputBatch: inputBatch)
//                }
//                if eval_res == false {
//                    throw ModelError.failedToEval
//                }
                
                nPast += Int32(evalCount)
            }
            
            // Output
            var outputRepeatTokens: [ModelToken] = []
            var outputTokens: [ModelToken] = []
            var output = ""
            // Loop until target count is reached
            var outputEnabled = true
            while outputEnabled {
                // Pull a generation from context
                var outputToken: Int32 = -1
                try ExceptionCatcher.catchException {
                    outputToken = self.llm_sample(
                        ctx: self.context,
                        last_n_tokens: &outputRepeatTokens,
                        temp: params.temp,
                        top_k: params.top_k,
                        top_p: params.top_p,
                        tfs_z: params.tfs_z,
                        typical_p: params.typical_p,
                        repeat_last_n: params.repeat_last_n,
                        repeat_penalty: params.repeat_penalty,
                        alpha_presence: params.presence_penalty,
                        alpha_frequency: params.frequence_penalty,
                        mirostat: params.mirostat,
                        mirostat_tau: params.mirostat_tau,
                        mirostat_eta: params.mirostat_eta,
                        penalize_nl: params.penalize_nl
                    )
                }
                // Add output token to array
                outputTokens.append(outputToken)
                // Repeat tokens update
                outputRepeatTokens.append(outputToken)
                if outputRepeatTokens.count > params.repeat_last_n {
                    outputRepeatTokens.removeFirst()
                }
                // Check for eos - end early - check eos before bos in case they are the same
                if outputToken == llama_token_eos(self.model) {
                    outputEnabled = false
                    print("[EOS]")
                    break
                }
                // Check for bos, skip callback if so, bos = eos for most gptneox so this should typically never occur
                var skipCallback = false
                if outputToken == llama_token_bos(self.model) {
                    print("[BOS]")
                    skipCallback = true
                }
                // Convert token to string and callback
                //                self.session_tokens.append(outputToken)
                
                if !skipCallback {
                    let str = token_to_piece(token: outputToken)
                    output += str
                    // Per token callback
                    let (incrementalStr, time) = Utils.time {
                        return str
                    }
                    let (check, processedTextSoFar) = await callback(incrementalStr, output, time)
                    output = processedTextSoFar
                    if check {
                        // Early exit if requested by callback
                        print("* exit requested by callback *")
                        //generating = false
                        outputEnabled = false //outputRemaining = 0
                        break
                    }
                }
                
                // Check if we need to run another response eval
                if outputEnabled {
                    if self.nPast >= self.contextParams.context - 4 {
                        //                        self.nPast = self.nPast / 2
                        outputToken = llama_token_eos(self.model)
                        //                        try ExceptionCatcher.catchException {
                        //                            _ = try? self.llm_eval(inputBatch: [outputToken])
                        //                        }
                        //                        print("Context Limit!")
                        //                        throw ModelError.contextLimit
                        break
                    }

                    // Send generated token back into model for next generation
//                    var eval_res: Bool? = nil
                    
//                    batch.n_tokens = 0
//                    batch.token[Int(batch.n_tokens)] = outputToken
//                    batch.pos[Int(batch.n_tokens)] = nPast
//                    batch.n_seq_id[Int(batch.n_tokens)] = 1
//                    batch.seq_id[Int(batch.n_tokens)]![0] = 0
//                    batch.logits[Int(batch.n_tokens)] = 1 // true
//                    batch.n_tokens += 1
//                    
//                    if llama_decode(context, batch) != 0 {
//                        throw ModelError.failedToEval
//                    }
                    var outputBatch = [outputToken]
                    if llama_eval(self.context, outputBatch.mutPtr, Int32(outputBatch.count), min(self.contextParams.context, self.nPast)) != 0 {
                        throw ModelError.failedToEval
                    }
                    
//                    try ExceptionCatcher.catchException {
//                        eval_res = try? self.llm_eval(inputBatch: [outputToken])
//                    }
//                    if eval_res == false{
//                        print("Eval res false")
//                        throw ModelError.failedToEval
//                    }
                    
                    // Increment past count
                    nPast += 1
                }
            }
            // Update past with most recent response
            past.append(outputTokens)
//            print("Total tokens: \(inputTokensCount + outputTokens.count) (\(inputTokensCount) -> \(outputTokens.count))")
//            print("Past token count: \(nPast)/\(contextLength) (\(past.count))")
            // Return full string for case without callback
            return output
        } catch {
            print(error)
            throw error
        }
    }
   
    private func token_to_piece(token: llama_token) -> String {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: Int8(0), count: 8)
        defer {
            result.deallocate()
        }
        let nTokens = llama_token_to_piece(model, token, result, 8)
        
        if nTokens < 0 {
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-nTokens))
            newResult.initialize(repeating: Int8(0), count: Int(-nTokens))
            defer {
                newResult.deallocate()
            }
            _ = llama_token_to_piece(model, token, newResult, -nTokens)
            return String(cString: newResult)
        } else {
            return String(cString: result)
        }
    }
    
    public func tokenizePrompt(_ input: String, format: String, output: String? = nil) -> [ModelToken] {
        var formated_input = format.replacingOccurrences(of: "{{prompt}}", with: input)
        if let output = output {
            formated_input += output
        }
        // TODO: Maybe not necessary?
        formated_input = formated_input.replacingOccurrences(of: "\\n", with: "\n")
        let bos = !formated_input.contains("<s>")
        return llm_tokenize(formated_input, bos: bos)
    }
    
    // Simple topK, topP, temp sampling, with repeat penalty
    func llm_sample(ctx: OpaquePointer!,
                    last_n_tokens: inout [ModelToken],
                    temp: Float32,
                    top_k: Int32,
                    top_p: Float32,
                    tfs_z: Float32,
                    typical_p: Float32,
                    repeat_last_n: Int32,
                    repeat_penalty: Float32,
                    alpha_presence: Float32,
                    alpha_frequency: Float32,
                    mirostat: Int32,
                    mirostat_tau: Float32,
                    mirostat_eta: Float32,
                    penalize_nl: Bool) -> ModelToken {
        // Model input context size
        let n_ctx = llama_n_ctx(ctx)
        
        // Auto params
        let top_k = top_k <= 0 ? llama_n_vocab(model) : top_k
        let repeat_last_n = repeat_last_n < 0 ? n_ctx : repeat_last_n
        
        //
        let vocabSize = llama_n_vocab(model)
        guard let logits = llama_get_logits_ith(context, batch.n_tokens - 1) else {
            print("GPT sample error logits nil")
            return 0
        }
        var candidates = Array<llama_token_data>()
        for i in 0..<vocabSize {
            candidates.append(llama_token_data(id: i, logit: logits[Int(i)], p: 0.0))
        }
        var candidates_p = llama_token_data_array(data: candidates.mutPtr, size: candidates.count, sorted: false)
        
        // Apply penalties
        let nl_token = Int(llama_token_nl(model))
        //        let nl_logit = logits[nl_token]
        let nl_index = max(0, min(Int(vocabSize) - 1, nl_token))
        let nl_logit = logits[nl_index]
        let last_n_repeat = min(min(Int32(last_n_tokens.count), repeat_last_n), n_ctx)
        
        //        llama_sample_repetition_penalty(ctx, &candidates_p,
        //                    last_n_tokens.mutPtr.advanced(by: last_n_tokens.count - Int(repeat_last_n)),
        //                    Int(repeat_last_n), repeat_penalty)
        if !last_n_tokens.isEmpty {
            llama_sample_repetition_penalties(
                ctx,
                &candidates_p,
                last_n_tokens.mutPtr.advanced(by: last_n_tokens.count - Int(repeat_last_n)),
                Int(last_n_repeat),
                repeat_penalty,
                alpha_frequency,
                alpha_presence)
            if !penalize_nl {
                logits[nl_token] = nl_logit
            }
        }
        
        if grammar != nil {
            llama_sample_grammar(ctx, &candidates_p, grammar)
        }
        
        var res_token: Int32 = 0
        
        if temp <= 0 {
            // Greedy sampling
            res_token = llama_sample_token_greedy(ctx, &candidates_p)
        } else {
            var class_name = String(describing: self)
            // Mirostat currently unused...
            if mirostat == 1 {
                var mirostat_mu: Float = 2.0 * mirostat_tau
                let mirostat_m = 100
                llama_sample_temp(ctx, &candidates_p, temp)
                res_token =  llama_sample_token_mirostat(ctx, &candidates_p, mirostat_tau, mirostat_eta, Int32(mirostat_m), &mirostat_mu); // vocabSize);
            } else if mirostat == 2 {
                var mirostat_mu: Float = 2.0 * mirostat_tau
                llama_sample_temp(ctx, &candidates_p, temp)
                res_token =  llama_sample_token_mirostat_v2(ctx, &candidates_p, mirostat_tau, mirostat_eta, &mirostat_mu)
            } else {
                // Temperature sampling
                llama_sample_top_k(ctx, &candidates_p, top_k, 1)
                llama_sample_tail_free(ctx, &candidates_p, tfs_z, 1)
                llama_sample_typical(ctx, &candidates_p, typical_p, 1)
                llama_sample_top_p(ctx, &candidates_p, top_p, 1)
//                llama_sample_min_p(ctx, &candidates_p, min_p, 1) // TODO: implement
                llama_sample_temp(ctx, &candidates_p, temp)
                res_token = llama_sample_token(ctx, &candidates_p)
            }
        }
        
        if grammar != nil {
            llama_grammar_accept_token(ctx, grammar, res_token);
        }
        return res_token
    }
    
    public func reinitialize(systemPrompt: String?) throws {
        past.removeAll(keepingCapacity: true)
        nPast = 0
        
        llama_kv_cache_clear(context)
        
        if let prompt = systemPrompt {
            var inputTokens = tokenizePrompt(prompt, format: systemFormat)
            if inputTokens.count == 0 {
                return
            }
            let inputTokensCount = inputTokens.count
            if inputTokensCount > Int32(contextParams.context) {
                throw ModelError.inputTooLong
            }
            past.append(inputTokens)
        }
    }
    
    // FIXME: proper context size checking incl. past tokens...
    public func preparePast(messages: [(String, String)]) throws {
        let params = sampleParams
        let contextLength = Int32(contextParams.context)
        
        for message in messages {
            let (input, output) = message
            //        print("Past token count: \(nPast)/\(contextLength) (\(past.count))")
            // Tokenize with prompt format
            var inputTokens = tokenizePrompt(input, format: promptFormat, output: output)
            if inputTokens.count == 0 {
                return
            }
            //            self.session_tokens.append(contentsOf: inputTokens)
            let inputTokensCount = inputTokens.count
            //        print("Input tokens: \(inputTokens)")
            // Add new input tokens to past array
            // Create space in context if needed
            if inputTokensCount > contextLength {
                throw ModelError.inputTooLong
            }
            // Output
//            var outputTokens = tokenizePrompt(input, format: promptFormat, output: output)
            // TODO: Maybe not necessary for output?
            let bos = !output.contains("<s>")
            let outputTokens = llm_tokenize(output, bos: bos)

            // Update past with most recent response
            past.append(outputTokens)
        }
    }
    
//    public override func llm_eval(inputBatch:[ModelToken]) throws -> Bool{
//        var mutable_inputBatch = inputBatch
//        if llama_eval(self.context, mutable_inputBatch.mutPtr, Int32(inputBatch.count), min(self.contextParams.context, self.nPast)) != 0 {
//            return false
//        }
//        return true
//    }
    
    public func llm_tokenize(_ input: String, bos: Bool = true, eos: Bool = false) -> [ModelToken] {
        if input.count == 0 {
            return []
        }

        let n_tokens = Int32(input.utf8.count) + (bos == true ? 1 : 0)
        var embeddings: [llama_token] = Array<llama_token>(repeating: llama_token(), count: input.utf8.count)
        print("### TOKENIZING: \(input)")
        let n = llama_tokenize(self.model, input, Int32(input.utf8.count), &embeddings, n_tokens, bos, true)
        if n <= 0 {
            return []
        }
        if Int(n) <= embeddings.count {
            embeddings.removeSubrange(Int(n)..<embeddings.count)
        }
        
        if eos {
            embeddings.append(llama_token_eos(self.model))
        }
        
        return embeddings
    }
}

