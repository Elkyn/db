/**
 * Observable-style watch API for Elkyn Store
 * Provides high-performance event streaming from the Zig core
 */

class Subscription {
  constructor(id, observable) {
    this._id = id;
    this._observable = observable;
    this._active = true;
  }

  unsubscribe() {
    if (this._active) {
      this._observable._unsubscribe(this._id);
      this._active = false;
    }
  }

  get closed() {
    return !this._active;
  }
}

class Observable {
  constructor(store, path) {
    this._store = store;
    this._path = path;
    this._subscriptions = new Map();
  }

  /**
   * Subscribe to changes on this path
   * @param {Function} observer - Callback function or observer object
   * @returns {Subscription}
   */
  subscribe(observer) {
    let next, error, complete;

    // Handle both function and observer object
    if (typeof observer === 'function') {
      next = observer;
    } else if (observer && typeof observer === 'object') {
      next = observer.next?.bind(observer);
      error = observer.error?.bind(observer);
      complete = observer.complete?.bind(observer);
    } else {
      throw new TypeError('Observer must be a function or object with next method');
    }

    // Create subscription in native code
    const id = this._store._watchNative(this._path, (event) => {
      try {
        // Parse JSON value if it's a string
        const parsedEvent = { ...event };
        if (parsedEvent.value && typeof parsedEvent.value === 'string') {
          try {
            // Values come from Zig as JSON strings, might need double parsing
            let parsed = JSON.parse(parsedEvent.value);
            
            // If the result is still a JSON string, parse again
            // This handles cases where Zig double-encodes (e.g., storing a string becomes "\"string\"")
            if (typeof parsed === 'string' && 
                ((parsed.startsWith('"') && parsed.endsWith('"')) ||
                 (parsed.startsWith('{') && parsed.endsWith('}')) ||
                 (parsed.startsWith('[') && parsed.endsWith(']')) ||
                 parsed === 'null' || parsed === 'true' || parsed === 'false' ||
                 !isNaN(Number(parsed)))) {
              try {
                parsed = JSON.parse(parsed);
              } catch (e2) {
                // Keep first parse result
              }
            }
            
            parsedEvent.value = parsed;
          } catch (e) {
            // Keep as string if parsing fails
          }
        }
        
        if (next) {
          next(parsedEvent);
        }
      } catch (err) {
        if (error) {
          error(err);
        } else {
          // Unhandled error in observer
          console.error('Unhandled error in Elkyn observer:', err);
        }
      }
    });

    const subscription = new Subscription(id, this);
    this._subscriptions.set(id, subscription);

    return subscription;
  }

  /**
   * Internal method to unsubscribe
   */
  _unsubscribe(id) {
    if (this._subscriptions.has(id)) {
      this._store._unwatchNative(id);
      this._subscriptions.delete(id);
    }
  }

  /**
   * Convert to async iterator
   */
  async *[Symbol.asyncIterator]() {
    const queue = [];
    let resolve = null;
    let reject = null;
    let completed = false;

    const subscription = this.subscribe({
      next: (event) => {
        if (resolve) {
          resolve({ value: event, done: false });
          resolve = null;
        } else {
          queue.push(event);
        }
      },
      error: (err) => {
        if (reject) {
          reject(err);
        }
        completed = true;
      },
      complete: () => {
        completed = true;
        if (resolve) {
          resolve({ done: true });
        }
      }
    });

    try {
      while (!completed) {
        if (queue.length > 0) {
          yield queue.shift();
        } else {
          const event = await new Promise((res, rej) => {
            resolve = res;
            reject = rej;
          });
          if (!event.done) {
            yield event.value;
          } else {
            break;
          }
        }
      }
    } finally {
      subscription.unsubscribe();
    }
  }

  /**
   * Filter events
   */
  filter(predicate) {
    const filtered = new Observable(this._store, this._path);
    const originalSubscribe = filtered.subscribe.bind(filtered);

    filtered.subscribe = (observer) => {
      return originalSubscribe({
        next: (event) => {
          if (predicate(event)) {
            if (typeof observer === 'function') {
              observer(event);
            } else {
              observer.next?.(event);
            }
          }
        },
        error: observer.error?.bind(observer),
        complete: observer.complete?.bind(observer)
      });
    };

    return filtered;
  }

  /**
   * Map events
   */
  map(mapper) {
    const mapped = new Observable(this._store, this._path);
    const originalSubscribe = mapped.subscribe.bind(mapped);

    mapped.subscribe = (observer) => {
      return originalSubscribe({
        next: (event) => {
          try {
            const mappedEvent = mapper(event);
            if (typeof observer === 'function') {
              observer(mappedEvent);
            } else {
              observer.next?.(mappedEvent);
            }
          } catch (err) {
            observer.error?.(err);
          }
        },
        error: observer.error?.bind(observer),
        complete: observer.complete?.bind(observer)
      });
    };

    return mapped;
  }

  /**
   * Take first N events
   */
  take(count) {
    const limited = new Observable(this._store, this._path);
    const originalSubscribe = limited.subscribe.bind(limited);

    limited.subscribe = (observer) => {
      let received = 0;
      let subscription;

      subscription = originalSubscribe({
        next: (event) => {
          if (received < count) {
            received++;
            if (typeof observer === 'function') {
              observer(event);
            } else {
              observer.next?.(event);
            }
            
            if (received >= count) {
              subscription.unsubscribe();
              observer.complete?.();
            }
          }
        },
        error: observer.error?.bind(observer),
        complete: observer.complete?.bind(observer)
      });

      return subscription;
    };

    return limited;
  }

  /**
   * Debounce events
   */
  debounce(ms) {
    const debounced = new Observable(this._store, this._path);
    const originalSubscribe = debounced.subscribe.bind(debounced);

    debounced.subscribe = (observer) => {
      let timeout;
      
      return originalSubscribe({
        next: (event) => {
          clearTimeout(timeout);
          timeout = setTimeout(() => {
            if (typeof observer === 'function') {
              observer(event);
            } else {
              observer.next?.(event);
            }
          }, ms);
        },
        error: observer.error?.bind(observer),
        complete: observer.complete?.bind(observer)
      });
    };

    return debounced;
  }
}

module.exports = { Observable, Subscription };