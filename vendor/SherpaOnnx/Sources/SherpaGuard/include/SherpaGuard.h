#ifndef SHERPA_GUARD_H
#define SHERPA_GUARD_H

#ifdef __cplusplus
extern "C" {
#endif

/// TTS oturumunu (Ort::Session) güvenli oluşturur.
///
/// onnxruntime, model uyumsuz/bozuk/eksik ya da oturum açılamadığında bir C++
/// exception fırlatır. Swift bu C++ exception'ını YAKALAYAMAZ → yakalanmadan
/// `std::terminate()` → `abort()` → uygulama çöker. Bu sarmalayıcı gerçek
/// `SherpaOnnxCreateOfflineTts` çağrısını `try/catch(...)` içine alır: hata
/// olursa exception yutulur ve `NULL` döner. Böylece Swift tarafı `nil` görür,
/// `SherpaTTSEngine.init?` nil'e düşer ve uygulama Apple sistem sesine (Yelda)
/// geçer — çökmeden.
///
/// `config`/dönüş opak `const void *` olarak tutulur: sherpa-onnx header'ına
/// bağımlılık gerekmez (extern "C" => isim bozulmaz, pointer ABI'si sabittir).
const void *SherpaGuardCreateOfflineTts(const void *config);

#ifdef __cplusplus
}
#endif

#endif /* SHERPA_GUARD_H */
