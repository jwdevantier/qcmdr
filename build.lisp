(ql:quickload "deploy")
(push :deploy-console *features*)

;; load qcmdr from local directory
(push *default-pathname-defaults* asdf:*central-registry*)
(load "qcmdr.asd")

(let ((compression-lib (uiop:getenv "DPL_COMPRESSION_LIB")))
  ; deploy will use compression if the lisp implementation supports it.
  ; For SBCL, that's either libzlib (for SBCL <= 2.2.5) or libzstd
  (format t "instructing deploy to look for compression-lib at: ~a~&" compression-lib)
  (deploy:define-library deploy::compression-lib
    :path compression-lib))

(ql:quickload "qcmdr")
;; create binary directory (bin)
(asdf:make "qcmdr")
