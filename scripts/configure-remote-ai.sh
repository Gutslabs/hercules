#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
APP_PATH="/Applications/Apps/Hercules.app"
APP_SUPPORT="$HOME/Library/Application Support/Hercules"
CONFIG="$APP_SUPPORT/remote-ai.plist"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.samorai.hercules.remote-ai.plist"
LOCAL_URL="http://127.0.0.1:8765"
SERVE_PATH="/hercules-ai"

[[ -d "$APP_PATH" ]] || {
  echo "HATA: $APP_PATH bulunamadi. Once ./scripts/mac-build-install.sh Debug calistir." >&2
  exit 1
}

status_json=$("$SCRIPT_DIR/tailscale-cli.sh" status --json)
fields=$(print -r -- "$status_json" | /usr/bin/python3 -c '
import json, sys
s = json.load(sys.stdin)
me = s.get("Self", {})
user = s.get("User", {}).get(str(me.get("UserID")), {}).get("LoginName", "")
dns = str(me.get("DNSName", "")).rstrip(".")
if s.get("BackendState") != "Running" or not user or not dns:
    raise SystemExit(2)
print(user)
print(dns)
') || {
  echo "HATA: Tailscale Running degil veya kullanici/DNS okunamadi." >&2
  exit 2
}
user=${${(f)fields}[1]:-}
dns=${${(f)fields}[2]:-}
user=${user:l}

mkdir -p "$APP_SUPPORT" "$HOME/Library/LaunchAgents"
chmod 700 "$APP_SUPPORT"
rm -f "$CONFIG"
/usr/bin/plutil -create xml1 "$CONFIG"
/usr/bin/plutil -insert Enabled -bool true "$CONFIG"
/usr/bin/plutil -insert AllowedUsers -array "$CONFIG"
/usr/bin/plutil -insert AllowedUsers.0 -string "$user" "$CONFIG"
/usr/bin/plutil -insert DNSName -string "$dns" "$CONFIG"
chmod 600 "$CONFIG"

# Kullanıcı oturum açtığında Hercules'ı bir kez başlat. Bilgisayarı awake tutma
# işi ayrı uygulamada; bu agent yalnız AI endpoint'inin yeniden hazır olmasını sağlar.
rm -f "$LAUNCH_AGENT"
/usr/bin/plutil -create xml1 "$LAUNCH_AGENT"
/usr/bin/plutil -insert Label -string "com.samorai.hercules.remote-ai" "$LAUNCH_AGENT"
/usr/bin/plutil -insert ProgramArguments -array "$LAUNCH_AGENT"
/usr/bin/plutil -insert ProgramArguments.0 -string "/usr/bin/open" "$LAUNCH_AGENT"
/usr/bin/plutil -insert ProgramArguments.1 -string "-gja" "$LAUNCH_AGENT"
/usr/bin/plutil -insert ProgramArguments.2 -string "$APP_PATH" "$LAUNCH_AGENT"
/usr/bin/plutil -insert RunAtLoad -bool true "$LAUNCH_AGENT"
# `open` hemen sonlandığı için KeepAlive yeniden başlatma döngüsü yaratır. Dakikada
# bir sessiz yoklama zaten açık uygulamada no-op, kapanmış uygulamada yeniden açılıştır.
/usr/bin/plutil -insert StartInterval -integer 60 "$LAUNCH_AGENT"
chmod 600 "$LAUNCH_AGENT"
/bin/launchctl bootout "gui/$UID/com.samorai.hercules.remote-ai" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT"

/usr/bin/open -gja "$APP_PATH"
local_ready=false
for _ in {1..40}; do
  if /usr/bin/curl -fsS --max-time 1 "$LOCAL_URL/health" >/dev/null 2>&1; then
    local_ready=true
    break
  fi
  sleep 0.25
done
[[ "$local_ready" == "true" ]] || {
  echo "HATA: Hercules acildi ama $LOCAL_URL/health hazir olmadi." >&2
  echo "Uygulamanin guncel build oldugunu ve 8765 portunu baska surecin kullanmadigini kontrol et." >&2
  exit 3
}

# Mevcut Serve kökünü sıfırlama: Robinhood/MintOps '/' yolunda kalır. Yalnız
# Hercules alt yolunu ekle veya güncelle.
"$SCRIPT_DIR/tailscale-cli.sh" serve --yes --bg --set-path "$SERVE_PATH" "$LOCAL_URL" >/dev/null

remote_url="https://$dns$SERVE_PATH"
if ! /usr/bin/curl -fsS --max-time 10 "$remote_url/health" >/dev/null; then
  echo "HATA: Tailscale HTTPS health kontrolu basarisiz: $remote_url/health" >&2
  exit 4
fi

echo "remote=ON"
echo "user=$user"
echo "url=$remote_url"
echo "local=$LOCAL_URL"
echo "Robinhood root Serve yapilandirmasi korunmustur."
