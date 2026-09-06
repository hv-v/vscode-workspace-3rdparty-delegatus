# Headers

Baseline: [Google C++ Style Guide — Header Files](https://google.github.io/styleguide/cppguide.html#Header_Files).

## Contents
- Where this repo differs from Google
- Self-contained headers
- Forward declarations: when they pay and what they cost
- Inline functions
- Include what you use

## Where this repo differs from Google

| rule | Google | here |
|---|---|---|
| include guard | `#define` guards | **`#pragma once`** |
| forward declarations | discouraged by default | **used deliberately** for `unique_ptr` members (below) |

Do not mix guard styles — every header here starts with `#pragma once`.

## Self-contained headers

Every header must compile on its own. If it names a type it either includes that
type's header or forward declares it; it must never rely on the includer having
done that first. A header that only compiles when included second is a build
break waiting for the next file that uses it.

## Forward declarations: when they pay and what they cost

Google's default is to include rather than forward declare, because forward
declarations hide dependencies. The exception worth taking is a
`std::unique_ptr` member whose type the header never dereferences — it keeps a
heavy implementation header out of every consumer:

```cpp
#pragma once

#include <memory>
#include <string>

namespace app {

class Storage;  // forward declaration - definition lives in Registry.cpp

class Registry {
   public:
    Registry();
    ~Registry();  // REQUIRED out-of-line, see below

    bool add(std::string name, int value);

    const Storage* storage() const { return storage_.get(); }

   private:
    std::unique_ptr<Storage> storage_;
};

}  // namespace app
```

Rules that make this legal and keep it working:

- **Declare the destructor in the header, define it in the `.cpp`.** An implicit
  destructor is generated inline where the type is still incomplete, and
  `unique_ptr`'s deleter needs a complete type. `Registry::~Registry() = default;`
  in the `.cpp` is the fix. The same applies to any move operations you declare.
- **The constructor also belongs in the `.cpp`** if it calls `std::make_unique`.
- **Forward declare only what you never use by value.** A function returning a
  type by value, or taking it by value, needs the complete type — include it.
  A pointer or reference parameter does not.
- **Consumers must include what the header stopped including.** Dropping an
  include from a header breaks every `.cpp` that was getting it transitively; the
  symptom is `invalid use of incomplete type`. That is the forward declaration
  working as designed — add the direct include to the `.cpp` files that actually
  touch the type.

Do not forward declare types you do not own — standard library or third-party
types. Include their headers.

## Inline functions

Define a function in the header only if it is genuinely trivial, like the
`storage()` accessor above. Anything with a loop, or a branch beyond a null
check, belongs in the `.cpp`.

## Include what you use

Include the header for every symbol a file names, even when it already arrives
transitively. Transitive includes break the moment an unrelated header is tidied
up, and the resulting error points at your file rather than at the change that
caused it.
