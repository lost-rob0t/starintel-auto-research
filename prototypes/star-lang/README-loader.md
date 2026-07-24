# Star-Lang loader and Lisp API

The loader is a Common Lisp API. The shell command is only a wrapper around the exported Lisp functions.

```lisp
(load "prototypes/star-lang/common-lisp/star-lang-api.lisp")

(defparameter *graph*
  (star-lang.api:load-star-file "path/to/root.star"))
```

Load a local `.star` specification library from the shell:

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

The equivalent Lisp entry point is:

```lisp
(star-lang.api:load-star
 "root.star"
 :allow-network t
 :cache-directory #P"/tmp/star-cache/")
```

Use `--cache DIR` to override the default cache and `--manifest FILE` to write the resolved library graph.

Local imports use the same version and digest lock:

```lisp
(import "org.example/spec@1"
  :version "1.0.0"
  :digest "sha256:<64 hexadecimal digits>"
  :path "relative/spec.star")
```

## Generated constructors

Constructor signatures are declared in Star-Lang library metadata and installed as real Common Lisp functions:

```lisp
(defparameter *star-cl*
  (star-lang.api:load-star-runtime
   "prototypes/star-lang/fixtures/star-cl-constructors.star"
   :constructor-package "STARINTEL"))

(starintel:new-person
 "people" "Ada" "Lovelace" "person"
 :bio "Mathematician")

(starintel:new-relation
 "relations" source-id target-id
 :predicate "member-of")
```

Explicit constructor declarations preserve legacy Star-CL signatures. Documents without an explicit compatibility declaration receive an automatic `new-<document>` function with `(dataset &rest args)`.

Generated source can also be written without installing it:

```lisp
(with-open-file (stream "star-cl-constructors.lisp"
                        :direction :output
                        :if-exists :supersede
                        :if-does-not-exist :create)
  (star-lang.api:generate-constructor-source
   *star-cl* stream :package "STARINTEL"))
```
