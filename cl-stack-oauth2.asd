(defsystem "cl-stack-oauth2"
  :version "0.2.0"
  :description "OAuth2 + OIDC token flows for cl-stack-http (scopes, grants, PKCE, discovery, ID tokens)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("cl-stack-http"
               "http-protocol"
               "alexandria"
               "encoding-protocol"
               "crypto-protocol"
               "secrets-protocol"
               "json-protocol"
               "cl-stack-jwt"
               "quri")
  :properties
  (:cl-repo
   (:ci (:with ("http-backend-dexador" "crypto-backend-ironclad" "json-backend-jzon")
         :load-before-test ("http-backend-dexador" "crypto-backend-ironclad" "json-backend-jzon"))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "scope")
               (:file "pkce")
               (:file "auth")
               (:file "token")
               (:file "authorize")
               (:file "http-auth")
               (:file "oidc"))
  :in-order-to ((test-op (test-op "cl-stack-oauth2/tests"))))

(defsystem "cl-stack-oauth2/tests"
  :depends-on ("cl-stack-oauth2" "crypto-backend-ironclad" "json-backend-jzon" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "scope-test")
               (:file "auth-test")
               (:file "authorize-test")
               (:file "oidc-test"))
  :perform (test-op (o c)
             (symbol-call :rove :run c)))
