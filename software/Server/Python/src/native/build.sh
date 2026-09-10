#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp "$here/.libmsxpi_gpio.XXXXXX.so")"
trap 'rm -f "$tmp"' EXIT
"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared \
    "$here/gpio_transfer.c" -o "$tmp"
# Refuse an old source/library before replacing the installed engine.
if ! "${NM:-nm}" -D --defined-only "$tmp" | awk '
    $3 == "msxpi_gpio_transfer" { ordinary=1 }
    $3 == "msxpi_gpio_burst" { burst=1 }
    END { exit !(ordinary && burst) }
'; then
    echo "Native build is missing required exports. Copy the updated native/gpio_transfer.c and rebuild." >&2
    exit 1
fi
mv -f "$tmp" "$here/libmsxpi_gpio.so"
echo "Built $here/libmsxpi_gpio.so for $(uname -m) (transfer + burst exports verified)"
