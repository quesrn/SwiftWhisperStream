//
//  GPTNeoX.swift
//  Mia
//
//  Created by Byron Everson on 4/19/23.
//

import Foundation
import whisper_cpp

public class Starcoder: LLMBase {

    public override func llm_load_model(path: String = "", contextParams: ModelAndContextParams = .default, params:gpt_context_params ) throws -> Bool{
        self.context = starcoder_init_from_file(path, params)
        if self.context == nil {
            return false
        }
        self.promptFormat = .None
        return true
    }
    
    deinit {
        starcoder_free(context)
    }
    
    public override func llm_eval(inputBatch:[ModelToken]) throws -> Bool{
        if starcoder_eval(context, inputBatch, Int32(inputBatch.count), nPast, contextParams.n_threads) != 0 {
            throw ModelError.failedToEval
        }
        return true
    }
    
}

