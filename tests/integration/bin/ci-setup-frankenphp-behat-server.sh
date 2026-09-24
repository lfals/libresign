#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 LibreCode coop and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Install FrankenPHP and put a `php` wrapper earlier on PATH so PhpBuiltin\RunServerListener's
# `php -S` invocation becomes FrankenPHP instead of the experimental built-in server.
# Prints the wrapper bin directory (prepend to PATH). Safe to re-run.
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
	# escapeshellarg may quote the document root
	ROOT="${ROOT#\'}"
	ROOT="${ROOT%\'}"
	FRANKENPHP="$(cd "$(dirname "$0")/.." && pwd)/frankenphp"
	# Keep argv0 looking like php -S so RunServerListener killZombies can find leftovers.
	exec -a "php -S ${LISTEN}" "$FRANKENPHP" php-server --listen="$LISTEN" --root="$ROOT"
fi
exec "$(dirname "$0")/php.real" "$@"
WRAP
chmod +x "$DEST/bin/php"

# Also match frankenphp in killZombies (idempotent).
LISTENER=""
if [[ -f vendor/libresign/behat-builtin-extension/src/RunServerListener.php ]]; then
	LISTENER="vendor/libresign/behat-builtin-extension/src/RunServerListener.php"
elif [[ -f vendor/phpbuiltin/server/src/RunServerListener.php ]]; then
	LISTENER="vendor/phpbuiltin/server/src/RunServerListener.php"
fi
if [[ -n "$LISTENER" ]] && grep -q 'grep "php -S ' "$LISTENER"; then
	sed -i.bak 's/grep "php -S /grep -E "php -S|frankenphp php-server /' "$LISTENER"
fi

echo "$DEST/bin"
