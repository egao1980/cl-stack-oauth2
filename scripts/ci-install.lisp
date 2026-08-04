;;;; Phase 1: install SUT dependency closure via cl-repository-client.
;;;; http-backend-dexador is CI :with (needed to exercise cl-stack-http; not in oauth2.asd).

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

(cl-repo:add-registry "https://ghcr.io" :namespace "egao1980/cl-systems" :priority :prepend)

(call-with-ci-muffles
 (lambda ()
   (cl-repo:ensure-system-dependencies "cl-stack-oauth2"
     :also-tests t
     :with '("http-backend-dexador")
     :sources '(("babel" :ql)
                ("trivial-features" :ql)
                ("cl-unicode" :ql)))))

(format t "~&; ci: install phase done~%")
(uiop:quit 0)
