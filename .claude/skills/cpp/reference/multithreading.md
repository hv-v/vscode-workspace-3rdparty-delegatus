# Concurrency and object lifetime

Baseline: [Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)
— Static and Global Variables, `thread_local` Variables, `constexpr`/`constinit`.

## Contents
- Where this repo differs from Google
- Statics: the rule that bites hardest
- thread_local
- Locking
- The executor owns the threading model
- Callback re-entrancy
- Testing concurrent code

## Where this repo differs from Google

| rule | Google | here |
|---|---|---|
| statics, `thread_local`, `constinit` | as written | **followed as written** |
| threading model | unspecified | **the framework executor owns it** — do not spawn threads |
| naming in the examples | `PascalCase` functions | **`camelCase`** — see [naming.md](naming.md) |

## Statics: the rule that bites hardest

> "Objects with static storage duration are forbidden unless they are trivially
> destructible."

Trivially destructible means the destructor does nothing, counting bases and
members. Fundamental types and arrays of them qualify; `std::string`,
`std::vector`, `std::map`, and any class owning one, do **not**.

Destruction order across translation units is unspecified, so such a static can be
destroyed before its last user — a shutdown crash that reproduces on one machine
and not another.

```cpp
// Forbidden: non-trivial destructor at namespace scope.
const std::string kServiceAddress = "app.internal";
```

```cpp
// Correct, and the idiom used here.
constexpr auto kServiceAddress = "app.internal";
```

Constant initialization is always allowed and should be marked: `constexpr` when
the value is a constant expression, `constinit` when the type needs dynamic
construction but must still be initialised at compile time.

For a genuinely non-trivial singleton, use a function-local static — initialised
on first use, thread-safe since C++11 — and accept that it is never destroyed.

## thread_local

> "`thread_local` variables that aren't declared inside a function must be
> initialized with a true compile-time constant, and this must be enforced by
> using the `constinit` attribute."

Its cost is per-thread storage that scales with thread count, and objects
destroyed at thread shutdown are a common source of use-after-free. Prefer passing
state explicitly.

## Locking

- `std::lock_guard` for a scoped lock; `std::scoped_lock` when taking more than
  one mutex, because it orders them and avoids deadlock.
- Never hand-roll `lock()` / `unlock()` — an early return or a throw leaks it.
- Mark the mutex `mutable` when a `const` method must lock.
- Hold the lock for the shortest region. Copy what you need out, then release
  before doing work:

```cpp
void Registry::updateStatus(bool healthy, std::string reason) {
    {
        std::lock_guard<std::mutex> lock(statusMutex_);
        isHealthy_    = healthy;
        statusReason_ = std::move(reason);
    }
    // Logging and notification happen outside the lock.
    notifyObservers();
}
```

- **Never call out of the class while holding a lock** — no publishing, no remote
  calls, no user callbacks. That is how lock-order inversions get built.
- `std::atomic` for a single counter or flag, not as a substitute for a mutex
  across several fields that must change together.

## The executor owns the threading model

Nodes run on a single-threaded executor, so callbacks are serialised and most
state needs no lock. Mutexes that are present are deliberate defensive coding in
case the executor is switched to multi-threaded — say so in a comment when you
add one.

Do not introduce `std::thread` or a second executor to fix a latency problem. Use
a timer, an async client with a completion callback, or a separate callback group.

## Callback re-entrancy

The trap specific to this codebase: **blocking on a future inside a live callback
re-enters the executor and deadlocks.** Never wait on a future from inside a
service or subscription callback running on the same executor.

The correct shape is a deferred response — take the request handle, return
immediately, and answer from the async completion:

```cpp
void Registry::onLookupRequested(const RequestHandle& handle, const LookupRequest& request) {
    client_.sendRequest(request.name, [this, handle](const Response& response) {
        sendResponse(handle, response.ok, response.message);
    });
}
```

Capture by value anything the callback needs after the caller's frame is gone.

## Testing concurrent code

Drive the executor with an explicit deadline loop rather than sleeping, and report
what was actually observed on timeout — "no data" is not a diagnosis:

```cpp
const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
while (!future.isReady() && std::chrono::steady_clock::now() < deadline) {
    executor.spinSome(std::chrono::milliseconds(50));
}
```

A test that never spins the executor observes nothing and passes for the wrong
reason. Build with ThreadSanitizer when changing locking.
