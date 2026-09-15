---
name: l-cpp
description: Modern C++17/20/23 standards - RAII and smart-pointer ownership, move semantics, const/constexpr, type safety, error handling, concurrency and gtest. Use when writing, editing or reviewing C++ code (.cpp/.hpp/.h), designing a class or its ownership model, or reviewing a C++ diff.
---

# C++ Development Guidelines

Modern C++20. The baseline is the
[Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html); the
reference files below record where this workspace deviates from it, and the
deviations win.

## Where this workspace differs from Google

Google is the baseline, but these four differences apply everywhere and each
reference file repeats the ones it owns:

| area | Google | here |
|---|---|---|
| function and method names | `PascalCase` — `FindAll()` | **`camelCase`** — `findAll()` |
| local and parameter names | `snake_case` — `item_count` | **`camelCase`** — `itemCount` |
| formatting | 2-space indent, 80 columns | **4-space indent, 120 columns**, plus consecutive-assignment alignment |
| exceptions | "We do not use C++ exceptions" | **used**, for programming errors and startup failures |

A `PascalCase` identifier followed by `(` is a constructor or a type here — never
a function.

## Reference files

Read the one the task needs — not all of them:

| read | when |
|---|---|
| [reference/formating.md](reference/formating.md) | laying out code, wrapping a long line, ordering includes, or a `clang_format` test failed |
| [reference/naming.md](reference/naming.md) | naming anything, or considering a rename — some names are interface contracts |
| [reference/headers.md](reference/headers.md) | deciding what goes in a header, forward declaring, or hitting `invalid use of incomplete type` |
| [reference/templates_features.md](reference/templates_features.md) | writing a template, `auto`, a lambda capture, an alias or an operator overload |
| [reference/std20_features.md](reference/std20_features.md) | reaching for a modern feature — what is available and what to avoid |
| [reference/std23_features.md](reference/std23_features.md) | a C++23 feature came to mind — it is not enabled; see the C++20 substitute |
| [reference/multithreading.md](reference/multithreading.md) | locking, statics, callbacks, or anything touching the ROS executor |

## Ownership

This is the decision that matters most; get it right before writing the class.

- `std::unique_ptr` for exclusive ownership. It is the default.
- `std::shared_ptr` **only** when ownership is genuinely shared. ROS APIs hand
  you `shared_ptr` — that is theirs, not a licence to use it for your own members.
- `std::weak_ptr` to break cycles.
- Raw pointer means "observes, does not own", and must not outlive the owner.
  `const Storage* storage() const` returning `storage_.get()` is that: a
  non-owning view of a `unique_ptr` member.
- A reference member makes the class non-assignable. Prefer a pointer.
- Never `new`/`delete` in application code. `std::make_unique`, `std::make_shared`.
- Prefer stack allocation. Heap-allocate when the object is polymorphic, must
  outlive the scope, or is forward declared in a header.

RAII everywhere: every resource — memory, file, socket, lock, subscription — is
owned by an object whose destructor releases it. That is what makes the code
exception-safe without try/catch.

## Const, references and copies

- `const` by default on methods, parameters and locals; `constexpr` when the value
  is compile-time known.
- Pass by `const&` for anything larger than a pointer; by value only when you need
  a copy anyway, then `std::move` it into place.
- Return by value and let the compiler elide. Do not return `const T`.
- `std::move` transfers; it does not copy-and-delete. A moved-from object is valid
  but unspecified — do not read it.
- `std::forward` only in a template taking a forwarding reference.

## Type safety

- `enum class`, never a plain `enum`.
- `static_cast` / `dynamic_cast` / `const_cast`, never a C-style cast except to
  `void`. Google: "Use C++-style casts... C-style casts should be avoided."
- `nullptr`, never `NULL` or `0`.
- `std::array` and `std::vector`, never a C array. `std::string`, never `char*`.
- `std::string_view` for a non-owning string parameter — but never store one whose
  backing buffer you do not control.
- Compile with warnings on and treat them as errors.

## Error handling

**This codebase uses exceptions; Google does not.** Google states "We do not use
C++ exceptions", which is a decision about their build, not a portable rule. Here:

- Throw for programming errors and unrecoverable startup failures.
- For expected, recoverable outcomes return a small result struct instead —
  `struct Result { bool ok; std::string reason; };`. A validation failure is
  data, not an exception.
- Catch by `const&`.
- `noexcept` where it is useful and correct — move constructors especially, since
  containers use it to choose between move and copy.
- Never let an exception escape a destructor or a ROS callback.

## Performance

Measure before optimising. Then: avoid needless copies, `reserve()` a vector whose
size you know, prefer algorithms to hand-written loops, and keep hot data
contiguous. `inline` is a linkage instruction, not a speed knob.

## Testing

- gtest and gmock. `TEST(SuiteName, TestName)` — both bare identifiers, never
  quoted strings.
- Test edge cases and failure paths, not just the happy one.
- Register every new test file in `test/Sources.cmake`, or it silently never runs.
- Sanitizers (ASan, UBSan, TSan) when changing memory or locking.
- Tests touching the ROS graph must spin an executor with a deadline loop — see
  [reference/multithreading.md](reference/multithreading.md).

## Documentation

Doxygen comments on public APIs. Document *why* and any thread-safety
requirement; do not restate the signature in prose.

## Build

CMake. A new `.cpp` must be added to `src/Sources.cmake` — the symptom of
forgetting is `undefined reference` at link time, never a missing-file error. A
new `find_package` needs a matching `<depend>` in `package.xml`.
