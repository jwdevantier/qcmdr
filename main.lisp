;;;; main.lisp

(in-package #:qcmdr)

(defun ssh (ctx vm-name &rest cmd)
  (apply #'cmd:$cmd "ssh" "-F" (ctx-ssh-conf-fpath ctx) vm-name cmd))

(defun ssh-test-connection (ctx vm-name &key (timeout 5))
  (let ((timeout-arg (format nil "ConnectTimeout=~a" timeout)))
    (handler-case
        (progn (funcall #'cmd:$cmd "ssh" "-F" (ctx-ssh-conf-fpath ctx) "-o" "BatchMode=yes" "-o" timeout-arg vm-name "true")
               (values t nil))
      (cmd:cmd-error (c)
        (values nil c)))))

(define-condition program-missing (error)
  ((program-name :initarg :program-name
                 :initform nil
                 :reader program-name))
  (:documentation "this error is signalled when a required external program is not found on the system"))

(defun -init-context* (&key data-dir cli-cmd config-fpath vm-name)
  (confread:make-context :data-dir data-dir
                         :config-fpath config-fpath
                         :cmd cli-cmd
                         :vm-name vm-name))

(defun -init-context (cli-cmd cmd)
  (when (not (which-exe "ssh"))
    (error 'program-missing :program-name "ssh"))
  (when (not (which-exe "mutagen"))
    (error 'program-missing :program-name "mutagen"))
  (let ((ver (mutagen:version)))
    (when (and (= (getf ver :major) 0)
               (< (getf ver :minor) 15))
      (error "copy of mutagen is too old, expects 0.15 or later, got ~a.~a.~a~&"
             (getf ver :major)
             (getf ver :minor)
             (getf ver :patch))))
  (let* ((config-fpath (path-join *default-pathname-defaults*
                                  (cli:getopt cmd :config)))
         (data-dir (merge-pathnames (pathname (format nil "~a.data/" (pathname-name config-fpath)))
                                    (path-parent config-fpath)))
         (vm-name (cli:getopt cmd :vm)))
    (-init-context* :data-dir data-dir
                    :cli-cmd cli-cmd
                    :config-fpath config-fpath
                    :vm-name vm-name)
    ;; TODO: to the extent possible
    ;; 1) validate general config
    ;; 2) validate VM config in particular (does it exist, does it have required keys?)
    ))

(defun -cli/opts/vm (&key (required t))
  (cli:make-option
   :string
   :description "the VM to operate on"
   :long-name "vm"
   :key :vm
   :required required))

(defun pid-alive? (pid)
  "true iff pid marks a live process (required unix)"
  (handler-case (progn (cmd:cmd! "ps" "-p" pid) t)
    (cmd:cmd-error
      nil)))

(defun process-kill (pid)
  "kill process identified by PID iff alive"
  (when (pid-alive? pid)
    (cmd:cmd! "kill" pid)
    t))

(defun vm-pid (vm-conf)
  "get VM pid, if any"
  (let ((pid-fpath (probe-file (vm-pid-fpath vm-conf))))
    (when pid-fpath
      (ignore-errors (-> pid-fpath
                         uiop:read-file-string
                         parse-integer)))))

(defun vm-alive? (vm-conf)
  "true iff VM PID is used"
  (let ((pid (vm-pid vm-conf)))
    (when pid (pid-alive? pid))))

(define-condition vm-running-error (error)
  ((program-name :initarg :vm-name
                 :initform nil
                 :reader vm-name))
  (:documentation "this error is signalled when attempting to start an already running VM"))

(defun -wait-for-login (fr &key (retries 5) (sleep-secs 1) (print? t) (wait-str "login:"))
  (let ((current-retries retries))
    (loop (let ((string (reader-read fr)))
            (if string
                (progn (when (and print? (reader-fresh-line? fr))
                         (format t "~a~&" (reader-peekline fr)))
                       (setf current-retries retries)
                       (when (str:contains? wait-str (reader-peekline fr))
                         (return)))
                (progn (when (zerop (decf current-retries))
                         (return))
                       (sleep sleep-secs)
                       (reader-refresh fr)))))))

(defun -vm-start-sync (mctx vm-conf)
  "(re-)start synchronization sessions between HOST and VM."
  (let ((vm-name (vm-name vm-conf)))
    (mutagen:sync-terminate mctx :label vm-name)
    (loop :for sync :in (confread:vm-sync vm-conf)
          :do (mutagen:sync-create mctx
                                   :name (format nil "qcmdr-~a"
                                                 (sxhash (format nil "~a~a~a" vm-name (sync-source sync)
                                                                 (sync-dest sync))))
                                   :label vm-name
                                   :source (sync-source sync)
                                   ;; fmt string denoting endpoint and path (same format as for SCP)
                                   :sink (format nil "~a:~a" vm-name (sync-dest sync))
                                   ;; TODO: ignore and ignore-vcs, respect
                                   :flags (append (sync-flags sync)
                                                  (when (sync-ignore-vcs? sync)
                                                    (list "--ignore-vcs"))
                                                  (when (sync-ignore sync)
                                                    (list "-i" (str:join "," (sync-ignore sync)))))))))

(defun -vm-start (ctx vm-conf)
  "start QEMU VM if not already started"
  (when (vm-alive? vm-conf)
    (error 'vm-running-error :vm-name (vm-name vm-conf)))
  (let ((vm-launch-cmd (cons (qemu-bin-path (ctx-config ctx)
                                            vm-conf)
                             (vm-args vm-conf)))
        (serial-path (vm-serial-fpath vm-conf)))
    (format t "Starting QEMU:~&")
    (format t "~{~a~^ \~&  ~}~&" vm-launch-cmd)
    (when (probe-file serial-path)
      (delete-file serial-path))
    (apply #'cmd:cmd vm-launch-cmd)
    (format t "starting to listen on serial ~a~&" serial-path)
    (let ((fr (make-instance 'file-reader :fpath serial-path)))
      ;; TODO pass along arg if to boot silently
      (-wait-for-login fr)
      ;; ensures we can connect via SSH
      (ssh ctx (ctx-vm-name ctx) "true")
      (-vm-start-sync (confread:ctx-mutagen-ctx ctx) vm-conf)
      (format t "~&~%VM '~a' started.~&  To connect: ~a ~a~&"
              (vm-name vm-conf)
              (path-join (ctx-ssh-bin-fpath ctx))
              (vm-name vm-conf)))))

(defun cli/cmds/start/handler (cmd)
  "on start"
  (let* ((ctx (-init-context "start" cmd))
         (vm-conf (ctx-vm-get ctx)))
    (-vm-start ctx vm-conf)))

(defun cli/cmds/start ()
  "start a VM"
  (cli:make-command
   :name "start"
   :description "start a VM"
   :handler #'cli/cmds/start/handler
   :options (list (-cli/opts/vm))))

(defun -vm-stop (ctx vm-conf)
  "stop QEMU VM if alive"
  ;; TODO: should stop nicely unless instructed to be harsh
  (let ((pid (vm-pid vm-conf)))
    (when (and pid (pid-alive? pid))
      (handler-case
          (progn (mutagen:sync-terminate (confread:ctx-mutagen-ctx ctx) :label (vm-name vm-conf))
                 (ssh ctx (confread:vm-name vm-conf) "poweroff")
                 (format t "VM ~a shut down nicely" (vm-name vm-conf)))
        (cmd:cmd-error (c)
          (declare (ignore c))
          (progn (format t "SSH failed, killing VM ~a at PID ~a~&" (vm-name vm-conf) pid)
                 (process-kill pid)))))))

(defun cli/cmds/stop/handler (cmd)
  "when stopping a VM"
  (let* ((ctx (-init-context "stop" cmd))
         (vm-conf (ctx-vm-get ctx)))
    (-vm-stop ctx vm-conf)))

(defun cli/cmds/stop ()
  "stop a VM"
  (cli:make-command
   :name "stop"
   :description "stop a VM"
   :handler #'cli/cmds/stop/handler
   :options (list (-cli/opts/vm))))

(defun -vm-status (ctx vm-conf)
  "pretty-print"
  (with-accessors ((name vm-name)
                   (arch vm-arch)
                   (builder vm-builder)
                   (pid-fpath vm-pid-fpath)
                   (monitor-fpath vm-monitor-fpath)
                   (serial-fpath vm-monitor-fpath)) vm-conf
    (list "Host" name
          "Arch" arch
          "Builder" (or builder :none)
          "Monitor file" monitor-fpath
          "Pid file" pid-fpath
          "Serial file" serial-fpath
          "Status" (if (vm-alive? vm-conf)
                       (let ((pid (vm-pid vm-conf)))
                         (format nil "running (pid: ~a)" pid))
                       "stopped")
          "SSH" (if (vm-alive? vm-conf)
                    (if (ssh-test-connection ctx (vm-name vm-conf) :timeout 10)
                        "OK (success)"
                        "ERR (failed)")
                    "SKIPPED"))))

(defun -vm-status-all (ctx)
  (let ((vms (loop :for vm-conf :being :each :hash-value
                   :of (-> ctx ctx-config config-vms)
                   :collect vm-conf)))
    (pmap (lambda (vm-conf)
            (-vm-status ctx vm-conf)) vms)))

(defun cli/cmds/status/handler (cmd)
  "when inspecting the state of a VM (running/stopped/... sync)"
  (let* ((ctx (-init-context "status" cmd))
         (vm-name (ctx-vm-name ctx))
         (vm-status-data (if vm-name
                             (list (-vm-status ctx (ctx-vm-get vm-name)))
                             (-vm-status-all ctx))))
    (loop :for res :in vm-status-data
          :for host-name = (cadr res)
          :for details = (cddr res)
          :do (format t "Host ~a:~&~{  * ~a~17t ~a~&~}~&" host-name details))))

(defun cli/cmds/status ()
  "inspect status of VM and any file synchronization"
  (cli:make-command
   :name "status"
   :description "inspect state of VM process and file synchronization(s)"
   :handler #'cli/cmds/status/handler
   :options (list (-cli/opts/vm :required nil))))

(defun cli/cmds/build/handler (cmd)
  "when building the VM image"
  (declare (ignore cmd)) ;; TODO HACK -- implement fn
  (format t "building VM image...~&"))

(defun cli/cmds/build ()
  "build the VM image"
  (cli:make-command
   :name "build"
   :description "build the VM image"
   :handler #'cli/cmds/build/handler
   :options (list (-cli/opts/vm))))

(defun cli/toplvl/opts ()
  "options/flags for toplvl CLI"
  (list
   (cli:make-option
    :filepath
    :description "configuration file"
    :short-name #\c
    :long-name "config"
    :key :config
    :required nil
    :initial-value (uiop:native-namestring "qcmdr.lisp"))))

(defun cli/toplvl/cmd ()
  "top-level of CLI interface"
  (cli:make-command
   :name "qcmdr"
   :description "easily manage QEMU VMs"
   :version "0.0.1"
   :authors '("Jesper Wendel Devantier <jwd@defmacro.it>")
   :license "BSD 2-Clause"
   :options (cli/toplvl/opts)
   :handler (lambda (cmd)
              (cli:print-usage cmd t))
   :sub-commands (list (cli/cmds/start)
                       (cli/cmds/stop)
                       (cli/cmds/status)
                       (cli/cmds/build))))

(defun main (&rest argv)
  (declare (ignore argv))
  (cli:run (cli/toplvl/cmd)))
