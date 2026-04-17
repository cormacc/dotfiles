# Tool Guide: clj-nrepl-eval and clj-paren-repair

Complete reference for Clojure development tools.

## clj-nrepl-eval

Interface to a running Clojure nREPL server.

### Basic Syntax

```shell
clj-nrepl-eval [options] "clojure-expression"
```

Options:
- `-p, --port PORT` - nREPL port (read from `.nrepl-port` if present, or use `--discover-ports`)
- `-h, --host HOST` - nREPL host (default: localhost)

### Evaluating Code

```shell
# Simple expressions
clj-nrepl-eval -p PORT "(+ 1 2 3)"

# Define functions
clj-nrepl-eval -p PORT "(defn greet [name] (str \"Hello, \" name))"
clj-nrepl-eval -p PORT "(greet \"World\")"

# Work with collections
clj-nrepl-eval -p PORT "(map inc [1 2 3])"
clj-nrepl-eval -p PORT "(filter even? [1 2 3 4])"

# Require and use namespaces
clj-nrepl-eval -p PORT "(require '[clojure.string :as str])"
clj-nrepl-eval -p PORT "(str/upper-case \"hello\")"
```

### Discovery Commands

```shell
# List all public functions in a namespace
clj-nrepl-eval -p PORT "(clojure.repl/dir clojure.string)"

# Get function documentation
clj-nrepl-eval -p PORT "(clojure.repl/doc map)"

# Search by name pattern
clj-nrepl-eval -p PORT "(clojure.repl/apropos \"split\")"

# Search documentation text
clj-nrepl-eval -p PORT "(clojure.repl/find-doc \"regular expression\")"

# Read function source
clj-nrepl-eval -p PORT "(clojure.repl/source filter)"

# Get function signatures
clj-nrepl-eval -p PORT "(:arglists (meta #'reduce))"
```

### Loading Project Code

```shell
# Load a namespace
clj-nrepl-eval -p PORT "(require '[project.core :as core] :reload)"

# List namespace contents
clj-nrepl-eval -p PORT "(clojure.repl/dir project.core)"

# Test loaded functions
clj-nrepl-eval -p PORT "(core/my-function test-data)"
```

### Debugging

```shell
# Inspect data structures
clj-nrepl-eval -p PORT "(type [1 2 3])"
clj-nrepl-eval -p PORT "(keys my-map)"

# Test pipeline steps
clj-nrepl-eval -p PORT "(def data [1 2 3 4 5])"
clj-nrepl-eval -p PORT "(filter even? data)"
clj-nrepl-eval -p PORT "(map #(* % 2) (filter even? data))"

# Check predicates
clj-nrepl-eval -p PORT "(even? 4)"
clj-nrepl-eval -p PORT "(nil? [])"
clj-nrepl-eval -p PORT "(empty? [])"
```

## clj-paren-repair

Fixes delimiter errors (mismatched parentheses, brackets, braces) in Clojure files.

### Usage

```shell
# Fix a single file
clj-paren-repair path/to/file.clj

# Fix multiple files
clj-paren-repair src/core.clj src/util.clj test/core_test.clj

# Check code without file (stdin mode)
echo '(defn hello [x] (+ x 1)' | clj-paren-repair
```

The tool:
1. Detects delimiter errors using edamame parser
2. Repairs them using parinfer-rust (or parinferish fallback)
3. Formats with cljfmt
4. Reports what was fixed

### When to Use

- Parse error or unbalanced delimiter after editing
- REPL eval fails with unexpected delimiter/EOF error
- Editing multiple files and want to verify they're well-formed

### Supported File Types

.clj, .cljs, .cljc, .bb, .edn, .lpy

## Troubleshooting

### Connection refused

Ask user to start nREPL:
```bash
bb nrepl
lein repl :headless
clj -Sdeps '{:deps {nrepl/nrepl {:mvn/version "1.0.0"}}}' -M -m nrepl.cmdline
```

### Wrong port

Check actual port and adjust:
```shell
clj-nrepl-eval -p <correct-port> "(...)"
```

### Namespace not found

Require it first:
```shell
clj-nrepl-eval -p PORT "(require '[namespace.name])"
```

### Expression errors

Test simpler expressions to isolate, then use `(clojure.repl/doc ...)` to verify signatures.
