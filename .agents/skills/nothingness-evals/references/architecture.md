# Architecture

The image is built from a generated context containing only evaluator Docker files, the ten committed Opus files plus manifest, and an operator-supplied Pi artifact. It never receives repository source.

`prepare-run` exports fixture `5fc7e04`, initializes a one-commit Git baseline, creates a fresh internal Docker network, then creates a candidate container with all Linux capabilities dropped and `no-new-privileges`. The candidate joins only that network and receives non-secret `HTTP_PROXY`, `HTTPS_PROXY`, and localhost-only `NO_PROXY` settings. A second, equally restricted Python proxy sidecar joins the internal network and Docker bridge; it allows HTTPS CONNECT only to the hostname derived from the selected provider's `baseUrl` in host Pi configuration, rejects literal IPs and other ports, and does not log requests. noVNC is still published from the candidate on `127.0.0.1` only.

Provider credentials are never stored in Docker container configuration. `launch-candidate` sends the allowlisted values over stdin to a short-lived Python bootstrap; only the candidate worker inherits them. Task manifests declare the internal-proxy allowlist policy; `run.json` records hostnames and policy but never credential values.

The container has isolated HOME, XDG, Pi session, drive, and app-data paths under `/run/nothingness`. Candidate source and app launch remain the candidate's responsibility.