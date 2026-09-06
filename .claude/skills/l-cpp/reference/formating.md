# Formatting

Baseline: [Google C++ Style Guide — Formatting](https://google.github.io/styleguide/cppguide.html#Formatting).
Every code block below has been run through this repo's `.clang-format`, so it is
exactly what the formatter produces.

## Contents
- Where this repo differs from Google
- Authority: clang-format wins
- Canonical layout
- Alignment is enabled — beware scripted edits
- Line, declaration and expression rules
- Include order

## Where this repo differs from Google

`.clang-format` is `BasedOnStyle: Google` with deliberate overrides. **When this
table and the Google guide disagree, this table wins.**

| setting | Google | here | effect |
|---|---|---|---|
| `IndentWidth` | 2 | **4** | every nesting level is 4 columns |
| `ColumnLimit` | 80 | **120** | lines wrap much later |
| `AllowShortIfStatementsOnASingleLine` | allowed | **Never** | `if (x) { return; }` always breaks across lines |
| `AllowShortLoopsOnASingleLine` | allowed | **false** | same for loops |
| `InsertBraces` | — | **true** | the formatter *adds* missing braces for you |
| `QualifierAlignment` | Leave | **Left** | `const auto*`, never `auto const*` |
| `IndentPPDirectives` | None | **BeforeHash** | nested `#if` indents before the `#`, not after |
| `AlignConsecutiveAssignments` | off | **on** (across empty lines and comments, compound ops too) | `=` column-aligned in runs |
| `AlignConsecutiveMacros` | off | **on** | `#define` values aligned |
| `AlignConsecutiveBitFields` | off | **on** | bit-field widths aligned |
| `AlignArrayOfStructures` | None | **Left** | struct array initialisers form a grid |

Access specifiers still follow Google's `AccessModifierOffset: -1`, which at
`IndentWidth: 4` puts them at **3 spaces**.

## Authority: clang-format wins

Do not hand-format, and do not argue with the table above — run the formatter.
`ament_clang_format` is a separate ctest entry, so style drift fails the test
suite on its own, independently of the unit tests.

```bash
clang-format -i --style=file:.clang-format include/*.hpp src/*.cpp test/*.cpp
```

It reads the config at the *repo* root (`${CMAKE_SOURCE_DIR}/../.clang-format`),
not one inside the package.

## Canonical layout

```cpp
namespace app {

class Registry {
   public:
    explicit Registry(std::size_t capacity);
    ~Registry();

    bool add(std::string name, int value);
    const int* find(const std::string& name) const;

    std::size_t size() const { return items_.size(); }

   private:
    std::size_t capacity_ = 0;
    std::map<std::string, int> items_;
};

}  // namespace app
```

Note: namespace contents are **not** indented, the closing brace carries
`}  // namespace app` with two spaces before the comment, `public:` sits at 3
spaces, members at 4, and a trivial accessor stays on one line.

## Alignment is enabled — beware scripted edits

`AlignConsecutiveAssignments` column-aligns runs of assignments, and it keeps
aligning across blank lines and comments:

```cpp
constexpr auto kMaxRetries     = 3;
constexpr auto kRetryDelayMs   = 250;
constexpr auto kDefaultBudget  = 1024;
constexpr auto kServiceAddress = "app.internal";
```

**Consequence:** a `sed` or string-replace that assumes a single space around `=`
silently matches nothing. After any scripted edit, re-read the file instead of
trusting that it applied.

## Line, declaration and expression rules

- Spaces only, never tabs.
- `*` and `&` bind to the variable: `int* p`, not `int *p`.
- `const` goes on the left: `const std::string&`, `const auto*`.
- Return type on the function's line when it fits; otherwise one parameter per
  line, indented 4 from the function name.
- Break long boolean expressions before the operator, continuation indented 4.
- Do not parenthesise a return value unless needed.
- Floating literals always carry a decimal point or exponent: `25.0`, `1e4`.
- Trailing return types only where the leading form reads worse — an explicit
  lambda return type is the usual legitimate case.
- Empty loop bodies use `{}` or `continue`, never a bare `;`.
- `case` labels indent to the same level as their `switch`.
- Constructor initializer entries one per line, indented 4.
- Blank lines inside functions sparingly, to separate logical groups.

## Include order

Groups separated by a blank line, alphabetical within each group:

1. Related header (the `.hpp` this `.cpp` implements)
2. C system headers — `<unistd.h>`
3. C++ standard library — `<algorithm>`, `<memory>`
4. Other libraries — third-party and framework headers
5. This project's headers — `"Registry.hpp"`

clang-format sorts *within* a group; it will not move a header into the right
group. See [headers.md](headers.md) for what belongs in a header at all.
