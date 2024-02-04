;;;; package.lisp

(defpackage #:qcmdr.utils
  (:use #:cl #:arrows)
  (:export :make-keyword
           :path-is-dir?
           :path-join
           :path-mkdirs
           :path-is-relative?
           :path-parent
           :path-absolute
           :write-file
           :which-exe
           :plist-dissoc-duplicates
           :plist-merge
           :plist-map-kv
           :plist-assoc
           :ht-assoc
           :ht-assoc*
           :ht-dissoc
           :ht-merge
           :pmap))

(defpackage #:qcmdr.mutagen
  (:use #:cl #:arrows #:qcmdr.utils)
  (:local-nicknames (#:cmd #:cmd/cmd)
                    (#:jzon #:com.inuoe.jzon))
  (:export :context
           :context-data-dir
           :version
           :with-env
           :sync-list
           :sync-create
           :sync-flush-session
           :sync-flush
           :sync-pause-session
           :sync-pause
           :sync-reset-session
           :sync-reset
           :sync-terminate-session
           :sync-terminate))

(defpackage #:qcmdr.confread
  (:use #:cl #:arrows #:qcmdr.utils)
  (:local-nicknames (#:mutagen #:qcmdr.mutagen))
  (:export :make-context
           :sync-source
           :sync-dest
           :sync-ignore-vcs?
           :sync-ignore
           :sync-flags
           :vm-name
           :vm-arch
           :vm-builder
           :vm-sync
           :vm-args
           :vm-pid-fpath
           :vm-monitor-fpath
           :vm-serial-fpath
           :config-vms
           :ctx-config
           :ctx-config-path
           :ctx-data-dir
           :ctx-mutagen-ctx
           :ctx-ssh-bin-fpath
           :ctx-scp-bin-fpath
           :ctx-ssh-conf-fpath
           :ctx-cmd
           :ctx-vm-name
           :ctx-vm-get
           :qemu-bin-path))

(defpackage #:qcmdr
  (:use #:cl #:arrows #:qcmdr.utils #:qcmdr.confread)
  (:local-nicknames (#:cmd #:cmd/cmd)
                    (#:cli #:clingon)
                    (#:jzon #:com.inuoe.jzon)
                    (#:mutagen #:qcmdr.mutagen)
                    (#:confread #:qcmdr.confread))
  (:export :main))
