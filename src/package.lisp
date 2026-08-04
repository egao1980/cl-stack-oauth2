(defpackage #:cl-stack-oauth2
  (:nicknames #:stack-oauth2)
  (:use #:cl #:http-protocol)
  (:import-from #:http-protocol #:http-error-message)
  (:local-nicknames (#:http #:cl-stack-http)
                    (#:alex #:alexandria))
  (:export
   ;; scope (RFC 6749 §3.3)
   #:normalize-scope
   #:parse-scope
   #:scope-string
   #:scope-list
   #:scope-subset-p
   #:merge-scopes
   ;; PKCE (RFC 7636)
   #:make-pkce
   #:pkce-verifier
   #:pkce-challenge
   #:pkce-method
   ;; credentials / token state
   #:oauth2-auth
   #:oauth2-auth-p
   #:make-oauth2-auth
   #:oauth2-access-token
   #:oauth2-refresh-token
   #:oauth2-token-type
   #:oauth2-expires-at
   #:oauth2-token-url
   #:oauth2-authorize-url
   #:oauth2-client-id
   #:oauth2-client-secret
   #:oauth2-client-auth
   #:oauth2-username
   #:oauth2-password
   #:oauth2-scope
   #:oauth2-granted-scope
   #:oauth2-audience
   #:oauth2-resource
   #:oauth2-redirect-uri
   #:oauth2-code
   #:oauth2-code-verifier
   #:oauth2-state
   #:oauth2-grant
   #:oauth2-extra-params
   #:oauth2-get-token-fn
   #:oauth2-refresh-fn
   #:oauth2-leeway
   #:oauth2-expired-p
   #:oauth2-bearer-auth
   #:oauth2-apply-token-response!
   #:oauth2-fetch-token!
   #:oauth2-refresh!
   #:oauth2-ensure-access-token!
   #:oauth2-revoke!
   #:oauth2-authorization-uri
   #:oauth2-exchange-code!
   ;; conditions
   #:oauth2-error
   #:oauth2-error-message
   #:oauth2-error-status
   #:oauth2-error-body))
