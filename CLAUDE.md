# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **content-less Hugo site** that acts as a generic renderer for OKF ([Open Knowledge
Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md))
bundles. No bundle ships in this repo or in the built image. At runtime an OKF bundle
(a directory of Markdown files with YAML frontmatter, cross-linked with plain Markdown
links) is cloned into place, transformed, and served as a static site.

Deployment target: a Docker image deployed to Kubernetes, where an initContainer clones
a bundle into a shared volume before this container starts.

## Runtime pipeline (`entrypoint.sh`)

1. Expect an OKF bundle at `$BUNDLE_DIR` (default `/bundle`), optionally under `$BUNDLE_SUBDIR`.
2. Copy it into `$CONTENT_DIR` (default `/src/content`), stripping `.git`, `.gitignore`, `.gitattributes`.
3. **Rename every `index.md` → `_index.md`** (see OKF↔Hugo mismatch below).
4. `hugo --minify --gc` → `$PUBLIC_DIR` (default `/src/public`), with `--baseURL "$HUGO_BASEURL"`.
5. `exec caddy file-server` on `$PORT` (default 8080).

Env knobs: `HUGO_BASEURL` (per-deployment, required in prod), `OKF_TITLE` (exported as
`HUGO_TITLE`), `BUNDLE_DIR`, `BUNDLE_SUBDIR`, `CONTENT_DIR`, `PUBLIC_DIR`, `SRC_DIR`, `PORT`.

## OKF ↔ Hugo impedance mismatch — the core design constraint

- **`index.md` is reserved differently.** In OKF it is a *branch listing* with first-class
  concept siblings. In Hugo, a directory containing `index.md` is a *leaf bundle*: siblings
  stop being pages and become resources with no URL. So `entrypoint.sh` renames
  `index.md` → `_index.md` (Hugo's branch/section page). Never author `_index.md` as
  repo content — `content/` is disposable staging, regenerated every container start.
- **Cross-links are `[text](/path/to/concept.md)`.** Hugo does not resolve `.md` links by
  default. `layouts/_markup/render-link.html` rewrites them to rendered URLs (handling
  `/x/index.md` → section `/x/`, fragments, relative paths) and marks unresolved targets
  with `class="link-missing"` + a `warnf`.
- **Concept ID** = file path minus `.md` (`/tables/customers.md` → `tables/customers`).

## Layouts

Uses Hugo's **new template system** (requires Hugo ≥ 0.146; this repo targets **0.162.1
extended**). Flat `layouts/*.html`, partials in `layouts/_partials/`, render hooks in
`layouts/_markup/`.

- **Generic, not per-type.** One `page.html` / `section.html` renders every OKF `type`.
  Adding per-type layouts later means `layouts/<Type>/page.html` with these as fallback.
- `_partials/okf-meta.html` — renders the OKF frontmatter families (`type`, `status`,
  `resource`, `tags`, and the trust/provenance/lifecycle fields: `generated`, `verified`,
  `sources`, `usage_window`, `stale_after`) as a metadata panel.
- `_partials/backlinks.html` — builds a site-wide source→target link index by regex over
  every page's `.RawContent`, caches it on `site.Store` (`okf_backlinks`), renders
  "Referenced by".
- `_partials/nav.html` + `nav-branch.html` — recursive bundle tree in the sidebar.
- Use `.LinkTitle`, never `.File.BaseFileName` — auto-created section pages (a dir with
  no `_index.md`) have a nil `.File`.

## `hugo.toml` choices that matter

- `refLinksErrorLevel = "warning"` — a bundle we don't control may ship dead links;
  don't fail the build on them.
- `markup.goldmark.renderer.unsafe = true` — OKF bundles are curated/trusted; allow raw HTML.
- `baseURL` in the file is only a local-dev placeholder; production value comes from `--baseURL`.

## Commands

```sh
# Local dev against a sample bundle (Hugo needs content to serve):
mkdir -p content && cp -a path/to/some-okf-bundle/. content/
find content -type f -name index.md -exec sh -c 'for f do mv "$f" "$(dirname "$f")/_index.md"; done' sh {} +
hugo server -D                        # http://localhost:1313/

# One-off production-style build:
hugo --minify --gc --baseURL https://example.org/

# Exercise the full runtime path locally (needs hugo + caddy on PATH):
SRC_DIR=$PWD BUNDLE_DIR=path/to/bundle HUGO_BASEURL=http://localhost:8080/ ./entrypoint.sh

# Clean regenerated artifacts:
rm -rf content public resources .hugo_build.lock
```

There is no test suite, linter, or Makefile. "Does it work" = `hugo` exits 0 and the
expected URLs appear under `public/`.

## Notes for changes

- `content/`, `public/`, `resources/` are all build artifacts — keep them out of commits
  and out of the image (`.gitignore` / `.dockerignore`). Note: the initial commit
  mistakenly tracked a stale `public/` (old ananke build) and `.hugo_build.lock`; remove
  them if you touch that area.
- The ananke theme was removed; this project has no theme and no submodules.
