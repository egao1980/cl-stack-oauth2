(in-package #:cl-stack-oauth2)

(define-condition oauth2-error (http-protocol-error)
  ((status :initarg :status :reader oauth2-error-status :initform nil)
   (body :initarg :body :reader oauth2-error-body :initform nil))
  (:report (lambda (c s)
             (format s "OAuth2 error~@[ (HTTP ~A)~]: ~A"
                     (oauth2-error-status c)
                     (http-error-message c)))))

(defun oauth2-error-message (c)
  (http-error-message c))

(defclass oauth2-auth (http:auth-object)
  ((access-token :initarg :access-token :accessor oauth2-access-token :initform nil)
   (refresh-token :initarg :refresh-token :accessor oauth2-refresh-token :initform nil)
   (token-type :initarg :token-type :accessor oauth2-token-type :initform "Bearer")
   (expires-at :initarg :expires-at :accessor oauth2-expires-at :initform nil
               :documentation "Universal time when access-token expires.")
   (token-url :initarg :token-url :accessor oauth2-token-url :initform nil)
   (authorize-url :initarg :authorize-url :accessor oauth2-authorize-url :initform nil)
   (revoke-url :initarg :revoke-url :accessor oauth2-revoke-url :initform nil)
   (client-id :initarg :client-id :accessor oauth2-client-id :initform nil)
   (client-secret :initarg :client-secret :accessor oauth2-client-secret :initform nil)
   (client-auth :initarg :client-auth :accessor oauth2-client-auth :initform :basic
                :documentation ":basic (default) | :body (client_secret_post) | :none")
   (username :initarg :username :accessor oauth2-username :initform nil)
   (password :initarg :password :accessor oauth2-password :initform nil)
   (scope :initarg :scope :accessor oauth2-scope :initform nil
          :documentation "Requested scope (string | list of strings).")
   (granted-scope :initarg :granted-scope :accessor oauth2-granted-scope :initform nil
                  :documentation "Scope granted by AS (from token response).")
   (audience :initarg :audience :accessor oauth2-audience :initform nil
             :documentation "Optional audience (Auth0 / some OIDC ASes).")
   (resource :initarg :resource :accessor oauth2-resource :initform nil
             :documentation "RFC 8707 resource indicator (string | list).")
   (redirect-uri :initarg :redirect-uri :accessor oauth2-redirect-uri :initform nil)
   (code :initarg :code :accessor oauth2-code :initform nil)
   (code-verifier :initarg :code-verifier :accessor oauth2-code-verifier :initform nil)
   (state :initarg :state :accessor oauth2-state :initform nil)
   (grant :initarg :grant :accessor oauth2-grant :initform nil
          :documentation ":client-credentials | :password | :refresh-token | :authorization-code | NIL (auto).")
   (extra-params :initarg :extra-params :accessor oauth2-extra-params :initform nil
                 :documentation "Extra form/query fields (alist of string keys).")
   (get-token-fn :initarg :get-token-fn :accessor oauth2-get-token-fn :initform nil)
   (refresh-fn :initarg :refresh-fn :accessor oauth2-refresh-fn :initform nil)
   (leeway :initarg :leeway :accessor oauth2-leeway :initform 60
           :documentation "Seconds before expires-at to treat token as expired."))
  (:documentation
   "OAuth2 credentials for cl-stack-http CLOS auth protocol.
    Pass as :AUTH to REQUEST / MAKE-SESSION. Auto-fetches, refreshes, retries 401.
    Scopes: use string or list; stored normalized; GRANTED-SCOPE from token response.
    JWT create/verify → cl-stack-jwt."))

(defun oauth2-auth-p (x) (typep x 'oauth2-auth))

(defun make-oauth2-auth (&rest keys
                         &key access-token refresh-token token-type expires-at expires-in
                           token-url authorize-url revoke-url
                           client-id client-secret client-auth
                           username password
                           scope granted-scope audience resource
                           redirect-uri code code-verifier state
                           grant extra-params
                           get-token-fn refresh-fn leeway
                         &allow-other-keys)
  "Build OAUTH2-AUTH. SCOPE may be string or list. EXPIRES-IN sets EXPIRES-AT from now."
  (declare (ignore access-token refresh-token token-type expires-at token-url
                   authorize-url revoke-url client-id client-secret client-auth
                   username password scope granted-scope audience resource
                   redirect-uri code code-verifier state grant extra-params
                   get-token-fn refresh-fn leeway))
  (let* ((keys (copy-list keys))
         (expires-in (getf keys :expires-in))
         (scope (getf keys :scope))
         (granted (getf keys :granted-scope)))
    (remf keys :expires-in)
    (when scope
      (setf (getf keys :scope) (normalize-scope scope)))
    (when granted
      (setf (getf keys :granted-scope) (normalize-scope granted)))
    (let ((auth (apply #'make-instance 'oauth2-auth keys)))
      (when expires-in
        (setf (oauth2-expires-at auth) (+ (get-universal-time) (round expires-in))))
      auth)))

(defun oauth2-expired-p (auth &optional (now (get-universal-time)))
  (cond
    ((null (oauth2-access-token auth)) t)
    ((null (oauth2-expires-at auth)) nil)
    (t (<= (oauth2-expires-at auth) (+ now (oauth2-leeway auth))))))

(defun oauth2-bearer-auth (auth)
  (let ((tok (oauth2-access-token auth)))
    (unless tok
      (error 'oauth2-error :message "oauth2-auth has no access-token"))
    (list :bearer tok)))
