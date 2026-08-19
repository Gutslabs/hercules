import Foundation

/// Hafızayı sabit bir okuma bütçesine sığdıran yaş-ağırlıklı blok seçimi.
///
/// Fikir OptMem'den (github.com/VictorTaelin/OptMem) alındı, kodu değil — o repoda LICENSE
/// dosyası yok, yani varsayılan olarak tüm haklar saklı; ayrıca Python bir CLI ve buraya
/// hiçbir şekilde uymuyor. Algoritma burada Swift'e yeniden yazıldı ve referans uygulamayla
/// birebir karşılaştırılarak doğrulandı (bkz. MemoryCoverTests).
///
/// NEDEN gerekli: `LocalMemoryProvider.contextMemories` hafızayı sorguya ANLAMSAL benzerlikle
/// seçiyor — "şu an sorulanla ilgili olan" için doğru, ama koça genel gidişatı vermiyor.
/// Sorgu embedding'ine benzemeyen eski bir kayıt hiç görünmüyor. Cover bunu tamamlıyor:
/// [0,T) aralığını hizalı ikinin-kuvveti bloklarla döşüyor, bloğu bütün bırakma koşulu
/// `blokBoyu <= alpha * yaş`. Sonuç: yeni kayıtlar birebir, eskiler giderek irileşen
/// bloklara çöküyor — hiçbir şey kaybolmadan sabit sayıda satır.
enum MemoryCover {
    /// Yarı-açık aralık: `[lo, hi)`. `hi - lo == 1` ise blok tek bir kaydı temsil eder,
    /// yani birebir gösterilir; daha büyükse özetlenir.
    struct Block: Equatable, Sendable {
        let lo: Int
        let hi: Int
        var count: Int { hi - lo }
        var isVerbatim: Bool { count == 1 }
    }

    /// `[0,T)` aralığını hizalı ikinin-kuvveti bloklarıyla döşer; bir bloğu bütün bırakır
    /// ancak ve ancak boyu yaşının `alpha` katından küçükse. Büyük alpha = daha kaba = az satır.
    static func cover(total T: Int, alpha: Double) -> [Block] {
        guard T > 0 else { return [] }
        var root = 1
        while root < T { root *= 2 }

        var out: [Block] = []
        var stack: [(Int, Int)] = [(0, root)]
        while let (lo, hi) = stack.popLast() {
            if lo >= T { continue }
            let size = hi - lo
            // `hi > T`: blok sondan taşıyorsa bölünmek zorunda, yoksa var olmayan
            // kayıtları kapsayan bir blok üretirdik.
            if size > 1 && (hi > T || Double(size) > alpha * Double(T - lo)) {
                let mid = (lo + hi) / 2
                stack.append((mid, hi))
                stack.append((lo, mid))
            } else {
                out.append(Block(lo: lo, hi: hi))
            }
        }
        out.sort { $0.lo < $1.lo }
        return out
    }

    /// Bir aralığı hizalı ikinin-kuvveti bloklarla döşemenin ALT SINIRI.
    ///
    /// `[0,T)` en az `popcount(T)` blok gerektirir: T=13 (1101₂) için 8+4+1, yani üç blok.
    /// Bu yüzden `budget` katı bir tavan DEĞİL — bütçe bu sınırın altındaysa cover daha çok
    /// blok döndürür. (Referans uygulama da aynı davranıyor; ölçüldü.) Çağıran gerçekten
    /// sabit bir tavana ihtiyaç duyuyorsa sonucu ayrıca kırpmalı.
    static func minimumBlocks(total T: Int) -> Int {
        T > 0 ? T.nonzeroBitCount : 0
    }

    /// Bütçeye sığan blok listesi: hedef `budget` blok, en ince ayrıntı en yenilerde.
    /// Gerçek sonuç `max(budget, minimumBlocks(total:))` kadar olabilir — üstteki nota bak.
    ///
    /// Her şey sığıyorsa hiç sıkıştırma yapılmaz — küçük hafızada bu fonksiyon
    /// görünmez olur, ki 132 kayıtlık bir depoda istediğimiz tam olarak bu.
    static func cover(total T: Int, budget: Int) -> [Block] {
        guard T > 0 else { return [] }
        guard budget > 0 else { return [] }
        if T <= budget {
            return (0..<T).map { Block(lo: $0, hi: $0 + 1) }
        }

        // alpha'yı ikili aramayla bütçeye oturt. 60 tur, Double hassasiyetini tüketmeye yeter.
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if cover(total: T, alpha: mid).count > budget { lo = mid } else { hi = mid }
        }
        var out = cover(total: T, alpha: hi)

        // Blok boyları ikinin kuvvetiyle sıçradığı için alpha tek başına bütçenin altında
        // kalabiliyor. Artan payı BUGÜNE harca — detayın en değerli olduğu yer orası.
        while out.count < budget {
            guard let i = out.lastIndex(where: { $0.count > 1 }) else { break }
            let block = out[i]
            let mid = (block.lo + block.hi) / 2
            out.replaceSubrange(i...i, with: [Block(lo: block.lo, hi: mid),
                                              Block(lo: mid, hi: block.hi)])
        }
        return out
    }
}
