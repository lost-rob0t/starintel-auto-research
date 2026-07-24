(in-package #:quasar.tests)

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (condition (caught)
      (typep caught condition-type))))

(defun run-core-tests ()
  (let ((graph (make-graph-document :id "test-graph" :title "Test Graph")))
    (add-node graph
              (make-graph-node
               :id "a"
               :type "test/node@1"
               :label "A \"quoted\" node"
               :x 10
               :y 20))
    (add-node graph
              (make-graph-node
               :id "b"
               :type "test/node@1"
               :label "B"
               :x 30
               :y 40))
    (add-edge graph
              (make-graph-edge
               :id "a-b"
               :type "test/related-to@1"
               :source "a"
               :target "b"
               :label "related"))
    (assert (= 3 (graph-revision graph)))
    (assert (= 2 (length (graph-nodes graph))))
    (assert (= 1 (length (graph-edges graph))))
    (assert
     (condition-signaled-p
      'duplicate-graph-entity
      (lambda ()
        (add-node graph
                  (make-graph-node
                   :id "a"
                   :type "test/node@1"
                   :label "duplicate")))))
    (assert
     (condition-signaled-p
      'missing-graph-node
      (lambda ()
        (add-edge graph
                  (make-graph-edge
                   :id "bad-edge"
                   :type "test/related-to@1"
                   :source "a"
                   :target "missing")))))
    (let ((json (graph->cytoscape-json graph)))
      (assert (search "\"graphId\":\"test-graph\"" json))
      (assert (search "\"revision\":3" json))
      (assert (search "A \\\"quoted\\\" node" json))
      (assert (search "\"source\":\"a\"" json))
      (assert (search "\"target\":\"b\"" json)))
    t))
