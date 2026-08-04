(in-package #:cl-stack-oauth2)

;;; RFC 6749 §3.3 — scope is a space-delimited list of case-sensitive strings.

(defun parse-scope (scope)
  "SCOPE (string | list | NIL) → list of non-empty scope tokens (order preserved, deduped)."
  (cond
    ((null scope) nil)
    ((listp scope)
     (remove-duplicates
      (remove "" (mapcar (lambda (s) (string-trim '(#\Space #\Tab) (string s)))
                         scope)
              :test #'string=)
      :test #'string=
      :from-end t))
    ((stringp scope)
     (parse-scope (remove "" (uiop:split-string scope :separator '(#\Space #\Tab))
                          :test #'string=)))
    (t (error 'oauth2-error
              :message (format nil "invalid scope ~S (want string or list)" scope)))))

(defun scope-list (scope)
  "Alias for PARSE-SCOPE."
  (parse-scope scope))

(defun scope-string (scope)
  "SCOPE → RFC space-delimited string, or NIL if empty."
  (let ((parts (parse-scope scope)))
    (when parts
      (format nil "~{~A~^ ~}" parts))))

(defun normalize-scope (scope)
  "Canonical space-delimited scope string, or NIL."
  (scope-string scope))

(defun scope-subset-p (requested granted)
  "T when every token in REQUESTED appears in GRANTED (both string|list|NIL).
   Empty requested is always a subset."
  (let ((req (parse-scope requested))
        (got (parse-scope granted)))
    (every (lambda (s) (member s got :test #'string=)) req)))

(defun merge-scopes (&rest scopes)
  "Union of SCOPES (string|list|NIL), first-seen order."
  (scope-string
   (reduce (lambda (a b) (append a (parse-scope b)))
           scopes
           :initial-value nil)))
