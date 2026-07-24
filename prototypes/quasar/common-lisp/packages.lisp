(defpackage #:quasar.core
  (:use #:cl)
  (:export
   #:graph-error
   #:duplicate-graph-entity
   #:missing-graph-node
   #:graph-node
   #:graph-node-id
   #:graph-node-type
   #:graph-node-label
   #:graph-node-x
   #:graph-node-y
   #:graph-edge
   #:graph-edge-id
   #:graph-edge-type
   #:graph-edge-source
   #:graph-edge-target
   #:graph-edge-label
   #:graph-document
   #:graph-id
   #:graph-title
   #:graph-revision
   #:make-graph-node
   #:make-graph-edge
   #:make-graph-document
   #:add-node
   #:add-edge
   #:find-node
   #:find-edge
   #:graph-nodes
   #:graph-edges
   #:make-demo-graph
   #:encode-json-string
   #:graph->cytoscape-json))

(defpackage #:quasar.ui.clog
  (:use #:cl)
  (:import-from #:quasar.core
                #:encode-json-string
                #:graph->cytoscape-json
                #:graph-revision
                #:make-demo-graph)
  (:export
   #:*cytoscape-url*
   #:*last-session*
   #:quasar-ui-session
   #:renderer-ready-p
   #:start-quasar
   #:stop-quasar
   #:project-graph
   #:project-demo-graph))

(defpackage #:quasar.tests
  (:use #:cl)
  (:import-from #:quasar.core
                #:duplicate-graph-entity
                #:missing-graph-node
                #:graph-revision
                #:graph-nodes
                #:graph-edges
                #:make-graph-document
                #:make-graph-node
                #:make-graph-edge
                #:add-node
                #:add-edge
                #:graph->cytoscape-json)
  (:export #:run-core-tests))
