#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 LibreCode coop and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Install FrankenPHP and put a `php` wrapper earlier on PATH so
# PhpBuiltin\RunServerListener's `php -S` becomes FrankenPHP php-server.
# CLI php (occ, behat) still uses setup-php via php.real.
# Prints the wrapper bin directory to stdout (prepend to PATH).
set -euo pipefail

DEST="${FRANKENPHP_DIR:-/tmp/libresign-frankenphp-behat}"
mkdir -p "$DEST/bin"

ARCH="$(uname -m)"
case "$ARCH" in
	x86_64|amd64) ASSET="frankenphp-linux-x86_64" ;;
	aarch64|arm64) ASSET="frankenphp-linux-aarch64" ;;
	*)
		echo "ci-setup-frankenphp-behat-server: unsupported architecture: $ARCH" >&2
		exit 1
		;;
esac

VER="${FRANKENPHP_VERSION:-1.12.7}"
if [[ ! -x "$DEST/frankenphp" ]]; then
	echo "Downloading FrankenPHP v${VER} (${ASSET})..." >&2
	curl -fsSL -o "$DEST/frankenphp" \
		"https://github.com/php/frankenphp/releases/download/v${VER}/${ASSET}"
	chmod +x "$DEST/frankenphp"
fi

REAL_PHP="$(command -v php)"
if [[ -z "$REAL_PHP" ]]; then
	echo "ci-setup-frankenphp-behat-server: php not found on PATH" >&2
	exit 1
fi
ln -sfn "$REAL_PHP" "$DEST/bin/php.real"

cat >"$DEST/bin/php" <<'WRAP'
#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 LibreCode coop and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
if [[ "${1:-}" == "-S" ]]; then
	LISTEN="${2:?php -S requires host:port}"
	ROOT="."
	shift 2
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-t)
				ROOT="${2:?}"
				shift 2
				;;
			*)
				shift
				;;
		esac
	done
	# escapeshellarg() may quote the document root
	ROOT="${ROOT#\'}"
	ROOT="${ROOT%\'}"
	FRANKENPHP="$(cd "$(dirname "$0")/.." && pwd)/frankenphp"
	# Keep argv0 looking like php -S so leftover-process scans still match.
	exec -a "php -S ${LISTEN}" "$FRANKENPHP" php-server --listen="$LISTEN" --root="$ROOT"
fi
exec "$(dirname "$0")/php.real" "$@"
WRAP
chmod +x "$DEST/bin/php"

# RunServerListener prefers PHP_BINARY over PATH php. Force PATH so the wrapper
# is the binary used for `php -S` without changing committed vendor code.
LISTENER=""
if [[ -f vendor/libresign/behat-builtin-extension/src/RunServerListener.php ]]; then
	LISTENER="vendor/libresign/behat-builtin-extension/src/RunServerListener.php"
elif [[ -f vendor/phpbuiltin/server/src/RunServerListener.php ]]; then
	LISTENER="vendor/phpbuiltin/server/src/RunServerListener.php"
fi
if [[ -n "$LISTENER" ]]; then
	python3 - "$LISTENER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
old = "$php = PHP_BINARY !== '' && is_file(PHP_BINARY) ? escapeshellarg(PHP_BINARY) : 'php';"
new = "$php = 'php';"
if old not in text:
	raise SystemExit(f"ci-setup-frankenphp-behat-server: {path} no longer selects PHP_BINARY; update the wrapper")
path.write_text(text.replace(old, new, 1))
PY
fi

echo "$DEST/bin"
