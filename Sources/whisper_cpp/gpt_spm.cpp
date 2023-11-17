#include "./include/gpt_spm.h"
#include "gpt_helpers.h"
//#include "./spm-headers/llama_dadbed9.h"
//#include "./spm-headers/llama.h"
//#include "llama.h"
#include "common.h"
#include "common-ggml.h"
//#include "./include/rwkv.h"
#include "grammar-parser.h"
//#include "ggml_dadbed9.h"
#include "ggml.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cinttypes>
#include <fstream>
#include <map>
#include <string>
#include <vector>
#include <random>

//
//
//gpt_token gpt_base_token_bos(){
//   return 0;
//}
//
//gpt_token gpt_base_token_eos() {
//    return 0;
//}
//
////const char * print_system_info(void) {
////    static std::string s;
////
////    s  = "";
////    s += "AVX = "         + std::to_string(ggml_dadbed9_cpu_has_avx())         + " | ";
////    s += "AVX2 = "        + std::to_string(ggml_dadbed9_cpu_has_avx2())        + " | ";
////    s += "AVX512 = "      + std::to_string(ggml_dadbed9_cpu_has_avx512())      + " | ";
////    s += "AVX512_VBMI = " + std::to_string(ggml_dadbed9_cpu_has_avx512_vbmi()) + " | ";
////    s += "AVX512_VNNI = " + std::to_string(ggml_dadbed9_cpu_has_avx512_vnni()) + " | ";
////    s += "FMA = "         + std::to_string(ggml_dadbed9_cpu_has_fma())         + " | ";
////    s += "NEON = "        + std::to_string(ggml_dadbed9_cpu_has_neon())        + " | ";
////    s += "ARM_FMA = "     + std::to_string(ggml_dadbed9_cpu_has_arm_fma())     + " | ";
////    s += "F16C = "        + std::to_string(ggml_dadbed9_cpu_has_f16c())        + " | ";
////    s += "FP16_VA = "     + std::to_string(ggml_dadbed9_cpu_has_fp16_va())     + " | ";
////    s += "WASM_SIMD = "   + std::to_string(ggml_dadbed9_cpu_has_wasm_simd())   + " | ";
////    s += "BLAS = "        + std::to_string(ggml_dadbed9_cpu_has_blas())        + " | ";
////    s += "SSE3 = "        + std::to_string(ggml_dadbed9_cpu_has_sse3())        + " | ";
////    s += "VSX = "         + std::to_string(ggml_dadbed9_cpu_has_vsx())         + " | ";
////
////    return s.c_str();
////}

const char * print_system_info(void) {
    static std::string s;

    s  = "";
    s += "AVX = "         + std::to_string(ggml_cpu_has_avx())         + " | ";
    s += "AVX2 = "        + std::to_string(ggml_cpu_has_avx2())        + " | ";
    s += "AVX512 = "      + std::to_string(ggml_cpu_has_avx512())      + " | ";
    s += "AVX512_VBMI = " + std::to_string(ggml_cpu_has_avx512_vbmi()) + " | ";
    s += "AVX512_VNNI = " + std::to_string(ggml_cpu_has_avx512_vnni()) + " | ";
    s += "FMA = "         + std::to_string(ggml_cpu_has_fma())         + " | ";
    s += "NEON = "        + std::to_string(ggml_cpu_has_neon())        + " | ";
    s += "ARM_FMA = "     + std::to_string(ggml_cpu_has_arm_fma())     + " | ";
    s += "F16C = "        + std::to_string(ggml_cpu_has_f16c())        + " | ";
    s += "FP16_VA = "     + std::to_string(ggml_cpu_has_fp16_va())     + " | ";
    s += "WASM_SIMD = "   + std::to_string(ggml_cpu_has_wasm_simd())   + " | ";
    s += "BLAS = "        + std::to_string(ggml_cpu_has_blas())        + " | ";
    s += "SSE3 = "        + std::to_string(ggml_cpu_has_sse3())        + " | ";
    s += "SSSE3 = "       + std::to_string(ggml_cpu_has_ssse3())       + " | ";
    s += "VSX = "         + std::to_string(ggml_cpu_has_vsx())         + " | ";

    return s.c_str();
}

//struct gpt_context_params gpt_context_default_params() {
//    struct gpt_context_params result = {
//        /*.n_ctx                       =*/ 512,
//        /*.n_parts                     =*/ -1,
//        /*.seed                        =*/ 0,
//        /*.n_batch                     =*/ 8,
//        /*.f16_kv                      =*/ false,
//        /*.logits_all                  =*/ false,
//        /*.vocab_only                  =*/ false,
//        /*.use_mmap                    =*/ true,
//        /*.use_mlock                   =*/ false,
//        /*.embedding                   =*/ false,
//        /*.progress_callback           =*/ nullptr,
//        /*.progress_callback_user_data =*/ nullptr,
//    };
//    return result;
//};
//
//
//int gpt_base_n_vocab(struct gpt_base_context * ctx) {
//    return ctx->vocab.id_to_token.size();
//}
//
//int gpt_base_n_ctx(struct gpt_base_context * ctx) {
//    return ctx->model.hparams.n_ctx;
//}
//
//int gpt_base_n_embd(struct gpt_base_context * ctx) {
//    return ctx->model.hparams.n_embd;
//}
//
//float * gpt_base_get_logits(struct gpt_base_context * ctx) {
//    return ctx->logits.data();
//}
//
//float * gpt_base_get_embeddings(struct gpt_base_context * ctx) {
//    return ctx->embedding.data();
//}
//
//gpt_token gpt_base_str_to_token(struct gpt_base_context * ctx, const char * str) {
//    return ctx->vocab.token_to_id[str];
//}
//
//const char * gpt_base_token_to_str(struct gpt_base_context * ctx, gpt_token token) {
//    if (token >= ctx->vocab.id_to_token.size()) {
//        return nullptr;
//    }
//    return ctx->vocab.id_to_token[token].c_str();
//}
//
//
//
//
//int gpt_base_tokenize(
//        struct gpt_base_context * ctx,
//                  const char * text,
//                 gpt_token * tokens,
//                         int   n_max_tokens,
//                        bool   add_bos) {
////    auto res = gptneox_tokenize(ctx->vocab, text, add_bos);
//    auto res = gpt_tokenize(ctx->vocab, text);
//    
//    if (n_max_tokens < (int) res.size()) {
//        fprintf(stderr, "%s: too many tokens\n", __func__);
//        return -((int) res.size());
//    }
//
//    for (size_t i = 0; i < res.size(); i++) {
//        tokens[i] = res[i];
//    }
//
//    return res.size();
//}
//
//
////void rwkv_tokenize(){
////    
////}
////
////void rwkv_init_logits(struct rwkv_context * model) {
////
//////    struct rwkv_context * model = rwkv_init_from_file(model_path, N_THREADS);
//////    enum rwkv_error_flags error = rwkv_get_last_error(NULL);
//////    ASSERT(error == 0, "Unexpected error %d", error);
//////
//////#ifdef GGML_dadbed9_USE_CUBLAS
//////    ASSERT(rwkv_gpu_offload_layers(model, rwkv_get_n_layer(model)), "Failed to offload layers to GPU");
//////#endif
////
////    const size_t n_vocab = rwkv_get_logits_len(model);
////
////
////    float * state = (float * )malloc(sizeof(float) * rwkv_get_state_len(model));
////    float * logits = (float * )malloc(sizeof(float) * n_vocab);
////
////    uint32_t prompt_seq[] = { 10002, 209, 312, 209, 74 };
////
////    const size_t prompt_length = 4;
////
////    rwkv_init_state(model, state);
////    rwkv_eval_sequence(model, prompt_seq, prompt_length, state, state, logits);
////
////}
//
////int32_t rwkv_sample(int n_logits, float * logits, int top_k, float top_p, float temp) {
////    std::mt19937 rng = std::mt19937(time(NULL));
//////    gpt_vocab::id smpl = gpt_sample_top_k_top_p(n_logits, logits, top_k, top_p, temp, rng);
////    gpt_vocab::id smpl = gpt_sample_top_k_top_p(n_logits, logits, top_k, top_p, temp, rng);
////    return  smpl;
////}
//
//
////int32_t rwkv_sample_repeat(int n_logits, float * logits,
////                               const int32_t * last_n_tokens_data,
////                               size_t last_n_tokens_data_size,
////                               int top_k, float top_p, float temp,
////                               int repeat_last_n,
////                               float repeat_penalty) {
////    std::mt19937 rng = std::mt19937(time(NULL));
////    gpt_vocab::id smpl = gpt_sample_top_k_top_p_repeat(n_logits, logits,
////                                                       last_n_tokens_data,last_n_tokens_data_size,
////                                                       top_k, top_p, temp,
////                                                       repeat_last_n,repeat_penalty,
////                                                       rng);
////    return  smpl;
////}

char* llama_token_to_str_res = new char[3];

const char * llama_token_to_str(const struct llama_context * ctx, llama_token token) {
    std::vector<char> result(8, 0);
    const int n_tokens = llama_token_to_piece(llama_get_model(ctx), token, result.data(), result.size());
    if (n_tokens < 0) {
        result.resize(-n_tokens);
        int check = llama_token_to_piece(llama_get_model(ctx), token, result.data(), result.size());
        GGML_ASSERT(check == -n_tokens);
    } else {
        result.resize(n_tokens);
    }
//    auto res = std::string(result.data(), result.size());
//    fprintf(stderr, "%s: %s\n", __func__,res.c_str());
    strcpy(llama_token_to_str_res, std::string(result.data(), result.size()).c_str());
    return  llama_token_to_str_res;
//    return res.c_str();
}

struct llama_grammar* llama_load_grammar(const char* grammar_path){
    struct llama_grammar * grammar = NULL;
    grammar_parser::parse_state parsed_grammar;
    
    std::ifstream infile;
    infile.open(grammar_path, std::ios::binary);
    infile.seekg(0, std::ios::end);
    size_t file_size_in_byte = infile.tellg();
    std::vector<char> grammar_context; // used to store text data
    grammar_context.resize(file_size_in_byte);
    infile.seekg(0, std::ios::beg);
    infile.read(&grammar_context[0], file_size_in_byte);
    
    parsed_grammar = grammar_parser::parse(grammar_context.data());
    // will be empty (default) if there are parse errors
    if (parsed_grammar.rules.empty()) {
        return NULL;
    }
    grammar_parser::print_grammar(stderr, parsed_grammar);
    std::vector<const llama_grammar_element *> grammar_rules(parsed_grammar.c_rules());
    grammar = llama_grammar_init(grammar_rules.data(), grammar_rules.size(), parsed_grammar.symbol_ids.at("root"));
    return grammar;
}
