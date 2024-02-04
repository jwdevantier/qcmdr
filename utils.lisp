(in-package #:qcmdr.utils)

(defun make-keyword (s)
  "create keyword from string"
  (values (intern (string-upcase s) "KEYWORD")))

(defun path-is-dir? (p)
  "true iff p is a directory"
  (let ((path (probe-file (uiop:native-namestring p))))
    (and path (uiop:directory-pathname-p path))))

(defun path-join (base &rest paths)
  (let ((*default-pathname-defaults* #P""))
    (reduce (lambda (dir path)
              (->> dir
                   uiop:ensure-directory-pathname
                   (merge-pathnames path)))
            paths
            :initial-value (uiop:native-namestring base))))

(defun path-mkdirs (dir)
  "create directory (and any missing parent directories)"
  (-> dir
      uiop:ensure-directory-pathname
      ensure-directories-exist))

(defun path-is-relative? (p)
  (let ((pd (pathname-directory (pathname p))))
    (or (null pd) (equalp :relative (first pd)))))

(defun path-absolute (p)
  "will resolve a relative path into an absolute one."
  (let ((*default-pathname-defaults* (make-pathname :directory (pathname-directory *default-pathname-defaults*))))
    (merge-pathnames p *default-pathname-defaults*)))

(defun path-parent (p)
  "get parent directory of `p` unless p is root, in which case return `p`."
  (let ((dir (pathname-directory p))
        ;; ensure we inherit no components from a default pathname
        (*default-pathname-defaults* #P""))
    (if (equal dir '(:absolute))
        p ;; parent of root is root
        (make-pathname :directory (if (pathname-name p)
                                      ;; ex: #P"/etc/passwd
                                      dir
                                      ;; ex: #P"/usr/bin/"
                                      (butlast dir))))))

(defun write-file (fpath contents)
  (with-open-file (stream fpath
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (format stream "~A~&" contents)))

;; TODO: perhaps remove if we're just gonna run binaries and see if that works.
(defun exec-paths ()
  "get list of (existing) dirs in PATH"
  (reduce (lambda (acc v)
            (let ((pf (probe-file v)))
              (if (uiop:directory-exists-p pf)
                  (cons pf acc)
                  acc)))
          (append cmd:*cmd-env*
                  (->> "PATH" uiop:getenv (str:split ":")))
          :initial-value '()))

(defun find-file-in (fname paths)
  (loop for path in paths
        for fpath = (merge-pathnames path fname)
        when (uiop:file-exists-p fpath)
        return fpath
        end
        finally (return nil)))

(defun which-exe (fname)
  "equivalent to shell `which` command"
  (find-file-in fname (exec-paths)))

(defun plist-dissoc-duplicates (plist)
  (labels ((fn (acc plist keys)
             (if (null plist)
                 acc
                 (destructuring-bind (k v &rest lst) plist
                   (if (member k keys)
                       (fn acc lst keys)
                       ;; only cons'ing in this order because of the final reverse
                       (fn (->> acc (cons k) (cons v))
                           lst (cons k keys)))))))
    (reverse (fn '() plist '()))))

(defun plist-merge (plist1 plist2 &rest plists)
  "merge plists left->right and removing duplicates."
  (->> plists (cons plist2) (cons plist1) reverse (apply #'append) plist-dissoc-duplicates))

(defun plist-map-kv (plist &key (kfn #'identity) (vfn #'identity))
  "create new list resulting from mapping kfn on each key and vfn on each value."
  (loop :for (k v) :on plist :by #'cddr
        collect (funcall kfn k) collect (funcall vfn v)))

(defun plist-assoc (plist key value)
  "add new entry to plist"
  (->> plist (cons value) (cons key)))

;;(defun plist-keys (plist)
;;  (loop :for (k v) :on plist
;;        :by #'cddr
;;        collect k))
;;
;;(defun plist-dissoc (plist keys)
;;  (loop :for (k v) :on plist
;;        :by #'cddr
;;        :for keep = (not (member k keys))
;;        :when keep collect k :when keep collect v))

;; (defun plist-map-vals (plist fn &rest args)
;;   (loop :for (k v) :on plist
;;         :by #'cddr
;;         collect k collect (apply fn v args)))

(defun ht-assoc (ht key val &rest kvs)
  "associate (add) multiple entries to hash-table ht."
  (setf (gethash key ht) val)
  (when kvs
    (loop :for (key val) :on kvs :by #'cddr
          :do (setf (gethash key ht) val)))
  ht)

(defun ht-assoc* (ht &rest kvs)
  "associate (add) entries to hash-table ht, if any."
  (when kvs
    (loop :for (key val) :on kvs :by #'cddr
          :do (setf (gethash key ht) val))))

(defun ht-dissoc (ht key &rest keys)
  "dissociate (remove) multiple entries from hash-table ht."
  (remhash key ht)
  (when keys
    (loop :for (key) :on keys
          :do (remhash key ht)))
  ht)

(defun ht-merge (target first &rest rest)
  "merge one or more hash-tables into target hash-table."
  (loop :for ht :in (cons first rest)
        :do (when ht
              (loop :for v :being :each :hash-value :of ht
                      :using (hash-key k)
                    :do (setf (gethash k target) v))))
  target)

(defmacro ht-map-kv (fn ht) ;; TODO: not exported
  `(maphash ,fn ,ht))

(defun pmap (fn lst)
  "process map - map over a list of items using a separate process for each, return once all results are in"
  (let ((alist (mapcar (lambda (e)
                         (let ((res (make-array 1)))
                           (cons (bt:make-thread
                                  (lambda () (setf (aref res 0) (funcall fn e))))
                                 res)
                           )) lst)))
    (loop :for (thread . res) :in alist
          :do (bt:join-thread thread)
          :collect (aref res 0))))
