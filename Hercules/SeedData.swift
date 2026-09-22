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

#if DEBUG && targetEnvironment(simulator)
// MARK: - Örnek veri (YALNIZ simülatör)

/// Tasarım üstünde çalışırken boş ekranlara bakmamak için gerçekçi bir demo store.
///
/// ÜÇ KİLİT birden var ve hepsi aynı anda sağlanmadan tek satır yazılmaz:
///   1. `#if DEBUG`            → Release derlemesinde bu kod hiç var olmaz.
///   2. `targetEnvironment(simulator)` → gerçek cihazda ve Mac'te derlenmez bile.
///   3. `--seed-sample-data`   → simülatörde bile açıkça istenmeden çalışmaz.
/// Yani bu tohumlayıcının canlı store'a ulaşabileceği bir yol yok.
extension DemoSeed {
    static let sampleDataArgument = "--seed-sample-data"

    /// Deterministik LCG — aynı argümanla her koşuda AYNI demo veri çıksın ki
    /// tasarım değişikliklerini karşılaştırırken sayılar altından kaymasın.
    private struct Rng {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 11) & 0x1F_FFFF_FFFF_FFFF) / Double(0x20_0000_0000_0000)
        }
        /// [lo, hi] aralığında düzgün dağılım.
        mutating func between(_ lo: Double, _ hi: Double) -> Double { lo + next() * (hi - lo) }
        mutating func pick<T>(_ items: [T]) -> T { items[min(items.count - 1, Int(next() * Double(items.count)))] }
    }

    static func seedSampleDataIfRequested(_ ctx: ModelContext) {
        // İki tetik de kabul: simctl launch argümanı bazı kabuklarda yutuluyor,
        // SIMCTL_CHILD_ ile geçirilen ortam değişkeni her koşulda ulaşıyor.
        let info = ProcessInfo.processInfo
        let requested = info.arguments.contains(sampleDataArgument)
            || info.environment["HERCULES_SEED_SAMPLE"] == "1"
        guard requested else { return }
        NSLog("[Hercules] örnek veri tohumlanıyor…")

        wipeSampleData(ctx)

        var rng = Rng(state: 20_260_826)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        func day(_ back: Int) -> Date { cal.date(byAdding: .day, value: -back, to: today) ?? today }
        func at(_ back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: day(back)) ?? day(back)
        }

        // MARK: Profil
        let profiles = (try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []
        let profile = profiles.first ?? {
            let p = UserProfile()
            ctx.insert(p)
            return p
        }()
        profile.name = "Can"
        profile.sexRaw = Sex.male.rawValue
        profile.birthDate = cal.date(byAdding: .year, value: -29, to: today) ?? today
        profile.height = 178
        profile.activityRaw = ActivityLevel.moderate.rawValue
        profile.goalRaw = Goal.lose.rawValue
        profile.targetWeight = 78
        profile.about = "Sabah aç antrenman yapmayı sevmiyorum. Akşam 20:00'den sonra ağır öğün beni şişiriyor."
        profile.supplements = "Kreatin 5g\nProtein tozu\nD vitamini 2000 IU"
        profile.isSeedPlaceholder = false
        profile.updatedAt = .now

        // MARK: Ölçümler — 120 gün, hafif gürültülü düşen trend
        // Kilo 89,4 → 85,2 bandında; tam check-in'ler haftada bir (çevreler orada).
        for back in stride(from: 120, through: 0, by: -1) {
            let progress = Double(120 - back) / 120.0
            let trend = 89.4 - 4.2 * progress
            let noise = rng.between(-0.45, 0.45)
            let weight = ((trend + noise * (1 - 0.3 * progress)) * 100).rounded() / 100
            let bodyFat = ((22.4 - 2.5 * progress + rng.between(-0.2, 0.2)) * 10).rounded() / 10

            // Her gün tartı yok: ~%88 kayıt oranı, gerçekçi boşluklar bıraksın.
            if back > 0 { guard rng.next() < 0.88 else { continue } }

            let isCheckIn = back % 7 == 0
            let m = Measurement(
                date: at(back, 8, 10),
                weight: weight,
                bodyFat: isCheckIn ? bodyFat : nil,
                waist: isCheckIn ? ((95.5 - 3.5 * progress) * 10).rounded() / 10 : nil,
                chest: isCheckIn ? ((129 + 1.0 * progress) * 10).rounded() / 10 : nil,
                neck: isCheckIn ? ((40.0 - 1.0 * progress) * 10).rounded() / 10 : nil
            )
            ctx.insert(m)
        }

        // MARK: Aylık hedef rotası
        for month in 1...3 {
            let anchor = cal.date(byAdding: .month, value: month, to: today) ?? today
            ctx.insert(MonthlyGoal(
                anchorDate: anchor,
                targetWeight: ((85.2 - Double(month) * 1.6) * 10).rounded() / 10,
                note: month == 3 ? "Yaz hedefi" : nil
            ))
        }

        // MARK: Adımlar — 90 gün
        for back in stride(from: 90, through: 0, by: -1) {
            let weekday = cal.component(.weekday, from: day(back))
            let isWeekend = weekday == 1 || weekday == 7
            let base = isWeekend ? rng.between(3_200, 8_500) : rng.between(6_500, 14_500)
            let steps = Int(base.rounded())
            ctx.insert(StepEntry(
                date: at(back, 21, 30),
                steps: steps,
                source: "healthkit",
                distanceMeters: Double(steps) * 0.72,
                activeEnergyKcal: Double(steps) * 0.0004 * 85.2,
                syncedAt: at(back, 22, 0)
            ))
        }

        // MARK: Yemekler — 35 gün, günde 3-4 öğün
        struct Meal { let name: String; let g: Double; let kcal: Double; let p: Double; let c: Double; let f: Double }
        let breakfasts = [
            Meal(name: "5 yumurta + 2 dilim tam buğday ekmeği", g: 380, kcal: 620, p: 39, c: 44, f: 31),
            Meal(name: "Yulaf ezmesi + muz + fıstık ezmesi", g: 350, kcal: 580, p: 22, c: 78, f: 19),
            Meal(name: "Menemen + 100g beyaz peynir", g: 420, kcal: 540, p: 30, c: 18, f: 38),
            Meal(name: "Protein tozlu yoğurt bowl", g: 400, kcal: 470, p: 46, c: 42, f: 11),
        ]
        let lunches = [
            Meal(name: "200g tavuk göğsü + 150g pirinç + salata", g: 520, kcal: 720, p: 62, c: 62, f: 18),
            Meal(name: "3 lahmacun + ayran", g: 480, kcal: 960, p: 38, c: 108, f: 38),
            Meal(name: "Ton balıklı makarna", g: 450, kcal: 780, p: 44, c: 96, f: 21),
            Meal(name: "Kuru fasulye + pilav", g: 500, kcal: 810, p: 27, c: 118, f: 24),
        ]
        let dinners = [
            Meal(name: "250g kıymalı köfte + bulgur pilavı", g: 480, kcal: 890, p: 56, c: 68, f: 42),
            Meal(name: "Somon + fırın sebze", g: 430, kcal: 640, p: 48, c: 26, f: 38),
            Meal(name: "5 onigiri (ton balığı + mayonez)", g: 420, kcal: 760, p: 26, c: 112, f: 22),
            Meal(name: "Tavuk döner dürüm", g: 400, kcal: 820, p: 42, c: 76, f: 36),
        ]
        let snacks = [
            Meal(name: "80g karışık kuruyemiş", g: 80, kcal: 465, p: 14, c: 18, f: 39),
            Meal(name: "Protein bar", g: 60, kcal: 220, p: 20, c: 22, f: 7),
            Meal(name: "2 muz", g: 240, kcal: 210, p: 3, c: 54, f: 1),
            Meal(name: "200g süzme yoğurt + bal", g: 220, kcal: 260, p: 19, c: 28, f: 7),
        ]

        for back in stride(from: 34, through: 0, by: -1) {
            // Birkaç gün boş kalsın — "kayıtlı gün 29/30" gibi oranlar gerçekçi olsun.
            guard rng.next() < 0.93 else { continue }
            var plan: [(Meal, Int, Int)] = [
                (rng.pick(breakfasts), 9, 20),
                (rng.pick(lunches), 13, 15),
                (rng.pick(dinners), 20, 10),
            ]
            if rng.next() < 0.65 { plan.append((rng.pick(snacks), 16, 40)) }
            if rng.next() < 0.25 { plan.append((rng.pick(snacks), 23, 5)) }

            for (meal, hour, minute) in plan {
                // Porsiyon oynasın: aynı yemek her gün birebir aynı kaloriyi vermesin.
                let scale = rng.between(0.85, 1.15)
                ctx.insert(FoodEntry(
                    date: at(back, hour, minute),
                    name: meal.name,
                    grams: (meal.g * scale).rounded(),
                    calories: (meal.kcal * scale).rounded(),
                    protein: (meal.p * scale).rounded(),
                    carbs: (meal.c * scale).rounded(),
                    fat: (meal.f * scale).rounded()
                ))
            }
        }

        // MARK: Haftalık program (Calendar.weekday: 1=Pazar)
        let program: [(Int, String, String, [(String, Int, String, String)])] = [
            (2, "Push · Göğüs & Omuz", "Göğüs, ön omuz, triceps", [
                ("Bench Press", 4, "6-8", "80 kg"),
                ("Incline Dumbbell Press", 3, "8-10", "32 kg"),
                ("Overhead Press", 3, "8-10", "45 kg"),
                ("Cable Fly", 3, "12-15", "20 kg"),
                ("Triceps Pushdown", 3, "12-15", "35 kg"),
            ]),
            (3, "Pull · Sırt & Biceps", "Lat, orta sırt, biceps", [
                ("Barbell Row", 4, "6-8", "75 kg"),
                ("Lat Pulldown", 3, "10-12", "70 kg"),
                ("Chest Supported Row", 3, "10-12", "50 kg"),
                ("Face Pull", 3, "15", "25 kg"),
                ("Barbell Curl", 3, "10-12", "35 kg"),
            ]),
            (5, "Bacak", "Quad, hamstring, kalça", [
                ("Squat", 4, "5-6", "110 kg"),
                ("Romanian Deadlift", 3, "8-10", "90 kg"),
                ("Leg Press", 3, "10-12", "180 kg"),
                ("Leg Curl", 3, "12-15", "45 kg"),
                ("Calf Raise", 4, "15-20", "60 kg"),
            ]),
            (6, "Üst Vücut", "Hacim günü — bileşik + izolasyon", [
                ("Incline Bench Press", 4, "8", "70 kg"),
                ("Pull-up", 4, "AMRAP", "vücut"),
                ("Lateral Raise", 4, "15", "12 kg"),
                ("Hammer Curl", 3, "12", "20 kg"),
            ]),
            (7, "Kondisyon + Karın", "Tempolu kardiyo, core", [
                ("Koşu bandı", 1, "30 dk", "10 km/s"),
                ("Hanging Leg Raise", 3, "12-15", "vücut"),
                ("Plank", 3, "60 sn", "vücut"),
            ]),
        ]
        for (weekday, name, focus, exercises) in program {
            let session = WorkoutSession(
                weekday: weekday,
                name: name,
                estimatedCalories: 420,
                durationMinutes: 65,
                focus: focus,
                warmup: "8 dk bisiklet + hareket hazırlığı",
                progression: "Üst set hedef tekrarı tutarsa +2,5 kg"
            )
            ctx.insert(session)
            session.templateExercises = exercises.enumerated().map { idx, ex in
                let (exName, sets, reps, load) = ex
                // Teknik linki: gerçek programlarda her harekette var (Bugün satırının ikonu).
                let query = exName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? exName
                let t = WorkoutTemplateExercise(
                    name: exName, order: idx, sets: sets, reps: reps,
                    load: load, rir: "2", rest: "150 sn",
                    sourceURL: "https://www.youtube.com/results?search_query=\(query)"
                )
                t.session = session
                ctx.insert(t)
                return t
            }
        }

        // MARK: Antrenman kayıtları — son 30 gün, haftada ~4
        for back in stride(from: 30, through: 0, by: -1) {
            let weekday = cal.component(.weekday, from: day(back))
            guard let planned = program.first(where: { $0.0 == weekday }) else { continue }
            guard rng.next() < 0.82 else { continue }   // her planlı gün tutmamış

            let log = WorkoutLog(
                date: at(back, 19, 15),
                name: planned.1,
                durationMinutes: Int(rng.between(52, 78).rounded()),
                estimatedCalories: rng.between(360, 520).rounded()
            )
            ctx.insert(log)
            log.exercises = planned.3.enumerated().map { idx, ex in
                let (exName, sets, _, load) = ex
                let entry = WorkoutExerciseEntry(name: exName, order: idx)
                entry.log = log
                ctx.insert(entry)
                let baseLoad = Double(load.split(separator: " ").first.flatMap { Double($0) } ?? 0)
                entry.setEntries = (0..<sets).map { s in
                    let set = ExerciseSet(
                        order: s,
                        reps: Int(rng.between(6, 12).rounded()),
                        weight: baseLoad > 0 ? (baseLoad + rng.between(-5, 5)).rounded() : nil
                    )
                    set.entry = entry
                    ctx.insert(set)
                    return set
                }
                return entry
            }
        }

        // MARK: Tarifler + video defteri
        let recipes: [(String, RecipeCategory, Bool, String, Int, Double, Double, Double, Double)] = [
            ("Fırında tavuk göğsü + tatlı patates", .dinner, true,
             "Tek tepside, 40 dakikada hazır yüksek protein akşam yemeği.", 35, 640, 58, 52, 18),
            ("Protein pankek", .breakfast, true,
             "Yulaf + yumurta akı + protein tozu; şurup yerine meyve.", 15, 480, 42, 54, 9),
            ("Kıymalı bulgur pilavı", .dinner, false,
             "Az yağla kavrulmuş kıyma, domates, bol maydanoz.", 30, 720, 44, 78, 24),
            ("Menemen", .breakfast, false,
             "5 yumurta, biber, domates — tereyağı yerine zeytinyağı.", 12, 540, 30, 18, 38),
            ("Fıstık ezmeli protein topları", .dessert, true,
             "Fırınsız; yulaf, fıstık ezmesi, protein tozu, hurma.", 20, 180, 11, 16, 8),
            ("Somon + fırın sebze", .dinner, false,
             "Omega-3 günü. Limon, kekik, brokoli ve havuç.", 28, 620, 46, 24, 36),
        ]
        for (idx, r) in recipes.enumerated() {
            let (title, category, fav, summary, prep, kcal, p, c, f) = r
            ctx.insert(Recipe(
                title: title,
                urlString: "",
                category: category,
                isFavorite: fav,
                summary: summary,
                ingredientsText: "Malzemeler demo veridir — tasarım için dolgu.",
                instructionsText: "1. Hazırla\n2. Pişir\n3. Servis et",
                servings: 2,
                prepMinutes: prep,
                calories: kcal,
                protein: p,
                carbs: c,
                fat: f,
                createdAt: at(idx * 3, 12)
            ))
        }
        ctx.insert(RecipeVideo(title: "Bench press form", urlString: "https://youtu.be/vcBig73ojpE", createdAt: at(6, 12)))
        ctx.insert(RecipeVideo(title: "Yulaflı protein pankek", urlString: "https://youtu.be/1p9v_9pfV1U", createdAt: at(2, 12)))

        // MARK: Koç kanalı — kök mesaj + thread yanıtları
        seedChatChannel(day: day, at: at)

        ctx.saveOrReport("örnek veri tohumlama")
        let count = (try? ctx.fetchCount(FetchDescriptor<Measurement>())) ?? -1
        NSLog("[Hercules] örnek veri hazır — \(count) ölçüm")
    }

    /// Kanal/thread yapısını görebilmek için birkaç gerçekçi konuşma.
    /// Sohbet geçmişi SwiftData'da değil UserDefaults'ta yaşıyor.
    private static func seedChatChannel(day: (Int) -> Date, at: (Int, Int, Int) -> Date) {
        func turn(_ role: ChatTurn.Role, _ text: String, _ date: Date,
                  food: AIFoodResult? = nil, saved: Bool = false,
                  savedOn: Date? = nil, searched: String? = nil) -> ChatTurn {
            ChatTurn(role: role, text: text, food: food, saved: saved,
                     searchedFor: searched, savedFoodDate: savedOn, createdAt: date)
        }

        var conversations: [ChatConversation] = []

        // 1) Basit soru-cevap, tek yanıt.
        conversations.append(ChatConversation(
            title: "Bu hafta kilo neden sabit kaldı?",
            messages: [
                turn(.user, "Bu hafta kilo neden sabit kaldı?", at(4, 21, 12)),
                turn(.assistant, """
                Sabit değil aslında — 7 günlük ortalaman 85,6'dan 85,3'e indi, günlük tartılar sadece daha gürültülü. Cumartesi 86,1 gördüğün için sabit hissettiriyor.

                İki şey dikkat çekiyor: hafta sonu iki gün kalori 3.000'in üstünde ve sodyum yüksek gitmiş. Su tutulumu ölçüyü 0,5-0,8 kg şişirebilir. Bir hafta daha aynı protokolle devam et, karar için haftalık ortalamaya bak.
                """, at(4, 21, 13)),
            ],
            createdAt: at(4, 21, 12),
            updatedAt: at(4, 21, 13)
        ))

        // 2) Öğün kaydı — kart günlüğe eklenmiş hâlde.
        let food = AIFoodResult(
            name: "5 onigiri (250g çiğ pirinç + ton balığı + 30g mayonez) + 3 lahmacun",
            grams: 1245, calories: 2720, protein_g: 106, carbs_g: 319, fat_g: 111,
            message: "Toplam ~2.720 kalori."
        )
        conversations.append(ChatConversation(
            title: "5 onigiri, 3 lahmacun ve 80g kuruyemiş yedim",
            messages: [
                turn(.user, "5 onigiri, 3 lahmacun ve 80g kuruyemiş yedim, kaç kalori?", at(2, 1, 58)),
                turn(.assistant, """
                Toplam ~2.720 kcal · P106 · C319 · Y111. Dağılım: onigiriler ~1.300 kcal (çiğ pirinç 250g tek başına 900 kcal), 3 lahmacun ~960 kcal, kuruyemiş 80g ~465 kcal.

                İki nokta: protein 106g bu kalori için düşük kalmış (85 kg'da hedef 170-190g bandı) — karbonhidrat kaloriyi domine etmiş. Ve 80g kuruyemiş tek başına 465 kcal, yani lahmacunlardan yarısı kadar; en kolay kesilecek kalem o.
                """, at(2, 1, 59), food: food, saved: true, savedOn: at(2, 1, 59)),
                turn(.user, "Kuruyemişi kessem yerine ne koyayım?", at(2, 2, 4)),
                turn(.assistant, """
                Aynı doygunluk için 200g süzme yoğurt + 1 muz: ~330 kcal ama 20g protein getiriyor. Kuruyemişi tamamen atma, 25-30g'a indir — omega-3 ve E vitamini oradan geliyor.
                """, at(2, 2, 5)),
            ],
            createdAt: at(2, 1, 58),
            updatedAt: at(2, 2, 5)
        ))

        // 3) Web aramalı, uzun thread.
        conversations.append(ChatConversation(
            title: "Kreatin yüklemesi gerekli mi?",
            messages: [
                turn(.user, "Kreatin yüklemesi gerekli mi? Güncel çalışmalar ne diyor?", at(0, 11, 20)),
                turn(.assistant, """
                Gerekli değil. Yükleme (5 gün × 20g) kas kreatin doygunluğuna daha HIZLI ulaştırır, daha YÜKSEK bir plato sağlamaz. Günde 3-5g ile aynı doygunluğa ~3-4 haftada varırsın.

                Yüklemenin tek gerçek gerekçesi zaman baskısı — yarışmaya iki hafta kalmışsa mantıklı. Aksi hâlde 5g/gün hem mide şikâyetlerini hem gereksiz maliyeti düşürür.
                """, at(0, 11, 21), searched: "creatine loading phase necessity meta-analysis"),
                turn(.user, "Antrenman öncesi mi sonrası mı?", at(0, 11, 24)),
                turn(.assistant, """
                Fark ölçülebilir düzeyde değil — kreatin depoya çalışır, akut zamanlamaya değil. Önemli olan HER GÜN almak, antrenman olmayan günler dahil. Sen zaten sabah almayı unutmuyorsan orada bırak.
                """, at(0, 11, 25)),
            ],
            createdAt: at(0, 11, 20),
            updatedAt: at(0, 11, 25)
        ))

        MobileChatHistory.save(conversations)
        MobileChatHistory.saveCurrentID(conversations.last?.id)
    }

    /// Tohumlamadan önce eski demo veriyi temizler — tekrar tekrar çalıştırıldığında
    /// kayıtlar üst üste binmesin. (Yalnız simülatörde derlenen bir yol.)
    private static func wipeSampleData(_ ctx: ModelContext) {
        (try? ctx.fetch(FetchDescriptor<Measurement>()))?.forEach(ctx.delete)
        (try? ctx.fetch(FetchDescriptor<FoodEntry>()))?.forEach(ctx.delete)
        (try? ctx.fetch(FetchDescriptor<StepEntry>()))?.forEach(ctx.delete)
        (try? ctx.fetch(FetchDescriptor<WorkoutSession>()))?.forEach(ctx.delete)
        (try? ctx.fetch(FetchDescriptor<WorkoutLog>()))?.forEach(ctx.delete)
        (try? ctx.fetch(FetchDescriptor<MonthlyGoal>()))?.forEach(ctx.delete)
        (try? ctx.fetch(FetchDescriptor<Recipe>()))?.forEach(ctx.delete)
        (try? ctx.fetch(FetchDescriptor<RecipeVideo>()))?.forEach(ctx.delete)
        MobileChatHistory.save([])
        MobileChatHistory.saveCurrentID(nil)
        ctx.saveOrReport("örnek veri temizleme")
    }
}
#endif
