#!/usr/bin/env bash
#
# Hercules (Mac) — KARARLI imzayla derle + kur + karantinayı sil.
#
# NEDEN: Uygulama ad-hoc imzalanınca macOS'un "designated requirement"ı cdhash
# tabanlı olur; cdhash HER build'de değişir → TCC (mikrofon / HealthKit / dosya)
# izinleri her yeni build'de SIFIRLANIR ve tekrar sorulur. Apple Development
# sertifikasıyla imzalanınca requirement kimlik-tabanlı ve KARARLI olur:
#   identifier "com.samorai.hercules" and ... certificate leaf = "Apple Development: ..."
# → izni BİR KEZ ver, sonraki tüm build'lerde kalır.
#
# Ayrıca karantina bayrağını (com.apple.quarantine) siler → "internetten indirildi /
# doğrulanmamış geliştirici" launch uyarısı da kalkar.
#
# Kullanım:  ./scripts/mac-build-install.sh [Debug|Release]   (varsayılan: Debug)

set -euo pipefail

SCHEME="Hercules"
CONFIG="${1:-Debug}"
DEST_DIR="/Applications/Apps"
DERIVED="build/DD-install"

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ_DIR"

# 1) İmzalama sertifikası var mı?
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  echo "✗ 'Apple Development' sertifikası bulunamadı."
  echo "  Xcode ▸ Settings ▸ Accounts'tan Apple ID'ni ekle, sonra tekrar dene."
  exit 1
fi

echo "▸ Derleniyor ($CONFIG, otomatik Apple Development imzası)…"
xcodebuild -project Hercules.xcodeproj -scheme "$SCHEME" \
  -configuration "$CONFIG" -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Automatic \
  build >/dev/null

APP_SRC="$DERIVED/Build/Products/$CONFIG/Hercules.app"
[ -d "$APP_SRC" ] || { echo "✗ Derlenen app bulunamadı: $APP_SRC"; exit 1; }

# 1b) Iroh relay — telefonu VPN profili olmadan bağlayan yardımcı süreç.
#
# AYRI derived data ŞART: relay'in `Iroh.xcframework`'ü ile uygulamanın
# `sentencepiece.xcframework`'ü aynı `include/module.modulemap` yoluna yazıyor.
# Aynı ürün klasöründe derlenirlerse Xcode "Multiple commands produce" veriyor.
# Ayrı klasörde derleyip binary'yi app bundle'ına elle kopyalıyoruz.
RELAY_DERIVED="build/DD-relay-install"
echo "▸ Iroh relay derleniyor…"
xcodebuild -project Hercules.xcodeproj -scheme "hercules-iroh-relay" \
  -configuration "$CONFIG" -destination 'platform=macOS' \
  -derivedDataPath "$RELAY_DERIVED" \
  CODE_SIGN_STYLE=Automatic \
  build >/dev/null

RELAY_SRC="$RELAY_DERIVED/Build/Products/$CONFIG/hercules-iroh-relay"
[ -f "$RELAY_SRC" ] || { echo "✗ Relay binary bulunamadı: $RELAY_SRC"; exit 1; }

# Bundle'a sonradan dosya koymak imzayı geçersiz kılar → app'i yeniden imzalamalıyız.
# Entitlement'ları KAYNAK plist'ten alamayız: orada $(ICLOUD_CONTAINER_ENVIRONMENT)
# gibi build değişkenleri var ve codesign onları GENİŞLETMEZ — bundle'a düz metin
# olarak yazar, CloudKit senkronu sessizce ölür. Bu yüzden değerleri Xcode'un zaten
# genişlettiği İMZALI app'ten çekiyoruz.
SIGNED_ENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS" "$SIGNED_ENTS"' EXIT
codesign -d --entitlements "$SIGNED_ENTS" --xml "$APP_SRC" 2>/dev/null \
  || codesign -d --entitlements :- "$APP_SRC" >"$SIGNED_ENTS" 2>/dev/null
grep -q 'ICLOUD_CONTAINER_ENVIRONMENT' "$SIGNED_ENTS" && {
  echo "✗ İmzalı app'in entitlement'larında genişletilmemiş değişken var — imzalama bozuk."
  exit 1
}

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')"
[ -n "$IDENTITY" ] || { echo "✗ İmza kimliği bulunamadı."; exit 1; }

cp "$RELAY_SRC" "$APP_SRC/Contents/MacOS/hercules-iroh-relay"
# Yardımcı sürecin iCloud/APS entitlement'ına ihtiyacı yok — yalnız ağ açar.
codesign --force --options runtime --sign "$IDENTITY" \
  "$APP_SRC/Contents/MacOS/hercules-iroh-relay" >/dev/null
# `--deep` YOK: iç imzalar zaten geçerli, deep onları app'in entitlement'larıyla
# ezerdi (Apple da deep'i imzalama için önermiyor).
codesign --force --options runtime --sign "$IDENTITY" \
  --entitlements "$SIGNED_ENTS" "$APP_SRC" >/dev/null

# 2) İmza ad-hoc DEĞİL mi? (kararlılığın ön şartı)
if codesign -dv "$APP_SRC" 2>&1 | grep -q "adhoc"; then
  echo "✗ App hâlâ ad-hoc imzalı — imzalama düzgün çalışmadı."
  echo "  Xcode'da projeyi açıp Signing & Capabilities'te takımın seçili olduğunu kontrol et."
  exit 1
fi

# CloudKit entitlement'ları gerçekten imzaya girdi mi? Kaynak plist'in doğru olması
# yetmez; kurulan binary'de container + ortam yoksa cihaz senkronu çalışmaz.
ENTITLEMENTS="$(mktemp)"
codesign -d --entitlements :- "$APP_SRC" >"$ENTITLEMENTS" 2>/dev/null
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-identifiers' "$ENTITLEMENTS" \
  | grep -q "iCloud.com.samorai.hercules" || {
    echo "✗ İmzalı uygulamada Hercules CloudKit container'ı yok."
    exit 1
  }
EXPECTED_ENV="Development"
[ "$CONFIG" = "Release" ] && EXPECTED_ENV="Production"
ACTUAL_ENV="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-environment' "$ENTITLEMENTS" 2>/dev/null || true)"
[ "$ACTUAL_ENV" = "$EXPECTED_ENV" ] || {
  echo "✗ CloudKit ortamı yanlış: beklenen $EXPECTED_ENV, bulunan ${ACTUAL_ENV:-yok}."
  exit 1
}

# 3) Kur
echo "▸ Kuruluyor: $DEST_DIR/Hercules.app"
mkdir -p "$DEST_DIR"
# Çalışan eski binary dosya sistemi üzerinde değiştirilirse `open` onu yeni sürüm
# sanabilir. Önce nazikçe kapat, gerekirse yalnız Hercules sürecini sonlandır.
if /usr/bin/pgrep -x Hercules >/dev/null 2>&1; then
  /usr/bin/osascript -e 'tell application id "com.samorai.hercules" to quit' >/dev/null 2>&1 || true
  for _ in {1..30}; do
    /usr/bin/pgrep -x Hercules >/dev/null 2>&1 || break
    sleep 0.1
  done
  /usr/bin/pkill -TERM -x Hercules >/dev/null 2>&1 || true
fi
rm -rf "$DEST_DIR/Hercules.app"
cp -R "$APP_SRC" "$DEST_DIR/Hercules.app"

# 4) Karantinayı sil (download launch uyarısını kapatır)
xattr -dr com.apple.quarantine "$DEST_DIR/Hercules.app" 2>/dev/null || true

# 5) Kararlı requirement'ı göster
echo
echo "▸ Designated requirement (cdhash DEĞİL, identifier+cert görmelisin):"
codesign -d -r- "$DEST_DIR/Hercules.app" 2>&1 | grep -i "designated" | sed 's/^/    /'
echo
echo "✓ Kuruldu. Mikrofon iznini BİR KEZ ver — imza kararlı olduğu için"
echo "  bundan sonraki tüm build'lerde izinler KALICI (bu script'le kurduğun sürece)."
