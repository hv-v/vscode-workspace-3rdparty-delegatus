# C++20 features

Target standard: `CMAKE_CXX_STANDARD 20` (`REQUIRED ON`) and `Standard: c++20` in
`.clang-format`. Google targets the same:

> "Currently, code should target C++20, i.e., should not use C++23 features."

Baseline: [Google C++ Style Guide — C++ Version](https://google.github.io/styleguide/cppguide.html#C++_Version).

## Contents
- Where this repo differs from Google
- Established here
- Safe to reach for
- Use with care
- Not established here

## Where this repo differs from Google

| feature | Google | here |
|---|---|---|
| exceptions | not used | **used** — see the error-handling section of SKILL.md |
| C++ version | C++20 | C++20 (same) |

No divergence on the features below; the only difference is naming style in the
examples (`camelCase` functions, see [naming.md](naming.md)).

## Established here

**`std::format`** is the string-building idiom. Prefer it over `ostringstream` and
over concatenation — it is compile-time checked, so a wrong placeholder is a build
error instead of a runtime surprise:

```cpp
std::string describe(const std::string& name, std::size_t count) {
    return std::format("{} holds {} items", name, count);
}
```

**Structured bindings** when iterating pairs:

```cpp
for (const auto& [name, value] : items) {
    forEach(value, print);
}
```

## Safe to reach for

- **`std::span`** for a non-owning view over a contiguous range. Replaces
  `(pointer, length)` parameter pairs and the accidental copies that come from
  taking a `std::vector<T>` by value.
- **Designated initializers** for aggregates — members must appear in declaration
  order (example below).
- **`constinit`** on any non-trivially-destructible static. See
  [multithreading.md](multithreading.md), where it is mandatory rather than
  optional.
- **`std::erase` / `std::erase_if`** in place of the erase-remove idiom.
- **Three-way comparison (`<=>`)** to generate the relational operators from one
  declaration, when a type genuinely needs ordering.

```cpp
const Options options{.retries = kMaxRetries, .verbose = true};
```

## Use with care

- **Ranges (`<ranges>`)**: views compose well but dangle easily — a view over a
  temporary is a use-after-free with no warning. Materialise into a container
  before the full expression ends, and never return a view from a function.
- **`consteval`**: correct for a function that must never run at runtime, but the
  diagnostics are poor. Reach for `constexpr` first.
- **Coroutines**: the framework's executor already owns the concurrency model
  here. Adding coroutines alongside it means two schedulers — not without a
  design discussion.

## Not established here

**Modules.** Toolchain and build-system support has not been validated for this
project. Keep to headers.

For anything newer, see [std23_features.md](std23_features.md) — the short version
is that it is not available.
