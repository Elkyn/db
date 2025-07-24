#include <node_api.h>
#include <string>
#include <memory>
#include <map>
#include <cstring>

// Forward declarations for C functions from Zig
extern "C" {
    typedef struct ElkynDB ElkynDB;
    
    ElkynDB* elkyn_init(const char* data_dir);
    void elkyn_deinit(ElkynDB* db);
    int elkyn_enable_auth(ElkynDB* db, const char* secret);
    int elkyn_enable_rules(ElkynDB* db, const char* rules_json);
    int elkyn_set_string(ElkynDB* db, const char* path, const char* value, const char* token);
    char* elkyn_get_string(ElkynDB* db, const char* path, const char* token);
    int elkyn_delete(ElkynDB* db, const char* path, const char* token);
    char* elkyn_create_token(ElkynDB* db, const char* uid, const char* email);
    void elkyn_free_string(char* ptr);
}

// Global map to store DB instances
static std::map<std::string, ElkynDB*> db_instances;

#define DECLARE_NAPI_METHOD(name, func) \
    { name, 0, func, 0, 0, 0, napi_default, 0 }

// Helper to get string from napi_value
std::string GetStringFromValue(napi_env env, napi_value value) {
    size_t length;
    napi_get_value_string_utf8(env, value, nullptr, 0, &length);
    std::string result(length, '\0');
    napi_get_value_string_utf8(env, value, &result[0], length + 1, &length);
    return result;
}

// Initialize database
napi_value Init(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "data_dir argument required");
        return nullptr;
    }
    
    std::string data_dir = GetStringFromValue(env, args[0]);
    
    ElkynDB* db = elkyn_init(data_dir.c_str());
    if (!db) {
        napi_throw_error(env, nullptr, "Failed to initialize database");
        return nullptr;
    }
    
    // Store in global map
    db_instances[data_dir] = db;
    
    // Return the data_dir as handle
    napi_value result;
    napi_create_string_utf8(env, data_dir.c_str(), data_dir.length(), &result);
    return result;
}

// Enable authentication
napi_value EnableAuth(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "handle and secret arguments required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string secret = GetStringFromValue(env, args[1]);
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    int result = elkyn_enable_auth(it->second, secret.c_str());
    
    napi_value js_result;
    napi_create_int32(env, result, &js_result);
    return js_result;
}

// Enable rules
napi_value EnableRules(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "handle and rules_json arguments required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string rules_json = GetStringFromValue(env, args[1]);
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    int result = elkyn_enable_rules(it->second, rules_json.c_str());
    
    napi_value js_result;
    napi_create_int32(env, result, &js_result);
    return js_result;
}

// Set string value
napi_value SetString(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        napi_throw_error(env, nullptr, "handle, path, and value arguments required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string path = GetStringFromValue(env, args[1]);
    std::string value = GetStringFromValue(env, args[2]);
    
    const char* token = nullptr;
    std::string token_str;
    if (argc >= 4) {
        napi_valuetype type;
        napi_typeof(env, args[3], &type);
        if (type == napi_string) {
            token_str = GetStringFromValue(env, args[3]);
            token = token_str.c_str();
        }
    }
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    int result = elkyn_set_string(it->second, path.c_str(), value.c_str(), token);
    
    napi_value js_result;
    napi_create_int32(env, result, &js_result);
    return js_result;
}

// Get string value
napi_value GetString(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "handle and path arguments required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string path = GetStringFromValue(env, args[1]);
    
    const char* token = nullptr;
    std::string token_str;
    if (argc >= 3) {
        napi_valuetype type;
        napi_typeof(env, args[2], &type);
        if (type == napi_string) {
            token_str = GetStringFromValue(env, args[2]);
            token = token_str.c_str();
        }
    }
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    char* result_str = elkyn_get_string(it->second, path.c_str(), token);
    if (!result_str) {
        return nullptr; // null
    }
    
    napi_value result;
    napi_create_string_utf8(env, result_str, strlen(result_str), &result);
    elkyn_free_string(result_str);
    
    return result;
}

// Delete value
napi_value Delete(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "handle and path arguments required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string path = GetStringFromValue(env, args[1]);
    
    const char* token = nullptr;
    std::string token_str;
    if (argc >= 3) {
        napi_valuetype type;
        napi_typeof(env, args[2], &type);
        if (type == napi_string) {
            token_str = GetStringFromValue(env, args[2]);
            token = token_str.c_str();
        }
    }
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    int result = elkyn_delete(it->second, path.c_str(), token);
    
    napi_value js_result;
    napi_create_int32(env, result, &js_result);
    return js_result;
}

// Create token
napi_value CreateToken(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "handle and uid arguments required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string uid = GetStringFromValue(env, args[1]);
    
    const char* email = nullptr;
    std::string email_str;
    if (argc >= 3) {
        napi_valuetype type;
        napi_typeof(env, args[2], &type);
        if (type == napi_string) {
            email_str = GetStringFromValue(env, args[2]);
            email = email_str.c_str();
        }
    }
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    char* token = elkyn_create_token(it->second, uid.c_str(), email);
    if (!token) {
        napi_throw_error(env, nullptr, "Failed to create token");
        return nullptr;
    }
    
    napi_value result;
    napi_create_string_utf8(env, token, strlen(token), &result);
    elkyn_free_string(token);
    
    return result;
}

// Close database
napi_value Close(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "handle argument required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    
    auto it = db_instances.find(handle);
    if (it != db_instances.end()) {
        elkyn_deinit(it->second);
        db_instances.erase(it);
    }
    
    return nullptr;
}

// Module initialization
napi_value InitModule(napi_env env, napi_value exports) {
    napi_property_descriptor properties[] = {
        DECLARE_NAPI_METHOD("init", Init),
        DECLARE_NAPI_METHOD("enableAuth", EnableAuth),
        DECLARE_NAPI_METHOD("enableRules", EnableRules),
        DECLARE_NAPI_METHOD("setString", SetString),
        DECLARE_NAPI_METHOD("getString", GetString),
        DECLARE_NAPI_METHOD("delete", Delete),
        DECLARE_NAPI_METHOD("createToken", CreateToken),
        DECLARE_NAPI_METHOD("close", Close),
    };
    
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

NAPI_MODULE(elkyn_store, InitModule)