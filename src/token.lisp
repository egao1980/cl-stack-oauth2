(in-package #:cl-stack-oauth2)

(defun %json-get (obj key)
  (cond
    ((hash-table-p obj)
     (or (gethash key obj)
         (gethash (string-downcase key) obj)))
    ((listp obj) (cdr (assoc key obj :test #'equalp)))
    (t nil)))

(defun %resource-params (resource)
  "RFC 8707 — repeat resource= for each value."
  (cond
    ((null resource) nil)
    ((listp resource)
     (mapcar (lambda (r) (cons "resource" (string r))) resource))
    (t (list (cons "resource" (string resource))))))

(defun %scope-param (scope)
  (let ((s (normalize-scope scope)))
    (when s (list (cons "scope" s)))))

(defun %client-body-params (auth)
  (when (eq (oauth2-client-auth auth) :body)
    (append (when (oauth2-client-id auth)
              (list (cons "client_id" (oauth2-client-id auth))))
            (when (oauth2-client-secret auth)
              (list (cons "client_secret" (oauth2-client-secret auth)))))))

(defun %oauth2-form-params (auth grant &key (scope nil scope-p))
  "Build token-endpoint form alist for GRANT.
   SCOPE defaults to AUTH's requested scope; pass NIL explicitly to omit."
  (let* ((scope (if scope-p scope (oauth2-scope auth)))
         (extra (copy-list (oauth2-extra-params auth)))
         (aud (oauth2-audience auth))
         (base
           (ecase grant
             (:client-credentials
              (append (list (cons "grant_type" "client_credentials"))
                      (%scope-param scope)
                      (when aud (list (cons "audience" aud)))
                      (%resource-params (oauth2-resource auth))))
             (:password
              (append (list (cons "grant_type" "password")
                            (cons "username"
                                  (or (oauth2-username auth)
                                      (error 'oauth2-error
                                             :message "password grant needs :username")))
                            (cons "password"
                                  (or (oauth2-password auth)
                                      (error 'oauth2-error
                                             :message "password grant needs :password"))))
                      (%scope-param scope)
                      (%resource-params (oauth2-resource auth))))
             (:refresh-token
              (append (list (cons "grant_type" "refresh_token")
                            (cons "refresh_token"
                                  (or (oauth2-refresh-token auth)
                                      (error 'oauth2-error
                                             :message "refresh needs :refresh-token"))))
                      ;; RFC 6749: refresh MAY request equal/narrower scope
                      (%scope-param scope)
                      (%resource-params (oauth2-resource auth))))
             (:authorization-code
              (append (list (cons "grant_type" "authorization_code")
                            (cons "code"
                                  (or (oauth2-code auth)
                                      (error 'oauth2-error
                                             :message "authorization_code needs :code")))
                            (cons "redirect_uri"
                                  (or (oauth2-redirect-uri auth)
                                      (error 'oauth2-error
                                             :message "authorization_code needs :redirect-uri"))))
                      (when (oauth2-code-verifier auth)
                        (list (cons "code_verifier" (oauth2-code-verifier auth))))
                      ;; some ASes want client_id in body even with basic auth
                      (when (and (oauth2-client-id auth)
                                 (not (eq (oauth2-client-auth auth) :body)))
                        (list (cons "client_id" (oauth2-client-id auth))))
                      (%resource-params (oauth2-resource auth)))))))
    (append base (%client-body-params auth) extra)))

(defun %token-http-auth (auth)
  (case (oauth2-client-auth auth)
    (:basic
     (when (oauth2-client-id auth)
       (list :basic (oauth2-client-id auth) (or (oauth2-client-secret auth) ""))))
    ((:body :none) nil)
    (t (error 'oauth2-error
              :message (format nil "unknown :client-auth ~S" (oauth2-client-auth auth))))))

(defun %oauth2-token-http-post (auth form)
  (let ((url (or (oauth2-token-url auth)
                 (error 'oauth2-error :message "oauth2-auth :token-url required"))))
    (unless *http-backend*
      (setf *http-backend* (http:ensure-http-backend)))
    (let* ((http:*auth-in-flight* t)
           (basic (%token-http-auth auth))
           (res (apply #'http:post url
                       :form-data form
                       :force-binary t
                       (when basic (list :auth basic)))))
      (unless (http:response-ok-p res)
        (error 'oauth2-error
               :status (response-status res)
               :body (ignore-errors (http:response-text res))
               :message (format nil "token endpoint HTTP ~A: ~A"
                                (response-status res)
                                (ignore-errors (http:response-text res)))))
      (or (ignore-errors (http:response-json res))
          (http:decode-json (http:response-content res))))))

(defun oauth2-apply-token-response! (auth response-data)
  "Update AUTH from token JSON. Captures granted scope from `scope` if present."
  (let* ((access (%json-get response-data "access_token"))
         (refresh (%json-get response-data "refresh_token"))
         (token-type (%json-get response-data "token_type"))
         (expires-in (%json-get response-data "expires_in"))
         (scope (%json-get response-data "scope"))
         (err (%json-get response-data "error")))
    (when err
      (error 'oauth2-error
             :body response-data
             :message (format nil "token error ~A~@[: ~A~]"
                              err (%json-get response-data "error_description"))))
    (unless access
      (error 'oauth2-error
             :body response-data
             :message (format nil "token response missing access_token: ~S" response-data)))
    (setf (oauth2-access-token auth) access)
    (when refresh
      (setf (oauth2-refresh-token auth) refresh))
    (when token-type
      (setf (oauth2-token-type auth) (string token-type)))
    (when (numberp expires-in)
      (setf (oauth2-expires-at auth) (+ (get-universal-time) (round expires-in))))
    (when scope
      (setf (oauth2-granted-scope auth) (normalize-scope scope)))
    auth))

(defun %infer-grant (auth)
  (or (oauth2-grant auth)
      (cond
        ((oauth2-code auth) :authorization-code)
        ((and (oauth2-username auth) (oauth2-password auth)) :password)
        (t :client-credentials))))

(defun oauth2-fetch-token! (auth &key grant scope)
  "Obtain access token. SCOPE overrides requested scope for this call only."
  (when (oauth2-get-token-fn auth)
    (funcall (oauth2-get-token-fn auth) auth)
    (return-from oauth2-fetch-token! auth))
  (let ((grant (or grant (%infer-grant auth))))
    (oauth2-apply-token-response!
     auth
     (%oauth2-token-http-post
      auth
      (if scope
          (%oauth2-form-params auth grant :scope scope)
          (%oauth2-form-params auth grant))))))

(defun oauth2-refresh! (auth &key force (scope nil scope-p))
  "Refresh access token. SCOPE may narrow (RFC); default keeps AUTH's requested scope.
   Pass :SCOPE NIL to omit scope on refresh."
  (unless (or force (oauth2-expired-p auth))
    (return-from oauth2-refresh! auth))
  (when (oauth2-refresh-fn auth)
    (funcall (oauth2-refresh-fn auth) auth)
    (return-from oauth2-refresh! auth))
  (cond
    ((and (oauth2-refresh-token auth) (oauth2-token-url auth))
     (oauth2-apply-token-response!
      auth
      (%oauth2-token-http-post
       auth
       (if scope-p
           (%oauth2-form-params auth :refresh-token :scope scope)
           (%oauth2-form-params auth :refresh-token)))))
    (t
     (oauth2-fetch-token! auth)))
  auth)

(defun oauth2-ensure-access-token! (auth &key force)
  (when http:*auth-in-flight*
    (return-from oauth2-ensure-access-token! auth))
  (cond
    ((and (not force) (not (oauth2-expired-p auth))) auth)
    ((or (oauth2-refresh-token auth) (oauth2-refresh-fn auth))
     (oauth2-refresh! auth :force t))
    (t
     (oauth2-fetch-token! auth))))

(defun oauth2-exchange-code! (auth &key code redirect-uri code-verifier)
  "authorization_code grant helper — sets slots then fetches token."
  (when code (setf (oauth2-code auth) code))
  (when redirect-uri (setf (oauth2-redirect-uri auth) redirect-uri))
  (when code-verifier (setf (oauth2-code-verifier auth) code-verifier))
  (setf (oauth2-grant auth) :authorization-code)
  (oauth2-fetch-token! auth :grant :authorization-code))

(defun oauth2-revoke! (auth &key token hint)
  "RFC 7009 token revocation (best-effort). TOKEN defaults to access then refresh."
  (let ((url (or (oauth2-revoke-url auth)
                 (error 'oauth2-error :message "oauth2-auth :revoke-url required")))
        (token (or token
                   (oauth2-access-token auth)
                   (oauth2-refresh-token auth)
                   (error 'oauth2-error :message "nothing to revoke"))))
    (unless *http-backend*
      (setf *http-backend* (http:ensure-http-backend)))
    (let* ((http:*auth-in-flight* t)
           (form (append (list (cons "token" token))
                         (when hint (list (cons "token_type_hint" hint)))
                         (%client-body-params auth)))
           (basic (%token-http-auth auth))
           (res (apply #'http:post url
                       :form-data form
                       (when basic (list :auth basic)))))
      (unless (http:response-ok-p res)
        (error 'oauth2-error
               :status (response-status res)
               :body (ignore-errors (http:response-text res))
               :message (format nil "revoke endpoint HTTP ~A"
                                (response-status res))))
      auth)))
