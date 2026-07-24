(in-package #:quasar.ui.clog)

(defparameter *cytoscape-url*
  "https://cdn.jsdelivr.net/npm/cytoscape@3.34.0/dist/cytoscape.min.js")

(defvar *last-session* nil)

(defclass quasar-ui-session ()
  ((body :initarg :body :reader session-body)
   (status-element :initarg :status-element :reader session-status-element)
   (renderer-ready-p :initform nil :accessor renderer-ready-p)
   (pending-graph :initform nil :accessor session-pending-graph)
   (last-projected-revision :initform nil
                            :accessor session-last-projected-revision)))

(defun static-path (relative-path)
  (merge-pathnames relative-path
                   (asdf:system-source-directory "quasar/ui-clog")))

(defun read-static-file (relative-path)
  (uiop:read-file-string (static-path relative-path)))

(defun set-session-status (session message)
  (setf (clog:text (session-status-element session)) message)
  message)

(defun project-graph (graph &optional (session *last-session*))
  (unless session
    (error "No Quasar browser session exists. Open the CLOG application first."))
  (setf (session-pending-graph session) graph)
  (when (renderer-ready-p session)
    (clog:js-execute
     (session-body session)
     (format nil "window.QuasarCytoscape.setGraph(~A);"
             (graph->cytoscape-json graph)))
    (setf (session-pending-graph session) nil
          (session-last-projected-revision session) (graph-revision graph))
    (set-session-status
     session
     (format nil "Renderer ready — projected graph revision ~D."
             (graph-revision graph))))
  graph)

(defun project-demo-graph (&optional (session *last-session*))
  (project-graph (make-demo-graph) session))

(defun handle-renderer-bridge (session bridge)
  (let ((status (clog:attribute bridge "data-status" :default-answer "")))
    (cond
      ((string= status "ready")
       (setf (renderer-ready-p session) t)
       (set-session-status session "Renderer ready — project a graph from the REPL.")
       (when (session-pending-graph session)
         (project-graph (session-pending-graph session) session)))
      ((string= status "error")
       (setf (renderer-ready-p session) nil)
       (set-session-status
        session
        (format nil "Renderer failed: ~A"
                (clog:attribute bridge "data-error"
                                :default-answer "unknown browser error"))))
      (t
       (set-session-status
        session
        (format nil "Renderer bridge reported unknown status ~S." status))))))

(defun install-workbench (body)
  (clog:create-element
   body
   :style
   :content (read-static-file "static/quasar.css"))
  (let* ((root (clog:create-element body :div :html-id "quasar-root"))
         (header (clog:create-element root :header :html-id "quasar-header"))
         (title (clog:create-div header :content "Quasar"))
         (status (clog:create-div header :content "Loading Cytoscape…"))
         (main (clog:create-element root :main :html-id "quasar-main"))
         (graph-host (clog:create-element main :div :html-id "quasar-graph"))
         (inspector (clog:create-element main :aside :html-id "quasar-inspector"))
         (bridge
           (clog:create-element
            body
            :button
            :content ""
            :html-id "quasar-renderer-ready-bridge"))
         (session
           (make-instance 'quasar-ui-session
                          :body body
                          :status-element status)))
    (declare (ignore title graph-host))
    (setf (clog:text inspector)
          "Prototype boundary: renderer projection only; editing follows after review.")
    (setf (clog:hiddenp bridge) t)
    (clog:set-on-click
     bridge
     (lambda (object)
       (handle-renderer-bridge session object)))
    (setf *last-session* session)
    (clog:js-execute body
                     (read-static-file "static/quasar-cytoscape.js"))
    (clog:js-execute
     body
     (format nil
             "window.QuasarCytoscape.load({containerId:~A,readyBridgeId:~A,cytoscapeUrl:~A});"
             (encode-json-string "quasar-graph")
             (encode-json-string "quasar-renderer-ready-bridge")
             (encode-json-string *cytoscape-url*)))
    session))

(defun on-new-window (body)
  (handler-case
      (install-workbench body)
    (error (condition)
      (clog:create-div
       body
       :content (format nil "Quasar failed to initialize: ~A" condition)))))

(defun start-quasar (&key (host "127.0.0.1") (port 8080) (open-browser-p t))
  (clog:initialize #'on-new-window :host host :port port)
  (when open-browser-p
    (clog:open-browser))
  t)

(defun stop-quasar ()
  (when (clog:is-running-p)
    (clog:shutdown))
  (setf *last-session* nil)
  t)
