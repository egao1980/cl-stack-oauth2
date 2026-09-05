(in-package #:cl-stack-oauth2)

;;; RFC 7636 — PKCE (S256).

(defun %b64url-octets (octets)
  (encoding-protocol:encode octets :encoding :base64url :pad nil))

(defun %random-verifier (&optional (nbytes 32))
  "High-entropy code_verifier (43–128 chars base64url)."
  (%b64url-octets (secrets-protocol:random-bytes nbytes)))

(defun make-pkce (&key (verifier nil) (method :s256))
  "Return plist (:verifier :challenge :method). METHOD is :S256 (default) or :PLAIN."
  (let* ((verifier (or verifier (%random-verifier)))
         (method (alex:make-keyword (string-upcase (string method))))
         (challenge
           (ecase method
             (:s256
              (%b64url-octets
               (crypto-protocol:digest
                (encoding-protocol:encode verifier)
                :algorithm :sha256)))
             (:plain verifier))))
    (list :verifier verifier
          :challenge challenge
          :method (ecase method (:s256 "S256") (:plain "plain")))))

(defun pkce-verifier (pkce) (getf pkce :verifier))
(defun pkce-challenge (pkce) (getf pkce :challenge))
(defun pkce-method (pkce) (getf pkce :method))
