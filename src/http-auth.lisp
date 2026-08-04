(in-package #:cl-stack-oauth2)

;;; CLOS auth protocol methods — plug into cl-stack-http:request.

(defmethod http:prepare-auth ((auth oauth2-auth) request)
  (declare (ignore request))
  (unless http:*auth-in-flight*
    (oauth2-ensure-access-token! auth))
  (when (oauth2-access-token auth)
    (oauth2-bearer-auth auth)))

(defmethod http:auth-retry-p ((auth oauth2-auth) response)
  (and (http-response-p response)
       (= 401 (response-status response))
       (not http:*auth-in-flight*)))

(defmethod http:handle-auth-response ((auth oauth2-auth) backend client request response)
  (unless (http:auth-retry-p auth response)
    (return-from http:handle-auth-response response))
  (oauth2-refresh! auth :force t)
  (let* ((bearer (oauth2-bearer-auth auth))
         (retry (http:copy-request-with-auth request bearer :raise-for-status nil)))
    (send backend client retry)))
