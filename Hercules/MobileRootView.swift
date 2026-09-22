import SwiftUI
import LucideKit
import SwiftData
import PhotosUI
import UIKit
import Charts

/// Düzenlenebilir alanları (TextField) doldururken kullanılan gruplama-ayraçsız formatlayıcı.
/// Fmt.num tr_TR gruplama ayracı '.' üretir → "1.250" gibi değerler parse()'ta 1.25'e bozulur.
/// usesGroupingSeparator=false ile ayraç yok; digits>=1'de ',' ondalık işareti parse()/number() zaten normalize eder.
enum MobileFieldFmt {
    private static let lock = NSLock()
    private static var cache: [Int: NumberFormatter] = [:]

    private static func formatter(digits: Int) -> NumberFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[digits] { return cached }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = digits
        cache[digits] = f
        return f
    }

    static func num(_ v: Double, digits: Int = 0) -> String {
        formatter(digits: digits).string(from: NSNumber(value: v)) ?? ""
    }
}

struct MobileRootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \UserProfile.name) private var profiles: [UserProfile]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \StepEntry.date, order: .reverse) private var steps: [StepEntry]
    @Query(sort: \WorkoutSession.weekday) private var workouts: [WorkoutSession]
    @Query(sort: \WorkoutProgramArchive.archivedAt, order: .reverse) private var archives: [WorkoutProgramArchive]
    // NOT: `workoutLogs` sorgusu SİLİNDİ. Hiçbir yerde okunmuyordu ama @Query erişimde
    // değil `update()`'te fetch ettiği için WorkoutLog → egzersiz → set ilişki ağacını
    // her açılışta ve her antrenman yazımında materialize edip tüm root body'yi
    // (yani tüm dashboard hesaplarını) yeniden tetikliyordu.
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \RecipeVideo.createdAt, order: .reverse) private var recipeVideos: [RecipeVideo]
    @Query(sort: \FoodPreset.sortOrder) private var presets: [FoodPreset]

    /// Mac'ten gelen "Telefona gönder" feed'i (@Observable → akış/badge reaktif).
    @State private var health = HealthService.shared
    @State private var cloudSync = CloudSyncMonitor.shared

    @State private var selectedTab: MobileTab = .dashboard
    @State private var showAddMeasurement = false
    @State private var saveErrors = SaveErrorReporter.shared
    @State private var remoteAIHealth: RemoteAIHealthResponse?
    @State private var remoteAIError: String?
    @State private var remoteAIChecking = false
    @State private var showProfileEditor = false
    /// Avatar dosyası değişince yüzü tazeleyen sayaç.
    @State private var profileAvatarEpoch = 0
    @State private var showIrohPairing = false
    @State private var showRecipeEditor = false
    @State private var recipeToEdit: Recipe?
    @State private var recipeToView: Recipe?
    @State private var selectedRecipeCategory: RecipeCategory?
    @State private var recipeSearch = ""
    @State private var showFavoriteRecipesOnly = false
    /// Tarif videoları (sadece isim + link) ekleme alanı.
    @State private var newVideoTitle = ""
    @State private var newVideoURL = ""
    /// Tarifler "+" → Video linki sayfası.
    @State private var showAddVideo = false
    @State private var foodToDelete: FoodEntry?
    @State private var measurementToDelete: Measurement?
    @State private var workoutToDelete: WorkoutSession?
    /// Görünüm tercihi (Profil ▸ Görünüm). Değişince body .preferredColorScheme'i tazeler;
    /// dinamik Palette renkleri trait değişimiyle otomatik döner.
    @State private var appearance: AppAppearance = ThemeSettings.appearance

    // Bugün (V12 Çizgi) — öğün listesi açık mı + detayı açık hareket (RIR / dinlenme / not).
    @State private var mealsExpanded = false
    @State private var expandedExerciseID: PersistentIdentifier?


    @State private var aiFoodPickerItems: [PhotosPickerItem] = []
    @FocusState private var aiInputFocused: Bool

    @State private var measurementFullCheckIn = false
    @State private var selectedSeriesIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()

            selectedPage

            mobileBottomBar

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dynamicTypeSize(.small ... .xLarge)
        .preferredColorScheme(appearance.colorScheme)
        .alert("Kaydedilemedi", isPresented: Binding(
            get: { saveErrors.message != nil },
            set: { if !$0 { saveErrors.message = nil } }
        )) {
            Button("Tamam", role: .cancel) { saveErrors.message = nil }
        } message: {
            Text(saveErrors.message ?? "")
        }
        .sheet(isPresented: $showIrohPairing) {
            MobileIrohPairingView()
        }
        .sheet(isPresented: $showAddMeasurement) {
            MobileMeasurementEditor(startFull: measurementFullCheckIn, height: profiles.first?.height) { date, weight, bodyFat, waist, chest, neck, note in
                ctx.insert(Measurement(date: date, weight: weight, bodyFat: bodyFat, waist: waist, chest: chest, neck: neck, note: note))
                ctx.saveOrReport()
                showAddMeasurement = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // `item:` ile: profil satırı henüz yokken (CloudKit import'u inmemiş taze
        // kurulum) `isPresented` BOŞ bir sheet açıyor, kullanıcı da onu hiçbir
        // açıklama olmadan kapatmak zorunda kalıyordu.
        .sheet(item: Binding(
            get: { showProfileEditor ? profiles.first : nil },
            set: { if $0 == nil { showProfileEditor = false } }
        )) { profile in
            MobileProfileEditor(profile: profile) {
                ctx.saveOrReport()
            }
        }
        .sheet(isPresented: $showRecipeEditor) {
            MobileRecipeEditor(
                existing: recipeToEdit,
                onSave: { fields in applyRecipeFields(fields, to: recipeToEdit) },
                onDelete: recipeToEdit.map { recipe in { deleteRecipe(recipe) } }
            )
        }
        .sheet(item: $recipeToView) { recipe in
            MobileRecipeDetailSheet(
                recipe: recipe,
                onSaveEdit: { fields in applyRecipeFields(fields, to: recipe) },
                onDelete: { deleteRecipe(recipe); recipeToView = nil },
                onToggleFavorite: { toggleRecipeFavorite(recipe) }
            )
        }
        .alert(
            "Yemeği sil?",
            isPresented: Binding(get: { foodToDelete != nil }, set: { if !$0 { foodToDelete = nil } }),
            presenting: foodToDelete
        ) { food in
            Button("Sil", role: .destructive) {
                deleteFood(food)
                foodToDelete = nil
            }
            Button("Vazgeç", role: .cancel) { foodToDelete = nil }
        } message: { food in
            Text("\"\(food.name)\" silinecek. Senkronla diğer cihazdan da silinir.")
        }
        .confirmationDialog(
            "Ölçümü sil?",
            isPresented: Binding(get: { measurementToDelete != nil }, set: { if !$0 { measurementToDelete = nil } }),
            presenting: measurementToDelete
        ) { m in
            Button("Sil", role: .destructive) { deleteMeasurement(m); measurementToDelete = nil }
            Button("Vazgeç", role: .cancel) { measurementToDelete = nil }
        } message: { m in
            Text("\(m.date.formatted(date: .abbreviated, time: .omitted)) ölçümü silinecek. Senkronla diğer cihazdan da silinir.")
        }
        .confirmationDialog(
            "Antrenman gününü sil?",
            isPresented: Binding(get: { workoutToDelete != nil }, set: { if !$0 { workoutToDelete = nil } }),
            presenting: workoutToDelete
        ) { w in
            Button("Sil", role: .destructive) { deleteWorkout(w); workoutToDelete = nil }
            Button("Vazgeç", role: .cancel) { workoutToDelete = nil }
        } message: { w in
            Text("\"\(w.name)\" (\(w.weekdayName)) ve hareketleri silinecek. Senkronla diğer cihazdan da silinir.")
        }
        .task {
            await health.start(into: ctx)
            await refreshRemoteAIHealth()
        }
        .onChange(of: profiles.count) { _, count in
            // CloudKit/seed profili çiftlerse (mobil demo + Mac gerçek) tekle → doğru kalori hedefi.
            if count > 1 { DemoSeed.dedupUserProfiles(ctx) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { @MainActor in await health.synchronize(into: ctx) }
            }
        }
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selectedTab {
        case .dashboard:
            mobilePage { dashboardPage }
        case .ai:
            MobileAIChatView(userContext: mobileAIChatContext)
        case .measurements:
            measurementsPage
        case .recipes:
            recipesPage
        case .profile:
            profilePage
        }
    }

    /// Dock beş sekme: Bugün · Tarif · Koç (orta orb) · Ölçüm · Profil.
    private var visibleTabs: [MobileTab] { MobileTab.allCases }

    /// Dock: kartsız. Kayan kart/kenarlık/gölge yok — ikonlar doğrudan zeminde durur,
    /// altlarındaki gradyan içeriğin okunaklılığını korur. Aktif sekme nokta değil
    /// yumuşak hap arkaplanı alır; Koç ise ikon değil orb (uygulamanın kendi renkleri).
    private var mobileBottomBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                let on = selectedTab == tab
                Button {
                    dismissKeyboard()
                    selectedTab = tab
                } label: {
                    Group {
                        if tab == .ai {
                            MobileDockOrb(active: on)
                        } else {
                            Lucide(sf: tab.dockIcon, size: 19)
                                .foregroundStyle(on ? Palette.textPrimary : Palette.textTertiary)
                        }
                    }
                    .frame(width: 54, height: 36)
                    .background {
                        // Orb kendi başına zaten vurgulu — altına hap koymuyoruz.
                        if on, tab != .ai {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Palette.surfaceElevated)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selectedTab)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .background(alignment: .bottom) {
            // Kart yerine yumuşak geçiş. Üstte 28pt silinme, dock hizasından AŞAĞISI
            // düz zemin — safe-area'yı da kapsar, yoksa home-indicator şeridinden
            // kayan içerik görünüyor. Sabit yükseklik: oran hesabı kaba bağlı kalmasın.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Palette.background.opacity(0), Palette.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
                Palette.background
            }
            .padding(.top, -28)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func mobilePage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileChrome.pageSpacing) {
                content()
            }
            .padding(.horizontal, MobileChrome.pageInset)
            .padding(.top, 18)
            .padding(.bottom, MobileChrome.dockClearance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }

    // MARK: - Bugün (V12 "Çizgi")

    /// Mobil tuvaldeki "Bugün · V12 Çizgi": tarih → büyük kalan kalori → öğünlere bölünmüş
    /// kalori çizgisi (dokun → öğün listesi, sola kaydır → sil) → makrolar → bugünün
    /// antrenmanı (bugün plan yoksa Dinlenme + sıradaki seans) → en altta adım · kg · su.
    /// Öğün ekleme tek yoldan: dock'taki koç.
    private var dashboardPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            dashDateLabel
            dashHero
            dashMealLine
            if mealsExpanded {
                dashMealList
                    .transition(.opacity)
            }
            dashMacros
            dashWorkout
            dashCounters
        }
        // Tuvalde tarih satırı güvenli alanın 10 pt altında; mobilePage'in üst 18'i fazla
        // (simülatörde tuvalle piksel ölçümüyle eşlendi).
        .padding(.top, -15)
    }

    /// Tuvaldeki kenar boşlukları sayfanın 18'lik iç boşluğuna göre: metin 28, çizgi 32, sayılar 20.
    private static let dashInset: CGFloat = 10
    private static let dashLineInset: CGFloat = 14
    private static let dashNumberInset: CGFloat = 2

    private static let weekdayUpperFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEEE"
        return f
    }()

    // ── tarih ──
    private var dashDateLabel: some View {
        let text = "\(Self.weekdayUpperFmt.string(from: .now)) · \(Fmt.dayMonth.string(from: .now))"
        return dashSectionLabel(text)
            .padding(.horizontal, Self.dashInset)
            .padding(.top, 10)
    }

    // ── kalan kalori ──
    private var dashHero: some View {
        let intake = todayCalories
        let goal = calorieResult?.goalCalories
        let over = goal.map { intake > $0 } ?? false
        let caption = goal == nil ? "kcal yenen" : (over ? "kcal fazla" : "kcal kaldı")
        return VStack(spacing: 0) {
            CountUpText(
                value: (goal.map { abs($0 - intake) } ?? intake).rounded(),
                font: .system(size: 116, weight: .thin),
                color: over ? Palette.negative : Palette.textPrimary,
                tracking: -5.5
            )
            // Tuvalde satır yüksekliği = punto; SF'nin doğal satırı ~22 pt daha uzun.
            .padding(.top, -9)
            .padding(.bottom, -13.5)
            Text(caption)
                .font(.system(size: 16))
                .foregroundStyle(Palette.textTertiary)
            if goal == nil {
                Text("Profilini doldur — günlük hedefin burada belirir.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    // ── öğün çizgisi (dokun → öğün listesi) ──
    private var dashMealLine: some View {
        let intake = todayCalories
        let goal = calorieResult?.goalCalories ?? 0
        let meals = todayFoods.reversed().map {
            MealLineSegment(time: $0.date, calories: $0.calories)
        }
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { mealsExpanded.toggle() }
        } label: {
            VStack(spacing: 12) {
                MealSegmentLine(meals: meals, intake: intake, goal: goal)
                HStack(alignment: .center, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Fmt.int(intake))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        Text("yenen")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Lucide(sf: mealsExpanded ? "chevron.up" : "chevron.down", size: 12)
                        .foregroundStyle(Palette.textTertiary)
                    Spacer(minLength: 8)
                    if goal > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("hedef")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.textTertiary)
                            Text(Fmt.int(goal))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Öğünler: \(todayFoods.count) kayıt, \(Fmt.int(intake)) kalori")
        .accessibilityHint(mealsExpanded ? "Listeyi kapatır" : "Öğün listesini açar")
        .padding(.horizontal, Self.dashLineInset)
        .padding(.top, 24)
    }

    private var dashMealList: some View {
        VStack(spacing: 0) {
            if todayFoods.isEmpty {
                Text("Bugün öğün kaydı yok.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 11)
            } else {
                ForEach(Array(todayFoods.reversed().enumerated()), id: \.element.persistentModelID) { index, food in
                    if index > 0 { dashHairline }
                    mealRow(food)
                }
            }
        }
        .padding(.horizontal, Self.dashInset)
        .padding(.top, 14)
    }

    /// Sola kaydır → Sil (foodToDelete → onay alert'i → deleteFood). Aynı
    /// renkte kalsın diye rowBackground = page background.
    private func mealRow(_ food: FoodEntry) -> some View {
        MobileSwipeToDelete(onDelete: { foodToDelete = food }, rowBackground: Palette.background) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(Fmt.timeShort.string(from: food.date))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textQuaternary)
                    .frame(width: 40, alignment: .leading)
                Text(food.name)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Fmt.int(food.calories))
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textSecondary)
            }
            .monospacedDigit()
            .padding(.vertical, 11)
        }
    }

    // ── makrolar ──
    private var dashMacros: some View {
        let plan = calorieResult
        return HStack(spacing: 0) {
            dashStat(Fmt.int(todayProtein), "protein", target: plan?.protein.grams, value: todayProtein)
            dashStat(Fmt.int(todayCarbs), "karb", target: plan?.carbs.grams, value: todayCarbs)
            dashStat(Fmt.int(todayFat), "yağ", target: plan?.fat.grams, value: todayFat)
        }
        .padding(.horizontal, Self.dashNumberInset)
        .padding(.top, mealsExpanded ? 28 : 32)
    }

    /// İnce büyük sayı + altında etiket ("/ hedef" soluk). Hedef aşılınca sayı kırmızı.
    private func dashStat(_ text: String, _ label: String, target: Double? = nil, value: Double = 0, color: Color? = nil) -> some View {
        let over = target.map { value > $0 } ?? false
        return VStack(spacing: 3) {
            Text(text)
                .font(.system(size: 28, weight: .light))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(color ?? (over ? Palette.negative : Palette.textPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label)
                    .foregroundStyle(Palette.textTertiary)
                if let target {
                    Text("/ \(Fmt.int(target))")
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity)
    }

    // ── bugünün antrenmanı (yoksa Dinlenme + sıradaki seans) ──
    @ViewBuilder
    private var dashWorkout: some View {
        if let session = todayWorkout {
            VStack(alignment: .leading, spacing: 0) {
                dashSectionLabel("Antrenman")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.name)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(session.durationMinutes) dk")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize()
                }
                .padding(.vertical, 6)
                let exercises = session.sortedTemplateExercises
                if exercises.isEmpty {
                    Text("Hareketler senkronda — Mac'ten gelecek.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.vertical, 11)
                } else {
                    ForEach(Array(exercises.enumerated()), id: \.element.persistentModelID) { index, exercise in
                        if index > 0 { dashHairline }
                        exerciseRow(exercise)
                    }
                }
            }
            .padding(.horizontal, Self.dashInset)
            .padding(.top, 39)
        } else if let next = nextWorkout {
            VStack(alignment: .leading, spacing: 0) {
                dashSectionLabel("Antrenman")
                HStack(spacing: 10) {
                    Lucide(sf: "moon.fill", size: 17)
                        .foregroundStyle(Palette.textSecondary)
                    Text("Dinlenme")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                }
                .padding(.top, 6)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(workoutDayLabel(next))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                    Text(next.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(next.durationMinutes) dk")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize()
                }
                .padding(.top, 18)
                .padding(.bottom, 4)
                if let names = exerciseNamesText(next) {
                    names
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .lineSpacing(3.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Self.dashInset)
            .padding(.top, 39)
        }
    }

    /// Hareket satırı: set×tekrar · ad · yük · teknik linki (Mac'teki "Kaynak"). Satıra
    /// dokununca reçetenin geri kalanı açılır: RIR, dinlenme, hareket notu.
    @ViewBuilder
    private func exerciseRow(_ exercise: WorkoutTemplateExercise) -> some View {
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = exerciseDetail(exercise)
        let isOpen = detail != nil && expandedExerciseID == exercise.persistentModelID
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if name.isEmpty {
                    // İsimsiz satır (koç notu): reçete tam genişlik.
                    Text(exercise.prescriptionText)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(setsRepsText(exercise))
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textQuaternary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 52, alignment: .leading)
                    Text(name)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let load = exercise.load?.nilIfBlank {
                        Text(load)
                            .font(.system(size: 15))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                exerciseLink(exercise.sourceURL)
            }
            .padding(.vertical, 11.5)
            .contentShape(Rectangle())
            .onTapGesture {
                guard detail != nil else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedExerciseID = isOpen ? nil : exercise.persistentModelID
                }
            }
            if isOpen, let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 66)
                    .padding(.top, -3)
                    .padding(.bottom, 11)
                    .transition(.opacity)
            }
        }
    }

    /// Teknik linki. Dokunma alanı 36 pt, satır yüksekliğini büyütmez; link yoksa
    /// hizayı koruyan boş yer.
    @ViewBuilder
    private func exerciseLink(_ raw: String?) -> some View {
        if let url = normalizedURL(raw) {
            Link(destination: url) {
                Lucide(sf: "link", size: 14)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 16, height: 16, alignment: .trailing)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-10)
            .accessibilityLabel("Hareket tekniği linkini aç")
        } else {
            Color.clear
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        }
    }

    private func setsRepsText(_ exercise: WorkoutTemplateExercise) -> String {
        switch (exercise.sets, exercise.reps?.nilIfBlank) {
        case let (sets?, reps?): return "\(sets)×\(reps)"
        case let (sets?, nil): return "\(sets) set"
        case let (nil, reps?): return reps
        default: return ""
        }
    }

    private func exerciseDetail(_ exercise: WorkoutTemplateExercise) -> String? {
        var parts: [String] = []
        if let rir = exercise.rir?.nilIfBlank { parts.append("RIR \(rir)") }
        if let rest = exercise.rest?.nilIfBlank { parts.append("dinlenme \(rest)") }
        var lines = parts.isEmpty ? [] : [parts.joined(separator: " · ")]
        if let note = exercise.notes?.nilIfBlank { lines.append(note) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Dinlenme gününde sıradaki seansın hareketleri tek cümle ("Squat · Leg Press · …");
    /// ad ortadan bölünmesin diye içindeki boşluklar bölünmez boşluk.
    private func exerciseNamesText(_ session: WorkoutSession) -> Text? {
        let names = session.sortedTemplateExercises
            .compactMap { $0.name.nilIfBlank }
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
        guard let first = names.first else { return nil }
        return names.dropFirst().reduce(Text(first)) { text, name in
            text + Text(" · ").foregroundStyle(Palette.textQuaternary) + Text(name)
        }
    }

    /// "Yarın" ya da gün adı ("Perşembe").
    private func workoutDayLabel(_ session: WorkoutSession) -> String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return session.weekday == Calendar.current.component(.weekday, from: tomorrow)
            ? "Yarın"
            : WorkoutSession.weekdayName(session.weekday)
    }

    // ── en alt: adım · kg · su (eski sayaç şeridi) ──
    private var dashCounters: some View {
        VStack(spacing: 26) {
            dashHairline
                .padding(.horizontal, Self.dashInset)
            HStack(spacing: 0) {
                dashStat(Fmt.int(Double(todaySteps)), "adım")
                dashStat(measurements.first?.weight.map { Fmt.num($0, digits: 1) } ?? "—", "kg")
                dashStat(calorieResult.map { Fmt.num($0.water, digits: 1) } ?? "—", "L su")
            }
            .padding(.horizontal, Self.dashNumberInset)
        }
        .padding(.top, 30)
    }

    // ── ortak parçalar ──
    private var dashHairline: some View {
        Rectangle()
            .fill(Palette.textPrimary.opacity(0.06))
            .frame(height: 1)
    }

    private func dashSectionLabel(_ title: String) -> some View {
        Text(title.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.system(size: 12.5, weight: .medium))
            .tracking(1.6)
            .foregroundStyle(Palette.textTertiary)
    }

    private var todayWeekday: Int { Calendar.current.component(.weekday, from: .now) }

    private var todayWorkout: WorkoutSession? {
        activeWorkouts.first { $0.weekday == todayWeekday }
    }

    // MARK: - Ölçümler (V2 "İzleme")

    /// Mobil tuvaldeki "Ölçümler · V2 İzleme": seçili serinin büyük değeri + değişimi, kenardan
    /// kenara borsa çizgisi (basılı tut → gez) ve dönem seçici; altında 7 serinin izleme listesi
    /// (dokun → üstteki grafik o seri), en altta kayıtlar (sola kaydır → sil). Sayfa bütün kayar.
    private var measurementsPage: some View {
        let all = measurementSeries
        let index = min(selectedSeriesIndex, max(all.count - 1, 0))
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                measurementsHead
                if all.isEmpty {
                    Text("Ölçüm yok — + ile ekle.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    let series = all[index]
                    MeasurementTrendPanel(
                        series: series,
                        lowerIsBetter: measurementLowerIsBetter(series.kind),
                        goalDistance: series.kind == .weight ? measurementGoalDistance : nil,
                        cadenceToday: MeasurementCadence.isFullCheckInDay()
                    )
                    .padding(.top, 16)
                    measurementWatchlist(all, selected: index)
                        .padding(.top, 14)
                    measurementRecords
                        .padding(.top, 30)
                }
            }
            .padding(.bottom, MobileChrome.dockClearance)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }

    /// Tuvalde kenar boşluğu 28.
    private static let measureInset: CGFloat = 28

    private var measurementsHead: some View {
        HStack {
            dashSectionLabel("Ölçümler")
            Spacer(minLength: 8)
            Button {
                // Cumartesi tam ölçüm günü: editör o gün Tam Ölçüm modunda açılır.
                measurementFullCheckIn = MeasurementCadence.isFullCheckInDay()
                showAddMeasurement = true
            } label: {
                // Satır tuvaldeki gibi 19 pt; dokunma alanı 29 pt.
                Lucide(sf: "plus", size: 19)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 19, alignment: .trailing)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .padding(.vertical, -5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ölçüm ekle")
        }
        .padding(.horizontal, Self.measureInset)
        .padding(.top, 2)
    }

    /// true = düşük iyi, false = yüksek iyi, nil = nötr (göğüs, boyun). Kilo hedefe göre:
    /// hedef kilo varsa ona doğru, yoksa profildeki amaç (ver / al / koru).
    private func measurementLowerIsBetter(_ kind: MetricKind) -> Bool? {
        switch kind {
        case .bodyFat, .fatMass, .waist: return true
        case .leanMass: return false
        case .chest, .neck: return nil
        case .weight:
            if let target = profiles.first?.targetWeight,
               let now = measurements.first?.weight,
               abs(target - now) >= 0.1 {
                return target < now
            }
            let adjustment = profiles.first?.goal.calorieAdjustment ?? 0
            return adjustment == 0 ? nil : adjustment < 0
        }
    }

    private var measurementGoalDistance: Double? {
        guard let weight = measurements.first?.weight,
              let target = profiles.first?.targetWeight else { return nil }
        return abs(weight - target)
    }

    // ── izleme listesi ──
    private func measurementWatchlist(_ all: [MeasurementSeries], selected: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(all.enumerated()), id: \.element.id) { index, series in
                if index > 0 { dashHairline }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedSeriesIndex = index }
                } label: {
                    measurementWatchRow(series, selected: index == selected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Self.measureInset)
    }

    private func measurementWatchRow(_ series: MeasurementSeries, selected: Bool) -> some View {
        let delta = series.delta ?? 0
        let trend = MeasurementTrendPanel.trend(delta, lowerIsBetter: measurementLowerIsBetter(series.kind))
        let color = MeasurementTrendPanel.color(trend)
        let spark = series.kind == .weight
            ? MeasurementTrendPanel.weeklyAverage(series.dates, series.values).suffix(30).map(\.value)
            : Array(series.values.suffix(30))
        return HStack(spacing: 12) {
            Text(MeasurementTrendPanel.sentenceCase(series.kind.label))
                .font(.system(size: 15, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            MeasurementSparkline(values: spark, color: trend == nil ? Palette.textTertiary : color)
                .frame(width: 58, height: 22)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(series.current.map { Fmt.num($0, digits: 1) } ?? "—")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                Text(series.kind.unit)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(width: 74, alignment: .trailing)
            Text(MeasurementTrendPanel.signedText(delta))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 58)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(trend == nil ? Palette.textPrimary.opacity(0.06) : color.opacity(0.16))
                )
        }
        .monospacedDigit()
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // ── kayıtlar ──
    private var measurementRecords: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                dashSectionLabel("Kayıtlar")
                Spacer(minLength: 8)
                Text("\(measurements.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.bottom, 4)
            ForEach(Array(measurements.prefix(60).enumerated()), id: \.element.persistentModelID) { index, m in
                if index > 0 { dashHairline }
                measurementRow(m)
            }
        }
        .padding(.horizontal, Self.measureInset)
    }

    /// Tarih · saat · TAM · kilo; tam ölçümde yağ/bel/göğüs/boyun, varsa not. Sola kaydır → sil
    /// (measurementToDelete → onay).
    private func measurementRow(_ m: Measurement) -> some View {
        let detail = measurementDetailLine(m)
        return MobileSwipeToDelete(onDelete: { measurementToDelete = m }, rowBackground: Palette.background) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(Fmt.date.string(from: m.date))
                        .foregroundStyle(Palette.textQuaternary)
                        .frame(width: 48, alignment: .leading)
                    Text(Fmt.timeShort.string(from: m.date))
                        .foregroundStyle(Palette.textQuaternary)
                    if !detail.isEmpty {
                        Text("TAM")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(m.weight.map { Fmt.num($0, digits: 1) } ?? "—")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.textPrimary)
                        Text("kg")
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .font(.system(size: 13))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.leading, 62)
                }
                if let note = m.note?.nilIfBlank {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 62)
                }
            }
            .monospacedDigit()
            .padding(.vertical, 11)
        }
    }

    private func measurementDetailLine(_ m: Measurement) -> String {
        [m.bodyFat.map { "Yağ \(Fmt.num($0, digits: 1))" },
         m.waist.map { "Bel \(Fmt.num($0, digits: 1))" },
         m.chest.map { "Göğüs \(Fmt.num($0, digits: 1))" },
         m.neck.map { "Boyun \(Fmt.num($0, digits: 1))" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var measurementSeries: [MeasurementSeries] {
        let asc = measurements.sorted { $0.date < $1.date }
        return MetricKind.allCases.compactMap { kind in
            var vals: [Double] = []
            var dts: [Date] = []
            for m in asc {
                if let v = kind.value(from: m) { vals.append(v); dts.append(m.date) }
            }
            guard !vals.isEmpty else { return nil }
            return MeasurementSeries(kind: kind, values: vals, dates: dts)
        }
    }

    // MARK: - Profil (V6 "Yolculuk")

    /// Mobil tuvaldeki "Profil · V6 Yolculuk": kimlik → "N gündür yolda" → başlangıç · bugün ·
    /// hedef çizgisi (tahmini varış) → verilen kilo · yol · kalan hafta → günlük plan →
    /// Koç / Health / iCloud çipleri (dokun → işlemler). Kaydırınca görünüm ve veri sayımı.
    private var profilePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                profileHead
                profileIdentity
                    .padding(.top, 18)
                profileJourneySection
                profilePlanRow
                    .padding(.top, 30)
                profileStatusChips
                    .padding(.top, 30)
                profileAppearanceRow
                    .padding(.top, 40)
                profileDataLine
                    .padding(.top, 26)
            }
            .padding(.bottom, MobileChrome.dockClearance)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }

    /// Tuvalde kenar boşluğu 28.
    private static let profileInset: CGFloat = 28

    private var profileHead: some View {
        HStack {
            dashSectionLabel("Profil")
            Spacer(minLength: 8)
            // Profil satırı henüz yoksa (taze kurulum, CloudKit inmemiş) editör açılmaz.
            Button { showProfileEditor = true } label: {
                Lucide(sf: "pencil", size: 18)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 19, alignment: .trailing)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .padding(.vertical, -5)
            }
            .buttonStyle(.plain)
            .disabled(profiles.first == nil)
            .accessibilityLabel("Profili düzenle")
        }
        .padding(.horizontal, Self.profileInset)
        .padding(.top, 2)
    }

    private var profileIdentity: some View {
        HStack(spacing: 14) {
            profileAvatar(size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(profileName.isEmpty ? "İsimsiz" : profileName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if let p = profiles.first {
                    Text("\(MeasurementTrendPanel.sentenceCase(p.goal.label)) · \(MeasurementTrendPanel.sentenceCase(p.activity.label))")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Self.profileInset)
    }

    /// Mac'teki profil fotoğrafı (telefonda seçilmez). Yoksa ada göre renkli baş harf.
    private func profileAvatar(size: CGFloat) -> some View {
        Group {
            if profileAvatarEpoch >= 0, let img = ProfileAvatarStore.image() {
                Image(platform: img).resizable().scaledToFill()
            } else {
                InitialFace(name: profileName, fontSize: size * 0.42)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onReceive(NotificationCenter.default.publisher(for: ProfileAvatarStore.changed)) { _ in
            profileAvatarEpoch += 1
        }
    }

    // ── yolculuk ──
    private struct ProfileJourney {
        let startDate: Date
        let startWeight: Double
        let currentWeight: Double
        let target: Double?
        let days: Int
        /// 0…1 — başlangıçtan hedefe alınan yol.
        let progress: Double?
        let weeksLeft: Double?
        let eta: Date?

        var change: Double { currentWeight - startWeight }
        /// Değişim hedefe doğru mu (hedef yoksa nil).
        var towardTarget: Bool? {
            guard let target, abs(change) >= 0.05 else { return nil }
            return (target - startWeight) * change > 0
        }
    }

    /// İlk tartıdan bugüne. Tahmini varış: toplam haftalık hız hedefe doğruysa (≥ 2 hafta veri).
    private var profileJourney: ProfileJourney? {
        // `measurements` yeniden eskiye sıralı.
        let weighed = measurements.compactMap { m in m.weight.map { (date: m.date, weight: $0) } }
        guard let latest = weighed.first, let first = weighed.last else { return nil }
        let calendar = Calendar.current
        let days = max(0, calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: first.date),
            to: calendar.startOfDay(for: .now)
        ).day ?? 0)
        let target = profiles.first?.targetWeight
        var progress: Double?
        if let target, abs(first.weight - target) >= 0.1 {
            progress = min(max((first.weight - latest.weight) / (first.weight - target), 0), 1)
        }
        var weeksLeft: Double?
        var eta: Date?
        let spanDays = latest.date.timeIntervalSince(first.date) / 86_400
        if let target, spanDays >= 14 {
            let perWeek = (latest.weight - first.weight) / (spanDays / 7)
            let remaining = target - latest.weight
            if abs(remaining) < 0.05 {
                weeksLeft = 0
            } else if perWeek != 0, remaining / perWeek > 0, remaining / perWeek < 520 {
                weeksLeft = remaining / perWeek
                eta = calendar.date(byAdding: .day, value: Int((remaining / perWeek * 7).rounded()), to: .now)
            }
        }
        return ProfileJourney(
            startDate: first.date,
            startWeight: first.weight,
            currentWeight: latest.weight,
            target: target,
            days: days,
            progress: progress,
            weeksLeft: weeksLeft,
            eta: eta
        )
    }

    private static let etaFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    @ViewBuilder
    private var profileJourneySection: some View {
        if let journey = profileJourney {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("\(journey.days)")
                        .font(.system(size: 116, weight: .thin))
                        .tracking(-5.5)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.top, -9)
                        .padding(.bottom, -13.5)
                    Text("gündür yolda")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                if let target = journey.target, let progress = journey.progress {
                    journeyLine(journey, target: target, progress: progress)
                        .padding(.top, 28)
                    journeyNumbers(journey, progress: progress)
                        .padding(.top, 30)
                } else {
                    Button { showProfileEditor = true } label: {
                        HStack(spacing: 6) {
                            Lucide(sf: "target", size: 13)
                            Text("Hedef kilo belirle")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Palette.textPrimary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .disabled(profiles.first == nil)
                    .padding(.top, 24)
                }
            }
            .padding(.top, 34)
        } else {
            Text("İlk tartınla yolculuk başlar.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    /// Başlangıç ● ━━ bugün ● ┄┄┄ ○ hedef. Üstünde "bugün", altında tarih/kilo uçları.
    private func journeyLine(_ journey: ProfileJourney, target: Double, progress: Double) -> some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let width = geo.size.width
                let x = width * progress
                ZStack(alignment: .topLeading) {
                    Text("bugün")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize()
                        .position(x: min(max(x, 18), width - 18), y: 8)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 28))
                        p.addLine(to: CGPoint(x: width, y: 28))
                    }
                    .stroke(Palette.textPrimary.opacity(0.16), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                    Capsule()
                        .fill(Palette.textPrimary)
                        .frame(width: max(x, 0), height: 2)
                        .offset(y: 27)
                    Circle()
                        .fill(Palette.textPrimary)
                        .frame(width: 8, height: 8)
                        .position(x: 0, y: 28)
                    Circle()
                        .strokeBorder(Palette.positive, lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                        .position(x: width, y: 28)
                    Circle()
                        .fill(Palette.textPrimary)
                        .frame(width: 12, height: 12)
                        .shadow(color: Palette.textPrimary.opacity(0.45), radius: 7)
                        .position(x: x, y: 28)
                }
            }
            .frame(height: 34)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.date.string(from: journey.startDate))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                    Text("\(Fmt.num(journey.startWeight, digits: 1)) kg")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if let eta = journey.eta {
                        Text("~\(Self.etaFmt.string(from: eta))")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.positive)
                    } else {
                        Text("hedef")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Text("\(Fmt.num(target, digits: 1)) kg")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 32)
    }

    private func journeyNumbers(_ journey: ProfileJourney, progress: Double) -> some View {
        let change = journey.change
        let changeLabel = abs(change) < 0.05 ? "kg değişim" : (change < 0 ? "kg verildi" : "kg alındı")
        let changeColor: Color = {
            guard let toward = journey.towardTarget else { return Palette.textPrimary }
            return toward ? Palette.positive : Palette.negative
        }()
        return HStack(spacing: 0) {
            dashStat(MeasurementTrendPanel.signedText(change), changeLabel, color: changeColor)
            dashStat("%\(Int((progress * 100).rounded()))", "yol")
            dashStat(journey.weeksLeft.map { "\(Int($0.rounded()))" } ?? "—", "hafta kaldı")
        }
        .padding(.horizontal, Self.dashNumberInset)
    }

    // ── günlük plan (tek satır) ──
    @ViewBuilder
    private var profilePlanRow: some View {
        if let plan = calorieResult {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.int(plan.goalCalories))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    Text("kcal / gün")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
                .monospacedDigit()
                Spacer(minLength: 12)
                RecipeMacroBar(
                    protein: plan.protein.grams,
                    carbs: plan.carbs.grams,
                    fat: plan.fat.grams,
                    width: 150,
                    height: 4,
                    spacing: 3
                )
            }
            .padding(.horizontal, Self.profileInset)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Günlük hedef \(Fmt.int(plan.goalCalories)) kalori, protein \(Fmt.int(plan.protein.grams)) gram, karbonhidrat \(Fmt.int(plan.carbs.grams)) gram, yağ \(Fmt.int(plan.fat.grams)) gram")
        } else {
            Text("Profilini doldur — günlük hedef burada görünür.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, Self.profileInset)
        }
    }

    // ── Koç · Health · iCloud (dokun → işlemler) ──
    private var profileStatusChips: some View {
        HStack(spacing: 0) {
            Menu {
                Section(remoteAIStatusText) {
                    Button {
                        showIrohPairing = true
                    } label: {
                        Label(
                            HerculesIrohTransport.isAvailable ? "Telefon bağlantısı ✓" : "Telefon bağlantısı kur",
                            systemImage: "qrcode.viewfinder"
                        )
                    }
                    Button {
                        Task { await refreshRemoteAIHealth() }
                    } label: {
                        Label("Bağlantıyı kontrol et", systemImage: "arrow.clockwise")
                    }
                    .disabled(remoteAIChecking)
                }
            } label: {
                profileStatusChip("Koç", status: coachChipText, color: coachChipColor)
            }
            Menu {
                Section(health.statusText) {
                    Button {
                        Task { @MainActor in await health.requestAccessAndSync(into: ctx) }
                    } label: {
                        Label("Yenile", systemImage: "arrow.clockwise")
                    }
                    .disabled(health.status == .syncing)
                }
            } label: {
                profileStatusChip("Health", status: healthChipText, color: healthStatusColor)
            }
            Menu {
                Section(cloudSync.statusText) {
                    Text(cloudSync.detailText)
                }
            } label: {
                profileStatusChip("iCloud", status: cloudChipText, color: cloudChipColor)
            }
        }
        .padding(.horizontal, 16)
    }

    private func profileStatusChip(_ name: String, status: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.6), radius: 3)
                Text(name)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textPrimary)
            }
            Text(status)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var coachChipText: String {
        if remoteAIChecking { return "kontrol…" }
        if remoteAIHealth != nil { return "bağlı" }
        return remoteAIError != nil ? "ulaşılamıyor" : "kontrol edilmedi"
    }

    private var coachChipColor: Color {
        if remoteAIChecking { return Palette.warning }
        if remoteAIHealth != nil { return Palette.positive }
        return remoteAIError != nil ? Palette.negative : Palette.textTertiary
    }

    private var healthChipText: String {
        switch health.status {
        case .ready: return "\(Fmt.int(Double(todaySteps))) adım"
        case .syncing: return "okunuyor…"
        case .notDetermined: return "izin bekliyor"
        case .empty: return "veri yok"
        case .unavailable: return "kullanılamıyor"
        case .error: return "hata"
        }
    }

    private var healthStatusColor: Color {
        switch health.status {
        case .ready:
            return Palette.positive
        case .error:
            return Palette.negative
        default:
            return Palette.textTertiary
        }
    }

    private var cloudChipText: String {
        switch cloudSync.state {
        case .ready(let date): return date.map { Fmt.relative($0) } ?? "hazır"
        case .checking: return "kontrol…"
        case .syncing: return "senkronlanıyor…"
        case .unavailable: return "kullanılamıyor"
        case .error: return "hata"
        }
    }

    private var cloudChipColor: Color {
        switch cloudSync.state {
        case .ready: return Palette.positive
        case .checking, .syncing: return Palette.warning
        case .unavailable, .error: return Palette.negative
        }
    }

    // ── görünüm + veri (aşağıda) ──
    private var profileAppearanceRow: some View {
        HStack {
            dashSectionLabel("Görünüm")
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                appearanceOption(.dark, "Koyu")
                appearanceOption(.light, "Açık")
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
        }
        .padding(.horizontal, Self.profileInset)
    }

    private func appearanceOption(_ mode: AppAppearance, _ title: String) -> some View {
        let on = appearance == mode
        return Button {
            ThemeSettings.appearance = mode
            withAnimation(.easeInOut(duration: 0.2)) { appearance = mode }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Palette.textPrimary : Palette.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? Palette.textPrimary.opacity(0.10) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var profileDataLine: some View {
        let items: [(Int, String)] = [
            (measurements.count, "ölçüm"), (foods.count, "yemek"), (recipes.count, "tarif"),
            (activeWorkouts.count, "antrenman"), (steps.count, "adım günü"), (archives.count, "arşiv"),
        ]
        let text = items.enumerated().reduce(Text("")) { acc, pair in
            let (index, item) = pair
            let piece = Text("\(item.0)").foregroundStyle(Palette.textSecondary)
                + Text("\u{00A0}\(item.1.replacingOccurrences(of: " ", with: "\u{00A0}"))")
            return index == 0 ? piece : acc + Text(" · ").foregroundStyle(Palette.textQuaternary) + piece
        }
        return VStack(alignment: .leading, spacing: 8) {
            dashSectionLabel("Veri")
            text
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Self.profileInset)
    }

    private var remoteAIStatusText: String {
        if remoteAIHealth != nil { return "Koç hazır" }
        if let remoteAIError { return remoteAIError }
        return "Bağlantı henüz kontrol edilmedi"
    }

    private func heroStat(_ label: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Lucide(sf: systemImage, size: 12)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textQuaternary)
                    .textCase(.uppercase)
                Text(value)
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
    }

    // MARK: - Tarifler (V1 "Arama")

    /// Mobil tuvaldeki "Tarifler · V1 Arama": sabit baş (TARİFLER + "+", büyük ince arama,
    /// sayılı kategori sekmeleri + yalnız-favori kalbi) ve kayan liste (makro lejantı →
    /// tarif satırları → Videolar). Tarife dokun → detay; kalbe dokun → favori.
    private var recipesPage: some View {
        VStack(spacing: 0) {
            recipesHeader
            recipesSearchField
            recipesCategoryTabs
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filteredRecipes.isEmpty {
                        Text(recipes.isEmpty ? "Tarif yok — + ile ekle ya da koça sor." : "Bu aramada tarif yok.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 28)
                    } else {
                        recipeMacroLegend
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        ForEach(Array(filteredRecipes.enumerated()), id: \.element.persistentModelID) { index, recipe in
                            if index > 0 { dashHairline }
                            recipeRow(recipe)
                        }
                    }
                    if !recipeVideos.isEmpty {
                        recipeVideosSection
                            .padding(.top, 26)
                    }
                }
                .padding(.horizontal, Self.recipeInset)
                .padding(.bottom, MobileChrome.dockClearance)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .sheet(isPresented: $showAddVideo) {
            addVideoSheet
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }

    /// Tuvalde kenar boşluğu 28.
    private static let recipeInset: CGFloat = 28

    private var recipesHeader: some View {
        HStack {
            dashSectionLabel("Tarifler")
            Spacer(minLength: 8)
            // Mobilde tarif eklemenin tek yolu buydu (editör vardı ama açılmıyordu) + video linki.
            Menu {
                Button {
                    recipeToEdit = nil
                    showRecipeEditor = true
                } label: {
                    Label("Tarif", systemImage: "fork.knife")
                }
                Button {
                    showAddVideo = true
                } label: {
                    Label("Video linki", systemImage: "play.rectangle")
                }
            } label: {
                Lucide(sf: "plus", size: 19)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Ekle")
        }
        .padding(.horizontal, Self.recipeInset)
        .padding(.top, 2)
    }

    private var recipesSearchField: some View {
        HStack(spacing: 12) {
            Lucide(sf: "magnifyingglass", size: 22)
                .foregroundStyle(Palette.textTertiary)
            TextField(
                "",
                text: $recipeSearch,
                prompt: Text("Tarif ara").foregroundStyle(Palette.textTertiary)
            )
            .font(.system(size: 28, weight: .light))
            .tracking(-0.4)
            .foregroundStyle(Palette.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            if !recipeSearch.isEmpty {
                Button { recipeSearch = "" } label: {
                    Lucide(sf: "xmark", size: 14)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { dashHairline }
        .padding(.horizontal, Self.recipeInset)
        .padding(.top, 22)
    }

    /// Tümü · Kahvaltı · Akşam · Tatlı (yanında sayısı) + sağda yalnız-favoriler kalbi.
    private var recipesCategoryTabs: some View {
        HStack(alignment: .bottom, spacing: 20) {
            recipeTab("Tümü", count: recipes.count, active: selectedRecipeCategory == nil) {
                selectedRecipeCategory = nil
            }
            ForEach(RecipeCategory.allCases) { category in
                recipeTab(
                    category == .dinner ? "Akşam" : category.label,
                    count: recipes.filter { $0.category == category }.count,
                    active: selectedRecipeCategory == category
                ) {
                    selectedRecipeCategory = (selectedRecipeCategory == category) ? nil : category
                }
            }
            Spacer(minLength: 4)
            Button {
                showFavoriteRecipesOnly.toggle()
            } label: {
                Lucide(sf: "heart", size: 15)
                    .foregroundStyle(showFavoriteRecipesOnly ? Palette.warning : Palette.textTertiary)
                    .padding(.bottom, 7)
                    .overlay(alignment: .bottom) { recipeTabUnderline(showFavoriteRecipesOnly) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showFavoriteRecipesOnly ? "Tüm tarifler" : "Yalnız favoriler")
        }
        .padding(.horizontal, Self.recipeInset)
        // Tuvalde sekme çizgisi ekran boyu (arama çizgisi ise içeride).
        .overlay(alignment: .bottom) { dashHairline }
        .padding(.top, 18)
    }

    private func recipeTab(_ title: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Palette.textPrimary : Palette.textTertiary)
                Text("\(count)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textQuaternary)
            }
            .fixedSize()
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) { recipeTabUnderline(active) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recipeTabUnderline(_ active: Bool) -> some View {
        Rectangle()
            .fill(active ? Palette.textPrimary : .clear)
            .frame(height: 1.5)
    }

    private var recipeMacroLegend: some View {
        HStack(spacing: 14) {
            ForEach([("protein", Palette.macroProtein), ("karb", Palette.macroCarbs), ("yağ", Palette.macroFat)], id: \.0) { name, color in
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    /// Satır: kalp · ad · kcal; altında makro çubuğu (P/K/Y kalori payı) + protein · süre,
    /// sağda kategori ikonu.
    private func recipeRow(_ recipe: Recipe) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                toggleRecipeFavorite(recipe)
            } label: {
                Lucide(sf: "heart", size: 14)
                    .foregroundStyle(recipe.isFavorite ? Palette.warning : Palette.textQuaternary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-8)
            .padding(.top, 2)
            .accessibilityLabel(recipe.isFavorite ? "Favoriden çıkar" : "Favoriye ekle")

            VStack(alignment: .leading, spacing: 7) {
                Text(recipe.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    RecipeMacroBar(protein: recipe.protein, carbs: recipe.carbs, fat: recipe.fat)
                    recipeFacts(recipe)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(recipe.calories.map(Fmt.int) ?? "—")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textSecondary)
                    Text("kcal")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
                Lucide(sf: recipe.category.icon, size: 13)
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
        .monospacedDigit()
        .padding(.vertical, 12.75)
        .contentShape(Rectangle())
        .onTapGesture { recipeToView = recipe }
    }

    /// "58 g protein · 35 dk" — olmayan parça atlanır.
    @ViewBuilder
    private func recipeFacts(_ recipe: Recipe) -> some View {
        let protein = recipe.protein.map(Fmt.int)
        let minutes = recipe.prepMinutes
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let protein {
                Text(protein).foregroundStyle(Palette.textSecondary)
                Text("g protein").foregroundStyle(Palette.textTertiary)
            }
            if protein != nil, minutes != nil {
                Text("·").foregroundStyle(Palette.textQuaternary)
            }
            if let minutes {
                Text("\(minutes)").foregroundStyle(Palette.textSecondary)
                Text("dk").foregroundStyle(Palette.textTertiary)
            }
        }
        .font(.system(size: 13))
        .lineLimit(1)
    }

    private var filteredRecipes: [Recipe] {
        var result = recipes
        if showFavoriteRecipesOnly { result = result.filter(\.isFavorite) }
        if let category = selectedRecipeCategory { result = result.filter { $0.category == category } }
        let query = recipeSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { recipe in
                recipe.title.lowercased().contains(query)
                    || (recipe.summary?.lowercased().contains(query) ?? false)
                    || (recipe.ingredientsText?.lowercased().contains(query) ?? false)
                    || (recipe.instructionsText?.lowercased().contains(query) ?? false)
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func toggleRecipeFavorite(_ recipe: Recipe) {
        recipe.isFavorite.toggle()
        recipe.updatedAt = .now
        ctx.saveOrReport()
    }

    // MARK: - Tarif videoları (isim + link)

    private var canAddVideo: Bool {
        !newVideoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newVideoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// "Videolar" rafı — sadece isim + link, Mac ile senkron. Dokun → aç, uzun bas → sil.
    /// Ekleme "+" menüsünden (`addVideoSheet`).
    private var recipeVideosSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                dashSectionLabel("Videolar")
                Spacer(minLength: 8)
                Text("\(recipeVideos.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.bottom, 4)
            ForEach(Array(recipeVideos.enumerated()), id: \.element.persistentModelID) { index, video in
                if index > 0 { dashHairline }
                recipeVideoRow(video)
            }
        }
    }

    @ViewBuilder
    private func recipeVideoRow(_ video: RecipeVideo) -> some View {
        let row = HStack(spacing: 14) {
            Lucide(sf: "play.rectangle", size: 15)
                .foregroundStyle(Palette.textTertiary)
            Text(video.title)
                .font(.system(size: 15))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(video.sourceHost ?? video.urlString)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
            Lucide(sf: "arrow.up.right", size: 14)
                .foregroundStyle(Palette.textQuaternary)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())

        Group {
            if let url = video.url {
                Link(destination: url) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteRecipeVideo(video)
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    /// "+" → Video linki: isim + link, Ekle.
    private var addVideoSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            dashSectionLabel("Video ekle")
            addVideoField("İsim", text: $newVideoTitle, isURL: false)
                .padding(.top, 22)
            addVideoField("Link", text: $newVideoURL, isURL: true)
                .padding(.top, 18)
            Button {
                addRecipeVideo()
                showAddVideo = false
            } label: {
                Text("Ekle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canAddVideo ? Palette.btnFg : Palette.textQuaternary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(canAddVideo ? Palette.accent : Palette.surfaceElevated))
            }
            .buttonStyle(.plain)
            .disabled(!canAddVideo)
            .padding(.top, 28)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.recipeInset)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background.ignoresSafeArea())
    }

    private func addVideoField(_ title: String, text: Binding<String>, isURL: Bool) -> some View {
        TextField("", text: text, prompt: Text(title).foregroundStyle(Palette.textTertiary))
            .font(.system(size: 17))
            .foregroundStyle(Palette.textPrimary)
            .keyboardType(isURL ? .URL : .default)
            .textInputAutocapitalization(isURL ? .never : .sentences)
            .autocorrectionDisabled(isURL)
            .submitLabel(isURL ? .done : .next)
            .onSubmit {
                if isURL, canAddVideo {
                    addRecipeVideo()
                    showAddVideo = false
                }
            }
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { dashHairline }
    }

    private func presetRow(_ preset: FoodPreset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.brand)
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textTertiary)
                    Text(preset.name)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text("\(Fmt.int(preset.calories(for: preset.defaultServings))) kalori")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
            }
            Text("P \(Fmt.num(preset.protein(for: preset.defaultServings) ?? 0, digits: 1))g · K \(Fmt.num(preset.carbs(for: preset.defaultServings) ?? 0, digits: 1))g · Y \(Fmt.num(preset.fat(for: preset.defaultServings) ?? 0, digits: 1))g")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
            Button {
                addPreset(preset, servings: preset.defaultServings)
            } label: {
                Label { Text("+ \(preset.servingCountText(preset.defaultServings))") } icon: { Lucide(sf: "plus") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surfaceElevated))
    }

    private func metric(_ label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(Palette.textQuaternary)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Typography.monoLarge)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
    }

    private func macroPill(_ label: String, _ value: Double?, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(color)
            Text("\(Fmt.num(value ?? 0, digits: 0))g")
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.surface))
    }

    private func icon(_ systemName: String, color: Color) -> some View {
        Lucide(sf: systemName, size: 15)
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private var profileName: String {
        profiles.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Bugünün toplamları TEK geçişte. Eskiden dört ayrı computed property'nin her
    /// biri `todayFoods`'u sıfırdan kuruyordu (yeni Calendar + yeni filtrelenmiş dizi);
    /// tek dashboard render'ında tüm FoodEntry tablosu 6+ kez taranıyordu ve maliyet
    /// kayıt geçmişiyle birlikte sonsuza dek büyüyordu.
    struct DailyTotals: Equatable {
        var calories: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var entryCount: Int = 0
    }

    private var todayFoods: [FoodEntry] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? .distantFuture
        // `foods` tarihe göre AZALAN sıralı: önce (varsa) ileri tarihli satırları atla,
        // sonra bugünü al, ilk eski satırda dur. Tam tablo taraması yok.
        return Array(foods.drop { $0.date >= startOfTomorrow }.prefix { $0.date >= startOfToday })
    }

    /// Tek geçişte hesaplanır; `todayFoods` yalnız bugünün satırlarını gezdiği için
    /// birkaç kez okunması da ucuz.
    private var dailyTotals: DailyTotals { computeDailyTotals() }

    private func computeDailyTotals() -> DailyTotals {
        var totals = DailyTotals()
        for entry in todayFoods {
            totals.calories += entry.calories
            totals.protein += entry.protein ?? 0
            totals.carbs += entry.carbs ?? 0
            totals.fat += entry.fat ?? 0
            totals.entryCount += 1
        }
        return totals
    }

    private var todayCalories: Double { dailyTotals.calories }
    private var todayProtein: Double { dailyTotals.protein }
    private var todayCarbs: Double { dailyTotals.carbs }
    private var todayFat: Double { dailyTotals.fat }

    private var calorieResult: CalorieResult? {
        guard let profile = profiles.first,
              let latest = measurements.first,
              let weight = latest.weight else { return nil }
        return CalorieCalculator.compute(
            weight: weight,
            height: profile.height,
            age: profile.age,
            sex: profile.sex,
            bodyFat: latest.bodyFat ?? profile.manualBodyFat,
            activity: profile.activity,
            goal: profile.goal,
            manualOffset: profile.manualCalorieOffset,
            manualOffsetMacro: profile.manualCalorieOffsetMacro,
            manualProteinGrams: profile.manualProteinGrams,
            manualCarbsGrams: profile.manualCarbsGrams,
            manualFatGrams: profile.manualFatGrams
        )
    }

    private var todaySteps: Int {
        StepEntry.preferredToday(from: steps)?.steps ?? 0
    }

    private var activeWorkouts: [WorkoutSession] {
        workouts
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.weekday < $1.weekday }
    }

    private var presetItems: [MobilePresetItem] {
        presets.map { MobilePresetItem(id: $0.presetID, preset: $0) }
    }

    /// Sıradaki antrenman — haftayı Pazartesi'den başlatarak. Eskiden Gregorian
    /// weekday (1=Pazar) ile karşılaştırılıyordu; arayüz ise haftayı Pt→Pz
    /// gösteriyor. Sonuç: Pazar seansı hafta içi hiçbir zaman ">= bugün" koşulunu
    /// sağlayamıyor, fallback devreye girip 4 gün sonraki Pazar'ı "sıradaki" diye
    /// gösteriyordu — bu metin koça da gönderiliyor.
    private var nextWorkout: WorkoutSession? {
        let today = Self.mondayFirstIndex(Calendar.current.component(.weekday, from: .now))
        let ordered = activeWorkouts.sorted {
            Self.mondayFirstIndex($0.weekday) < Self.mondayFirstIndex($1.weekday)
        }
        return ordered.first { Self.mondayFirstIndex($0.weekday) >= today } ?? ordered.first
    }

    /// Gregorian weekday (1=Pazar…7=Cumartesi) → 0=Pazartesi…6=Pazar.
    private static func mondayFirstIndex(_ gregorianWeekday: Int) -> Int {
        (gregorianWeekday + 5) % 7
    }

    private func addPreset(_ preset: FoodPreset, servings: Double) {
        ctx.insert(preset.makeFoodEntry(servings: servings))
        ctx.saveOrReport()
    }

    private func applyRecipeFields(_ f: RecipeFields, to existing: Recipe?) {
        let recipe = existing ?? Recipe(title: f.title, urlString: f.url, category: f.category)
        recipe.title = f.title
        recipe.category = f.category
        recipe.urlString = f.url
        recipe.summary = f.summary
        recipe.ingredientsText = f.ingredients
        recipe.instructionsText = f.instructions
        recipe.calories = f.calories
        recipe.protein = f.protein
        recipe.carbs = f.carbs
        recipe.fat = f.fat
        if existing == nil { ctx.insert(recipe) }
        ctx.saveOrReport()
    }

    private func deleteRecipe(_ recipe: Recipe) {
        ctx.delete(recipe)
        ctx.saveOrReport()
    }

    private func addRecipeVideo() {
        let title = newVideoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var url = newVideoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !url.isEmpty else { return }
        let lower = url.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            url = "https://" + url
        }
        let video = RecipeVideo(title: title, urlString: url)
        ctx.insert(video)
        ctx.saveOrReport()
        newVideoTitle = ""
        newVideoURL = ""
    }

    private func deleteRecipeVideo(_ video: RecipeVideo) {
        ctx.delete(video)
        ctx.saveOrReport()
    }

    /// Yemek kaydını sil. SwiftData değişikliği CloudKit tarafından diğer cihazlara taşınır.
    private func deleteFood(_ food: FoodEntry) {
        ctx.delete(food)
        ctx.saveOrReport()
    }

    private func deleteMeasurement(_ m: Measurement) {
        ctx.delete(m)
        ctx.saveOrReport()
    }

    /// Antrenman programı gününü sil (hareketler cascade ile gider).
    private func deleteWorkout(_ w: WorkoutSession) {
        ctx.delete(w)
        ctx.saveOrReport()
    }

    private var mobileAIChatContext: String {
        let profile = profiles.first
        let latest = measurements.first
        let workout = nextWorkout.map { "\($0.weekdayName): \($0.name)" } ?? "plan yok"
        return """
        === HERCULES MOBILE LIVE CONTEXT ===
        Kullanıcı: \(profile?.name.nilIfBlank ?? "isimsiz")
        Hedef: \(profile?.goal.label ?? "bilinmiyor")
        Son kilo: \(latest?.weight.map { "\(Fmt.num($0, digits: 1)) kg" } ?? "yok")
        Son yağ oranı: \(latest?.bodyFat.map { "\(Fmt.num($0, digits: 1))%" } ?? "yok")
        Bugün: \(Fmt.int(todayCalories)) kcal · P \(Fmt.int(todayProtein))g · K \(Fmt.int(todayCarbs))g · Y \(Fmt.int(todayFat))g
        Bugünkü HealthKit adımı: \(todaySteps)
        Sıradaki antrenman: \(workout)
        Bu özet telefondaki son senkronlanan veriden üretildi; Mac snapshot'ı daha güncelse onu esas al.
        === MOBILE CONTEXT SONU ===
        """
    }

    @MainActor
    private func refreshRemoteAIHealth() async {
        guard !remoteAIChecking else { return }
        remoteAIChecking = true
        defer { remoteAIChecking = false }
        do {
            remoteAIHealth = try await RemoteAIClient().health()
            remoteAIError = nil
        } catch {
            remoteAIHealth = nil
            remoteAIError = "Koç'a ulaşılamıyor. Tailscale bağlantını kontrol et."
        }
    }

    private func number(_ raw: String) -> Double? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func normalizedURL(_ raw: String?) -> URL? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

}

/// Mobil profil editörü — kişisel bilgi, hedef, manuel makro ve supplement.
/// Sayı alanları string ayna ile tutulur (opsiyonel Double bağlama kolaylığı için).
/// Mac MeasurementEditor'ün mobil portu — V1 dili: segment (Tartı | Tam Ölçüm),
/// gizli/açılır tarih çipi (gün gezgini + saat), tek zorunlu alan kilo, Tam'da
/// US Navy oto yağ oranı + Not. Tasarım masaüstüyle aynı; dokunmaya uyarlandı.
struct MobileMeasurementEditor: View {
    var startFull: Bool
    var height: Double?
    var onSave: (_ date: Date, _ weight: Double?, _ bodyFat: Double?, _ waist: Double?, _ chest: Double?, _ neck: Double?, _ note: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var waist: Double?
    @State private var chest: Double?
    @State private var neck: Double?
    @State private var note = ""
    @State private var showExtra: Bool
    @State private var dateOpen = false
    @State private var bodyFatManual = false
    @State private var heightLocal: Double?
    @FocusState private var weightFocused: Bool

    private static let trLocale = Locale(identifier: "tr_TR")

    init(
        startFull: Bool,
        height: Double?,
        onSave: @escaping (Date, Double?, Double?, Double?, Double?, Double?, String?) -> Void
    ) {
        self.startFull = startFull
        self.height = height
        self.onSave = onSave
        _showExtra = State(initialValue: startFull)
        _heightLocal = State(initialValue: height)
    }

    private var canSave: Bool { weight != nil }
    private var titleText: String { showExtra ? "Tam ölçüm" : "Tartı ekle" }
    private var saveTitle: String { showExtra ? "Tam Ölçüm Ekle" : "Tartı Ekle" }
    private var modeHint: String { showExtra ? "kilo zorunlu, detaylar opsiyonel" : "günlük akış için sadece kilo yeterli" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                dateRow
                numberField(label: "Kilo", unit: "kg", value: $weight, big: true, required: true)
                    .focused($weightFocused)
                if showExtra {
                    detailFields
                        .transition(.opacity)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { footer }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showExtra)
        .animation(.easeInOut(duration: 0.16), value: dateOpen)
        .preferredColorScheme(ThemeSettings.appearance.colorScheme)
        .onAppear {
            if heightLocal == nil { heightLocal = height }
        }
        // `.task` sheet kapanınca otomatik iptal olur; `asyncAfter` iptal edilemediği
        // için 350 ms içinde kapatılan sayfada odak yok olmuş view'a gidiyordu.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            weightFocused = true
        }
    }

    // MARK: - Başlık + segment

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yeni Kayıt")
                        .font(Typography.label).tracking(0.9).textCase(.uppercase)
                        .foregroundStyle(Palette.textQuaternary)
                    Text(titleText)
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Lucide(sf: "xmark", size: 13)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Palette.surface))
                        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            modeSegment
        }
    }

    private var modeSegment: some View {
        HStack(spacing: 2) {
            segmentItem("Tartı", selected: !showExtra) { showExtra = false }
            segmentItem("Tam Ölçüm", selected: showExtra) { showExtra = true }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private func segmentItem(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(selected ? Palette.btnFg : Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Palette.btnBg : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tarih (gizli çip → gün gezgini + saat)

    private var dateRow: some View {
        HStack(alignment: .center, spacing: 10) {
            if dateOpen { openDateChip } else { collapsedDateChip }
            Spacer(minLength: 8)
            Text(dateOpen ? relativeDayHint : modeHint)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var collapsedDateChip: some View {
        Button { dateOpen = true } label: {
            HStack(spacing: 7) {
                Text(shortDayLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Text(Fmt.timeShort.string(from: date))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                Lucide(sf: "chevron.down", size: 8)
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var openDateChip: some View {
        HStack(spacing: 8) {
            Button { stepDay(-1) } label: {
                Lucide(sf: "chevron.left", size: 10)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain)

            Button { dateOpen = false } label: {
                Text(Fmt.dayMonth.string(from: date))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize().contentShape(Rectangle())
            }.buttonStyle(.plain)

            Button { stepDay(1) } label: {
                Lucide(sf: "chevron.right", size: 10)
                    .foregroundStyle(canStepForward ? Palette.textTertiary : Palette.textQuaternary.opacity(0.4))
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!canStepForward)

            Rectangle().fill(Palette.border).frame(width: 1, height: 14)

            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.locale, Self.trLocale)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.accent.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1))
    }

    private var shortDayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInYesterday(date) { return "Dün" }
        return Fmt.dayMonth.string(from: date)
    }

    private var relativeDayHint: String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: .now)).day ?? 0
        switch days {
        case 0:  return "bugünü giriyorsun"
        case 1:  return "dünü giriyorsun"
        default: return "\(days) gün öncesini giriyorsun"
        }
    }

    private var canStepForward: Bool { !Calendar.current.isDateInToday(date) && date < .now }

    private func stepDay(_ delta: Int) {
        guard let stepped = Calendar.current.date(byAdding: .day, value: delta, to: date) else { return }
        date = min(stepped, .now)
    }

    // MARK: - Alanlar

    private func numberField(label: String, unit: String, value: Binding<Double?>, big: Bool = false, required: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(label)
                    .font(Typography.label).tracking(0.9).textCase(.uppercase)
                    .foregroundStyle(Palette.textQuaternary)
                if required { Circle().fill(Palette.accent).frame(width: 4, height: 4) }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                TextField("0,0", value: value, format: .number.precision(.fractionLength(0...2)).locale(Self.trLocale))
                    .keyboardType(.decimalPad)
                    .font(.system(size: big ? 24 : 15, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                Text(unit)
                    .font(.system(size: big ? 12 : 10.5))
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.horizontal, big ? 16 : 14)
            .padding(.vertical, big ? 13 : 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(required ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 1))
        }
    }

    private var detailFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                numberField(label: "Bel", unit: "cm", value: $waist)
                numberField(label: "Boyun", unit: "cm", value: $neck)
                numberField(label: "Göğüs", unit: "cm", value: $chest)
                numberField(label: "Boy", unit: "cm", value: $heightLocal)
            }
            .onChange(of: waist) { _, _ in syncAutoBodyFat() }
            .onChange(of: neck) { _, _ in syncAutoBodyFat() }
            .onChange(of: heightLocal) { _, _ in syncAutoBodyFat() }

            bodyFatRow

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Not").font(Typography.label).tracking(0.9).textCase(.uppercase).foregroundStyle(Palette.textQuaternary)
                TextField("ör: sabah aç karnına", text: $note)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
    }

    // MARK: - Yağ oranı (US Navy oto; kalemle manuel)

    private var bodyFatRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Yağ Oranı").font(Typography.label).tracking(0.9).textCase(.uppercase).foregroundStyle(Palette.textQuaternary)
                if !bodyFatManual {
                    Text("oto · US Navy")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Palette.macroCarbs)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if bodyFatManual {
                    TextField("0,0", value: $bodyFat, format: .number.precision(.fractionLength(0...2)).locale(Self.trLocale))
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                } else {
                    Text(bodyFat.map { Fmt.num($0, digits: 1) } ?? "0,0")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(bodyFat == nil ? Palette.textQuaternary : Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("%").font(.system(size: 10.5)).foregroundStyle(Palette.textQuaternary)
                Button { toggleBodyFatMode() } label: {
                    Lucide(sf: bodyFatManual ? "arrow.uturn.backward" : "pencil", size: 11)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(!bodyFatManual && bodyFat != nil ? Palette.macroCarbs.opacity(0.3) : Palette.border, lineWidth: 1))
            Text("bel + boyun + boy girilince US Navy formülüyle otomatik hesaplanır")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleBodyFatMode() {
        if bodyFatManual {
            bodyFatManual = false
            syncAutoBodyFat()
        } else {
            bodyFatManual = true
            if bodyFat == nil { bodyFat = navyBodyFat }
        }
    }

    private var navyBodyFat: Double? {
        guard let waist, let neck, waist > neck, let h = heightLocal ?? height, h > 0 else { return nil }
        let bf = 495.0 / (1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(h)) - 450.0
        guard bf.isFinite else { return nil }
        return (min(max(bf, 2), 60) * 10).rounded() / 10
    }

    private func syncAutoBodyFat() {
        guard !bodyFatManual else { return }
        bodyFat = navyBodyFat
    }

    // MARK: - Alt bar

    private var footer: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("Vazgeç")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { save() } label: {
                Text(saveTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.btnFg)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.btnBg))
                    .opacity(canSave ? 1 : 0.45)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .top)
    }

    private func save() {
        guard canSave else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            date,
            weight,
            showExtra ? bodyFat : nil,
            showExtra ? waist : nil,
            showExtra ? chest : nil,
            showExtra ? neck : nil,
            trimmed.isEmpty ? nil : trimmed
        )
        dismiss()
    }
}

struct MobileProfileEditor: View {
    @Bindable var profile: UserProfile
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var heightStr = ""
    @State private var targetStr = ""
    @State private var bodyFatStr = ""
    @State private var proteinStr = ""
    @State private var carbsStr = ""
    @State private var fatStr = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Kişisel") {
                    TextField("İsim", text: $profile.name)
                    DatePicker("Doğum tarihi", selection: $profile.birthDate, displayedComponents: .date)
                    Picker("Cinsiyet", selection: $profile.sex) {
                        ForEach(Sex.allCases) { Text($0.label).tag($0) }
                    }
                    numberRow("Boy (cm)", text: $heightStr, prompt: "ör: 180")
                }
                Section("Hedef") {
                    Picker("Mod", selection: $profile.goal) {
                        ForEach(Goal.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Aktivite", selection: $profile.activity) {
                        ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
                    }
                    numberRow("Hedef kilo (kg)", text: $targetStr, prompt: "opsiyonel")
                    numberRow("Yağ % (manuel)", text: $bodyFatStr, prompt: "opsiyonel")
                }
                Section {
                    numberRow("Protein (g)", text: $proteinStr, prompt: "oto")
                    numberRow("Karbonhidrat (g)", text: $carbsStr, prompt: "oto")
                    numberRow("Yağ (g)", text: $fatStr, prompt: "oto")
                } header: {
                    Text("Manuel Makro Hedefi")
                } footer: {
                    Text("Boş bırakırsan profil + aktiviteye göre otomatik hesaplanır.")
                }
                Section("Supplementler") {
                    TextField("Her satıra bir supplement", text: $profile.supplements, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                }
            }
            .onAppear {
                heightStr = profile.height > 0 ? MobileFieldFmt.num(profile.height, digits: 0) : ""
                targetStr = profile.targetWeight.map { MobileFieldFmt.num($0, digits: 1) } ?? ""
                bodyFatStr = profile.manualBodyFat.map { MobileFieldFmt.num($0, digits: 1) } ?? ""
                proteinStr = profile.manualProteinGrams.map { MobileFieldFmt.num($0, digits: 0) } ?? ""
                carbsStr = profile.manualCarbsGrams.map { MobileFieldFmt.num($0, digits: 0) } ?? ""
                fatStr = profile.manualFatGrams.map { MobileFieldFmt.num($0, digits: 0) } ?? ""
            }
            .preferredColorScheme(ThemeSettings.appearance.colorScheme)
        }
    }

    private func numberRow(_ label: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(label) {
            TextField(prompt, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func parse(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Double(t)
    }

    private func save() {
        profile.isSeedPlaceholder = false
        if let h = parse(heightStr) { profile.height = h }
        profile.targetWeight = parse(targetStr)
        profile.manualBodyFat = parse(bodyFatStr)
        profile.manualProteinGrams = parse(proteinStr)
        profile.manualCarbsGrams = parse(carbsStr)
        profile.manualFatGrams = parse(fatStr)
        onDone()
        dismiss()
    }
}

struct RecipeFields {
    var title: String
    var category: RecipeCategory
    var summary: String?
    var ingredients: String?
    var instructions: String?
    var url: String
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
}

/// Mobil tarif editörü (oluştur + düzenle). Sayı alanları string ayna ile tutulur.
struct MobileRecipeEditor: View {
    let existing: Recipe?
    var onSave: (RecipeFields) -> Void
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category: RecipeCategory = .dinner
    @State private var summary = ""
    @State private var ingredients = ""
    @State private var instructions = ""
    @State private var url = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Tarif") {
                    TextField("Başlık", text: $title)
                    Picker("Kategori", selection: $category) {
                        ForEach(RecipeCategory.allCases) { cat in Text(cat.label).tag(cat) }
                    }
                    TextField("Kaynak URL (opsiyonel)", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Özet") {
                    TextField("Kısa özet", text: $summary, axis: .vertical).lineLimit(2...4)
                }
                Section("Malzemeler") {
                    TextField("Her satıra bir malzeme", text: $ingredients, axis: .vertical).lineLimit(3...12)
                }
                Section("Yapılış") {
                    TextField("Adımlar", text: $instructions, axis: .vertical).lineLimit(3...14)
                }
                Section("Makro (opsiyonel, porsiyon başı)") {
                    numberRow("Kalori", $calories)
                    numberRow("Protein (g)", $protein)
                    numberRow("Karbonhidrat (g)", $carbs)
                    numberRow("Yağ (g)", $fat)
                }
                if let onDelete {
                    Section {
                        Button("Tarifi Sil", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Yeni Tarif" : "Tarifi Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { commit() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: populate)
            .preferredColorScheme(ThemeSettings.appearance.colorScheme)
        }
    }

    private func numberRow(_ label: String, _ text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField("opsiyonel", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func populate() {
        guard let r = existing else { return }
        title = r.title
        category = r.category
        summary = r.summary ?? ""
        ingredients = r.ingredientsText ?? ""
        instructions = r.instructionsText ?? ""
        url = r.urlString
        calories = r.calories.map { MobileFieldFmt.num($0, digits: 0) } ?? ""
        protein = r.protein.map { MobileFieldFmt.num($0, digits: 0) } ?? ""
        carbs = r.carbs.map { MobileFieldFmt.num($0, digits: 0) } ?? ""
        fat = r.fat.map { MobileFieldFmt.num($0, digits: 0) } ?? ""
    }

    private func parse(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Double(t)
    }

    private func commit() {
        onSave(RecipeFields(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            summary: summary.nilIfBlank,
            ingredients: ingredients.nilIfBlank,
            instructions: instructions.nilIfBlank,
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: parse(calories),
            protein: parse(protein),
            carbs: parse(carbs),
            fat: parse(fat)
        ))
        dismiss()
    }
}

/// Mobil tarif detay sayfası (oku-odaklı, Mac RecipeDetailSheet paritesi):
/// makro kutuları, özet/malzeme/yapılış, kaynak linki + favori ve düzenle.
struct MobileRecipeDetailSheet: View {
    let recipe: Recipe
    var onSaveEdit: (RecipeFields) -> Void
    var onDelete: () -> Void
    var onToggleFavorite: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if hasMacros { macroRow }
                    if let summary = recipe.summary?.nilIfBlank {
                        detailSection("Özet", text: summary)
                    }
                    if let ingredients = recipe.ingredientsText?.nilIfBlank {
                        detailSection("Malzemeler", text: ingredients)
                    }
                    if let instructions = recipe.instructionsText?.nilIfBlank {
                        detailSection("Yapılış", text: instructions)
                    }
                    if let url = recipe.url {
                        Link(destination: url) {
                            Label { Text("Kaynağı aç") } icon: { Lucide(sf: "arrow.up.right.square") }
                                .font(Typography.captionBold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if !recipe.hasDetail && !hasMacros {
                        Text("Bu tarifte henüz detay yok. Düzenle ile malzeme, yapılış ve makro ekleyebilirsin.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Tarif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showEditor = true } label: {
                        Label { Text("Düzenle") } icon: { Lucide(sf: "pencil") }
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                MobileRecipeEditor(
                    existing: recipe,
                    onSave: onSaveEdit,
                    onDelete: {
                        onDelete()
                        dismiss()
                    }
                )
            }
        }
        .preferredColorScheme(ThemeSettings.appearance.colorScheme)
    }

    private var hasMacros: Bool {
        recipe.calories != nil || recipe.protein != nil || recipe.carbs != nil || recipe.fat != nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Lucide(sf: recipe.category.icon, size: 16)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.accentSoft))
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.category.label)
                        .font(Typography.label)
                        .foregroundStyle(Palette.textQuaternary)
                        .textCase(.uppercase)
                    Text(recipe.title)
                        .font(Typography.hero(24))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    onToggleFavorite()
                } label: {
                    Lucide(sf: recipe.isFavorite ? "heart.fill" : "heart", size: 18)
                        .foregroundStyle(recipe.isFavorite ? Palette.warning : Palette.textQuaternary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Palette.surfaceElevated))
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let servings = recipe.servings {
                        metaTag("\(servings) porsiyon", icon: "person.2.fill")
                    }
                    if let prep = recipe.prepMinutes {
                        metaTag("\(prep) dk hazırlık", icon: "clock.fill")
                    }
                    metaTag("Eklendi \(Fmt.dateLong.string(from: recipe.createdAt))", icon: "calendar")
                }
            }
        }
    }

    private func metaTag(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Lucide(sf: icon, size: 10)
            Text(text)
                .font(Typography.captionBold)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.surfaceElevated))
    }

    private var macroRow: some View {
        HStack(spacing: 10) {
            macroBox("Kalori", recipe.calories.map { Fmt.int($0) } ?? "—", "kalori")
            macroBox("Protein", recipe.protein.map { Fmt.int($0) } ?? "—", "g")
            macroBox("Karb", recipe.carbs.map { Fmt.int($0) } ?? "—", "g")
            macroBox("Yağ", recipe.fat.map { Fmt.int($0) } ?? "—", "g")
        }
    }

    private func macroBox(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Typography.label)
                .foregroundStyle(Palette.textQuaternary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Typography.monoLarge)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surfaceElevated))
    }

    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.label)
                .foregroundStyle(Palette.textQuaternary)
                .textCase(.uppercase)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }
}
