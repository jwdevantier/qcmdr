(in-package #:qcmdr)

;; (defmacro when-let (bindings &body body)
;;   (let ((syms (mapcar #'first bindings)))
;;     `(let ,bindings
;;        (when (and ,@syms)
;;          ,@body))))

;; THINK
;; I suspect, from read-line's second return val, that it ALWAYS returns whatever output is there
;; and then a second value indicating if it's terminated by a NEWLINE, or just a partial line, so far.
;; -- successive fast calls would read fragments of the same line. So piece them together in a buf
;; -- until we get that val indicating a newline.
;; WHEN this happens, line is done, next partial/full line cycles the current line buffer
(defclass file-reader ()
    ((fpath :initarg :fpath
            :initform (error "must specify file path")
            :reader file-reader-fpath)
     (line-buf :initform (make-array 300
                                     :element-type 'extended-char
                                     :adjustable t
                                     :fill-pointer 0))
     (fresh-line? :initform t
                  :reader reader-fresh-line?)
     stream))

(defmethod initialize-instance :after ((obj file-reader) &key)
  (with-slots (fpath stream) obj
      (setf stream (open fpath
                         :element-type 'extended-char
                         :direction :input))))

(defmethod reader-peekline ((obj file-reader))
  "peek at current line as it is read into the buffer.
  The secondary value, newline?, is true iff. the primary value represents a complete line."
  (let ((line (slot-value obj 'line-buf)))
    (if (string-not-equal "" line)
        (values line (slot-value obj 'fresh-line?))
        (values nil nil))))

(defmethod reader-read ((obj file-reader))
  "read new content from underlying stream, returning nil if nothing new was available

  NOTE: use reader-peekline to get the entire line as it is now"
  (with-slots (stream fresh-line? line-buf) obj
    (when (null stream)
      (error "file-reader for ~a is already closed" (slot-value obj 'fpath)))
    (when (listen stream)
      (let ((fl? fresh-line?))
        (multiple-value-bind (str missing-nl?) (read-line stream)
          (when fl?
            (setf (fill-pointer line-buf) 0)
            (setf fresh-line? nil))
          (with-output-to-string (s line-buf :element-type 'extended-char)
            (format s str))
          (when (not missing-nl?)
            (setf fresh-line? t))
          str)))))

(defmethod reader-more? ((obj file-reader))
  (listen (slot-value obj 'stream)))

(defmethod reader-refresh ((obj file-reader))
  "hack - re-open the stream to see if there's new content..."
  (with-slots (stream fpath) obj
      (let ((fp (file-position stream)))
        (close stream)
        (setf stream (open fpath :element-type 'extended-char
                                 :direction :input))
        (file-position stream fp))))

(defmethod reader-close ((obj file-reader))
  (with-slots (stream) obj
    (close stream)
    (setf stream nil)))
