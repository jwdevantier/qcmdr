;;;; qcmdr.asd

(asdf:defsystem #:qcmdr
  :description "tool for managing QEMU-based VM's"
  :author "Jesper Wendel Devantier <jwd@defmacro.it>"
  :license  "GPL-3.0-or-later"
  :version "0.0.1"
  :serial t
  :depends-on (#:clingon
               #:cmd
               #:str
               #:arrows
               #:cl-ppcre
               #:com.inuoe.jzon
               #:bordeaux-threads)
  :build-operation "deploy-op"
  :defsystem-depends-on (:deploy)
  :build-pathname "qcmdr"
  :entry-point "qcmdr:main"
  :components ((:file "package")
               (:file "utils")
               (:file "file-reader")
               (:file "mutagen")
               (:file "confread")
               (:file "main")))
