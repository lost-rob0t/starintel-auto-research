(in-package #:quasar.core)

(define-condition graph-error (error)
  ((message :initarg :message :reader graph-error-message))
  (:report (lambda (condition stream)
             (write-string (graph-error-message condition) stream))))

(define-condition duplicate-graph-entity (graph-error)
  ((entity-id :initarg :entity-id :reader duplicate-entity-id)))

(define-condition missing-graph-node (graph-error)
  ((node-id :initarg :node-id :reader missing-node-id)))

(defun ensure-non-empty-string (value name)
  (unless (and (stringp value) (plusp (length value)))
    (error 'graph-error
           :message (format nil "~A must be a non-empty string, got ~S."
                            name value)))
  value)

(defun ensure-coordinate (value name)
  (unless (realp value)
    (error 'graph-error
           :message (format nil "~A must be a real number, got ~S."
                            name value)))
  value)

(defclass graph-node ()
  ((id :initarg :id :reader graph-node-id)
   (type :initarg :type :reader graph-node-type)
   (label :initarg :label :accessor graph-node-label)
   (x :initarg :x :initform 0 :accessor graph-node-x)
   (y :initarg :y :initform 0 :accessor graph-node-y)))

(defmethod initialize-instance :after ((node graph-node) &key)
  (ensure-non-empty-string (graph-node-id node) "Node id")
  (ensure-non-empty-string (graph-node-type node) "Node type")
  (ensure-non-empty-string (graph-node-label node) "Node label")
  (ensure-coordinate (graph-node-x node) "Node x")
  (ensure-coordinate (graph-node-y node) "Node y"))

(defclass graph-edge ()
  ((id :initarg :id :reader graph-edge-id)
   (type :initarg :type :reader graph-edge-type)
   (source :initarg :source :reader graph-edge-source)
   (target :initarg :target :reader graph-edge-target)
   (label :initarg :label :initform "" :accessor graph-edge-label)))

(defmethod initialize-instance :after ((edge graph-edge) &key)
  (ensure-non-empty-string (graph-edge-id edge) "Edge id")
  (ensure-non-empty-string (graph-edge-type edge) "Edge type")
  (ensure-non-empty-string (graph-edge-source edge) "Edge source")
  (ensure-non-empty-string (graph-edge-target edge) "Edge target")
  (unless (stringp (graph-edge-label edge))
    (error 'graph-error
           :message (format nil "Edge label must be a string, got ~S."
                            (graph-edge-label edge)))))

(defclass graph-document ()
  ((id :initarg :id :reader graph-id)
   (title :initarg :title :accessor graph-title)
   (nodes :initform (make-hash-table :test #'equal)
          :reader graph-node-table)
   (edges :initform (make-hash-table :test #'equal)
          :reader graph-edge-table)
   (revision :initform 0 :accessor graph-revision)))

(defmethod initialize-instance :after ((graph graph-document) &key)
  (ensure-non-empty-string (graph-id graph) "Graph id")
  (ensure-non-empty-string (graph-title graph) "Graph title"))

(defun make-graph-node (&key id type label (x 0) (y 0))
  (make-instance 'graph-node
                 :id id
                 :type type
                 :label label
                 :x x
                 :y y))

(defun make-graph-edge (&key id type source target (label ""))
  (make-instance 'graph-edge
                 :id id
                 :type type
                 :source source
                 :target target
                 :label label))

(defun make-graph-document (&key id title)
  (make-instance 'graph-document :id id :title title))

(defun find-node (graph node-id)
  (gethash node-id (graph-node-table graph)))

(defun find-edge (graph edge-id)
  (gethash edge-id (graph-edge-table graph)))

(defun graph-nodes (graph)
  (sort (loop for node being the hash-values of (graph-node-table graph)
              collect node)
        #'string<
        :key #'graph-node-id))

(defun graph-edges (graph)
  (sort (loop for edge being the hash-values of (graph-edge-table graph)
              collect edge)
        #'string<
        :key #'graph-edge-id))

(defun signal-duplicate (kind entity-id)
  (error 'duplicate-graph-entity
         :entity-id entity-id
         :message (format nil "~A ~S already exists." kind entity-id)))

(defun require-node (graph node-id)
  (or (find-node graph node-id)
      (error 'missing-graph-node
             :node-id node-id
             :message (format nil "Graph node ~S does not exist." node-id))))

(defun add-node (graph node)
  (check-type graph graph-document)
  (check-type node graph-node)
  (when (find-node graph (graph-node-id node))
    (signal-duplicate "Node" (graph-node-id node)))
  (setf (gethash (graph-node-id node) (graph-node-table graph)) node)
  (incf (graph-revision graph))
  node)

(defun add-edge (graph edge)
  (check-type graph graph-document)
  (check-type edge graph-edge)
  (when (find-edge graph (graph-edge-id edge))
    (signal-duplicate "Edge" (graph-edge-id edge)))
  (require-node graph (graph-edge-source edge))
  (require-node graph (graph-edge-target edge))
  (setf (gethash (graph-edge-id edge) (graph-edge-table graph)) edge)
  (incf (graph-revision graph))
  edge)

(defun make-demo-graph ()
  (let ((graph (make-graph-document
                :id "quasar-demo"
                :title "Quasar CLOG Prototype")))
    (add-node graph
              (make-graph-node
               :id "node-domain"
               :type "star.core/domain@1"
               :label "example.org"
               :x 180
               :y 180))
    (add-node graph
              (make-graph-node
               :id "node-ip"
               :type "star.core/ip-address@1"
               :label "203.0.113.10"
               :x 520
               :y 180))
    (add-edge graph
              (make-graph-edge
               :id "edge-resolves"
               :type "star.core/resolves-to@1"
               :source "node-domain"
               :target "node-ip"
               :label "resolves to"))
    graph))
