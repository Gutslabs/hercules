#!/bin/zsh
set -euo pipefail

TAILSCALE_APP="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
[[ -x "$TAILSCALE_APP" ]] || { echo "HATA: Tailscale.app kurulu degil" >&2; exit 1; }

# Standalone macOS Tailscale uygulamasının binary'sini pencere açmadan CLI
# modunda kullan. App Store/standalone kurulumlarında ayrı `tailscale` şart değil.
export TAILSCALE_BE_CLI=1
export TERM="${TERM:-xterm-256color}"
export TERM_PROGRAM="${TERM_PROGRAM:-Apple_Terminal}"
export PS1="${PS1:-hercules> }"

exec "$TAILSCALE_APP" "$@"
