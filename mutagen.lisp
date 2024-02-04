(in-package #:qcmdr.mutagen)

(defclass context ()
  ((data-dir :initform (error "must provide a data directory")
             :initarg :data-dir
             :reader context-data-dir)))

(defmethod print-object ((self context) stream)
  (print-unreadable-object (self stream :type t)
    (with-slots (data-dir) self
        (format stream "data dir: ~s" data-dir))))

(defun mutagen-ssh-bindir-fpath (ctx)
  (path-join (context-data-dir ctx) ".mutagen-bins/"))

(defmethod initialize-instance :after ((self context) &key (ssh-bin-fpath nil) (scp-bin-fpath nil))
  (let ((ssh-bin-fpath (or ssh-bin-fpath (which-exe "ssh")))
        (scp-bin-fpath (or scp-bin-fpath (which-exe "scp")))
        (mutagen-bin-dir (mutagen-ssh-bindir-fpath self)))
    (ensure-directories-exist mutagen-bin-dir)
    (cmd:cmd "ln" "-sf" ssh-bin-fpath (path-join mutagen-bin-dir "ssh"))
    (cmd:cmd "ln" "-sf" scp-bin-fpath (path-join mutagen-bin-dir "scp"))))

(defun version ()
  "return (major minor patch) version information from mutagen"
  (multiple-value-bind (out retcode)
      (cmd:$cmd "mutagen version")
    (when (= 0 retcode)
      (ppcre:register-groups-bind
          ((#'parse-integer major minor patch))
          ("(\\d+)\.(\\d+)\.(\\d+)" out)
        (list :major major :minor minor :patch patch)))))

(defmacro with-env ((ctx) &body body)
  `(let ((cmd:*cmd-env* (->> cmd:*cmd-env*
                             (acons "MUTAGEN_DATA_DIRECTORY" (context-data-dir ,ctx))
                             (acons "MUTAGEN_SSH_PATH" (mutagen-ssh-bindir-fpath ,ctx)))))
     ,@body))


(defmethod sync-list ((self context) &optional label)
  "list synchronization sessions."
  (with-env (self)
    (-> (list "mutagen" "sync" "list" '("--template={{ json . }}"))
        (append (when label (list "--label-selector" label)))
        cmd:$cmd
        jzon:parse)))

;; TODO: can take multiple labels in a comma-separated list (e.g. "funny,ideal")
;; TODO: for general use permit just a list of flags
(defmethod sync-create ((self context)
                        &key name label source sink (flags nil)
                          (mode "one-way-replica"))
  "create a new synchronization.

  NOTE: flags can be a list of string flags to add, see `mutagen sync create -h` for inspiration."
  (with-env (self)
    (-> (list "mutagen" "sync" "create" "-n" name
              "-m" mode )
        (append (when label (list "--label" label)))
        (append flags)
        (append (list (format nil "~a" source)
                      (format nil "~a" sink)))
        cmd:$cmd)))

(defmethod sync-flush-session ((self context) session)
  "sync specific session"
  (with-env (self)
    (cmd:$cmd "mutagen" "sync" "flush" session)))

(defmethod sync-flush ((self context) &key label)
  "sync all or sessions with label."
  (with-env (self)
    (-> (list "mutagen" "sync" "flush")
        (append (if label (list "--label-selector" label)
                    (list "-a")))
        (cmd:$cmd))))


(defmethod sync-pause-session ((self context) session)
  "pause specific session"
  (with-env (self)
    (cmd:$cmd "mutagen" "sync" "pause" session)))

(defmethod sync-pause ((self context) &key label)
  "sync all or sessions with label."
  (with-env (self)
    (-> (list "mutagen" "sync" "pause")
        (append (if label (list "--label-selector" label)
                    (list "-a")))
        (cmd:$cmd))))

(defmethod sync-resume-session ((self context) session)
  "resume specific session"
  (with-env (self)
    (cmd:$cmd "mutagen" "sync" "resume" session)))

(defmethod sync-resume ((self context) &key label)
  "resume all or sessions with label."
  (with-env (self)
    (-> (list "mutagen" "sync" "resume")
      (append (if label (list "--label-selector" label)
                  (list "-a")))
      (cmd:$cmd))))

(defmethod sync-reset-session ((self context) session)
  "reset specific session"
  (with-env (self)
    (cmd:$cmd "mutagen" "sync" "reset" session)))

(defmethod sync-reset ((self context) &key label)
  "reset all or sessions with label."
  (with-env (self)
    (-> (list "mutagen" "sync" "reset")
      (append (if label (list "--label-selector" label)
                  (list "-a")))
      (cmd:$cmd))))

(defmethod sync-terminate-session ((self context) session)
  "terminate specific session"
  (with-env (self)
    (cmd:$cmd "mutagen" "sync" "terminate" session)))

(defmethod sync-terminate ((self context) &key label)
  "terminate all or sessions with label."
  (with-env (self)
    (-> (list "mutagen" "sync" "terminate")
      (append (if label (list "--label-selector" label)
                  (list "-a")))
      (cmd:$cmd))))
