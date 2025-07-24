#include <node_api.h>
#include <string>
#include <memory>
#include <vector>
#include <unordered_map>
#include <thread>
#include <atomic>
#include <chrono>

// Forward declarations for Zig functions
extern "C" {
    struct EventQueue;
    struct ElkynDB;
    
    EventQueue* elkyn_event_queue_create();
    void elkyn_event_queue_destroy(EventQueue* queue);
    
    struct EventData {
        uint8_t type;  // 1 = change, 2 = delete
        const char* path;
        const char* value;  // JSON string or null
        uint64_t sequence;
        int64_t timestamp;
    };
    
    // Pop events from queue (returns number of events)
    size_t elkyn_event_queue_pop_batch(EventQueue* queue, EventData* buffer, size_t max_count);
    size_t elkyn_event_queue_pending(EventQueue* queue);
    
    // Enable event queue on database
    void elkyn_enable_event_queue(ElkynDB* db, EventQueue* queue);
}

class Observable {
private:
    struct Subscription {
        std::string pattern;
        napi_threadsafe_function tsfn;
        napi_ref callback_ref;
        uint64_t id;
    };
    
    EventQueue* event_queue;
    std::vector<std::unique_ptr<Subscription>> subscriptions;
    std::atomic<uint64_t> next_subscription_id{1};
    std::atomic<bool> running{true};
    std::thread event_thread;
    
    // Pattern matching (simple wildcard support)
    bool matchesPattern(const std::string& pattern, const std::string& path) {
        if (pattern == "/") return true;  // Root watches everything
        
        // Handle wildcards
        if (pattern.back() == '*') {
            std::string prefix = pattern.substr(0, pattern.length() - 1);
            return path.substr(0, prefix.length()) == prefix;
        }
        
        return pattern == path;
    }
    
    // Event processing thread
    void processEvents() {
        const size_t BATCH_SIZE = 64;
        std::vector<EventData> events(BATCH_SIZE);
        
        while (running.load()) {
            // Check for pending events
            size_t pending = elkyn_event_queue_pending(event_queue);
            if (pending == 0) {
                // Sleep briefly to avoid busy waiting
                std::this_thread::sleep_for(std::chrono::microseconds(100));
                continue;
            }
            
            // Pop batch of events
            size_t count = elkyn_event_queue_pop_batch(
                event_queue, 
                events.data(), 
                std::min(pending, BATCH_SIZE)
            );
            
            // Process each event
            for (size_t i = 0; i < count; i++) {
                const EventData& event = events[i];
                
                // Find matching subscriptions
                for (const auto& sub : subscriptions) {
                    if (matchesPattern(sub->pattern, event.path)) {
                        // Call JavaScript callback via threadsafe function
                        auto* data = new EventData(event);
                        napi_call_threadsafe_function(
                            sub->tsfn,
                            data,
                            napi_tsfn_nonblocking
                        );
                    }
                }
            }
        }
    }
    
public:
    Observable(EventQueue* queue) : event_queue(queue) {
        // Start event processing thread
        event_thread = std::thread(&Observable::processEvents, this);
    }
    
    ~Observable() {
        running.store(false);
        if (event_thread.joinable()) {
            event_thread.join();
        }
        
        // Clean up subscriptions
        for (auto& sub : subscriptions) {
            napi_release_threadsafe_function(sub->tsfn, napi_tsfn_release);
        }
    }
    
    uint64_t subscribe(napi_env env, const std::string& pattern, napi_value callback) {
        auto sub = std::make_unique<Subscription>();
        sub->pattern = pattern;
        sub->id = next_subscription_id.fetch_add(1);
        
        // Create reference to callback
        napi_create_reference(env, callback, 1, &sub->callback_ref);
        
        // Create threadsafe function
        napi_value async_resource_name;
        napi_create_string_utf8(env, "elkynObservable", NAPI_AUTO_LENGTH, &async_resource_name);
        
        napi_create_threadsafe_function(
            env,
            callback,
            nullptr,  // async_resource
            async_resource_name,
            0,  // max_queue_size (unlimited)
            1,  // initial_thread_count
            nullptr,  // thread_finalize_data
            nullptr,  // thread_finalize_cb
            sub.get(),  // context
            [](napi_env env, napi_value js_callback, void* context, void* data) {
                // This runs in the JavaScript thread
                EventData* event = static_cast<EventData*>(data);
                
                // Create event object
                napi_value event_obj;
                napi_create_object(env, &event_obj);
                
                // Set type
                napi_value type_str;
                napi_create_string_utf8(env, 
                    event->type == 1 ? "change" : "delete", 
                    NAPI_AUTO_LENGTH, 
                    &type_str
                );
                napi_set_named_property(env, event_obj, "type", type_str);
                
                // Set path
                napi_value path_str;
                napi_create_string_utf8(env, event->path, NAPI_AUTO_LENGTH, &path_str);
                napi_set_named_property(env, event_obj, "path", path_str);
                
                // Set value (parse JSON)
                if (event->value) {
                    napi_value value_str;
                    napi_create_string_utf8(env, event->value, NAPI_AUTO_LENGTH, &value_str);
                    
                    // Parse JSON
                    napi_value global, json, parse_fn, parsed_value;
                    napi_get_global(env, &global);
                    napi_get_named_property(env, global, "JSON", &json);
                    napi_get_named_property(env, json, "parse", &parse_fn);
                    
                    napi_value parse_args[] = { value_str };
                    napi_call_function(env, json, parse_fn, 1, parse_args, &parsed_value);
                    
                    napi_set_named_property(env, event_obj, "value", parsed_value);
                } else {
                    napi_value null_value;
                    napi_get_null(env, &null_value);
                    napi_set_named_property(env, event_obj, "value", null_value);
                }
                
                // Set timestamp
                napi_value timestamp;
                napi_create_int64(env, event->timestamp, &timestamp);
                napi_set_named_property(env, event_obj, "timestamp", timestamp);
                
                // Call the JavaScript callback
                napi_value argv[] = { event_obj };
                napi_value result;
                napi_call_function(env, nullptr, js_callback, 1, argv, &result);
                
                // Clean up
                delete event;
            },
            &sub->tsfn
        );
        
        subscriptions.push_back(std::move(sub));
        return subscriptions.back()->id;
    }
    
    bool unsubscribe(uint64_t id) {
        auto it = std::remove_if(subscriptions.begin(), subscriptions.end(),
            [id](const std::unique_ptr<Subscription>& sub) {
                if (sub->id == id) {
                    napi_release_threadsafe_function(sub->tsfn, napi_tsfn_release);
                    return true;
                }
                return false;
            }
        );
        
        if (it != subscriptions.end()) {
            subscriptions.erase(it, subscriptions.end());
            return true;
        }
        return false;
    }
};

// Global map of observables per database handle
static std::unordered_map<std::string, std::unique_ptr<Observable>> observables;

// JavaScript API
napi_value Watch(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "handle and path required");
        return nullptr;
    }
    
    // Get handle and path
    size_t handle_len, path_len;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &handle_len);
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &path_len);
    
    std::string handle(handle_len, '\0');
    std::string path(path_len, '\0');
    napi_get_value_string_utf8(env, args[0], &handle[0], handle_len + 1, &handle_len);
    napi_get_value_string_utf8(env, args[1], &path[0], path_len + 1, &path_len);
    
    // Create observable if it doesn't exist
    if (observables.find(handle) == observables.end()) {
        EventQueue* queue = elkyn_event_queue_create();
        // TODO: Connect queue to database
        observables[handle] = std::make_unique<Observable>(queue);
    }
    
    // Return subscription object
    napi_value subscription;
    napi_create_object(env, &subscription);
    
    // Store handle and path for subscribe method
    napi_value handle_val, path_val;
    napi_create_string_utf8(env, handle.c_str(), handle.length(), &handle_val);
    napi_create_string_utf8(env, path.c_str(), path.length(), &path_val);
    napi_set_named_property(env, subscription, "_handle", handle_val);
    napi_set_named_property(env, subscription, "_path", path_val);
    
    // Add subscribe method
    napi_value subscribe_fn;
    napi_create_function(env, "subscribe", NAPI_AUTO_LENGTH,
        [](napi_env env, napi_callback_info info) -> napi_value {
            // Implementation continues in next message...
            return nullptr;
        },
        nullptr, &subscribe_fn
    );
    napi_set_named_property(env, subscription, "subscribe", subscribe_fn);
    
    return subscription;
}