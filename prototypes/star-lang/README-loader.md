# Star-Lang loader

Load a local `.star` specification library:

```sh
prototypes/star-lang/bin/star load path/to/root.star
```

Remote imports are explicit and digest locked:

```lisp
(import "org.example/spec@1"
  :version "1.0.0"
  :digest "sha256:<64 hexadecimal digits>"
  :url "https://example.org/spec.star")
```

Enable the first network fetch with `--allow-network`. Verified sources are cached by SHA-256 and can then be loaded with networking disabled:

```sh
prototypes/star-lang/bin/star load root.star --allow-network
prototypes/star-lang/bin/star load root.star
```

Use `--cache DIR` to override the default cache and `--manifest FILE` to write the resolved library graph.

Local imports use the same version and digest lock:

```lisp
(import "org.example/spec@1"
  :version "1.0.0"
  :digest "sha256:<64 hexadecimal digits>"
  :path "relative/spec.star")
```
