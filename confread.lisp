(in-package #:qcmdr.confread)

(defun kw->ssh-conf-key (kw)
  "transform a lispy keyword into the equivalent when capitalized as in ~/.ssh/config

  Example:
   * :hello-world  -> HelloWorld
   * :port         -> Port"
  (->> kw symbol-name
       (str:split "-")
       (mapcar #'str:capitalize)
       (str:join "")))

(defun load-conf (path)
  "load & eval conf file"
  (let ((pkg-name :qcmdr/conf))
    (when (find-package pkg-name)
      (delete-package pkg-name))
    (let ((tmp-pkg (make-package pkg-name :use (list :cl)))
          (current-pkg *package*))
      (unwind-protect
           (progn (setf *package* tmp-pkg)
                  (load path)
                  (let ((res (find-symbol "CONF" tmp-pkg)))
                    (when res
                      (symbol-value res))))
        (progn
               (setf *package* current-pkg))))))

(defclass sync ()
  ((source :initarg :source
           :initform (error "must provide :source")
           :reader sync-source)
   (dest :initarg :dest
         :initform (error "must provide :dest")
         :reader sync-dest)
   (ignore-vcs? :initarg :ignore-vcs?
                :initform t
                :reader sync-ignore-vcs?)
   (ignore :initarg :ignore
           :initform '()
           :reader sync-ignore)
   (flags :initarg :flags
          :initform '()
          :reader sync-flags)))

(defmethod print-object ((self sync) stream)
  (print-unreadable-object (self stream :type t)
    (with-slots (source dest) self
      (format stream "~s -> ~s" source dest))))

(defclass vm ()
  ((name :initarg :name
         :initform (error "must provide name")
         :reader vm-name)
   (arch :initarg :arch
         :initform (error "must provide :arch")
         :reader vm-arch)
   (builder :initarg :builder
            :initform :none
            :reader vm-builder)
   (ssh-conf :initarg :ssh-conf
             :initform '())
   (sync :initarg :sync
         :initform '()
         :reader vm-sync)
   (args :initarg :args
         :initform (error "must provide QEMU args for VM")
         :reader vm-args)
   (pid-fpath :initarg :pid-fpath
              :initform (error "must be set")
              :reader vm-pid-fpath)
   (monitor-fpath :initarg :monitor-fpath
                  :initform (error "must be set")
                  :reader vm-monitor-fpath)
   (serial-fpath :initarg :serial-fpath
                 :initform (error "must be set")
                 :reader vm-serial-fpath)))

(defun plist->ssh-conf-ht (plist)
  "create hash-table of ssh hosts config entries from given plist

  NOTE: transforms all keys from the form :one-two -> OneTwo
        (i.e. from a lispy keyword key to a Pascal-case string)"
  (when plist
    (let ((ht (make-hash-table :test #'equalp)))
      (loop :for (key value) :on plist :by #'cddr
            :for key* = (kw->ssh-conf-key key)
            :do (setf (gethash key* ht) value))
      ht)))

(defun make-vm-entry (data-dir &key name arch (builder :none) (ssh-conf nil) (sync nil) (args nil))
  (let ((pid-fpath (merge-pathnames data-dir (format nil "vm.~a.pid" name)))
        (monitor-fpath (merge-pathnames data-dir (format nil "vm.~a.monitor" name)))
        (serial-fpath (merge-pathnames data-dir (format nil "vm.~a.serial" name))))
    (make-instance 'vm
                   :name name
                   :arch arch
                   :builder builder
                   :ssh-conf (plist->ssh-conf-ht ssh-conf)
                   :sync (when sync
                           (loop :for (source sync-opts) :on sync :by #'cddr
                                 :collect (let ((sync-args (->> sync-opts (cons source) (cons :source))))
                                            (apply #'make-instance 'sync sync-args))))
                   :args (append args (list "-pidfile" pid-fpath
                                            "-monitor" (format nil "unix:~a,server,nowait" monitor-fpath)
                                            "-serial" (format nil "file:~a" serial-fpath)
                                            "-daemonize"))
                   :pid-fpath pid-fpath
                   :monitor-fpath monitor-fpath
                   :serial-fpath serial-fpath)))

(defmethod print-object ((self vm) stream)
  (print-unreadable-object (self stream :type t)
    (with-slots (name) self
      (format stream "name: ~s" name))))

;; config root object
(defclass config ()
  ((qemu-bin-dir :initarg :qemu-bin-dir
                 :initform (error "must specify directory of QEMU binaries"))
   (ssh-conf :initarg :ssh-conf
             :initform '())
   (vms :initarg :vms
        :initform (error "must provide a plist of vm configurations")
        :reader config-vms)))

(defun make-config (data-dir &key qemu-bin-dir (ssh-conf nil) vms)
  (make-instance 'config
                 :qemu-bin-dir qemu-bin-dir
                 :ssh-conf (plist->ssh-conf-ht ssh-conf)
                 :vms (let ((ht (make-hash-table :test #'equalp)))
                        (loop :for (vm-name vm-conf) :on vms :by #'cddr
                            :for vm-name-str = (str:downcase vm-name)
                            :do (setf (gethash vm-name-str ht)
                                      (apply #'make-vm-entry data-dir :name vm-name-str vm-conf)))
                        ht)))

(defun -ssh-hosts-entries (config ssh-control-fpath)
  "extracts SSH host entries from configuration.

  Returns a hash-table of <HOST: string> => <SSH Opts: hash-table> pairs."
  (let ((ht (ht-assoc (make-hash-table :test #'equalp)
                      "*" (ht-assoc (ht-merge (make-hash-table :test #'equalp)
                                    (slot-value config 'ssh-conf))
                                    ;; disable host-key checking - VM's change fingerprints often
                                    "StrictHostKeyChecking" "no"
                                    "UserKnownHostsFile" "/dev/null"
                                    ;; enable multiplexing, cache connections for 10m
                                    "ControlPath" (format nil "~a/%r@%h-%p" (probe-file ssh-control-fpath))
                                    "ControlMaster" "auto"
                                    "ControlPersist" "10m"
                                    )))
        (vms (slot-value config 'vms))
        (vm-ssh-conf-defaults (ht-assoc (make-hash-table :test #'equalp)
                                        ;; remember - already converted other keys
                                        "Hostname" "localhost"
                                        "User" "root")))
    (loop :for vm-entry :being :each :hash-value :of vms
          :using (hash-key host)
          :do (setf (gethash host ht) (ht-merge (make-hash-table :test #'equalp)
                                                vm-ssh-conf-defaults
                                                (slot-value vm-entry 'ssh-conf))))
    ht))

(defun write-ssh-config (stream entries)
  "write out a SSH hosts-style config."
  (loop :for vm-conf :being :each :hash-value :of entries
          :using (hash-key vm-name)
        :do (progn (format stream "~&Host ~a~&" vm-name)
                   (loop :for param-value :being :each :hash-value :of vm-conf
                           :using (hash-key param-key)
                         :do (format stream "   ~a ~a~&" param-key param-value))
                   (format stream "~%"))))

;; ROOT of all
(defclass context ()
  ((config :initarg :config
           :reader ctx-config
           :initform (error "must provide config"))
   (config-fpath :initarg :config-fpath
                 :initform (error "must provide :config-fpath")
                 :reader ctx-config-fpath)
   (data-dir :initarg :data-dir
             :initform (error "must specify a data directory")
             :reader ctx-data-dir)
   (mutagen-ctx :initarg :mutagen-ctx
                :initform (error "must provide mutagen context")
                :reader ctx-mutagen-ctx)
   (ssh-bin-fpath :initarg :ssh-bin-fpath
                  :initform (error "must specify where SSH binary resides")
                  :reader ctx-ssh-bin-fpath)
   (scp-bin-fpath :initarg :scp-bin-fpath
                  :initform (error "must specify where SCP binary resides")
                  :reader ctx-scp-bin-fpath)
   (ssh-conf-fpath :initarg :ssh-conf-fpath
                   :initform (error "must specify where SSH configuration is stored")
                   :reader ctx-ssh-conf-fpath)
   (cmd :initarg :cmd
        :initform (error "must provide :cmd")
        :reader ctx-cmd)
   (vm-name :initarg :vm-name
            :initform (error "must provide :vm-name")
            :reader ctx-vm-name)))

(defun ctx-vm-get (ctx &optional vm-name)
  "get configuration of specified VM.

  NOTE: if unspecified, reads the VM name from ctx"
  (-<> ctx
       (slot-value 'config)
       (slot-value 'vms)
       (gethash (or vm-name
                    (slot-value ctx 'vm-name))
                <>)))

(defmethod print-object ((self context) stream)
  (print-unreadable-object (self stream :type t)
    (with-slots (config-fpath) self
      (format stream "config-fpath: ~s" config-fpath))))

(defun make-context (&key data-dir config-fpath cmd vm-name)
  (let* ((raw-config (load-conf config-fpath))
         (config (apply #'make-config data-dir raw-config))
         (ssh-conf-fpath (path-join data-dir "ssh-conf"))
         (ssh-control-fpath (path-join data-dir ".ssh-control/"))
         (ssh-bin-fpath (path-join data-dir "ssh"))
         (scp-bin-fpath (path-join data-dir "scp")))
    (ensure-directories-exist data-dir)
    (ensure-directories-exist ssh-control-fpath)
    ; write out the SSH hosts configuration file
    (with-open-file (stream ssh-conf-fpath
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-ssh-config stream (-ssh-hosts-entries config ssh-control-fpath)))

    (write-file ssh-bin-fpath (format nil "#!/usr/bin/env sh
exec ~a -F ~a $*" (which-exe "ssh") ssh-conf-fpath))
    (cmd:$cmd "chmod" "+x" ssh-bin-fpath)
    (write-file scp-bin-fpath (format nil "#!/usr/bin/env sh
exec ~a -F ~a $*" (which-exe "scp") ssh-conf-fpath))
    (cmd:$cmd "chmod" "+x" scp-bin-fpath)
    ;; write mutagen wrapper, TODO: don't repeat the mutagen dir path here, call mutagen-ssh-bindir-fpath
    (let ((mutagen-bin-fpath (path-join data-dir "mutagen")))
      (write-file mutagen-bin-fpath (format nil "#!/usr/bin/env sh
export MUTAGEN_DATA_DIRECTORY=\"~a\"
export MUTAGEN_SSH_PATH=\"~a\"
exec ~a $*" data-dir (path-join data-dir ".mutagen-bins/") (which-exe "mutagen")))
      (cmd:$cmd "chmod" "+x" mutagen-bin-fpath))
    (make-instance 'context
                   :config config
                   :config-fpath config-fpath
                   :data-dir data-dir
                   :mutagen-ctx (make-instance 'mutagen:context
                                               :data-dir data-dir
                                               :ssh-bin-fpath ssh-bin-fpath
                                               :scp-bin-fpath scp-bin-fpath)
                   :ssh-bin-fpath ssh-bin-fpath
                   :scp-bin-fpath scp-bin-fpath
                   :ssh-conf-fpath ssh-conf-fpath
                   :cmd cmd
                   :vm-name vm-name)))

(defun qemu-bin-path (config vm)
  "construct path to QEMU binary relevant to VM"
  (let ((qemu-bin (path-join (slot-value config 'qemu-bin-dir)
                             (format nil "qemu-system-~a" (slot-value vm 'arch)))))
    (unless (probe-file qemu-bin)
      (error "failed to find qemu binary at ~a" qemu-bin))
    qemu-bin))
