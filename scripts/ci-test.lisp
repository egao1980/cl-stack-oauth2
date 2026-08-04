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
(cl-repository-client/asdf-integration:configure-asdf-source-registry)
(cl-repository-client/asdf-integration:load-system-init-files)

(call-with-ci-muffles
 (lambda ()
   (dolist (n '("rove" "alexandria" "babel" "yason" "trivial-mimes"
                "ironclad" "cl-base64" "quri" "dexador"
                "cl-stack-http" "http-protocol" "http-backend-dexador"))
     (unless (asdf:find-system n nil)
       (format t "~&; ci: ql fallback ~a~%" n)
       (ql:quickload n :silent t)))
   (asdf:load-system "cl-stack-oauth2")
   (unless (fboundp (find-symbol "PREPARE-AUTH" :cl-stack-http))
     (error "cl-stack-http missing CLOS auth protocol (need ≥0.1.1 with auth-protocol.lisp)"))
   (asdf:test-system "cl-stack-oauth2")))

(uiop:quit 0)
