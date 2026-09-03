#!/bin/sh
# Container entrypoint: turn a runtime-provided OKF bundle into a static site
# and serve it.
#
#   1. an initContainer (or a volume mount) places an OKF bundle at $BUNDLE_DIR
#   2. we assemble a Hugo project in $SRC_DIR: baked skeleton + the bundle as
#      content, applying the OKF -> Hugo fixups
#   3. `hugo` builds $PUBLIC_DIR
#   4. Caddy serves $PUBLIC_DIR on $PORT
#
# Everything is configurable by env so the same image works for any bundle,
# and $SRC_DIR / $PUBLIC_DIR / /tmp can all be emptyDir mounts with a
# read-only root filesystem.
set -eu

TEMPLATE_DIR="${TEMPLATE_DIR:-/app}"   # baked site skeleton (hugo.toml, layouts, assets)
SRC_DIR="${SRC_DIR:-/work}"            # assembled Hugo project (writable)
BUNDLE_DIR="${BUNDLE_DIR:-/bundle}"    # OKF bundle, placed here by an initContainer
BUNDLE_SUBDIR="${BUNDLE_SUBDIR:-}"     # set if the bundle lives in a subdir of the repo
CONTENT_DIR="${CONTENT_DIR:-$SRC_DIR/content}"
PUBLIC_DIR="${PUBLIC_DIR:-$SRC_DIR/public}"
PORT="${PORT:-8080}"
BASE_URL="${HUGO_BASEURL:-http://localhost:${PORT}/}"

# Assemble the project skeleton into the writable work dir (skip in local dev
# where TEMPLATE_DIR and SRC_DIR are the same checkout).
if [ -d "$TEMPLATE_DIR" ] && [ "$TEMPLATE_DIR" != "$SRC_DIR" ]; then
  mkdir -p "$SRC_DIR"
  cp -a "$TEMPLATE_DIR/." "$SRC_DIR/"
fi

src="$BUNDLE_DIR"
[ -n "$BUNDLE_SUBDIR" ] && src="$BUNDLE_DIR/$BUNDLE_SUBDIR"

if [ ! -d "$src" ] || [ -z "$(ls -A "$src" 2>/dev/null || true)" ]; then
  echo "entrypoint: no OKF bundle found at '$src'." >&2
  echo "entrypoint: an initContainer must clone/download the bundle there first." >&2
  exit 1
fi

echo "entrypoint: staging bundle from '$src' -> '$CONTENT_DIR'"
rm -rf "$CONTENT_DIR"
mkdir -p "$CONTENT_DIR"
cp -a "$src/." "$CONTENT_DIR/"

# Drop VCS / CI cruft a cloned bundle may carry.
find "$CONTENT_DIR" -maxdepth 2 -name '.git' -prune -exec rm -rf {} + 2>/dev/null || true
rm -f "$CONTENT_DIR/.gitignore" "$CONTENT_DIR/.gitattributes"

# OKF <-> Hugo fixup: OKF's `index.md` is a *branch listing* (siblings are
# separate concepts). Hugo treats a dir containing `index.md` as a leaf
# bundle and will not render those siblings as pages. `_index.md` is Hugo's
# branch page and renders equivalently for our purposes.
find "$CONTENT_DIR" -type f -name 'index.md' -exec sh -c '
  for f do mv "$f" "$(dirname "$f")/_index.md"; done
' sh {} +
echo "entrypoint: normalised index.md -> _index.md where present"

# Hugo reads HUGO_-prefixed env vars as config keys; OKF_TITLE overrides the
# site title without a config file.
[ -n "${OKF_TITLE:-}" ] && export HUGO_TITLE="$OKF_TITLE"

echo "entrypoint: building site (baseURL=$BASE_URL)"
hugo --source "$SRC_DIR" --destination "$PUBLIC_DIR" \
     --baseURL "$BASE_URL" --minify --gc --cleanDestinationDir --logLevel info

echo "entrypoint: serving '$PUBLIC_DIR' on :$PORT"
exec caddy file-server --root "$PUBLIC_DIR" --listen ":$PORT" --access-log
