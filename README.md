# okf-hugo

A generic **[OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
(Open Knowledge Format) renderer** built on Hugo.

The image contains **no bundle**. An OKF bundle — a directory of Markdown files with YAML
frontmatter, cross-linked with plain Markdown links — is supplied at runtime (typically by
a Kubernetes initContainer that clones a git repo), transformed, built into a static site,
and served by Caddy.

## How it works

```
initContainer clones bundle ──▶ /bundle (emptyDir)
                                   │
                          entrypoint.sh
                                   │  copy baked skeleton (/app) ─▶ /work
                                   │  copy bundle ─▶ /work/content
                                   │  rename index.md ─▶ _index.md   (OKF branch node ≠ Hugo leaf bundle)
                                   │  hugo --minify ─▶ /work/public
                                   ▼
                          caddy file-server :8080  ─▶ /work/public
```

Rendering specifics:

- **`type`** (the only required OKF frontmatter field) and the recommended/optional fields
  (`title`, `description`, `resource`, `tags`, `status`, `generated`, `verified`, `sources`,
  `usage_window`, `stale_after`) are rendered as a metadata panel on each concept.
- OKF cross-links `[x](/tables/customers.md)` are resolved to real URLs; unresolved targets
  are visibly marked and logged as build warnings.
- A "Referenced by" (backlinks) section is derived from the link graph.
- One generic layout renders every `type`. Per-type layouts can be added later as
  `layouts/<Type>/page.html`.

See [CLAUDE.md](./CLAUDE.md) for the architecture in detail.

## Build the image

```sh
docker build -t your-registry/okf-hugo:latest .
docker push your-registry/okf-hugo:latest
```

Build args: `HUGO_VERSION` (default `0.162.1`), `CADDY_VERSION` (default `2`).

### CI

`.github/workflows/docker.yml` builds `linux/amd64` + `linux/arm64` and pushes to
Docker Hub as `docker.io/<user>/okf-hugo` on every push to the default branch (tag
`latest` + `sha-…`) and on `v*` tags (semver tags). Pull requests build only.

Configure once in the repo settings:

- **Variable** `DOCKERHUB_USERNAME` — your Docker Hub username.
- **Secret** `DOCKERHUB_TOKEN` — a Docker Hub access token with Read/Write.

## Run locally

```sh
docker run --rm -p 8080:8080 \
  -v "$PWD/some-okf-bundle:/bundle:ro" \
  -e HUGO_BASEURL=http://localhost:8080/ \
  -e OKF_TITLE="My Bundle" \
  your-registry/okf-hugo:latest
```

Or without Docker, against a checkout (needs `hugo` extended ≥ 0.146 and `caddy` on `PATH`):

```sh
SRC_DIR="$PWD" TEMPLATE_DIR="$PWD" BUNDLE_DIR="$PWD/some-okf-bundle" \
  HUGO_BASEURL=http://localhost:8080/ ./entrypoint.sh
```

## Configuration

All via environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `HUGO_BASEURL` | `http://localhost:8080/` | Public base URL. **Set this in production** — Hugo bakes it into links. |
| `OKF_TITLE` | *(Hugo config)* | Site title shown in the header and `<title>`. |
| `BUNDLE_DIR` | `/bundle` | Where the bundle is expected. |
| `BUNDLE_SUBDIR` | *(empty)* | Set if the bundle lives in a subdirectory of the cloned repo. |
| `PORT` | `8080` | Port Caddy listens on. |
| `SRC_DIR` | `/work` | Writable work dir (mount an `emptyDir` here). |
| `TEMPLATE_DIR` | `/app` | Baked skeleton; don't change in the container. |

The container runs as UID 65532, needs no privileges, and works with a read-only root
filesystem given `emptyDir` mounts at `/work` and `/tmp`.

## Example Kubernetes manifest

Bundle source is held in a `ConfigMap`; the initContainer clones it into a per-Pod
`emptyDir`. Rolling the Deployment (`kubectl rollout restart deployment/okf-hugo`)
re-clones and rebuilds — that's how you pick up bundle updates.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: okf-hugo
spec:
  selector:
    matchLabels:
      app: okf-hugo
  template:
    metadata:
      labels:
        app: okf-hugo
    spec:
      initContainers:
        - name: clone-bundle
          image: alpine/git:2.45.2
          args:
            - clone
            - --depth=1
            - https://github.com/your-org/your-okf-bundle.git
            - /bundle
          volumeMounts:
            - name: bundle
              mountPath: /bundle
      containers:
        - name: renderer
          image: your-registry/okf-hugo:latest
          env:
            - name: HUGO_BASEURL
              value: https://knowledge.example.org/
            - name: OKF_TITLE
              value: "Acme Knowledge"
          volumeMounts:
            - name: bundle
              mountPath: /bundle
              readOnly: true
      volumes:
        - name: bundle
          emptyDir:
            medium: ""
```

`kubectl rollout restart deployment/okf-hugo` re-clones and rebuilds. Expose it with a
`Service` (targeting port `8080`) plus an `Ingress` whose host matches `HUGO_BASEURL`.

For a hardened variant (read-only root filesystem, dropped capabilities, probes,
resource limits) you need `emptyDir` mounts at `/work` and `/tmp` as well.
