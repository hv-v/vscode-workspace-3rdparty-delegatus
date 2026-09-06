# C++23 features — not enabled

## Contents
- Why not
- C++20 substitutes
- If you think you need one

**Nothing in this file is usable in this codebase today.** It exists so a C++23
feature is recognised and consciously rejected, rather than tried and then
debugged as a mysterious compile error.

## Why not

Two independent reasons, either sufficient:

1. **The build targets C++20.** `set(CMAKE_CXX_STANDARD 20)` with
   `CMAKE_CXX_STANDARD_REQUIRED ON`, and `Standard: c++20` in `.clang-format`. A
   C++23 construct is a compile error, not a warning.
2. **The style guide forbids it.** Google:
   > "Currently, code should target C++20, i.e., should not use C++23 features.
   > The C++ version targeted by this guide will advance (aggressively) over time."

Baseline: [Google C++ Style Guide — C++ Version](https://google.github.io/styleguide/cppguide.html#C++_Version).

This is one of the few places where the repo and Google agree exactly; there is no
local deviation.

## C++20 substitutes

| C++23 | use instead, today |
|---|---|
| `std::print` / `std::println` | `std::format` passed to the project's logging macros |
| `std::expected<T, E>` | a small result struct — `struct Result { bool ok; std::string reason; };` |
| `std::mdspan` | `std::span` over a flat buffer with explicit index arithmetic |
| deducing `this` | an ordinary const / non-const overload pair |
| `if consteval` | `if constexpr` with a `std::is_constant_evaluated()` guard |
| `std::flat_map` | `std::map`, or a sorted `std::vector` with `std::lower_bound` |
| multidimensional `operator[]` | `operator()` taking several indices |
| `std::ranges::to` | construct the container from the view's iterators |

## If you think you need one

Raising the standard is a project decision, not a file-local one: it touches the
base image's compiler, every package in the workspace, and the `.clang-format`
`Standard` setting. Propose it as a change to `CMakeLists.txt` with a reason —
never add `-std=c++23` to a single target.

When the project does move, this file's content folds into
[std20_features.md](std20_features.md)'s structure and this becomes the C++26
placeholder.
