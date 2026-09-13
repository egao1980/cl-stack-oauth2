# cl-stack-oauth2

OAuth2 + OIDC token flows for [`cl-stack-http`](https://github.com/egao1980/cl-stack-http) —
analogue of `requests-oauthlib` / Authlib client helpers.

Package: `cl-stack-oauth2` (nick `stack-oauth2`). **OCI: 0.2.0.**

Implements the cl-stack-http CLOS auth protocol (`prepare-auth` /
`handle-auth-response`): pass `oauth2-auth` as `:auth` for bearer get → refresh →
401 retry.

JWT create/verify → [`cl-stack-jwt`](https://github.com/egao1980/cl-stack-jwt)
(jose), not here.

## Install

```lisp
(cl-repo:load-system "cl-stack-http" :version "0.1.6")
(cl-repo:load-system "cl-stack-oauth2" :version "0.2.0")
```

OCI: `ghcr.io/egao1980/cl-systems/cl-stack-oauth2:0.2.0`

Requires `cl-stack-http` **≥ 0.1.1** (CLOS auth protocol).

## Scopes

RFC 6749 §3.3: space-delimited strings. API accepts **string or list**; stored
normalized.

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

Also: `oauth2-authorization-uri`, `oauth2-exchange-code!`, `oauth2-revoke!`
(RFC 7009), custom `:get-token-fn` / `:refresh-fn`.

## OIDC

Discovery, JWKS (`kid` cache), and ID-token validation via
[`cl-stack-jwt`](https://github.com/egao1980/cl-stack-jwt). Default `alg`
allowlist is `("RS256")`. SCIM is not implemented.

```lisp
(defvar *disc*
  (stack-oauth2:fetch-oidc-discovery "https://idp.example"))

(defvar *auth*
  (stack-oauth2:make-oidc-auth
   :client-id "cid" :redirect-uri "https://app/cb"
   :scope "profile"))
(stack-oauth2:apply-oidc-discovery! *auth* *disc*)
(stack-oauth2:oidc-authorization-url *auth* :pkce t)
;; → scope includes openid, nonce is stored on AUTH

(stack-oauth2:validate-id-token
 id-token
 :jwks (stack-oauth2:fetch-jwks (stack-oauth2:oidc-jwks-uri *disc*))
 :issuer (stack-oauth2:oidc-issuer *disc*)
 :audience "cid"
 :nonce (stack-oauth2:oauth2-nonce *auth*))
```

`oidc-client-credentials!` is a thin wrapper around the existing
client-credentials grant. Token responses may populate `oauth2-id-token`.

## Quick start

```lisp
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

## Publish

Source-only OCI publish is centralized in [`cl-stack-systems`](https://github.com/egao1980/cl-stack-systems)
(`imports/cl-stack-oauth2/qlfile` pin + shared `publish.yml`). Packaging metadata lives in the `.asd`
(`auto-package-spec`):

```bash
gh workflow run publish.yml -R egao1980/cl-stack-systems -f import=cl-stack-oauth2
```

## License

MIT
