(defpackage #:star-lang.core
  (:use #:cl)
  (:export
   #:analysis-plan
   #:analysis-plan-hash
   #:analysis-plan-name
   #:analysis-plan-nodes
   #:compile-source
   #:core-document
   #:core-document-content-hash
   #:core-document-fields
   #:core-document-id
   #:core-document-persistence
   #:core-document-schema-name
   #:core-document-schema-version
   #:document-field
   #:event-signature
   #:make-core-document
   #:make-core-registry
   #:make-example-registry
   #:parse-source
   #:plan-node
   #:plan-node-id
   #:plan-node-operation
   #:plan-node-source-span
   #:read-source-file
   #:register-capability
   #:register-schema
   #:run-event
   #:run-event-node-id
   #:run-event-payload
   #:run-event-sequence
   #:run-event-type
   #:run-plan
   #:runtime-dispatch-count
   #:runtime-events
   #:runtime-persisted
   #:sha256-string
   #:source-span
   #:source-span-end-column
   #:source-span-end-line
   #:source-span-source-name
   #:source-span-start-column
   #:source-span-start-line
   #:star-lang-error
   #:star-lang-error-code
   #:star-lang-error-message
   #:star-lang-error-span
   #:syntax-object
   #:syntax-object-datum
   #:syntax-object-span))

(in-package #:star-lang.core)

(define-condition star-lang-error (error)
  ((code :initarg :code :reader star-lang-error-code)
   (message :initarg :message :reader star-lang-error-message)
   (span :initarg :span :initform nil :reader star-lang-error-span))
  (:report
   (lambda (condition stream)
     (format stream "~A: ~A"
             (star-lang-error-code condition)
             (star-lang-error-message condition)))))

(define-condition source-error (star-lang-error) ())
(define-condition compile-error (star-lang-error) ())
(define-condition schema-error (star-lang-error) ())
(define-condition capability-error (star-lang-error) ())
(define-condition execution-error (star-lang-error) ())
(define-condition replay-error (star-lang-error) ())
(define-condition transient-persistence-denied (star-lang-error) ())

(defun fail (condition-type code span control &rest arguments)
  (error condition-type
         :code code
         :span span
         :message (apply #'format nil control arguments)))

(defstruct source-position
  offset
  line
  column)

(defstruct source-span
  source-name
  start-offset
  end-offset
  start-line
  start-column
  end-line
  end-column)

(defstruct source-symbol
  name
  keyword-p)

(defstruct syntax-object
  datum
  span
  (origin-chain '()))

(defstruct token
  kind
  text
  value
  start
  end)

(defstruct (reader-state (:constructor %make-reader-state))
  source
  source-name
  (index 0)
  (line 1)
  (column 1)
  (token-count 0)
  (max-source-bytes 65536)
  (max-tokens 20000)
  (max-depth 128)
  (max-token-length 4096)
  (max-list-length 10000)
  (max-integer-magnitude 1000000000000000000))

(defun make-reader-state (source source-name &key
                                             (max-source-bytes 65536)
                                             (max-tokens 20000)
                                             (max-depth 128)
                                             (max-token-length 4096)
                                             (max-list-length 10000)
                                             (max-integer-magnitude 1000000000000000000))
  (when (> (length source) max-source-bytes)
    (fail 'source-error :source-too-large nil
          "Source exceeds ~D bytes." max-source-bytes))
  (%make-reader-state
   :source source
   :source-name source-name
   :max-source-bytes max-source-bytes
   :max-tokens max-tokens
   :max-depth max-depth
   :max-token-length max-token-length
   :max-list-length max-list-length
   :max-integer-magnitude max-integer-magnitude))

(defun state-position (state)
  (make-source-position
   :offset (reader-state-index state)
   :line (reader-state-line state)
   :column (reader-state-column state)))

(defun make-span-between (state start end)
  (make-source-span
   :source-name (reader-state-source-name state)
   :start-offset (source-position-offset start)
   :end-offset (source-position-offset end)
   :start-line (source-position-line start)
   :start-column (source-position-column start)
   :end-line (source-position-line end)
   :end-column (source-position-column end)))

(defun state-end-p (state)
  (>= (reader-state-index state) (length (reader-state-source state))))

(defun state-peek (state)
  (unless (state-end-p state)
    (char (reader-state-source state) (reader-state-index state))))

(defun state-advance (state)
  (let ((character (state-peek state)))
    (when character
      (incf (reader-state-index state))
      (if (char= character #\Newline)
          (progn
            (incf (reader-state-line state))
            (setf (reader-state-column state) 1))
          (incf (reader-state-column state))))
    character))

(defun whitespace-character-p (character)
  (and character
       (or (char= character #\Space)
           (char= character #\Tab)
           (char= character #\Newline)
           (char= character #\Return)
           (char= character #\Page))))

(defun skip-space-and-comments (state)
  (loop
    (loop while (whitespace-character-p (state-peek state))
          do (state-advance state))
    (if (and (state-peek state) (char= (state-peek state) #\;))
        (loop for character = (state-advance state)
              while (and character (not (char= character #\Newline))))
        (return))))

(defun delimiter-character-p (character)
  (or (null character)
      (whitespace-character-p character)
      (char= character #\()
      (char= character #\))
      (char= character #\;)))

(defun forbidden-source-character-p (character)
  (member character '(#\# #\' #\` #\,) :test #'char=))

(defun increment-token-count (state span)
  (incf (reader-state-token-count state))
  (when (> (reader-state-token-count state) (reader-state-max-tokens state))
    (fail 'source-error :too-many-tokens span
          "Source exceeds ~D tokens." (reader-state-max-tokens state))))

(defun read-string-token (state start)
  (state-advance state)
  (let ((output (make-array 16 :element-type 'character :adjustable t :fill-pointer 0)))
    (loop
      (when (state-end-p state)
        (fail 'source-error :unterminated-string
              (make-span-between state start (state-position state))
              "String literal is not terminated."))
      (let ((character (state-advance state)))
        (cond
          ((char= character #\")
           (let* ((end (state-position state))
                  (span (make-span-between state start end))
                  (text (subseq (reader-state-source state)
                                (source-position-offset start)
                                (source-position-offset end))))
             (increment-token-count state span)
             (return (make-token :kind :string
                                 :text text
                                 :value (coerce output 'string)
                                 :start start
                                 :end end))))
          ((char= character #\\)
           (when (state-end-p state)
             (fail 'source-error :unterminated-escape
                   (make-span-between state start (state-position state))
                   "String escape is not terminated."))
           (let ((escaped (state-advance state)))
             (vector-push-extend
              (case escaped
                (#\n #\Newline)
                (#\r #\Return)
                (#\t #\Tab)
                (#\\ #\\)
                (#\" #\")
                (otherwise
                 (fail 'source-error :invalid-string-escape
                       (make-span-between state start (state-position state))
                       "Unsupported string escape \\~C." escaped)))
              output)))
          (t
           (vector-push-extend character output)))))))

(defun integer-token-p (text)
  (and (> (length text) 0)
       (let ((start (if (char= (char text 0) #\-) 1 0)))
         (and (< start (length text))
              (loop for index from start below (length text)
                    always (digit-char-p (char text index)))))))

(defun read-atom-token (state start)
  (let ((start-offset (source-position-offset start)))
    (loop for character = (state-peek state)
          until (delimiter-character-p character)
          do
             (when (forbidden-source-character-p character)
               (fail 'source-error :forbidden-reader-syntax
                     (make-span-between state start (state-position state))
                     "Character ~C is forbidden in Star-Lang source." character))
             (state-advance state)
             (when (> (- (reader-state-index state) start-offset)
                      (reader-state-max-token-length state))
               (fail 'source-error :token-too-long
                     (make-span-between state start (state-position state))
                     "Token exceeds ~D characters."
                     (reader-state-max-token-length state))))
    (let* ((end (state-position state))
           (text (subseq (reader-state-source state)
                         start-offset
                         (source-position-offset end)))
           (lower (string-downcase text))
           (span (make-span-between state start end))
           (value
             (cond
               ((string= lower "true") t)
               ((or (string= lower "false") (string= lower "nil")) nil)
               ((integer-token-p text)
                (let ((integer (parse-integer text)))
                  (when (> (abs integer) (reader-state-max-integer-magnitude state))
                    (fail 'source-error :integer-too-large span
                          "Integer exceeds magnitude limit ~D."
                          (reader-state-max-integer-magnitude state)))
                  integer))
               (t
                (make-source-symbol
                 :name (if (and (> (length lower) 0)
                                (char= (char lower 0) #\:))
                           (subseq lower 1)
                           lower)
                 :keyword-p (and (> (length lower) 0)
                                 (char= (char lower 0) #\:)))))))
      (when (zerop (length text))
        (fail 'source-error :empty-token span "Empty token."))
      (increment-token-count state span)
      (make-token :kind :atom :text text :value value :start start :end end))))

(defun next-token (state)
  (skip-space-and-comments state)
  (when (state-end-p state)
    (return-from next-token nil))
  (let* ((start (state-position state))
         (character (state-peek state)))
    (cond
      ((char= character #\()
       (state-advance state)
       (let ((end (state-position state)))
         (increment-token-count state (make-span-between state start end))
         (make-token :kind :left-paren :text "(" :start start :end end)))
      ((char= character #\))
       (state-advance state)
       (let ((end (state-position state)))
         (increment-token-count state (make-span-between state start end))
         (make-token :kind :right-paren :text ")" :start start :end end)))
      ((char= character #\")
       (read-string-token state start))
      ((forbidden-source-character-p character)
       (fail 'source-error :forbidden-reader-syntax
             (make-span-between state start (state-position state))
             "Character ~C is forbidden in Star-Lang source." character))
      (t
       (read-atom-token state start)))))

(defstruct (token-stream (:constructor %make-token-stream))
  tokens
  (index 0)
  source-name
  max-depth
  max-list-length)

(defun tokenize-source (source source-name &rest limits)
  (let ((state (apply #'make-reader-state source source-name limits))
        (tokens '()))
    (loop for token = (next-token state)
          while token
          do (push token tokens))
    (values (nreverse tokens) state)))

(defun token-stream-peek (stream)
  (when (< (token-stream-index stream) (length (token-stream-tokens stream)))
    (nth (token-stream-index stream) (token-stream-tokens stream))))

(defun token-stream-next (stream)
  (prog1 (token-stream-peek stream)
    (incf (token-stream-index stream))))

(defun token-span (stream token)
  (make-source-span
   :source-name (token-stream-source-name stream)
   :start-offset (source-position-offset (token-start token))
   :end-offset (source-position-offset (token-end token))
   :start-line (source-position-line (token-start token))
   :start-column (source-position-column (token-start token))
   :end-line (source-position-line (token-end token))
   :end-column (source-position-column (token-end token))))

(defun parse-expression (stream depth)
  (when (> depth (token-stream-max-depth stream))
    (fail 'source-error :nesting-too-deep nil
          "Source nesting exceeds ~D levels." (token-stream-max-depth stream)))
  (let ((token (token-stream-next stream)))
    (unless token
      (fail 'source-error :unexpected-end nil "Unexpected end of source."))
    (case (token-kind token)
      (:atom
       (make-syntax-object :datum (token-value token)
                           :span (token-span stream token)))
      (:string
       (make-syntax-object :datum (token-value token)
                           :span (token-span stream token)))
      (:right-paren
       (fail 'source-error :unexpected-right-paren (token-span stream token)
             "Unexpected right parenthesis."))
      (:left-paren
       (let ((items '())
             (count 0)
             (start (token-start token)))
         (loop
           (let ((next (token-stream-peek stream)))
             (unless next
               (fail 'source-error :unterminated-list
                     (token-span stream token)
                     "List is not terminated."))
             (when (eq (token-kind next) :right-paren)
               (token-stream-next stream)
               (let ((end (token-end next)))
                 (return
                   (make-syntax-object
                    :datum (nreverse items)
                    :span (make-source-span
                           :source-name (token-stream-source-name stream)
                           :start-offset (source-position-offset start)
                           :end-offset (source-position-offset end)
                           :start-line (source-position-line start)
                           :start-column (source-position-column start)
                           :end-line (source-position-line end)
                           :end-column (source-position-column end))))))
             (incf count)
             (when (> count (token-stream-max-list-length stream))
               (fail 'source-error :list-too-long (token-span stream token)
                     "List exceeds ~D elements."
                     (token-stream-max-list-length stream)))
             (push (parse-expression stream (1+ depth)) items))))))))

(defun parse-source (source &key (source-name "<string>")
                                 (max-source-bytes 65536)
                                 (max-tokens 20000)
                                 (max-depth 128)
                                 (max-token-length 4096)
                                 (max-list-length 10000)
                                 (max-integer-magnitude 1000000000000000000))
  (multiple-value-bind (tokens state)
      (tokenize-source source source-name
                       :max-source-bytes max-source-bytes
                       :max-tokens max-tokens
                       :max-depth max-depth
                       :max-token-length max-token-length
                       :max-list-length max-list-length
                       :max-integer-magnitude max-integer-magnitude)
    (declare (ignore state))
    (let ((stream (%make-token-stream
                   :tokens tokens
                   :source-name source-name
                   :max-depth max-depth
                   :max-list-length max-list-length)))
      (when (null tokens)
        (fail 'source-error :empty-source nil "Source is empty."))
      (let ((root (parse-expression stream 0)))
        (when (token-stream-peek stream)
          (fail 'source-error :multiple-top-level-forms
                (token-span stream (token-stream-peek stream))
                "Source must contain exactly one top-level form."))
        root))))

(defun read-source-file (pathname &rest limits)
  (let ((source
          (with-open-file (stream pathname :direction :input :external-format :utf-8)
            (let ((content (make-string (file-length stream))))
              (read-sequence content stream)
              content))))
    (apply #'parse-source source :source-name (namestring pathname) limits)))

(defun u32 (integer)
  (ldb (byte 32 0) integer))

(defun rotr32 (integer count)
  (let ((value (u32 integer)))
    (u32 (logior (ash value (- count))
                 (ash (ldb (byte count 0) value) (- 32 count))))))

(defun sha256-choice (x y z)
  (logxor (logand x y) (logand (lognot x) z)))

(defun sha256-majority (x y z)
  (logxor (logand x y) (logand x z) (logand y z)))

(defun sha256-big-sigma-0 (x)
  (logxor (rotr32 x 2) (rotr32 x 13) (rotr32 x 22)))

(defun sha256-big-sigma-1 (x)
  (logxor (rotr32 x 6) (rotr32 x 11) (rotr32 x 25)))

(defun sha256-small-sigma-0 (x)
  (logxor (rotr32 x 7) (rotr32 x 18) (ash x -3)))

(defun sha256-small-sigma-1 (x)
  (logxor (rotr32 x 17) (rotr32 x 19) (ash x -10)))

(defparameter +sha256-initial+
  #(#x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
    #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19))

(defparameter +sha256-k+
  #(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5 #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
    #xd807aa98 #x12835b01 #x243185be #x550c7dc3 #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
    #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
    #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7 #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
    #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13 #x650a7354 #x766a0abb #x81c2c92e #x92722c85
    #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3 #xd192e819 #xd6990624 #xf40e3585 #x106aa070
    #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5 #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
    #x748f82ee #x78a5636f #x84c87814 #x8cc70208 #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))

(defun string-octets (string)
  (let ((output (make-array 16 :element-type '(unsigned-byte 8)
                               :adjustable t :fill-pointer 0)))
    (labels ((emit (byte) (vector-push-extend byte output)))
      (loop for character across string
            for code = (char-code character)
            do
               (cond
                 ((<= code #x7f)
                  (emit code))
                 ((<= code #x7ff)
                  (emit (logior #xc0 (ash code -6)))
                  (emit (logior #x80 (logand code #x3f))))
                 ((<= code #xffff)
                  (emit (logior #xe0 (ash code -12)))
                  (emit (logior #x80 (logand (ash code -6) #x3f)))
                  (emit (logior #x80 (logand code #x3f))))
                 (t
                  (emit (logior #xf0 (ash code -18)))
                  (emit (logior #x80 (logand (ash code -12) #x3f)))
                  (emit (logior #x80 (logand (ash code -6) #x3f)))
                  (emit (logior #x80 (logand code #x3f)))))))
    output))

(defun sha256-octets (input)
  (let* ((length (length input))
         (bit-length (* length 8))
         (message (make-array (+ length 72)
                              :element-type '(unsigned-byte 8)
                              :adjustable t
                              :fill-pointer 0)))
    (loop for byte across input do (vector-push-extend byte message))
    (vector-push-extend #x80 message)
    (loop until (= (mod (length message) 64) 56)
          do (vector-push-extend 0 message))
    (loop for shift from 56 downto 0 by 8
          do (vector-push-extend (ldb (byte 8 shift) bit-length) message))
    (let ((hash (copy-seq +sha256-initial+)))
      (loop for chunk-start from 0 below (length message) by 64
            do
               (let ((words (make-array 64 :element-type '(unsigned-byte 32)
                                           :initial-element 0)))
                 (dotimes (index 16)
                   (let ((offset (+ chunk-start (* index 4))))
                     (setf (aref words index)
                           (u32 (logior (ash (aref message offset) 24)
                                        (ash (aref message (+ offset 1)) 16)
                                        (ash (aref message (+ offset 2)) 8)
                                        (aref message (+ offset 3)))))))
                 (loop for index from 16 below 64
                       do (setf (aref words index)
                                (u32 (+ (aref words (- index 16))
                                        (sha256-small-sigma-0 (aref words (- index 15)))
                                        (aref words (- index 7))
                                        (sha256-small-sigma-1 (aref words (- index 2)))))))
                 (let ((a (aref hash 0))
                       (b (aref hash 1))
                       (c (aref hash 2))
                       (d (aref hash 3))
                       (e (aref hash 4))
                       (f (aref hash 5))
                       (g (aref hash 6))
                       (h (aref hash 7)))
                   (dotimes (index 64)
                     (let* ((temporary-1
                              (u32 (+ h
                                      (sha256-big-sigma-1 e)
                                      (sha256-choice e f g)
                                      (aref +sha256-k+ index)
                                      (aref words index))))
                            (temporary-2
                              (u32 (+ (sha256-big-sigma-0 a)
                                      (sha256-majority a b c)))))
                       (setf h g
                             g f
                             f e
                             e (u32 (+ d temporary-1))
                             d c
                             c b
                             b a
                             a (u32 (+ temporary-1 temporary-2)))))
                   (setf (aref hash 0) (u32 (+ (aref hash 0) a))
                         (aref hash 1) (u32 (+ (aref hash 1) b))
                         (aref hash 2) (u32 (+ (aref hash 2) c))
                         (aref hash 3) (u32 (+ (aref hash 3) d))
                         (aref hash 4) (u32 (+ (aref hash 4) e))
                         (aref hash 5) (u32 (+ (aref hash 5) f))
                         (aref hash 6) (u32 (+ (aref hash 6) g))
                         (aref hash 7) (u32 (+ (aref hash 7) h))))))
      (with-output-to-string (stream)
        (loop for word across hash
              do (format stream "~8,'0X" word))))))

(defun sha256-string (string)
  (string-downcase (sha256-octets (string-octets string))))

(defstruct schema-definition
  name
  version
  persistence
  fields)

(defstruct capability-definition
  name
  kind
  input-schema
  output-schema
  effects
  allowed-tools
  function)

(defstruct (core-registry (:constructor %make-core-registry))
  schemas
  capabilities)

(defun make-core-registry ()
  (%make-core-registry
   :schemas (make-hash-table :test #'equal)
   :capabilities (make-hash-table :test #'equal)))

(defun normalize-name (name)
  (string-downcase
   (etypecase name
     (string name)
     (symbol (symbol-name name))
     (source-symbol (source-symbol-name name)))))

(defun register-schema (registry name version persistence fields)
  (let ((normalized (normalize-name name)))
    (when (gethash normalized (core-registry-schemas registry))
      (fail 'schema-error :duplicate-schema nil
            "Schema ~A is already registered." normalized))
    (setf (gethash normalized (core-registry-schemas registry))
          (make-schema-definition
           :name normalized
           :version version
           :persistence persistence
           :fields fields))))

(defun register-capability (registry name kind input-schema output-schema effects function
                             &key (allowed-tools '()))
  (let ((normalized (normalize-name name)))
    (when (gethash normalized (core-registry-capabilities registry))
      (fail 'capability-error :duplicate-capability nil
            "Capability ~A is already registered." normalized))
    (setf (gethash normalized (core-registry-capabilities registry))
          (make-capability-definition
           :name normalized
           :kind kind
           :input-schema (and input-schema (normalize-name input-schema))
           :output-schema (and output-schema (normalize-name output-schema))
           :effects effects
           :allowed-tools (mapcar #'normalize-name allowed-tools)
           :function function))))

(defun require-schema (registry name span)
  (or (gethash (normalize-name name) (core-registry-schemas registry))
      (fail 'schema-error :unknown-schema span "Unknown schema ~A." name)))

(defun require-capability (registry name span)
  (or (gethash (normalize-name name) (core-registry-capabilities registry))
      (fail 'capability-error :unknown-capability span "Unknown capability ~A." name)))

(defstruct (core-document (:constructor %make-core-document))
  id
  schema-name
  schema-version
  persistence
  fields
  content-hash
  (provenance '()))

(defun canonical-escape-string (string)
  (with-output-to-string (stream)
    (write-char #\" stream)
    (loop for character across string
          do (case character
               (#\\ (write-string "\\\\" stream))
               (#\" (write-string "\\\"" stream))
               (#\Newline (write-string "\\n" stream))
               (#\Return (write-string "\\r" stream))
               (#\Tab (write-string "\\t" stream))
               (otherwise (write-char character stream))))
    (write-char #\" stream)))

(defun canonical-value (value)
  (cond
    ((null value) "nil")
    ((eq value t) "true")
    ((stringp value) (canonical-escape-string value))
    ((integerp value) (format nil "~D" value))
    ((keywordp value) (format nil ":~A" (string-downcase (symbol-name value))))
    ((source-symbol-p value)
     (format nil "~:[~;:~]~A"
             (source-symbol-keyword-p value)
             (source-symbol-name value)))
    ((core-document-p value)
     (format nil "(document ~A ~D ~A ~A)"
             (core-document-schema-name value)
             (core-document-schema-version value)
             (canonical-value (core-document-persistence value))
             (canonical-value (core-document-fields value))))
    ((syntax-object-p value)
     (canonical-value (syntax-object-datum value)))
    ((consp value)
     (format nil "(~{~A~^ ~})" (mapcar #'canonical-value value)))
    ((symbolp value) (string-downcase (symbol-name value)))
    (t (fail 'execution-error :uncanonicalizable-value nil
             "Cannot canonicalize value of type ~S." (type-of value)))))

(defun email-address-p (value)
  (and (stringp value)
       (let ((at (position #\@ value)))
         (and at (> at 0) (< at (1- (length value)))
              (position #\. value :start (1+ at))))))

(defun value-type-valid-p (type value)
  (cond
    ((eq type :string) (stringp value))
    ((eq type :boolean) (or (eq value t) (null value)))
    ((eq type :integer) (integerp value))
    ((eq type :number) (numberp value))
    ((eq type :symbol) (symbolp value))
    ((eq type :email) (email-address-p value))
    ((eq type :document) (core-document-p value))
    ((eq type :any) t)
    ((and (consp type) (eq (first type) :list))
     (and (listp value)
          (every (lambda (item) (value-type-valid-p (second type) item)) value)))
    (t nil)))

(defun make-core-document (registry schema-name fields &key (provenance '()))
  (let* ((schema (require-schema registry schema-name nil))
         (normalized-fields
           (sort (copy-list fields) #'string<
                 :key (lambda (entry) (normalize-name (first entry))))))
    (dolist (field (schema-definition-fields schema))
      (destructuring-bind (field-name field-type required-p) field
        (declare (ignore field-type))
        (when (and required-p
                   (null (assoc field-name normalized-fields :test #'equal)))
          (fail 'schema-error :missing-field nil
                "Schema ~A requires field ~A."
                (schema-definition-name schema) field-name))))
    (dolist (entry normalized-fields)
      (let ((definition
              (assoc (normalize-name (first entry))
                     (schema-definition-fields schema)
                     :test #'equal
                     :key (lambda (field) (normalize-name (first field))))))
        (unless definition
          (fail 'schema-error :unknown-field nil
                "Schema ~A does not define field ~A."
                (schema-definition-name schema) (first entry)))
        (unless (value-type-valid-p (second definition) (second entry))
          (fail 'schema-error :invalid-field-type nil
                "Field ~A on schema ~A does not satisfy type ~S."
                (first entry) (schema-definition-name schema) (second definition)))))
    (let* ((content-hash
             (sha256-string
              (format nil "(~A ~D ~A ~A)"
                      (schema-definition-name schema)
                      (schema-definition-version schema)
                      (canonical-value (schema-definition-persistence schema))
                      (canonical-value normalized-fields))))
           (identifier (subseq content-hash 0 24)))
      (%make-core-document
       :id identifier
       :schema-name (schema-definition-name schema)
       :schema-version (schema-definition-version schema)
       :persistence (schema-definition-persistence schema)
       :fields normalized-fields
       :content-hash content-hash
       :provenance provenance))))

(defun document-field (document field-name)
  (let ((entry (assoc (normalize-name field-name)
                      (core-document-fields document)
                      :test #'equal
                      :key (lambda (candidate) (normalize-name (first candidate))))))
    (unless entry
      (fail 'schema-error :missing-field nil
            "Document ~A has no field ~A." (core-document-id document) field-name))
    (second entry)))

(defun syntax-list (syntax)
  (unless (and (syntax-object-p syntax) (listp (syntax-object-datum syntax)))
    (fail 'compile-error :expected-list (and (syntax-object-p syntax) (syntax-object-span syntax))
          "Expected a list."))
  (syntax-object-datum syntax))

(defun syntax-name (syntax)
  (let ((datum (syntax-object-datum syntax)))
    (unless (source-symbol-p datum)
      (fail 'compile-error :expected-symbol (syntax-object-span syntax)
            "Expected a symbol."))
    (source-symbol-name datum)))

(defun syntax-keyword-name (syntax)
  (let ((datum (syntax-object-datum syntax)))
    (unless (and (source-symbol-p datum) (source-symbol-keyword-p datum))
      (fail 'compile-error :expected-keyword (syntax-object-span syntax)
            "Expected a keyword."))
    (source-symbol-name datum)))

(defun syntax-integer (syntax)
  (let ((datum (syntax-object-datum syntax)))
    (unless (integerp datum)
      (fail 'compile-error :expected-integer (syntax-object-span syntax)
            "Expected an integer."))
    datum))

(defun form-name (syntax)
  (let ((items (syntax-list syntax)))
    (when items (syntax-name (first items)))))

(defstruct plan-node
  id
  operation
  arguments
  effects
  capabilities
  source-span
  (origin-chain '()))

(defstruct analysis-plan
  name
  version
  source-hash
  hash
  effects
  nodes
  source-map)

(defun stable-node-id (analysis-name index operation arguments)
  (subseq
   (sha256-string
    (format nil "(~A ~D ~A ~A)"
            analysis-name index operation (canonical-value arguments)))
   0 24))

(defun syntax-keyword-list (syntax)
  (mapcar #'syntax-keyword-name (syntax-list syntax)))

(defun compile-stage (syntax registry allowed-effects analysis-name index)
  (let* ((items (syntax-list syntax))
         (name (and items (syntax-name (first items))))
         (span (syntax-object-span syntax)))
    (labels ((node (operation arguments effects capabilities)
               (dolist (effect effects)
                 (unless (member effect allowed-effects :test #'string=)
                   (fail 'compile-error :undeclared-effect span
                         "Stage ~A requires undeclared effect :~A." name effect)))
               (make-plan-node
                :id (stable-node-id analysis-name index operation arguments)
                :operation operation
                :arguments arguments
                :effects effects
                :capabilities capabilities
                :source-span span)))
      (cond
        ((string= name "from")
         (unless (= (length items) 2)
           (fail 'compile-error :invalid-from span "FROM expects one schema."))
         (let ((schema-name (syntax-name (second items))))
           (require-schema registry schema-name span)
           (node :from (list :schema schema-name) '() '())))
        ((member name '("filter" "map" "flat-map") :test #'string=)
         (unless (= (length items) 2)
           (fail 'compile-error :invalid-pure-stage span
                 "~A expects one capability." name))
         (let* ((capability-name (syntax-name (second items)))
                (capability (require-capability registry capability-name span)))
           (unless (eq (capability-definition-kind capability) :pure)
             (fail 'compile-error :wrong-capability-kind span
                   "Capability ~A is not pure." capability-name))
           (node (intern (string-upcase name) :keyword)
                 (list :capability capability-name)
                 '()
                 (list capability-name))))
        ((string= name "through")
         (unless (= (length items) 2)
           (fail 'compile-error :invalid-through span "THROUGH expects one capability."))
         (let* ((capability-name (syntax-name (second items)))
                (capability (require-capability registry capability-name span))
                (kind (capability-definition-kind capability))
                (effect (ecase kind (:actor "actor") (:agent "agent"))))
           (node :through
                 (list :capability capability-name :kind kind)
                 (list effect)
                 (list capability-name))))
        ((string= name "parallel")
         (unless (= (length items) 3)
           (fail 'compile-error :invalid-parallel span
                 "PARALLEL expects a positive limit and one nested stage."))
         (let ((limit (syntax-integer (second items))))
           (unless (> limit 0)
             (fail 'compile-error :invalid-parallel-limit span
                   "Parallel limit must be positive."))
           (let ((nested (compile-stage (third items) registry allowed-effects
                                        analysis-name (+ index 1000000))))
             (unless (eq (plan-node-operation nested) :through)
               (fail 'compile-error :invalid-parallel-stage span
                     "PARALLEL currently accepts one THROUGH stage."))
             (node :parallel
                   (list :limit limit :stage nested)
                   (plan-node-effects nested)
                   (plan-node-capabilities nested)))))
        ((string= name "checkpoint")
         (unless (= (length items) 2)
           (fail 'compile-error :invalid-checkpoint span
                 "CHECKPOINT expects one name."))
         (node :checkpoint (list :name (syntax-name (second items))) '() '()))
        ((string= name "into")
         (unless (= (length items) 2)
           (fail 'compile-error :invalid-into span "INTO expects one sink."))
         (let ((sink (syntax-name (second items))))
           (unless (string= sink "persist")
             (fail 'compile-error :unknown-sink span "Unknown sink ~A." sink))
           (node :into (list :sink :persist) (list "persist") '())))
        ((string= name "branch")
         (unless (= (length items) 4)
           (fail 'compile-error :invalid-branch span
                 "BRANCH expects a predicate, THEN block, and ELSE block."))
         (let* ((predicate-name (syntax-name (second items)))
                (predicate (require-capability registry predicate-name span))
                (then-form (third items))
                (else-form (fourth items)))
           (unless (eq (capability-definition-kind predicate) :pure)
             (fail 'compile-error :wrong-capability-kind span
                   "Branch predicate ~A is not pure." predicate-name))
           (unless (string= (form-name then-form) "then")
             (fail 'compile-error :invalid-branch span "Expected THEN block."))
           (unless (string= (form-name else-form) "else")
             (fail 'compile-error :invalid-branch span "Expected ELSE block."))
           (let ((then-nodes
                   (loop for child in (rest (syntax-list then-form))
                         for child-index from 0
                         collect (compile-stage child registry allowed-effects
                                                analysis-name (+ (* index 1000) child-index 1))))
                 (else-nodes
                   (loop for child in (rest (syntax-list else-form))
                         for child-index from 0
                         collect (compile-stage child registry allowed-effects
                                                analysis-name (+ (* index 1000) child-index 501)))))
             (node :branch
                   (list :predicate predicate-name
                         :then then-nodes
                         :else else-nodes)
                   (remove-duplicates
                    (append (mapcan (lambda (child) (copy-list (plan-node-effects child))) then-nodes)
                            (mapcan (lambda (child) (copy-list (plan-node-effects child))) else-nodes))
                    :test #'string=)
                   (remove-duplicates
                    (append (list predicate-name)
                            (mapcan (lambda (child) (copy-list (plan-node-capabilities child))) then-nodes)
                            (mapcan (lambda (child) (copy-list (plan-node-capabilities child))) else-nodes))
                    :test #'string=)))))
        (t
         (fail 'compile-error :unknown-stage span "Unknown stage ~A." name))))))

(defun plan-node-canonical (node)
  (list
   (plan-node-id node)
   (plan-node-operation node)
   (let ((arguments (plan-node-arguments node)))
     (if (eq (plan-node-operation node) :parallel)
         (list :limit (getf arguments :limit)
               :stage (plan-node-canonical (getf arguments :stage)))
         (if (eq (plan-node-operation node) :branch)
             (list :predicate (getf arguments :predicate)
                   :then (mapcar #'plan-node-canonical (getf arguments :then))
                   :else (mapcar #'plan-node-canonical (getf arguments :else)))
             arguments)))
   (plan-node-effects node)
   (plan-node-capabilities node)))

(defun compile-source (source registry &key (source-name "<string>"))
  (let* ((syntax (parse-source source :source-name source-name))
         (items (syntax-list syntax)))
    (unless (and (>= (length items) 4)
                 (string= (syntax-name (first items)) "analysis"))
      (fail 'compile-error :expected-analysis (syntax-object-span syntax)
            "Top-level form must be ANALYSIS."))
    (let* ((analysis-name (syntax-name (second items)))
           (version-form (third items))
           (effects-form (fourth items)))
      (unless (string= (form-name version-form) "version")
        (fail 'compile-error :expected-version (syntax-object-span version-form)
              "Third form must be (:VERSION integer)."))
      (unless (string= (form-name effects-form) "effects")
        (fail 'compile-error :expected-effects (syntax-object-span effects-form)
              "Fourth form must be (:EFFECTS (...))."))
      (let* ((version-items (syntax-list version-form))
             (effects-items (syntax-list effects-form))
             (version (syntax-integer (second version-items)))
             (effects (syntax-keyword-list (second effects-items)))
             (body-forms (subseq items 4))
             (stages
               (if (and (= (length body-forms) 1)
                        (string= (form-name (first body-forms)) "sequence"))
                   (rest (syntax-list (first body-forms)))
                   body-forms))
             (nodes
               (loop for stage in stages
                     for index from 0
                     collect (compile-stage stage registry effects analysis-name index)))
             (source-hash (sha256-string source))
             (plan-data
               (list analysis-name version source-hash effects
                     (mapcar #'plan-node-canonical nodes)))
             (plan-hash (sha256-string (canonical-value plan-data))))
        (make-analysis-plan
         :name analysis-name
         :version version
         :source-hash source-hash
         :hash plan-hash
         :effects effects
         :nodes nodes
         :source-map (mapcar (lambda (node)
                               (list (plan-node-id node) (plan-node-source-span node)))
                             nodes))))))

(defstruct run-event
  sequence
  type
  run-id
  plan-hash
  node-id
  payload)

(defstruct (core-runtime (:constructor %make-core-runtime))
  registry
  (events '())
  (persisted '())
  (dispatch-count 0)
  replay-results
  current-capability)

(defun make-core-runtime (registry &key history)
  (let ((results (make-hash-table :test #'equal)))
    (dolist (event history)
      (when (eq (run-event-type event) :command-result)
        (setf (gethash (getf (run-event-payload event) :command-id) results)
              (getf (run-event-payload event) :result))))
    (%make-core-runtime :registry registry :replay-results results)))

(defun runtime-events (runtime)
  (reverse (copy-list (core-runtime-events runtime))))

(defun runtime-persisted (runtime)
  (reverse (copy-list (core-runtime-persisted runtime))))

(defun runtime-dispatch-count (runtime)
  (core-runtime-dispatch-count runtime))

(defun record-run-event (runtime type run-id plan node-id payload)
  (let ((event
          (make-run-event
           :sequence (1+ (length (core-runtime-events runtime)))
           :type type
           :run-id run-id
           :plan-hash (analysis-plan-hash plan)
           :node-id node-id
           :payload payload)))
    (push event (core-runtime-events runtime))
    event))

(defun event-signature (event)
  (list (run-event-sequence event)
        (run-event-type event)
        (run-event-run-id event)
        (run-event-plan-hash event)
        (run-event-node-id event)
        (canonical-value (run-event-payload event))))

(defun call-tool (runtime tool-name input)
  (let* ((registry (core-runtime-registry runtime))
         (agent (core-runtime-current-capability runtime))
         (tool (require-capability registry tool-name nil)))
    (unless (and agent (eq (capability-definition-kind agent) :agent))
      (fail 'capability-error :tool-outside-agent nil
            "Tool ~A was called outside an agent." tool-name))
    (unless (member (normalize-name tool-name)
                    (capability-definition-allowed-tools agent)
                    :test #'equal)
      (fail 'capability-error :undeclared-tool nil
            "Agent ~A did not declare tool ~A."
            (capability-definition-name agent) tool-name))
    (unless (eq (capability-definition-kind tool) :tool)
      (fail 'capability-error :wrong-capability-kind nil
            "Capability ~A is not a tool." tool-name))
    (funcall (capability-definition-function tool) input runtime)))

(defun command-id (run-id plan node input)
  (sha256-string
   (format nil "(~A ~A ~A ~A)"
           run-id
           (analysis-plan-hash plan)
           (plan-node-id node)
           (canonical-value input))))

(defun invoke-effect-capability (runtime capability input run-id plan node mode)
  (let* ((identifier (command-id run-id plan node input))
         (recorded (gethash identifier (core-runtime-replay-results runtime))))
    (record-run-event runtime :command-created run-id plan (plan-node-id node)
                      (list :command-id identifier
                            :capability (capability-definition-name capability)
                            :input-hash (sha256-string (canonical-value input))))
    (cond
      ((eq mode :replay)
       (unless recorded
         (fail 'replay-error :missing-command-result (plan-node-source-span node)
               "Replay has no result for command ~A." identifier))
       (record-run-event runtime :command-result run-id plan (plan-node-id node)
                         (list :command-id identifier :result recorded :replayed t))
       recorded)
      (t
       (incf (core-runtime-dispatch-count runtime))
       (let ((previous (core-runtime-current-capability runtime)))
         (unwind-protect
              (progn
                (setf (core-runtime-current-capability runtime) capability)
                (let ((result
                        (funcall (capability-definition-function capability)
                                 input runtime)))
                  (record-run-event runtime :command-result run-id plan (plan-node-id node)
                                    (list :command-id identifier :result result :replayed nil))
                  result))
           (setf (core-runtime-current-capability runtime) previous)))))))

(defun execute-node-list (runtime plan nodes documents run-id mode)
  (dolist (node nodes documents)
    (setf documents (execute-node runtime plan node documents run-id mode))))

(defun execute-node (runtime plan node documents run-id mode)
  (let* ((registry (core-runtime-registry runtime))
         (arguments (plan-node-arguments node))
         (node-id (plan-node-id node)))
    (record-run-event runtime :node-started run-id plan node-id
                      (list :operation (plan-node-operation node)
                            :input-count (length documents)))
    (let ((result
            (case (plan-node-operation node)
              (:from
               (let ((schema-name (getf arguments :schema)))
                 (dolist (document documents)
                   (unless (string= (core-document-schema-name document) schema-name)
                     (fail 'execution-error :input-schema-mismatch
                           (plan-node-source-span node)
                           "Expected schema ~A, received ~A."
                           schema-name (core-document-schema-name document))))
                 documents))
              (:filter
               (let* ((name (getf arguments :capability))
                      (capability (require-capability registry name (plan-node-source-span node))))
                 (remove-if-not
                  (lambda (document)
                    (funcall (capability-definition-function capability) document runtime))
                  documents)))
              (:map
               (let* ((name (getf arguments :capability))
                      (capability (require-capability registry name (plan-node-source-span node))))
                 (mapcar (lambda (document)
                           (funcall (capability-definition-function capability) document runtime))
                         documents)))
              (:flat-map
               (let* ((name (getf arguments :capability))
                      (capability (require-capability registry name (plan-node-source-span node))))
                 (mapcan
                  (lambda (document)
                    (copy-list
                     (funcall (capability-definition-function capability) document runtime)))
                  documents)))
              (:through
               (let* ((name (getf arguments :capability))
                      (capability (require-capability registry name (plan-node-source-span node))))
                 (ecase (getf arguments :kind)
                   (:actor
                    (mapcar (lambda (document)
                              (invoke-effect-capability runtime capability document
                                                        run-id plan node mode))
                            documents))
                   (:agent
                    (list (invoke-effect-capability runtime capability documents
                                                    run-id plan node mode))))))
              (:parallel
               (record-run-event runtime :parallel-opened run-id plan node-id
                                 (list :limit (getf arguments :limit)))
               (let ((nested (getf arguments :stage)))
                 (execute-node runtime plan nested documents run-id mode)))
              (:checkpoint
               (record-run-event runtime :checkpoint-written run-id plan node-id
                                 (list :name (getf arguments :name)
                                       :document-hashes
                                       (mapcar #'core-document-content-hash documents)))
               documents)
              (:branch
               (let* ((predicate
                        (require-capability registry (getf arguments :predicate)
                                            (plan-node-source-span node)))
                      (selected
                        (if (and documents
                                 (funcall (capability-definition-function predicate)
                                          (first documents) runtime))
                            (getf arguments :then)
                            (getf arguments :else))))
                 (record-run-event runtime :branch-selected run-id plan node-id
                                   (list :branch (if (eq selected (getf arguments :then))
                                                     :then :else)))
                 (execute-node-list runtime plan selected documents run-id mode)))
              (:into
               (ecase (getf arguments :sink)
                 (:persist
                  (dolist (document documents)
                    (unless (eq (core-document-persistence document) :persistent)
                      (fail 'transient-persistence-denied
                            :transient-persistence-denied
                            (plan-node-source-span node)
                            "Document ~A with schema ~A is transient."
                            (core-document-id document)
                            (core-document-schema-name document)))
                    (push document (core-runtime-persisted runtime)))
                  documents)))
              (otherwise
               (fail 'execution-error :unknown-plan-operation
                     (plan-node-source-span node)
                     "Unknown plan operation ~S." (plan-node-operation node))))))
      (record-run-event runtime :node-completed run-id plan node-id
                        (list :output-count (length result)
                              :output-hashes
                              (mapcar #'core-document-content-hash result)))
      result)))

(defun run-plan (plan registry inputs &key (run-id "run-0001") history (mode :live))
  (unless (member mode '(:live :replay))
    (fail 'execution-error :invalid-run-mode nil "Unknown run mode ~S." mode))
  (let ((runtime (make-core-runtime registry :history history)))
    (record-run-event runtime :run-created run-id plan nil
                      (list :analysis (analysis-plan-name plan)
                            :version (analysis-plan-version plan)))
    (record-run-event runtime :run-started run-id plan nil nil)
    (let ((outputs
            (execute-node-list runtime plan (analysis-plan-nodes plan)
                               inputs run-id mode)))
      (record-run-event runtime :run-completed run-id plan nil
                        (list :output-count (length outputs)
                              :output-hashes
                              (mapcar #'core-document-content-hash outputs)))
      (values outputs runtime))))

(defun make-example-registry (domains actor-results)
  (let ((registry (make-core-registry)))
    (register-schema registry "user" 1 :persistent
                     '(("username" :string t)))
    (register-schema registry "target" 1 :persistent
                     '(("enumeration" :boolean t)
                       ("user" :document t)))
    (register-schema registry "email-candidate" 1 :transient
                     '(("username" :string t)
                       ("email" :email t)))
    (register-schema registry "tested-email-candidate" 1 :transient
                     '(("username" :string t)
                       ("email" :email t)
                       ("status" :symbol t)))
    (register-schema registry "final-review" 1 :persistent
                     '(("username" :string t)
                       ("found-emails" (:list :email) t)
                       ("decision" :symbol t)))
    (register-capability
     registry "enumeration-target-p" :pure "target" nil '()
     (lambda (target runtime)
       (declare (ignore runtime))
       (eq (document-field target "enumeration") t)))
    (register-capability
     registry "generate-email-candidates" :pure "target" "email-candidate" '()
     (lambda (target runtime)
       (let ((username (document-field (document-field target "user") "username")))
         (mapcar
          (lambda (domain)
            (make-core-document
             (core-runtime-registry runtime)
             "email-candidate"
             (list (list "username" username)
                   (list "email" (format nil "~A@~A" username domain)))
             :provenance (list (core-document-id target))))
          domains))))
    (register-capability
     registry "found-candidate-p" :pure "tested-email-candidate" nil '()
     (lambda (candidate runtime)
       (declare (ignore runtime))
       (eq (document-field candidate "status") :found)))
    (register-capability
     registry "never-p" :pure "target" nil '()
     (lambda (document runtime)
       (declare (ignore document runtime))
       nil))
    (register-capability
     registry "email-testing-actor" :actor "email-candidate" "tested-email-candidate"
     '("actor")
     (lambda (candidate runtime)
       (let* ((email (document-field candidate "email"))
              (status (or (cdr (assoc email actor-results :test #'string=)) :unknown)))
         (make-core-document
          (core-runtime-registry runtime)
          "tested-email-candidate"
          (list (list "username" (document-field candidate "username"))
                (list "email" email)
                (list "status" status))
          :provenance (list (core-document-id candidate))))))
    (register-capability
     registry "candidate-summary" :tool nil nil '()
     (lambda (candidates runtime)
       (declare (ignore runtime))
       (mapcar (lambda (candidate) (document-field candidate "email")) candidates)))
    (register-capability
     registry "review-agent" :agent nil "final-review" '("agent")
     (lambda (candidates runtime)
       (let* ((emails (call-tool runtime "candidate-summary" candidates))
              (username (if candidates
                            (document-field (first candidates) "username")
                            "unknown")))
         (make-core-document
          (core-runtime-registry runtime)
          "final-review"
          (list (list "username" username)
                (list "found-emails" emails)
                (list "decision" :review-required))
          :provenance (mapcar #'core-document-id candidates))))
     :allowed-tools '("candidate-summary"))
    registry))
