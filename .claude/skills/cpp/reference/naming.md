# Naming

Baseline: [Google C++ Style Guide — Naming](https://google.github.io/styleguide/cppguide.html#Naming).

## Contents
- Where this repo differs from Google
- The conventions
- Aliases
- Namespaces and files
- Names that are contracts

## Where this repo differs from Google

**This is the biggest divergence in the whole style, so read it before naming
anything.**

| kind | Google | here |
|---|---|---|
| free function | `PascalCase` — `AnyOf()` | **`camelCase`** — `anyOf()` |
| member function | `PascalCase` — `FindAll()` | **`camelCase`** — `findAll()` |
| local variable | `snake_case` — `item_count` | **`camelCase`** — `itemCount` |
| parameter | `snake_case` — `max_size` | **`camelCase`** — `maxSize` |

Everything else matches Google: `PascalCase` types, trailing underscore on
private members, `k` prefix on constants, `snake_case` namespaces,
`SCREAMING_SNAKE_CASE` for macros only.

**Never write a `PascalCase` function here.** A `PascalCase` identifier followed
by `(` means a constructor or a type, and nothing else.

## The conventions

| kind | convention | example |
|---|---|---|
| class, struct, enum | `PascalCase` | `Registry`, `ParseResult` |
| enumerator | `k` + `PascalCase` | `kPending`, `kComplete` |
| free function | `camelCase` | `anyOf`, `findAll`, `forEach` |
| member function | `camelCase` | `add`, `find`, `countMatching` |
| local variable, parameter | `camelCase` | `itemCount`, `maxSize` |
| private data member | `camelCase` + trailing `_` | `items_`, `capacity_` |
| constant, `constexpr` | `k` + `PascalCase` | `kMaxRetries`, `kDefaultBudget` |
| namespace | `snake_case` | `app`, `helpers` |
| macro | `SCREAMING_SNAKE_CASE` | `LOG_INFO` |
| file | matches its primary class | `Registry.hpp` / `Registry.cpp` |

```cpp
namespace app {

class Registry {
   public:
    bool add(std::string name, int value);
    std::size_t countMatching(const std::string& prefix) const;

   private:
    static constexpr std::size_t kMaxItems = 256;

    std::map<std::string, int> items_;
};

bool anyOf(const std::vector<int>& values, int wanted);

}  // namespace app
```

## Aliases

`using`, never `typedef`. Name the alias like the type it stands for:

```cpp
using ItemMap  = std::map<std::string, int>;
using NamePair = std::pair<std::string, std::string>;
```

## Namespaces and files

- One primary class per header/source pair, the file named for that class.
- Free helper functions live in a nested `helpers` namespace, not at global scope.
- File-local constants and helpers go in an anonymous namespace in the `.cpp`, so
  they do not leak into other translation units.

## Names that are contracts

Some names are consumed by something outside the code, so renaming one is an
interface change rather than a refactor. Before renaming, check whether it is:

- a **configuration or serialized key** that config files and stored data use;
- a **service, topic or endpoint path** that other processes address;
- a **published metric or diagnostics key** that downstream aggregation matches on;
- a **test suite name** that CI filters select.

Grep the whole workspace, deployment values and any driver scripts before
changing one of those.
