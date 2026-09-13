(in-package #:cl-stack-oauth2/tests)

(defparameter *oidc-discovery-json*
  "{
  \"issuer\": \"https://idp.example\",
  \"authorization_endpoint\": \"https://idp.example/authorize\",
  \"token_endpoint\": \"https://idp.example/token\",
  \"jwks_uri\": \"https://idp.example/jwks\",
  \"userinfo_endpoint\": \"https://idp.example/userinfo\",
  \"id_token_signing_alg_values_supported\": [\"RS256\"]
}")

(deftest parse-discovery-fixture
  (let ((d (parse-oidc-discovery *oidc-discovery-json*)))
    (ok (oidc-discovery-p d))
    (ok (string= "https://idp.example" (oidc-issuer d)))
    (ok (string= "https://idp.example/authorize" (oidc-authorization-endpoint d)))
    (ok (string= "https://idp.example/token" (oidc-token-endpoint d)))
    (ok (string= "https://idp.example/jwks" (oidc-jwks-uri d)))
    (ok (string= "https://idp.example/userinfo" (oidc-userinfo-endpoint d)))))

(deftest fetch-discovery-injected-http
  (let ((seen nil))
    (let ((d (fetch-oidc-discovery
              "https://idp.example/"
              :http (lambda (url)
                      (setf seen url)
                      *oidc-discovery-json*))))
      (ok (string= "https://idp.example/.well-known/openid-configuration" seen))
      (ok (string= "https://idp.example" (oidc-issuer d))))))

(deftest apply-discovery-to-auth
  (let ((a (make-oauth2-auth :client-id "cid"))
        (d (parse-oidc-discovery *oidc-discovery-json*)))
    (apply-oidc-discovery! a d)
    (ok (string= "https://idp.example/authorize" (oauth2-authorize-url a)))
    (ok (string= "https://idp.example/token" (oauth2-token-url a)))))

(deftest oidc-authorization-url-openid-nonce
  (let* ((a (make-oidc-auth
             :authorize-url "https://idp.example/authorize"
             :client-id "cid"
             :redirect-uri "https://app/cb"
             :scope "profile"))
         (uri (oidc-authorization-url a :state "st" :nonce "n-1" :pkce t))
         (q (quri:uri-query-params (quri:uri uri))))
    (ok (equal "openid profile" (cdr (assoc "scope" q :test #'string=))))
    (ok (equal "n-1" (cdr (assoc "nonce" q :test #'string=))))
    (ok (string= "n-1" (oauth2-nonce a)))
    (ok (stringp (oauth2-code-verifier a)))))

(defun %hs-key ()
  (encoding-protocol:encode "secret-key-123456789012345678901234"))

(defun %id-token (&key (iss "https://idp.example")
                       (aud "app")
                       (nonce "n1")
                       (sub "user")
                       (exp (+ (cl-stack-jwt:unix-time) 3600))
                       (kid "k1"))
  (cl-stack-jwt:encode
   :hs256 (%hs-key)
   `(("iss" . ,iss)
     ("aud" . ,aud)
     ("nonce" . ,nonce)
     ("sub" . ,sub)
     ("exp" . ,exp))
   :headers `(("kid" . ,kid))))

(deftest validate-id-token-ok
  (let ((tok (%id-token)))
    (multiple-value-bind (claims header)
        (validate-id-token tok
                           :algorithms '("HS256")
                           :key (%hs-key)
                           :issuer "https://idp.example"
                           :audience "app"
                           :nonce "n1")
      (ok (equal "user" (cdr (assoc "sub" claims :test #'string=))))
      (ok (equal "HS256" (cdr (assoc "alg" header :test #'string=)))))))

(deftest validate-id-token-jwks-kid
  (let* ((tok (%id-token :kid "rot-1"))
         (cache (make-jwks-cache)))
    (jwks-cache-put cache "rot-1" (%hs-key))
    (ok (equal "user"
               (cdr (assoc "sub"
                           (validate-id-token tok
                                              :algorithms '("HS256")
                                              :jwks cache
                                              :issuer "https://idp.example"
                                              :audience "app"
                                              :nonce "n1")
                           :test #'string=))))))

(deftest validate-id-token-bad-iss
  (ok (signals (validate-id-token (%id-token)
                                  :algorithms '("HS256")
                                  :key (%hs-key)
                                  :issuer "https://other.example"
                                  :audience "app"
                                  :nonce "n1")
               'oidc-claim-error)))

(deftest validate-id-token-bad-aud
  (ok (signals (validate-id-token (%id-token)
                                  :algorithms '("HS256")
                                  :key (%hs-key)
                                  :issuer "https://idp.example"
                                  :audience "other-app"
                                  :nonce "n1")
               'oidc-claim-error)))

(deftest validate-id-token-bad-nonce
  (ok (signals (validate-id-token (%id-token)
                                  :algorithms '("HS256")
                                  :key (%hs-key)
                                  :issuer "https://idp.example"
                                  :audience "app"
                                  :nonce "nope")
               'oidc-claim-error)))

(deftest validate-id-token-alg-not-allowed
  (ok (signals (validate-id-token (%id-token)
                                  :algorithms '("RS256")
                                  :key (%hs-key)
                                  :issuer "https://idp.example")
               'oidc-id-token-error)))

(deftest jwks-kid-rotation-refetch
  (let* ((tok (%id-token :kid "new"))
         (cache (make-jwks-cache :uri "https://idp.example/jwks"))
         (fetched nil))
    (jwks-cache-put cache "old" (%hs-key))
    (validate-id-token tok
                       :algorithms '("HS256")
                       :jwks cache
                       :http (lambda (url)
                               (setf fetched url)
                               (jwks-cache-put cache "new" (%hs-key))
                               (let ((ht (make-hash-table :test #'equal)))
                                 (setf (gethash "keys" ht) #())
                                 ht))
                       :issuer "https://idp.example"
                       :audience "app"
                       :nonce "n1")
    (ok (string= "https://idp.example/jwks" fetched))))

(deftest apply-token-captures-id-token
  (let* ((a (make-oauth2-auth :scope "openid"))
         (ht (make-hash-table :test #'equal)))
    (setf (gethash "access_token" ht) "atk"
          (gethash "id_token" ht) "header.payload.sig"
          (gethash "expires_in" ht) 60)
    (oauth2-apply-token-response! a ht)
    (ok (string= "atk" (oauth2-access-token a)))
    (ok (string= "header.payload.sig" (oauth2-id-token a)))))
