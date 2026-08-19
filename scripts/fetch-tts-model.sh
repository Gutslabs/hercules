#!/usr/bin/env bash
# Sesli koçun kullandığı sherpa-onnx Piper Türkçe (dfki) TTS modelini indirir.
# Model gitignore'lu (büyük + CC-BY-NC-SA ticari-yasak). Taze clone sonrası bir kez çalıştır.
set -euo pipefail
DEST="$(cd "$(dirname "$0")/.." && pwd)/Hercules/Resources/tts"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-tr_TR-dfki-medium.tar.bz2"
mkdir -p "$DEST"
if [ -d "$DEST/vits-piper-tr_TR-dfki-medium" ]; then
  echo "Model zaten var: $DEST/vits-piper-tr_TR-dfki-medium"
  exit 0
fi
echo "dfki TTS modeli indiriliyor (~64MB)…"
curl -L -sS -o "/tmp/dfki.tar.bz2" "$URL"
tar xjf "/tmp/dfki.tar.bz2" -C "$DEST"
rm -f "/tmp/dfki.tar.bz2"
echo "Tamam: $DEST/vits-piper-tr_TR-dfki-medium"
