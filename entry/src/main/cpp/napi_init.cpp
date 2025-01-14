#include <cstdint>
#include <vector>
#include <string>

#include "PowerServe/app/server/local_server.hpp"
#include "napi/native_api.h"
#include <memory>
#include <string>
#include <js_native_api.h>
#include <js_native_api_types.h>

static std::unique_ptr<LocalServer> g_local_server_ptr;

static napi_value NAPI_Global_powerserveInfer(napi_env env, napi_callback_info info) {
    /*
     * Parse arguments
     */
    size_t input_argc = 2;
    napi_value input_argv[2] = { nullptr };
    napi_get_cb_info(env, info, &input_argc, input_argv, nullptr, nullptr);
    
    std::string work_folder;
    {
        napi_valuetype input_argv_type;
        napi_typeof(env, input_argv[0], &input_argv_type);
        
        work_folder.resize(256, 0);
        
        size_t content_size = 0;
        napi_get_value_string_utf8(env, input_argv[0], work_folder.data(), work_folder.size(), &content_size);
        work_folder.resize(content_size);
    }
    
    std::string request;
    {
        napi_valuetype input_argv_type;
        napi_typeof(env, input_argv[1], &input_argv_type);
        
        request.resize(2048, 0);
        
        size_t content_size = 0;
        napi_get_value_string_utf8(env, input_argv[1], request.data(), request.size(), &content_size);
        request.resize(content_size);
    }
    
    /*
     * Generate request
     */
    
    if (g_local_server_ptr == nullptr) {
        g_local_server_ptr = std::make_unique<LocalServer>(work_folder, "");
    }
    
    const LocalRequest local_request{request};
    LocalResponse *response_ptr = g_local_server_ptr->create_chat_response(local_request);
    
    const uint64_t response_ptr_val = (uint64_t)response_ptr;
    napi_value napi_result;
    napi_create_bigint_uint64(env, response_ptr_val, &napi_result);
    return napi_result;
}

static napi_value NAPI_Global_powerserveInferGetResponse(napi_env env, napi_callback_info info) {
    size_t input_argc = 1;
    napi_value input_argv[1] = { nullptr };
    napi_get_cb_info(env, info, &input_argc, input_argv, nullptr, nullptr);
    
    uint64_t response_ptr_val = 0;
    {
        napi_valuetype input_argv_type;
        napi_typeof(env, input_argv[0], &input_argv_type);
        
        bool lossless = true;
        napi_get_value_bigint_uint64(env, input_argv[0], &response_ptr_val, &lossless);
    }
    
    try {
        // try to get response
        LocalResponse *response_ptr = (LocalResponse *)response_ptr_val;
        const std::optional<std::string> response_chunk = g_local_server_ptr->get_response(response_ptr);
        const std::string response_string = response_chunk.value_or("");
        if (response_string.empty()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
        napi_value napi_response;
        napi_create_string_utf8(env, response_string.data(), response_string.size(), &napi_response);
        return napi_response;
    } catch (std::exception &err) {
        // return error information
        const auto error_response = std::string("[ERROR]: ") + err.what();
        napi_value napi_response;
        napi_create_string_utf8(env, error_response.data(), error_response.size(), &napi_response);
        return napi_response;
    }
}

static napi_value NAPI_Global_powerserveInferDestroyResponse(napi_env env, napi_callback_info info) {
    size_t input_argc = 1;
    napi_value input_argv[1] = { nullptr };
    napi_get_cb_info(env, info, &input_argc, input_argv, nullptr, nullptr);
    
    uint64_t response_ptr_val = 0;
    {
        napi_valuetype input_argv_type;
        napi_typeof(env, input_argv[0], &input_argv_type);
        
        bool lossless = true;
        napi_get_value_bigint_uint64(env, input_argv[0], &response_ptr_val, &lossless);
    }
    
    try {
        // try to get response
        LocalResponse *response_ptr = (LocalResponse *)response_ptr_val;
        g_local_server_ptr->destroy_response(response_ptr);
    } catch (std::exception &err) {
    }
    
    napi_value napi_response;
    return napi_response;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "powerserveInfer", nullptr, NAPI_Global_powerserveInfer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "powerserveInferGetResponse", nullptr, NAPI_Global_powerserveInferGetResponse, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "powerserveInferDestroyResponse", nullptr, NAPI_Global_powerserveInferDestroyResponse, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&demoModule);
}
