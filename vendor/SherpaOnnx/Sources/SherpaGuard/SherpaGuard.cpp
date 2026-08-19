#include "SherpaGuard.h"

#include <cstdio>
#include <exception>

// sherpa-onnx C API sembolünün opak yeniden bildirimi. Gerçek imza:
//   const SherpaOnnxOfflineTts *SherpaOnnxCreateOfflineTts(const SherpaOnnxOfflineTtsConfig *);
// Header'a bağımlı olmamak için pointer'lar `const void *` alınır; extern "C"
// olduğundan isim bozulmaz (sembol: _SherpaOnnxCreateOfflineTts) ve tüm
// argüman/dönüşler pointer olduğu için ABI birebir aynıdır.
extern "C" const void *SherpaOnnxCreateOfflineTts(const void *config);

extern "C" const void *SherpaGuardCreateOfflineTts(const void *config) {
    try {
        return SherpaOnnxCreateOfflineTts(config);
    } catch (const std::exception &e) {
        // Ort::Exception dahil std::exception türevleri: Console'a hata mesajını
        // düşür (teşhis için) ve NULL dön → Swift Apple sesine geçer, çökmez.
        std::fprintf(stderr, "[SherpaGuard] TTS oturumu açılamadı (onnxruntime): %s\n", e.what());
        return nullptr;
    } catch (...) {
        std::fprintf(stderr, "[SherpaGuard] TTS oturumu açılamadı (bilinmeyen C++ hata)\n");
        return nullptr;
    }
}
