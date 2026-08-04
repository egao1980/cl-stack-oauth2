(in-package #:cl-stack-oauth2/tests)

(deftest form-params-client-credentials-scope
  (let* ((a (make-oauth2-auth :client-id "cid" :client-secret "sec"
                              :scope '("api" "openid")
                              :audience "https://api.example"
                              :resource "urn:res:1"))
         (form (cl-stack-oauth2::%oauth2-form-params a :client-credentials)))
    (ok (equal "client_credentials" (cdr (assoc "grant_type" form :test #'string=))))
    (ok (equal "api openid" (cdr (assoc "scope" form :test #'string=))))
    (ok (equal "https://api.example" (cdr (assoc "audience" form :test #'string=))))
    (ok (equal "urn:res:1" (cdr (assoc "resource" form :test #'string=))))))

(deftest form-params-refresh-narrow-scope
  (let* ((a (make-oauth2-auth :refresh-token "r" :scope "a b c"))
         (form (cl-stack-oauth2::%oauth2-form-params a :refresh-token :scope "a")))
    (ok (equal "refresh_token" (cdr (assoc "grant_type" form :test #'string=))))
    (ok (equal "a" (cdr (assoc "scope" form :test #'string=))))))

(deftest form-params-auth-code-pkce
  (let* ((a (make-oauth2-auth :code "abc" :redirect-uri "https://app/cb"
                              :code-verifier "v" :client-id "cid"
                              :client-auth :basic))
         (form (cl-stack-oauth2::%oauth2-form-params a :authorization-code)))
    (ok (equal "authorization_code" (cdr (assoc "grant_type" form :test #'string=))))
    (ok (equal "v" (cdr (assoc "code_verifier" form :test #'string=))))
    (ok (equal "cid" (cdr (assoc "client_id" form :test #'string=))))))

(deftest form-params-client-secret-post
  (let* ((a (make-oauth2-auth :client-id "cid" :client-secret "sec"
                              :client-auth :body :scope "x"))
         (form (cl-stack-oauth2::%oauth2-form-params a :client-credentials)))
    (ok (equal "cid" (cdr (assoc "client_id" form :test #'string=))))
    (ok (equal "sec" (cdr (assoc "client_secret" form :test #'string=))))))

(deftest ensure-via-get-token-fn
  (let* ((called nil)
         (a (make-oauth2-auth
             :get-token-fn (lambda (auth)
                             (setf called t
                                   (oauth2-access-token auth) "t"
                                   (oauth2-expires-at auth)
                                   (+ (get-universal-time) 3600))))))
    (oauth2-ensure-access-token! a)
    (ok called)
    (ok (string= "t" (oauth2-access-token a)))
    (ok (equal '(:bearer "t") (oauth2-bearer-auth a)))
    (ok (http:auth-object-p a))
    (ok (equal '(:bearer "t") (http:prepare-auth a nil)))))

(deftest expired-leeway
  (let ((a (make-oauth2-auth :access-token "t"
                             :expires-at (get-universal-time)
                             :leeway 60)))
    (ok (oauth2-expired-p a))))
