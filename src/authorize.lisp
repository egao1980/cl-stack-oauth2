(in-package #:cl-stack-oauth2)

(defun %random-state (&optional (nbytes 16))
  (%b64url-octets (ironclad:random-data nbytes)))

(defun oauth2-authorization-uri (auth &key scope state
                                        (pkce nil pkce-p)
                                        code-challenge code-challenge-method
                                        response-type
                                        extra-params)
  "Build authorization endpoint URI (RFC 6749 §4.1.1 + PKCE).

   SCOPE defaults to AUTH's requested scope (string|list).
   STATE defaults to AUTH's state or a fresh random value (stored on AUTH).
   PKCE: pass MAKE-PKCE result, or T to generate; stores :code-verifier on AUTH.
   Returns URI string."
  (let* ((base (or (oauth2-authorize-url auth)
                   (error 'oauth2-error :message "oauth2-auth :authorize-url required")))
         (client-id (or (oauth2-client-id auth)
                        (error 'oauth2-error :message "authorize needs :client-id")))
         (redirect (or (oauth2-redirect-uri auth)
                       (error 'oauth2-error :message "authorize needs :redirect-uri")))
         (scope (normalize-scope (or scope (oauth2-scope auth))))
         (state (or state (oauth2-state auth) (%random-state)))
         (pkce (cond
                 (pkce-p (if (eq pkce t) (make-pkce) pkce))
                 ((oauth2-code-verifier auth)
                  (make-pkce :verifier (oauth2-code-verifier auth)))
                 (t nil)))
         (challenge (or code-challenge (and pkce (pkce-challenge pkce))))
         (method (or code-challenge-method (and pkce (pkce-method pkce))))
         (params
           (append
            (list (cons "response_type" (or response-type "code"))
                  (cons "client_id" client-id)
                  (cons "redirect_uri" redirect)
                  (cons "state" state))
            (when scope (list (cons "scope" scope)))
            (when (oauth2-audience auth)
              (list (cons "audience" (oauth2-audience auth))))
            (%resource-params (oauth2-resource auth))
            (when challenge
              (list (cons "code_challenge" challenge)
                    (cons "code_challenge_method" (or method "S256"))))
            (oauth2-extra-params auth)
            extra-params)))
    (setf (oauth2-state auth) state)
    (when pkce
      (setf (oauth2-code-verifier auth) (pkce-verifier pkce)))
    (when scope
      (setf (oauth2-scope auth) scope))
    (let ((uri (quri:uri base)))
      (setf (quri:uri-query-params uri)
            (append (quri:uri-query-params uri) params))
      (quri:render-uri uri))))
