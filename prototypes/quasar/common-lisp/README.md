# Quasar CLOG Prototype

This is the first executable Quasar slice. It proves that a renderer-independent Common Lisp graph can be projected from the REPL into one Cytoscape.js component hosted by CLOG.

It intentionally does **not** implement editing gestures, actions, persistence, Star-Lang integration, or a public network protocol.

## Requirements

- SBCL or another CLOG-supported Common Lisp implementation
- ASDF
- CLOG available through Quicklisp, Ultralisp, OCICL, or a local source checkout
- a browser that can load the prototype's pinned Cytoscape.js URL

The prototype defaults to Cytoscape.js `3.34.0` from jsDelivr. This is a prototype convenience, not the final local-first packaging decision. Override `quasar.ui.clog:*cytoscape-url*` before opening a browser to test another hosted or locally served bundle.

## Load

From a REPL in this directory:

```lisp
(ql:quickload :clog)
(asdf:load-asd (truename "quasar.asd"))
(asdf:load-system "quasar/ui-clog")
(quasar.ui.clog:start-quasar)
```

After the browser reports that the renderer is ready:

```lisp
(defparameter *quasar-demo* (quasar.core:make-demo-graph))
(quasar.ui.clog:project-graph *quasar-demo*)
```

The graph contains two typed nodes and one typed edge.

## Core-only test

The core system does not depend on CLOG:

```lisp
(asdf:load-asd (truename "quasar.asd"))
(asdf:test-system "quasar/core")
```

Or invoke the test function directly:

```lisp
(asdf:load-system "quasar/tests")
(quasar.tests:run-core-tests)
```

## Stop

```lisp
(quasar.ui.clog:stop-quasar)
```

## Prototype boundary

Cytoscape owns browser-local rendering. The Common Lisp graph remains canonical. The renderer-ready callback crosses the CLOG WebSocket through a hidden bridge button, and graph projection uses one JSON payload. No graph element is represented as an individual CLOG object.
