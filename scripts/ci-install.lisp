;;;; Phase 1: fetch OCI deps. Bootstrap: oras-pulled cl-repository-client.

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&UNHANDLED: ~A~%" c)
        (uiop:quit 1)))

(setf asdf:*compile-file-failure-behaviour* :warn)

(defun call-with-ci-muffles (fn)
  #+sbcl
  (handler-bind ((sb-ext:defconstant-uneql
                  (lambda (c)
                    (declare (ignore c))
                    (let ((r (find-restart 'continue)))
                      (when r (invoke-restart r))))))
    (funcall fn))
  #-sbcl
  (funcall fn))

(call-with-ci-muffles (lambda () (asdf:load-system "cl-repository-client")))

(defparameter *ci-ql-sources*
  '(("babel" :ql)
    ("trivial-features" :ql)
    ("cl-unicode" :ql)))

(cl-repo:add-registry "https://ghcr.io" :namespace "egao1980/cl-systems" :priority :prepend)

(defun ci-on-disk-p (name)
  (cl-repository-client/quickload::system-already-installed-p name))

(defun ci-fetch (name &key version)
  (format t "~&; ci: fetch ~a~@[:~a~]~%" name version)
  (cl-repository-client/source-policy:call-with-policy-overrides
   *ci-ql-sources* nil nil nil
   (lambda ()
     (cl-repository-client/protected-systems:ensure-snapshot)
     (cl-repository-client/digest-cache:load-digest-cache)
     (let ((plan (cl-repository-client/quickload::compute-install-plan
                  (list name) :version version)))
       (dolist (entry plan)
         (let ((n (car entry))
               (ver (cdr entry)))
           (unless (or (cl-repository-client/source-policy:system-denied-p n)
                       (and (ci-on-disk-p n)
                            (let ((iv (cl-repository-client/quickload::installed-system-version n)))
                              (and iv (string= iv (princ-to-string ver))))))
             (format t "~&; ci: ensure-installed ~a~@[:~a~]~%" n ver)
             (let ((result (cl-repository-client/quickload::ensure-system-installed
                            n :version ver)))
               (when result
                 (cl-repository-client/asdf-integration:configure-asdf-source-registry))))))
       (when cl-repository-client/quickload::*missing-deps-accumulator*
         (format t "~&; ci: deferring ql fallback: ~{~a~^, ~}~%"
                 cl-repository-client/quickload::*missing-deps-accumulator*)))))
  (cl-repository-client/asdf-integration:configure-asdf-source-registry)
  (unless (or (ci-on-disk-p name) (asdf:find-system name nil))
    (error "ci-fetch: ~a not on disk / ASDF after install" name)))

(defun ci-ql (name)
  (unless (or (ci-on-disk-p name) (asdf:find-system name nil))
    (format t "~&; ci: ql fallback ~a~%" name)
    (ql:quickload name :silent t)))

(call-with-ci-muffles
 (lambda ()
   (ci-fetch "http-protocol" :version "0.2.0")
   (ci-fetch "cl-stack-pathlib" :version "0.1.1")
   (ci-fetch "http-backend-dexador" :version "0.1.1")
   ;; Prefer OCI cl-stack-http ≥0.1.1 (auth protocol). Until published, QL won't help —
   ;; local/dev: put checkout on CL_SOURCE_REGISTRY ahead of OCI.
   (ignore-errors (ci-fetch "cl-stack-http" :version "0.1.1"))
   (ci-fetch "http-encoding-chipz")
   (ci-fetch "quri")
   (dolist (n '("rove" "alexandria" "babel" "yason" "trivial-mimes"
                "blackbird" "cl-cookie" "dexador" "chipz" "salza2"
                "cl-unicode" "bordeaux-threads" "trivial-gray-streams"
                "ironclad" "cl-base64" "quri" "cl-stack-http"))
     (ci-ql n))))

(format t "~&; ci: install phase done~%")
(uiop:quit 0)
