#include <node_api.h>
#include <string>
#include <memory>
#include <map>
#include <cstring>
#include <thread>
#include <atomic>
#include <vector>
#include <chrono>

// Forward declarations for C functions from Zig
extern "C" {
    typedef struct ElkynDB ElkynDB;
    
    ElkynDB* elkyn_init(const char* data_dir);
    void elkyn_deinit(ElkynDB* db);
    int elkyn_enable_auth(ElkynDB* db, const char* secret);
    int elkyn_enable_rules(ElkynDB* db, const char* rules_json);
    int elkyn_set_string(ElkynDB* db, const char* path, const char* value, const char* token);
    char* elkyn_get_string(ElkynDB* db, const char* path, const char* token);
    int elkyn_set_binary(ElkynDB* db, const char* path, const void* data, size_t length, const char* token);
    void* elkyn_get_binary(ElkynDB* db, const char* path, size_t* length, const char* token);
    int elkyn_delete(ElkynDB* db, const char* path, const char* token);
    char* elkyn_create_token(ElkynDB* db, const char* uid, const char* email);
    void elkyn_free_string(char* ptr);
    
    // Zero-copy read
    struct ReadInfo {
        const uint8_t* data;
        size_t length;
        uint8_t type_tag;
        bool needs_free;
    };
    int elkyn_get_raw(ElkynDB* db, const char* path, ReadInfo* info, const char* token);
    
    // Event queue functions
    int elkyn_enable_event_queue(ElkynDB* db);
    
    struct C_EventData {
        uint8_t type;
        const char* path;
        const char* value;
        uint64_t sequence;
        int64_t timestamp;
    };
    
    size_t elkyn_event_queue_pop_batch(ElkynDB* db, C_EventData* buffer, size_t max_count);
    size_t elkyn_event_queue_pending(ElkynDB* db);
    
    // Write queue functions
    int elkyn_enable_write_queue(ElkynDB* db);
    uint64_t elkyn_set_async(ElkynDB* db, const char* path, const void* data, size_t length, const char* token);
    uint64_t elkyn_delete_async(ElkynDB* db, const char* path, const char* token);
    int elkyn_wait_for_write(ElkynDB* db, uint64_t id);
    
    // SharedArrayBuffer functions
    int elkyn_enable_sab_queue(ElkynDB* db, uint8_t* sab_ptr, uint32_t size);
    int elkyn_sab_queue_stats(ElkynDB* db, uint32_t* head, uint32_t* tail, uint32_t* pending);
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

// Set binary value (MessagePack)
napi_value SetBinary(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        napi_throw_error(env, nullptr, "handle, path, and binaryData arguments required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string path = GetStringFromValue(env, args[1]);
    
    // Get binary data from Buffer
    void* data;
    size_t length;
    napi_status status = napi_get_buffer_info(env, args[2], &data, &length);
    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Expected Buffer for binaryData argument");
        return nullptr;
    }
    
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
    
    int result = elkyn_set_binary(it->second, path.c_str(), data, length, token);
    
    napi_value js_result;
    napi_create_int32(env, result, &js_result);
    return js_result;
}

// Get binary value (MessagePack)
napi_value GetBinary(napi_env env, napi_callback_info info) {
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
    
    size_t length;
    void* data = elkyn_get_binary(it->second, path.c_str(), &length, token);
    if (!data) {
        return nullptr; // null
    }
    
    napi_value result;
    napi_create_buffer_copy(env, length, data, nullptr, &result);
    free(data); // elkyn_get_binary allocates, we need to free
    
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

// Event queue support
struct EventListener {
    napi_threadsafe_function tsfn;
    std::string pattern;
    std::atomic<bool> active{true};
};

// Event handling globals
static std::map<std::string, std::vector<std::unique_ptr<EventListener>>> event_listeners;
static std::map<std::string, std::thread> event_threads;
static std::atomic<uint64_t> next_subscription_id{1};

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
    
    // Clean up event listeners first
    auto listeners_it = event_listeners.find(handle);
    if (listeners_it != event_listeners.end()) {
        for (auto& listener : listeners_it->second) {
            listener->active.store(false);
            napi_release_threadsafe_function(listener->tsfn, napi_tsfn_abort);
        }
        event_listeners.erase(listeners_it);
    }
    
    // Clean up the database and signal thread to exit
    auto it = db_instances.find(handle);
    ElkynDB* db = nullptr;
    if (it != db_instances.end()) {
        db = it->second;
        db_instances.erase(it);
    }
    
    // Wait for event thread to finish
    auto thread_it = event_threads.find(handle);
    if (thread_it != event_threads.end()) {
        // Wait for thread to finish
        thread_it->second.join();
        event_threads.erase(thread_it);
    }
    
    // Now deinit the database
    if (db != nullptr) {
        elkyn_deinit(db);
    }
    
    return nullptr;
}

// Enable event queue
napi_value EnableEventQueue(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "handle argument required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    int result = elkyn_enable_event_queue(it->second);
    
    // printf("EnableEventQueue: result=%d for handle=%s\n", result, handle.c_str());
    
    // Start event processing thread if not already running
    if (result == 0 && event_threads.find(handle) == event_threads.end()) {
        event_threads[handle] = std::thread([handle, db = it->second]() {
            const size_t BATCH_SIZE = 64;
            std::vector<C_EventData> events(BATCH_SIZE);
            
            // printf("Event thread started for handle=%s\n", handle.c_str());
            
            while (db_instances.find(handle) != db_instances.end()) {
                size_t pending = elkyn_event_queue_pending(db);
                // if (pending > 0) {
                //     printf("Event thread: %zu events pending\n", pending);
                // }
                
                size_t count = elkyn_event_queue_pop_batch(db, events.data(), BATCH_SIZE);
                
                if (count == 0) {
                    std::this_thread::sleep_for(std::chrono::microseconds(100));
                    continue;
                }
                
                // printf("Event thread: popped %zu events\n", count);
                
                // Process events
                auto listeners_it = event_listeners.find(handle);
                if (listeners_it != event_listeners.end()) {
                    // printf("Event thread: found %zu listeners for handle=%s\n", listeners_it->second.size(), handle.c_str());
                    for (size_t i = 0; i < count; i++) {
                        const C_EventData& event = events[i];
                        // printf("Event thread: processing event path=%s type=%d\n", event.path, event.type);
                        
                        // Call each matching listener
                        for (const auto& listener : listeners_it->second) {
                            if (!listener->active.load()) continue;
                            
                            // Simple pattern matching
                            bool matches = false;
                            if (listener->pattern == "/") {
                                matches = true;
                            } else if (listener->pattern.back() == '*') {
                                std::string prefix = listener->pattern.substr(0, listener->pattern.length() - 1);
                                matches = (std::string(event.path).substr(0, prefix.length()) == prefix);
                            } else {
                                matches = (listener->pattern == event.path);
                            }
                            
                            // printf("Event thread: listener pattern=%s matches=%d\n", listener->pattern.c_str(), matches);
                            
                            if (matches) {
                                // Create a deep copy of the event data
                                auto* event_copy = new C_EventData();
                                event_copy->type = event.type;
                                event_copy->sequence = event.sequence;
                                event_copy->timestamp = event.timestamp;
                                
                                // Copy strings
                                if (event.path) {
                                    size_t len = strlen(event.path);
                                    char* path_copy = new char[len + 1];
                                    strcpy(path_copy, event.path);
                                    event_copy->path = path_copy;
                                } else {
                                    event_copy->path = nullptr;
                                }
                                
                                if (event.value) {
                                    size_t len = strlen(event.value);
                                    char* value_copy = new char[len + 1];
                                    strcpy(value_copy, event.value);
                                    event_copy->value = value_copy;
                                } else {
                                    event_copy->value = nullptr;
                                }
                                
                                // printf("Event thread: passing event to N-API, path=%s\n", event_copy->path);
                                napi_call_threadsafe_function(
                                    listener->tsfn,
                                    event_copy,
                                    napi_tsfn_nonblocking
                                );
                            }
                        }
                    }
                } else {
                    // printf("Event thread: no listeners for handle=%s\n", handle.c_str());
                }
                
                // Free C strings now that all deep copies have been made
                for (size_t i = 0; i < count; i++) {
                    if (events[i].path) elkyn_free_string((char*)events[i].path);
                    if (events[i].value) elkyn_free_string((char*)events[i].value);
                }
            }
        });
    }
    
    napi_value js_result;
    napi_create_int32(env, result, &js_result);
    return js_result;
}

// Watch for changes
napi_value Watch(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        napi_throw_error(env, nullptr, "handle, pattern, and callback required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string pattern = GetStringFromValue(env, args[1]);
    napi_value callback = args[2];
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    // Enable event queue if not already enabled
    if (event_threads.find(handle) == event_threads.end()) {
        elkyn_enable_event_queue(it->second);
        EnableEventQueue(env, info); // Reuse the function to start thread
    }
    
    // Create event listener
    auto listener = std::make_unique<EventListener>();
    listener->pattern = pattern;
    
    // Create threadsafe function
    napi_value async_resource_name;
    napi_create_string_utf8(env, "elkynWatch", NAPI_AUTO_LENGTH, &async_resource_name);
    
    napi_create_threadsafe_function(
        env,
        callback,
        nullptr,
        async_resource_name,
        0,  // unlimited queue
        1,  // initial thread count
        nullptr,
        nullptr,
        listener.get(),
        [](napi_env env, napi_value js_callback, void* context, void* data) {
            // printf("N-API callback invoked\n");
            C_EventData* event = static_cast<C_EventData*>(data);
            
            if (!event) {
                // printf("ERROR: event is null!\n");
                return;
            }
            
            // printf("Event: path=%s type=%d\n", event->path ? event->path : "(null)", event->type);
            
            // Create event object
            napi_value event_obj;
            napi_create_object(env, &event_obj);
            
            // Type
            napi_value type_str;
            napi_create_string_utf8(env, 
                event->type == 1 ? "change" : "delete", 
                NAPI_AUTO_LENGTH, 
                &type_str
            );
            napi_set_named_property(env, event_obj, "type", type_str);
            
            // Path
            napi_value path_str;
            napi_create_string_utf8(env, event->path, NAPI_AUTO_LENGTH, &path_str);
            napi_set_named_property(env, event_obj, "path", path_str);
            
            // Value - pass as string, let JS handle parsing
            if (event->value) {
                napi_value value_str;
                napi_create_string_utf8(env, event->value, NAPI_AUTO_LENGTH, &value_str);
                napi_set_named_property(env, event_obj, "value", value_str);
            } else {
                napi_value null_value;
                napi_get_null(env, &null_value);
                napi_set_named_property(env, event_obj, "value", null_value);
            }
            
            // Timestamp
            napi_value timestamp;
            napi_create_int64(env, event->timestamp, &timestamp);
            napi_set_named_property(env, event_obj, "timestamp", timestamp);
            
            // Call callback
            // printf("Calling JS callback\n");
            napi_value global;
            napi_get_global(env, &global);
            
            napi_value argv[] = { event_obj };
            napi_value result;
            napi_status status = napi_call_function(env, global, js_callback, 1, argv, &result);
            if (status != napi_ok) {
                // printf("ERROR: Failed to call JS callback, status=%d\n", status);
                
                // Try to get error info
                const napi_extended_error_info* error_info;
                napi_get_last_error_info(env, &error_info);
                if (error_info->error_message) {
                    // printf("Error message: %s\n", error_info->error_message);
                }
            } // else {
                // printf("JS callback called successfully\n");
            // }
            
            // Clean up the deep copies
            if (event->path) {
                delete[] event->path;
            }
            if (event->value) {
                delete[] event->value;
            }
            delete event;
        },
        &listener->tsfn
    );
    
    // Generate subscription ID
    uint64_t subscription_id = next_subscription_id.fetch_add(1);
    
    // Store listener
    event_listeners[handle].push_back(std::move(listener));
    
    // Return subscription ID as string
    napi_value id_str;
    std::string id = std::to_string(subscription_id);
    napi_create_string_utf8(env, id.c_str(), id.length(), &id_str);
    return id_str;
}

// Unwatch
napi_value Unwatch(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "handle and subscriptionId required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string id_str = GetStringFromValue(env, args[1]);
    
    // For now, just return success
    // TODO: Implement proper subscription tracking
    
    return nullptr;
}

// Enable write queue
napi_value EnableWriteQueue(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "handle argument required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    int result = elkyn_enable_write_queue(it->second);
    
    napi_value js_result;
    napi_create_int32(env, result, &js_result);
    return js_result;
}

// Set binary async
napi_value SetBinaryAsync(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        napi_throw_error(env, nullptr, "handle, path, and binaryData arguments required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string path = GetStringFromValue(env, args[1]);
    
    // Get binary data from Buffer
    void* data;
    size_t length;
    napi_status status = napi_get_buffer_info(env, args[2], &data, &length);
    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Expected Buffer for binaryData argument");
        return nullptr;
    }
    
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
    
    uint64_t id = elkyn_set_async(it->second, path.c_str(), data, length, token);
    if (id == 0) {
        napi_throw_error(env, nullptr, "Failed to queue write operation");
        return nullptr;
    }
    
    // Return id as string
    napi_value js_result;
    std::string id_str = std::to_string(id);
    napi_create_string_utf8(env, id_str.c_str(), id_str.length(), &js_result);
    return js_result;
}

// Delete async
napi_value DeleteAsync(napi_env env, napi_callback_info info) {
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
    
    uint64_t id = elkyn_delete_async(it->second, path.c_str(), token);
    if (id == 0) {
        napi_throw_error(env, nullptr, "Failed to queue delete operation");
        return nullptr;
    }
    
    // Return id as string
    napi_value js_result;
    std::string id_str = std::to_string(id);
    napi_create_string_utf8(env, id_str.c_str(), id_str.length(), &js_result);
    return js_result;
}

// Wait for write
napi_value WaitForWrite(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "handle and writeId arguments required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    std::string id_str = GetStringFromValue(env, args[1]);
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    uint64_t id = std::stoull(id_str);
    int result = elkyn_wait_for_write(it->second, id);
    
    napi_value js_result;
    napi_create_int32(env, result, &js_result);
    return js_result;
}

// Get raw (zero-copy for primitives)
napi_value GetRaw(napi_env env, napi_callback_info info) {
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
    
    ReadInfo read_info;
    int result = elkyn_get_raw(it->second, path.c_str(), &read_info, token);
    
    if (result != 0) {
        return nullptr; // Return null on error
    }
    
    napi_value value;
    
    switch (read_info.type_tag) {
        case 's': // String
            napi_create_string_utf8(env, reinterpret_cast<const char*>(read_info.data), read_info.length, &value);
            break;
            
        case 'n': // Number
            if (read_info.length >= 9) {
                double num;
                std::memcpy(&num, read_info.data + 1, sizeof(double));
                napi_create_double(env, num, &value);
            } else {
                napi_get_null(env, &value);
            }
            break;
            
        case 'b': // Boolean
            if (read_info.length >= 2) {
                napi_get_boolean(env, read_info.data[1] != 0, &value);
            } else {
                napi_get_null(env, &value);
            }
            break;
            
        case 'z': // Null
            napi_get_null(env, &value);
            break;
            
        case 'm': // MessagePack (complex types)
            napi_create_buffer_copy(env, read_info.length, read_info.data, nullptr, &value);
            break;
            
        default:
            napi_get_null(env, &value);
            break;
    }
    
    // Free if needed
    if (read_info.needs_free) {
        free(const_cast<uint8_t*>(read_info.data));
    }
    
    return value;
}

// Enable SharedArrayBuffer queue
napi_value EnableSABQueue(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "handle and sharedArrayBuffer arguments required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    // Get ArrayBuffer (SharedArrayBuffer access requires newer N-API)
    bool is_array_buffer;
    napi_status status = napi_is_arraybuffer(env, args[1], &is_array_buffer);
    if (status != napi_ok || !is_array_buffer) {
        napi_throw_error(env, nullptr, "Expected ArrayBuffer or SharedArrayBuffer");
        return nullptr;
    }
    
    void* data;
    size_t byte_length;
    status = napi_get_arraybuffer_info(env, args[1], &data, &byte_length);
    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to get SharedArrayBuffer info");
        return nullptr;
    }
    
    // Enable SAB queue in Zig
    int result = elkyn_enable_sab_queue(it->second, 
                                        static_cast<uint8_t*>(data), 
                                        static_cast<uint32_t>(byte_length));
    
    napi_value js_result;
    napi_create_int32(env, result, &js_result);
    return js_result;
}

// Get SAB queue statistics
napi_value GetSABStats(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "handle argument required");
        return nullptr;
    }
    
    std::string handle = GetStringFromValue(env, args[0]);
    
    auto it = db_instances.find(handle);
    if (it == db_instances.end()) {
        napi_throw_error(env, nullptr, "Invalid database handle");
        return nullptr;
    }
    
    uint32_t head, tail, pending;
    int result = elkyn_sab_queue_stats(it->second, &head, &tail, &pending);
    
    if (result != 0) {
        napi_throw_error(env, nullptr, "SAB queue not enabled");
        return nullptr;
    }
    
    // Create result object
    napi_value js_result;
    napi_create_object(env, &js_result);
    
    napi_value js_head, js_tail, js_pending;
    napi_create_uint32(env, head, &js_head);
    napi_create_uint32(env, tail, &js_tail);
    napi_create_uint32(env, pending, &js_pending);
    
    napi_set_named_property(env, js_result, "head", js_head);
    napi_set_named_property(env, js_result, "tail", js_tail);
    napi_set_named_property(env, js_result, "pending", js_pending);
    
    return js_result;
}

// Module initialization
napi_value InitModule(napi_env env, napi_value exports) {
    napi_property_descriptor properties[] = {
        DECLARE_NAPI_METHOD("init", Init),
        DECLARE_NAPI_METHOD("enableAuth", EnableAuth),
        DECLARE_NAPI_METHOD("enableRules", EnableRules),
        DECLARE_NAPI_METHOD("setString", SetString),
        DECLARE_NAPI_METHOD("getString", GetString),
        DECLARE_NAPI_METHOD("setBinary", SetBinary),
        DECLARE_NAPI_METHOD("getBinary", GetBinary),
        DECLARE_NAPI_METHOD("delete", Delete),
        DECLARE_NAPI_METHOD("createToken", CreateToken),
        DECLARE_NAPI_METHOD("close", Close),
        DECLARE_NAPI_METHOD("enableEventQueue", EnableEventQueue),
        DECLARE_NAPI_METHOD("watch", Watch),
        DECLARE_NAPI_METHOD("unwatch", Unwatch),
        DECLARE_NAPI_METHOD("enableWriteQueue", EnableWriteQueue),
        DECLARE_NAPI_METHOD("setBinaryAsync", SetBinaryAsync),
        DECLARE_NAPI_METHOD("deleteAsync", DeleteAsync),
        DECLARE_NAPI_METHOD("waitForWrite", WaitForWrite),
        DECLARE_NAPI_METHOD("getRaw", GetRaw),
        DECLARE_NAPI_METHOD("enableSABQueue", EnableSABQueue),
        DECLARE_NAPI_METHOD("getSABStats", GetSABStats),
    };
    
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

NAPI_MODULE(elkyn_store, InitModule)