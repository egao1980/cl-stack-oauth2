# cl-stack-oauth2

OAuth2 token flows for [`cl-stack-http`](https://github.com/egao1980/cl-stack-http) — analogue of
`requests-oauthlib` / Authlib client helpers.

Package: `cl-stack-oauth2` (nick `stack-oauth2`).

Implements the cl-stack-http CLOS auth protocol (`prepare-auth` / `handle-auth-response`):
pass `oauth2-auth` as `:auth` for bearer get → refresh → 401 retry.

JWT create/verify → [`cl-stack-jwt`](https://github.com/egao1980/cl-stack-jwt) (jose), not here.

## Scopes

RFC 6749 §3.3: space-delimited strings. API accepts **string or list**; stored normalized.

```lisp
(make-oauth2-auth :scope '("openid" "profile" "api.read"))
;; ≡ :scope "openid profile api.read"

(normalize-scope "  a   b ") ; => "a b"
(parse-scope "a b")          ; => ("a" "b")
(scope-subset-p "a" "a b c") ; => T

;; Token response `scope` → oauth2-granted-scope
```

## Grants

| Grant | Keys |
|-------|------|
| `:client-credentials` | `:client-id` / `:client-secret`, optional `:scope` `:audience` `:resource` |
| `:password` | `:username` `:password` + client |
| `:refresh-token` | `:refresh-token`; optional narrower `:scope` |
| `:authorization-code` | `:code` `:redirect-uri`; PKCE `:code-verifier` |

`:client-auth` — `:basic` (default) | `:body` (`client_secret_post`) | `:none`

`:resource` — RFC 8707 (string or list; repeated query/form fields).

## Quick start

```lisp
(ql:quickload '(:cl-stack-http :cl-stack-oauth2))

(defvar *auth*
  (stack-oauth2:make-oauth2-auth
   :token-url "https://as.example/oauth/token"
   :client-id "cid" :client-secret "sec"
   :scope '("api.read" "api.write")
   :grant :client-credentials))

(stack-http:with-backend (:dexador)
  (stack-http:get "https://api.example/v1/me" :auth *auth*))
```

### Auth code + PKCE

```lisp
(defvar *auth*
  (stack-oauth2:make-oauth2-auth
   :authorize-url "https://as.example/authorize"
   :token-url "https://as.example/token"
   :client-id "cid"
   :redirect-uri "https://app/cb"
   :scope "openid profile"))

(stack-oauth2:oauth2-authorization-uri *auth* :pkce t)
;; redirect user → callback with ?code=&state=
(stack-oauth2:oauth2-exchange-code! *auth* :code "…")
```

## Install

```lisp
(cl-repo:load-system "cl-stack-oauth2" :version "0.1.0")
```

OCI: `ghcr.io/egao1980/cl-systems/cl-stack-oauth2:0.1.0` (after publish).
