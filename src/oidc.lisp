(in-package #:cl-stack-oauth2)

;;; OpenID Connect Core 1.0 — discovery, JWKS, ID-token validation.
;;; SCIM is tier 2 and is not implemented here.

(define-condition oidc-error (oauth2-error) ())

(define-condition oidc-id-token-error (oidc-error) ())

(define-condition oidc-claim-error (oidc-id-token-error)
  ((claim :initarg :claim :reader oidc-error-claim :initform nil))
  (:report (lambda (c s)
             (format s "OIDC ID token claim ~A invalid~@[: ~A~]"
                     (or (oidc-error-claim c) "?")
                     (http-error-message c)))))

(defclass oidc-discovery ()
  ((issuer :initarg :issuer :accessor oidc-issuer :initform nil)
   (authorization-endpoint :initarg :authorization-endpoint
                           :accessor oidc-authorization-endpoint :initform nil)
   (token-endpoint :initarg :token-endpoint :accessor oidc-token-endpoint :initform nil)
   (jwks-uri :initarg :jwks-uri :accessor oidc-jwks-uri :initform nil)
   (userinfo-endpoint :initarg :userinfo-endpoint
                      :accessor oidc-userinfo-endpoint :initform nil)
   (end-session-endpoint :initarg :end-session-endpoint
                         :accessor oidc-end-session-endpoint :initform nil)
   (raw :initarg :raw :accessor oidc-discovery-raw :initform nil)))

(defun oidc-discovery-p (x)
  (typep x 'oidc-discovery))

(defun oidc-discovery-url (issuer)
  (format nil "~A/.well-known/openid-configuration"
          (string-right-trim '(#\/) (string issuer))))

(defun %decode-json-source (source)
  (cond
    ((hash-table-p source) source)
    ((and (listp source) (consp (first source))) source)
    ((or (stringp source)
         (and (vectorp source) (not (stringp source))))
     (cond
       ((and (find-package :json-protocol)
             (boundp (find-symbol "*JSON-BACKEND*" :json-protocol))
             (symbol-value (find-symbol "*JSON-BACKEND*" :json-protocol)))
        (json-protocol:decode source))
       (t (http:decode-json source))))
    (t (error 'oidc-error
              :message (format nil "cannot parse OIDC JSON from ~S" (type-of source))))))

(defun %json-vec->list (value)
  (cond
    ((and (vectorp value) (not (stringp value)))
     (coerce value 'list))
    ((listp value) value)
    (t value)))

(defun parse-oidc-discovery (source)
  "Parse a discovery document (JSON string, octets, or hash-table) → OIDC-DISCOVERY."
  (let ((obj (%decode-json-source source)))
    (make-instance 'oidc-discovery
                   :issuer (%json-get obj "issuer")
                   :authorization-endpoint (%json-get obj "authorization_endpoint")
                   :token-endpoint (%json-get obj "token_endpoint")
                   :jwks-uri (%json-get obj "jwks_uri")
                   :userinfo-endpoint (%json-get obj "userinfo_endpoint")
                   :end-session-endpoint (%json-get obj "end_session_endpoint")
                   :raw obj)))

(defun %oidc-http-get (url)
  (unless *http-backend*
    (setf *http-backend* (http:ensure-http-backend)))
  (let ((res (http:get url :force-binary t)))
    (unless (http:response-ok-p res)
      (error 'oidc-error
             :status (response-status res)
             :body (ignore-errors (http:response-text res))
             :message (format nil "OIDC HTTP ~A for ~A"
                              (response-status res) url)))
    (or (ignore-errors (http:response-json res))
        (http:response-text res))))

(defun fetch-oidc-discovery (issuer &key http)
  "GET {issuer}/.well-known/openid-configuration. HTTP is (lambda (url) json-or-string)."
  (let* ((url (oidc-discovery-url issuer))
         (body (funcall (or http #'%oidc-http-get) url)))
    (parse-oidc-discovery body)))

(defun apply-oidc-discovery! (auth discovery)
  "Copy authorization/token URLs from DISCOVERY onto AUTH."
  (when (oidc-authorization-endpoint discovery)
    (setf (oauth2-authorize-url auth) (oidc-authorization-endpoint discovery)))
  (when (oidc-token-endpoint discovery)
    (setf (oauth2-token-url auth) (oidc-token-endpoint discovery)))
  auth)

(defclass jwks-cache ()
  ((uri :initarg :uri :accessor jwks-cache-uri :initform nil)
   (keys :initarg :keys :accessor jwks-cache-keys
         :initform (make-hash-table :test #'equal))
   (fetched-at :initarg :fetched-at :accessor jwks-cache-fetched-at :initform nil)))

(defun jwks-cache-p (x)
  (typep x 'jwks-cache))

(defun make-jwks-cache (&key uri keys)
  (let ((cache (make-instance 'jwks-cache :uri uri)))
    (when keys
      (jwks-cache-ingest cache keys))
    cache))

(defun jwks-cache-put (cache kid jwk)
  (setf (gethash (string kid) (jwks-cache-keys cache)) jwk)
  jwk)

(defun jwks-cache-get (cache kid)
  (gethash (string kid) (jwks-cache-keys cache)))

(defun jwks-cache-ingest (cache source)
  "Load a JWKS object (hash/alist/string) or a list of JWKs into CACHE by kid."
  (let* ((obj (if (or (stringp source) (hash-table-p source) (listp source))
                  (if (and (listp source)
                           (or (null source)
                               (hash-table-p (first source))
                               (and (consp (first source))
                                    (not (stringp (car (first source)))))))
                      source
                      (%decode-json-source source))
                  source))
         (keys (cond
                 ((hash-table-p obj)
                  (%json-vec->list (%json-get obj "keys")))
                 ((and (listp obj) (consp (first obj))
                       (%json-get obj "keys"))
                  (%json-vec->list (%json-get obj "keys")))
                 ((listp obj) obj)
                 (t nil))))
    (dolist (jwk (or keys nil) cache)
      (let ((kid (%json-get jwk "kid")))
        (when kid
          (jwks-cache-put cache kid jwk))))
    (setf (jwks-cache-fetched-at cache) (get-universal-time))
    cache))

(defun fetch-jwks (uri &key http cache)
  "GET JWKS at URI into CACHE (created if omitted). Replaces kids from the document."
  (let* ((cache (or cache (make-jwks-cache :uri uri)))
         (body (funcall (or http #'%oidc-http-get) uri)))
    (setf (jwks-cache-uri cache) (or (jwks-cache-uri cache) uri))
    (jwks-cache-ingest cache body)
    cache))

(defun %only-key (cache)
  (let ((n (hash-table-count (jwks-cache-keys cache)))
        (found nil))
    (when (= n 1)
      (maphash (lambda (k v)
                 (declare (ignore k))
                 (setf found v))
               (jwks-cache-keys cache)))
    found))

(defun %jwks-lookup (jwks kid &key http)
  (cond
    ((null jwks) nil)
    ((jwks-cache-p jwks)
     (or (and kid (jwks-cache-get jwks kid))
         (and kid (jwks-cache-uri jwks) http
              (progn
                (fetch-jwks (jwks-cache-uri jwks) :http http :cache jwks)
                (jwks-cache-get jwks kid)))
         (and (null kid) (%only-key jwks))))
    ((hash-table-p jwks)
     (%jwks-lookup (jwks-cache-ingest (make-jwks-cache) jwks) kid :http http))
    (t jwks)))

(defun %jwt-algorithm (alg)
  (let ((s (string-upcase (string alg))))
    (cond
      ((string= s "RS256") :rs256)
      ((string= s "PS256") :ps256)
      ((string= s "ES256") :es256)
      ((string= s "EDDSA") :eddsa)
      ((string= s "HS256") :hs256)
      ((string= s "HS384") :hs384)
      ((string= s "HS512") :hs512)
      (t (intern s :keyword)))))

(defun %alg-allowed-p (alg allowlist)
  (let ((name (string-upcase (string alg))))
    (member name allowlist
            :test (lambda (a b) (string= a (string-upcase (string b)))))))

(defun %as-string-list (value)
  (cond
    ((null value) nil)
    ((stringp value) (list value))
    ((and (vectorp value) (not (stringp value)))
     (map 'list #'string value))
    ((listp value) (mapcar #'string value))
    (t (list (string value)))))

(defun %aud-matches-p (expected token-aud)
  (let ((want (%as-string-list expected))
        (got (%as-string-list token-aud)))
    (some (lambda (e) (member e got :test #'string=)) want)))

(defun %claim (claims name)
  (or (cdr (assoc name claims :test #'string=))
      (cdr (assoc name claims :test #'equalp))))

(defun %jwk-as-key (jwk)
  "Return something cl-stack-jwt can verify with, or NIL."
  (cond
    ((null jwk) nil)
    ((hash-table-p jwk) nil)
    ((and (listp jwk) (consp (first jwk)) (stringp (car (first jwk))))
     nil)
    (t jwk)))

(defun validate-id-token (token &key jwks issuer audience nonce
                                  (algorithms '("RS256"))
                                  key
                                  http
                                  (verify t)
                                  (leeway 60)
                                  (now (cl-stack-jwt:unix-time)))
  "Verify TOKEN (compact JWT) and check iss/aud/nonce/exp.

   ALGORITHMS is an allowlist (default (\"RS256\")). JWKS is a JWKS-CACHE,
   a JWKS JSON object, or a single key. KEY overrides JWKS lookup.
   VERIFY NIL skips the signature (claim checks still run).
   Returns (values claims-alist header-alist)."
  (multiple-value-bind (claims header)
      (cl-stack-jwt:inspect-token token)
    (let* ((alg (%claim header "alg"))
           (kid (%claim header "kid"))
           (allow (or algorithms '("RS256"))))
      (unless (%alg-allowed-p alg allow)
        (error 'oidc-id-token-error
               :message (format nil "ID token alg ~S not in allowlist ~S" alg allow)))
      (when verify
        (let ((key (or key (%jwk-as-key (%jwks-lookup jwks kid :http http)))))
          (unless key
            (error 'oidc-id-token-error
                   :message (format nil "no verification key for kid ~S" kid)))
          (setf (values claims header)
                (cl-stack-jwt:decode (%jwt-algorithm alg) key token))))
      (when issuer
        (unless (string= (string issuer) (string (or (%claim claims "iss") "")))
          (error 'oidc-claim-error
                 :claim "iss"
                 :message (format nil "iss ~S != ~S" (%claim claims "iss") issuer))))
      (when audience
        (unless (%aud-matches-p audience (%claim claims "aud"))
          (error 'oidc-claim-error
                 :claim "aud"
                 :message (format nil "aud ~S does not include ~S"
                                  (%claim claims "aud") audience))))
      (when nonce
        (unless (string= (string nonce) (string (or (%claim claims "nonce") "")))
          (error 'oidc-claim-error
                 :claim "nonce"
                 :message (format nil "nonce ~S != ~S" (%claim claims "nonce") nonce))))
      (let ((exp (%claim claims "exp")))
        (when (and (numberp exp) (>= now (+ exp leeway)))
          (error 'oidc-claim-error
                 :claim "exp"
                 :message (format nil "token expired at ~A" exp))))
      (values claims header))))

(defun oidc-authorization-url (auth &key scope state
                                      (pkce t)
                                      nonce
                                      extra-params)
  "Authorization URL with scope containing openid and a nonce parameter."
  (let* ((scope (merge-scopes "openid" (or scope (oauth2-scope auth))))
         (nonce (or nonce (oauth2-nonce auth) (%random-state))))
    (setf (oauth2-nonce auth) nonce)
    (oauth2-authorization-uri
     auth
     :scope scope
     :state state
     :pkce pkce
     :extra-params (append (list (cons "nonce" nonce)) extra-params))))

(defun oidc-client-credentials! (auth &key scope)
  "Client-credentials grant against AUTH's token URL (OIDC token endpoint)."
  (oauth2-fetch-token! auth :grant :client-credentials :scope scope))

(defun make-oidc-auth (&rest keys &key scope &allow-other-keys)
  "MAKE-OAUTH2-AUTH with openid merged into SCOPE."
  (let ((keys (copy-list keys)))
    (setf (getf keys :scope) (merge-scopes "openid" scope))
    (apply #'make-oauth2-auth keys)))
