(in-package #:cl-stack-oauth2/tests)

(deftest normalize-scope-shapes
  (ok (null (normalize-scope nil)))
  (ok (string= "a" (normalize-scope "a")))
  (ok (string= "a b" (normalize-scope "  a   b  ")))
  (ok (string= "openid profile email" (normalize-scope '("openid" "profile" "email"))))
  (ok (string= "a b" (normalize-scope '("a" "a" "b"))))
  (ok (equal '("openid" "profile") (parse-scope "openid profile"))))

(deftest scope-subset
  (ok (scope-subset-p nil "a b"))
  (ok (scope-subset-p "a" "a b c"))
  (ok (scope-subset-p '("a" "c") "a b c"))
  (ng (scope-subset-p "a d" "a b c")))

(deftest merge-scopes-union
  (ok (string= "a b c" (merge-scopes "a b" '("b" "c")))))

(deftest make-auth-normalizes-scope
  (let ((a (make-oauth2-auth :scope '("api.read" "api.write")
                             :granted-scope "api.read")))
    (ok (string= "api.read api.write" (oauth2-scope a)))
    (ok (string= "api.read" (oauth2-granted-scope a)))))

(deftest apply-token-response-granted-scope
  (let* ((a (make-oauth2-auth :scope "openid profile email"))
         (ht (make-hash-table :test #'equal)))
    (setf (gethash "access_token" ht) "tok"
          (gethash "expires_in" ht) 3600
          (gethash "scope" ht) "openid profile")
    (oauth2-apply-token-response! a ht)
    (ok (string= "tok" (oauth2-access-token a)))
    (ok (string= "openid profile" (oauth2-granted-scope a)))
    (ok (scope-subset-p (oauth2-granted-scope a) (oauth2-scope a)))))
