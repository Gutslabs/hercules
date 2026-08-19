#!/usr/bin/env bash
# sherpa-onnx + onnxruntime xcframework'lerini vendor/sherpa/ altına indirir (yerel SPM paketi için).
# Bunlar büyük (~347MB) ve gitignore'lu; taze clone sonrası bir kez çalıştır.
# onnxruntime'ın module.modulemap'i silinir (çakışma fix'i — Package.swift açıklamasına bak).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/vendor/sherpa"
# willwade/sherpa-onnx-spm tag 1.13.14 ikili varlıkları 1.13.2 release'inden gelir.
BASE="https://github.com/willwade/sherpa-onnx-spm/releases/download/1.13.2"
mkdir -p "$DEST"
if [ -d "$DEST/sherpa-onnx.xcframework" ] && [ -d "$DEST/onnxruntime.xcframework" ]; then
  echo "xcframework'ler zaten var: $DEST"
else
  echo "sherpa-onnx + onnxruntime xcframework indiriliyor (~347MB)…"
  curl -L -sS -o /tmp/sherpa-onnx.xcframework.zip "$BASE/sherpa-onnx.xcframework.zip"
  curl -L -sS -o /tmp/onnxruntime.xcframework.zip "$BASE/onnxruntime.xcframework.zip"
  unzip -q -o /tmp/sherpa-onnx.xcframework.zip -d "$DEST"
  unzip -q -o /tmp/onnxruntime.xcframework.zip -d "$DEST"
  rm -f /tmp/sherpa-onnx.xcframework.zip /tmp/onnxruntime.xcframework.zip
fi
# Çakışma fix'i: onnxruntime'ın modulemap'ini kaldır (Swift'ten import edilmiyor).
find "$DEST/onnxruntime.xcframework" -name module.modulemap -delete 2>/dev/null || true
echo "Tamam: $DEST"
