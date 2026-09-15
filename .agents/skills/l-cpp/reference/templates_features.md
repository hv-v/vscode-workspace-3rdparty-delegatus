# Templates and generic programming

Baseline: [Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)
— Template metaprogramming, Type deduction, Operator overloading, Friends, Aliases.

## Contents
- Where this repo differs from Google
- Keep templates boring
- Type deduction and `auto`
- Lambdas
- Aliases
- Operator overloading
- Friends
- Concepts (C++20)
- Prefer runtime polymorphism

## Where this repo differs from Google

| rule | Google | here |
|---|---|---|
| function naming in every example below | `PascalCase` | **`camelCase`** — see [naming.md](naming.md) |
| concepts | no rule stated | permitted, kept simple (below) |

The template rules themselves are Google's and are followed as written.

## Keep templates boring

> "Avoid complicated template programming... In particular, avoid using templates
> to do type computation."

Templates exist here to avoid writing the same function for several types, not to
compute at compile time. If a template needs a comment explaining how it resolves,
it is too clever — prefer a virtual interface, an overload set, or plain
duplication.

A reasonable template looks like this and no more elaborate:

```cpp
template <typename Range, typename Predicate>
bool anyOf(const Range& range, Predicate predicate) {
    return std::any_of(std::begin(range), std::end(range), predicate);
}
```

Warning signs it has gone too far: errors longer than the function, a helper whose
only job is `enable_if`, or a template only ever instantiated for one type. In the
last case, write the concrete type.

## Type deduction and `auto`

> "Use `auto` to avoid type names that are noisy, obvious, or unimportant."

```cpp
auto results       = findAll(items, "prefix");  // type is obvious from the call
const auto* record = registry.find(name);       // pointer-ness stays visible
const auto& first  = results.front();           // no copy
for (const auto& [name, value] : items) {       // structured binding
    forEach(value, print);
}
```

Keep the manifest type when it carries information the reader needs — a numeric
width, an ownership decision, a signedness that changes the arithmetic. Never let
`auto` hide indirection: write `auto*` and `auto&`, and `const auto&` when binding
to something you must not copy. `QualifierAlignment: Left` means it is always
`const auto*`, never `auto const*`.

## Lambdas

Prefer explicit captures. `[&]` and `[=]` hide lifetime bugs. A lambda that
outlives its enclosing frame — an async completion, a stored callback — must
capture by value, or capture a `shared_ptr` that keeps the owner alive:

```cpp
void Registry::refreshAsync(std::string name) {
    client_.sendRequest(name, [this, name](const Response& response) {
        // 'name' is captured by value: the caller's frame is gone by now.
        applyResponse(name, response);
    });
}
```

Format a lambda body like a normal function body. Once it grows past a few
statements, make it a named member function.

## Aliases

`using`, never `typedef`:

```cpp
using ItemMap  = std::map<std::string, int>;
using Callback = std::function<void(const std::string&)>;
```

## Operator overloading

> "Define overloaded operators only if their meaning is obvious, unsurprising, and
> consistent with the corresponding built-in operators."

Define them in the same header and namespace as their operand type. Never overload
`&&`, `||`, comma, or unary `&`. **User-defined literals are prohibited.**

## Friends

Permitted within reason, in the same file as the class. Legitimate uses are
builder classes and test fixtures that need one private member — prefer that over
widening the public interface just so a test can reach in.

## Concepts (C++20)

Google states no rule, so this is a local decision: use a concept where it
replaces an `enable_if`, keep it named and simple, and do not build a hierarchy.

```cpp
template <typename T>
concept Printable = requires(const T& value) { std::format("{}", value); };

template <Printable T>
void forEach(const std::vector<T>& values, const Callback& callback);
```

A `requires` clause longer than two lines is the "complicated template
programming" the guide tells you to avoid.

## Prefer runtime polymorphism

Extension here happens through virtual interfaces and a registry, not template
parameters. New behaviour is a new class registered at construction:

```cpp
class IRule {
   public:
    virtual ~IRule()                                   = default;
    virtual std::string name() const                   = 0;
    virtual bool check(const Registry& registry) const = 0;
};
```

Note the aligned `=` — `AlignConsecutiveAssignments` applies to pure-virtual
declarations too. Add checks this way unless there is a concrete reason not to.
