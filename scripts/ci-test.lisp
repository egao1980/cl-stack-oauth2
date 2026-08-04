;;;; Phase 2: load SUT + run tests (install already fetched deps).

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
(cl-repo:configure-asdf-source-registry)
(cl-repo:load-system-init-files)

(call-with-ci-muffles
 (lambda ()
   (asdf:load-system "http-backend-dexador")
   (asdf:load-system "cl-stack-oauth2")
   (unless (fboundp (find-symbol "PREPARE-AUTH" :cl-stack-http))
     (error "cl-stack-http missing CLOS auth protocol (need ≥0.1.1 with auth-protocol.lisp)"))
   (asdf:test-system "cl-stack-oauth2")))

(uiop:quit 0)
