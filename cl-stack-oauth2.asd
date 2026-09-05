(defsystem "cl-stack-oauth2"
  :version "0.1.1"
  :description "OAuth2 token flows for cl-stack-http (scopes, grants, PKCE, 401 refresh)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("cl-stack-http"
               "http-protocol"
               "alexandria"
               "babel"
               "encoding-protocol"
               "ironclad"
               "quri")
  :properties
  (:cl-repo
   (:ci (:with ("http-backend-dexador")
         :sources (("encoding-protocol" :oci))
         :load-before-test ("http-backend-dexador"))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "scope")
               (:file "pkce")
               (:file "auth")
               (:file "token")
               (:file "authorize")
               (:file "http-auth"))
  :in-order-to ((test-op (test-op "cl-stack-oauth2/tests"))))

(defsystem "cl-stack-oauth2/tests"
  :depends-on ("cl-stack-oauth2" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "scope-test")
               (:file "auth-test")
               (:file "authorize-test"))
  :perform (test-op (o c)
             (symbol-call :rove :run c)))
