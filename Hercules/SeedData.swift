import Foundation
import SwiftData

enum DemoSeed {
    static func seedIfEmpty(_ ctx: ModelContext) {
        let profileCount = (try? ctx.fetchCount(FetchDescriptor<UserProfile>())) ?? 0
        var changed = false

        if profileCount == 0 {
            let profile = UserProfile(
                name: "",
                sex: .male,
                birthDate: Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now,
                height: 178,
                activity: .moderate,
                goal: .maintain,
                isSeedPlaceholder: true
            )
            ctx.insert(profile)
            changed = true
        }

        // NOT: Örnek antrenman günü SEED'LENMİYOR — gerçek program Mac'ten / AI koçtan gelir.
        // (Eskiden 3 boş demo gün (Sırt+Göğüs/Biceps+Triceps/Karın+Bacak) seed'leniyordu;
        // bunlar hem kullanıcıyı yanıltıyor hem de gerçek programı engelliyordu.
        // Mevcut store'daki demo'lara DOKUNULMAZ — silmek kullanıcının (boş da olsa) günlerini
        // yok ediyordu; mevcut kullanıcı kayıtlarına dokunmuyoruz.)

        // Boş save bile CoreData+CloudKit export scheduler'ını uyandırabiliyor. Her açılışta
        // gereksiz export task'ı üretme; yalnız gerçekten seed eklendiyse kaydet.
        if changed {
            ctx.saveOrReport("ilk profili hazırlama")
        }
    }

    /// UserProfile mantıken TEKİL ama CloudKit + seed onu ÇİFTLEYEBİLİR (mobil DemoSeed'in boş
    /// demo profili + Mac'ten CloudKit ile gelen gerçek profil → 2 kayıt; app `.first` yanlışını
    /// gösterir, ör. mobilde kalori hedefi Mac'ten farklı çıkar). Birden fazla varsa: ismi DOLU
    /// olan + en GÜNCEL (updatedAt) profili tut, gerisini sil. Açılışta VE CloudKit profili
    /// geldiğinde (reaktif, view .onChange) çağrılır. Böylece "hangi cihazda değişirse o güncel".
    @discardableResult
    static func dedupUserProfiles(_ ctx: ModelContext, save: Bool = true) -> Bool {
        let all = (try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []
        guard all.count > 1 else { return false }
        let keeper = all.sorted { a, b in
            if a.isSeedPlaceholder != b.isSeedPlaceholder { return !a.isSeedPlaceholder }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            let aEmpty = a.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let bEmpty = b.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if aEmpty != bEmpty { return !aEmpty }
            return String(describing: a.persistentModelID) < String(describing: b.persistentModelID)
        }.first!
        for p in all where p.persistentModelID != keeper.persistentModelID {
            ctx.delete(p)
        }
        if save { ctx.saveOrReport("profili tekilleştirme") }
        return true
    }
}
