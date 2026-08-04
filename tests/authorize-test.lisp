(in-package #:cl-stack-oauth2/tests)

(deftest pkce-s256-shape
  (let ((p (make-pkce :verifier "verifier-value-012345678901234567890123")))
    (ok (string= "verifier-value-012345678901234567890123" (pkce-verifier p)))
    (ok (string= "S256" (pkce-method p)))
    (ok (plusp (length (pkce-challenge p))))
    (ok (not (find #\= (pkce-challenge p))))))

(deftest authorization-uri-scopes-and-pkce
  (let* ((a (make-oauth2-auth
             :authorize-url "https://as.example/authorize"
             :client-id "cid"
             :redirect-uri "https://app/cb"
             :scope '("openid" "profile")
             :audience "api"
             :resource '("urn:a" "urn:b")))
         (uri (oauth2-authorization-uri a :state "st" :pkce t))
         (q (quri:uri-query-params (quri:uri uri))))
    (ok (search "https://as.example/authorize" uri :test #'char=))
    (ok (equal "code" (cdr (assoc "response_type" q :test #'string=))))
    (ok (equal "openid profile" (cdr (assoc "scope" q :test #'string=))))
    (ok (equal "st" (cdr (assoc "state" q :test #'string=))))
    (ok (equal "api" (cdr (assoc "audience" q :test #'string=))))
    (ok (equal '("urn:a" "urn:b")
               (mapcar #'cdr (remove "resource" q :key #'car :test-not #'string=))))
    (ok (stringp (cdr (assoc "code_challenge" q :test #'string=))))
    (ok (equal "S256" (cdr (assoc "code_challenge_method" q :test #'string=))))
    (ok (stringp (oauth2-code-verifier a)))))
