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
    @Query(sort: \FeedItem.createdAt, order: .reverse) private var feedItems: [FeedItem]

    /// Mac'ten gelen "Telefona gönder" feed'i (@Observable → akış/badge reaktif).
    private let feedStore = FeedStore.shared
    @State private var health = HealthService.shared
    @State private var cloudSync = CloudSyncMonitor.shared

    @State private var selectedTab: MobileTab = .dashboard
    @State private var showAddMeasurement = false
    @State private var showFoodAIEstimator = false
    @State private var saveErrors = SaveErrorReporter.shared
    @State private var remoteAIHealth: RemoteAIHealthResponse?
    @State private var remoteAIError: String?
    @State private var remoteAIChecking = false
    @State private var showProfileEditor = false
    @State private var showRecipeEditor = false
    @State private var recipeToEdit: Recipe?
    @State private var recipeToView: Recipe?
    @State private var selectedRecipeCategory: RecipeCategory?
    @State private var recipeSearch = ""
    @State private var showFavoriteRecipesOnly = false
    /// Tarif videoları (sadece isim + link) ekleme alanı.
    @State private var newVideoTitle = ""
    @State private var newVideoURL = ""
    @State private var foodToDelete: FoodEntry?
    @State private var measurementToDelete: Measurement?
    @State private var workoutToDelete: WorkoutSession?
    /// Görünüm tercihi (Profil ▸ Görünüm). Değişince body .preferredColorScheme'i tazeler;
    /// dinamik Palette renkleri trait değişimiyle otomatik döner.
    @State private var appearance: AppAppearance = ThemeSettings.appearance

    // Bugün (V1 Tek Akış) — açılır bölümler + seçili antrenman günü (nil → bugün/ilk plan).
    @State private var mealsExpanded = false
    @State private var workoutExpanded = false
    @State private var selectedWorkoutDayState: Int? = nil

    // Akış gelen-kutusu (Bugün başlığındaki butondan sağdan kayar).
    @State private var showAkisFeed = false
    @State private var akisOpenId: String? = nil
    @State private var akisUnreadSnapshot: Set<String> = []
    @State private var akisDragX: CGFloat = 0

    @State private var aiFoodInput = ""
    @State private var aiFoodResult: AIFoodResult?
    @State private var aiFoodStatus: String?
    @State private var aiFoodError: String?
    @State private var isEstimatingFood = false
    @State private var aiFoodPickerItems: [PhotosPickerItem] = []
    @State private var aiFoodImages: [Data] = []
    @FocusState private var aiInputFocused: Bool

    @State private var measurementFullCheckIn = false
    @State private var selectedSeriesIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()

            selectedPage

            mobileBottomBar

            if showAkisFeed {
                akisFeedOverlay
                    .offset(x: akisDragX)
                    .gesture(
                        // Sağa kaydır → geri (ok'a basmaya gerek yok). Dikey kaydırma ScrollView'da kalsın
                        // diye yalnız yatay-baskın, sağa hareketle açılır.
                        DragGesture(minimumDistance: 18)
                            .onChanged { v in
                                if v.translation.width > 0, abs(v.translation.width) > abs(v.translation.height) {
                                    akisDragX = v.translation.width
                                }
                            }
                            .onEnded { v in
                                if v.translation.width > 90 {
                                    // Offset geçerli konumda kalsın; move-out transition oradan sağa kaydırıp çıkarır.
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { showAkisFeed = false }
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { akisDragX = 0 }
                                }
                            }
                    )
                    .transition(.move(edge: .trailing))
                    .shadow(color: .black.opacity(0.25), radius: 24, x: -10, y: 0)
                    .zIndex(20)
            }
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
        .sheet(isPresented: $showFoodAIEstimator) {
            foodAIEstimatorSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
        .onChange(of: feedItems.count) { _, _ in
            FeedStore.deduplicate(feedItems, in: ctx)
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

    // MARK: - Akış (gelen kutusu — Bugün başlığındaki butondan sağdan kayar)

    /// Tam ekran kaplayan Akış paneli. Öğeler SwiftData/CloudKit üzerinden gelir;
    /// okundu bilgisi yalnız bu cihazda tutulur.
    private var akisFeedOverlay: some View {
        VStack(spacing: 0) {
            akisHeader
            ScrollView {
                // LazyVStack: akış sınırsız büyüyor ve düz VStack panel açılışında
                // HER satırı kuruyordu (satır başına RelativeDateTimeFormatter +
                // karakter karakter mention parse'ı).
                LazyVStack(alignment: .leading, spacing: 0) {
                    flowSectionHeader("Bu hafta") { EmptyView() }
                    if feedItems.isEmpty {
                        akisEmpty
                    } else {
                        ForEach(feedItems) { item in
                            akisMessageRow(item)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .task {
            feedStore.markAllSeen(feedItems)
        }
    }

    private var akisHeader: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { showAkisFeed = false }
            } label: {
                Lucide(sf: "chevron.left", size: 13)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.surface))
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Text("Akış")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
            if !akisUnreadSnapshot.isEmpty {
                Text("\(akisUnreadSnapshot.count) YENİ")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
    }

    private func akisMessageRow(_ item: FeedItem) -> some View {
        let open = akisOpenId == item.id
        let unread = akisUnreadSnapshot.contains(item.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { akisOpenId = open ? nil : item.id }
            } label: {
                HStack(alignment: .top, spacing: 11) {
                    akisAvatar(item)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(item.source == "Mac" ? "Mac Hercules" : item.source)
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(Palette.textPrimary)
                            Text(Fmt.relative(item.createdAt))
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textQuaternary)
                            Spacer(minLength: 4)
                            if unread && !open {
                                Circle().fill(Palette.accent).frame(width: 6, height: 6)
                            }
                            chevron(open: open)
                        }
                        if !item.title.isEmpty {
                            mentionText(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(open ? nil : 1)
                                .fixedSize(horizontal: false, vertical: open)
                        }
                        if !open {
                            Text(akisPreview(item.body))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                HStack(spacing: 0) {
                    Rectangle().fill(Palette.track).frame(width: 2)
                    Text(item.body)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                }
                .padding(.leading, 45)
                .padding(.top, 10)
            }
        }
        .padding(.vertical, 12)
    }

    private func akisAvatar(_ item: FeedItem) -> some View {
        Lucide(sf: item.kind == "recipe" ? "fork.knife" : "laptopcomputer", size: 13)
            .foregroundStyle(Palette.accent)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Palette.accentSoft))
            .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private var akisEmpty: some View {
        VStack(spacing: 10) {
            Lucide(sf: "tray", size: 30)
                .foregroundStyle(Palette.textTertiary)
            Text("Akış boş")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            Text("Mac Hercules'te bir sohbet mesajında \"Telefona gönder\"e bas — burada belirir.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, 16)
    }

    /// Gövdenin ilk dolu satırı — kapalı önizleme için.
    private func akisPreview(_ body: String) -> String {
        body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
            ?? body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// @etiketleri (ör. @Ölçümler, @Takvim) nötr accent ile vurgular; gerisi birincil metin.
    private func mentionText(_ string: String) -> Text {
        var result = Text("")
        var buffer = ""
        var inMention = false
        func flush() {
            guard !buffer.isEmpty else { return }
            result = result + Text(buffer).foregroundStyle(inMention ? Palette.accent : Palette.textPrimary)
            buffer = ""
        }
        for ch in string {
            if ch == "@" {
                flush(); inMention = true; buffer.append(ch)
            } else if inMention && (ch.isLetter || ch.isNumber || ch == "_") {
                buffer.append(ch)
            } else {
                if inMention { flush(); inMention = false }
                buffer.append(ch)
            }
        }
        flush()
        return result
    }

    // MARK: - Bugün (V1 "Tek Akış")

    /// Tek akış Bugün sayfası: başlık → kalori bandı + makrolar → sayaç şeridi →
    /// açılır Yemekler → hafta şeridi + açılır Antrenman → Son ölçüm. Kartsız, bordo'suz.
    private var dashboardPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            dashHeader
            dashCalorieGauge
            dashCounterStrip
            dashMealsSection
            dashWorkoutSection
            dashLastMeasurement
        }
        .padding(.top, 6)
    }

    private static let weekdayUpperFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEEE"
        return f
    }()
    private static let measureDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    // ── başlık ──
    private var dashHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(Self.weekdayUpperFmt.string(from: Date()).uppercased(with: Locale(identifier: "tr_TR")))
                        .tracking(1.4)
                        .foregroundStyle(Palette.textSecondary)
                    Text("— \(Fmt.dayMonth.string(from: Date()))")
                        .tracking(1.4)
                        .foregroundStyle(Palette.textQuaternary)
                }
                .font(Typography.label)
                Text(profileName.isEmpty ? "Hercules" : "Selam, \(profileName)")
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer(minLength: 8)
            headerActions
        }
    }

    /// Başlık eylemleri: gelen kutusu.
    private var headerActions: some View {
        HStack(spacing: 12) {
            akisInboxButton
        }
    }

    /// Başlık eylem kutusu — başlıktaki tüm eylemler bunu kullanır; tek tanım
    /// olduğu için ikonlar birbirinden kayamaz.
    private func headerActionBox(_ icon: some View) -> some View {
        icon
            .foregroundStyle(Palette.textSecondary)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
    }

    /// Akış'ı sağdan kaydıran gelen-kutusu butonu — Bugün ve Tarifler başlıklarında ortak.
    /// Okunmamış varsa nokta gösterir; açılışta okunmadı kümesini dondurur (panel içi için).
    private var akisInboxButton: some View {
        Button {
            akisUnreadSnapshot = Set(feedItems.lazy.filter { !feedStore.isSeen($0.id) }.map(\.id))
            akisOpenId = nil
            akisDragX = 0
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { showAkisFeed = true }
        } label: {
            headerActionBox(
                Lucide(sf: "tray", size: 17)
                    .overlay(alignment: .topTrailing) {
                        if feedStore.unseenCount(in: feedItems) > 0 {
                            Circle()
                                .fill(Palette.accent)
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: -2)
                        }
                    }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Akış — gelen kutusu")
    }

    // ── kalori bandı + makrolar ──
    @ViewBuilder
    private var dashCalorieGauge: some View {
        if let plan = calorieResult {
            let intake = todayCalories
            let goal = plan.goalCalories
            let over = max(0, intake - goal)
            let remaining = max(0, goal - intake)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    CountUpText(
                        value: intake,
                        font: .system(size: 46, weight: .semibold),
                        tracking: -1.4
                    )
                    Text("/ \(Fmt.int(goal)) kcal")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.textTertiary)
                    Spacer(minLength: 8)
                    calorieChip(over: over, remaining: remaining)
                }
                calorieBar(intake: intake, goal: goal)
                    .padding(.top, 14)
                HStack {
                    Text("\(Fmt.int(remaining)) kcal kaldı")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("hedef \(Fmt.int(goal))")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.top, 7)
                dashMacros(plan: plan)
                    .padding(.top, 16)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CountUpText(
                        value: todayCalories,
                        font: .system(size: 46, weight: .semibold),
                        tracking: -1.4
                    )
                    Text("kcal")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
                Text("Profilini doldur — günlük kalori ve makro hedefin burada belirir.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func calorieChip(over: Double, remaining: Double) -> some View {
        let isOver = over > 0
        // Hedef üstü = dikkat (pirinç/negative). Altı = olumlu/sakin. Bordo yok.
        let color = isOver ? Palette.negative : Palette.positive
        return Text(isOver ? "+\(Fmt.int(over)) üstü" : "\(Fmt.int(remaining)) kaldı")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    /// Yatay kalori bandı: taranmış mürekkep dolgu + ucunda "şu andasın" işareti.
    /// Hedef aşılınca bant dolar ve pirinç/negative'e döner (üstü ne kadar aştığını
    /// başlıktaki `calorieChip` söylüyor).
    private func calorieBar(intake: Double, goal: Double) -> some View {
        GoalBar(
            value: intake,
            goal: goal,
            tint: Palette.textPrimary,
            height: 10,
            hatchColor: Palette.background.opacity(0.22),
            hatchSpacing: 6,
            hatchWidth: 2.5,
            overflowTint: Palette.negative,
            trackColor: Palette.track
        )
    }

    private func dashMacros(plan: CalorieResult) -> some View {
        HStack(alignment: .top, spacing: 16) {
            macroColumn("PROTEIN", todayProtein, plan.protein.grams, Palette.macroProtein)
            macroColumn("KARB", todayCarbs, plan.carbs.grams, Palette.macroCarbs)
            macroColumn("YAĞ", todayFat, plan.fat.grams, Palette.macroFat)
        }
    }

    private func macroColumn(_ label: String, _ value: Double, _ target: Double, _ color: Color) -> some View {
        let over = value > target
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 4)
                Text(Fmt.int(value))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(over ? color : Palette.textSecondary)
                Text("/\(Fmt.int(target))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
            }
            GoalBar(
                value: value,
                goal: target,
                tint: color,
                height: 4,
                hatched: false,
                headMarker: false,
                overflowTint: color,
                trackColor: Palette.track
            )
        }
        .frame(maxWidth: .infinity)
    }

    // ── sayaç şeridi (Adım / Kilo / Su) ──
    private var dashCounterStrip: some View {
        HStack(spacing: 0) {
            counterCell("ADIM", Fmt.int(Double(todaySteps)), "")
            counterDivider
            counterCell("KİLO", measurements.first?.weight.map { Fmt.num($0, digits: 1) } ?? "—", "kg")
            counterDivider
            counterCell("SU", calorieResult.map { Fmt.num($0.water, digits: 1) } ?? "—", "L")
        }
        .padding(.vertical, 11)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
    }

    private var counterDivider: some View {
        Rectangle().fill(Palette.border).frame(width: 1, height: 22)
    }

    private func counterCell(_ key: String, _ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // ── Yemekler (açılır) ──
    private var dashMealsSection: some View {
        return VStack(alignment: .leading, spacing: 0) {
            flowSectionHeader("Yemekler") {
                Button {
                    showFoodAIEstimator = true
                } label: {
                    Lucide(sf: "plus", size: 12)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AI ile yemek ekle")
            }
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { mealsExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(todayFoods.count) kayıt")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 8)
                    Text("\(Fmt.int(todayCalories)) kcal")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                    chevron(open: mealsExpanded)
                }
                .padding(.top, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if mealsExpanded {
                VStack(spacing: 0) {
                    if todayFoods.isEmpty {
                        rowEmpty("Bugün yemek kaydı yok.")
                    } else {
                        ForEach(todayFoods.prefix(12), id: \.persistentModelID) { food in
                            mealRow(food)
                        }
                    }
                }
                .padding(.top, 3)
            }
        }
    }

    /// Sola kaydır → Sil (foodToDelete → onay alert'i → deleteFood). Akış sayfasıyla aynı
    /// renkte kalsın diye rowBackground = page background.
    private func mealRow(_ food: FoodEntry) -> some View {
        MobileSwipeToDelete(onDelete: { foodToDelete = food }, rowBackground: Palette.background) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(food.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let grams = food.grams {
                    Text("\(Fmt.int(grams)) g")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textQuaternary)
                        .fixedSize()
                        .layoutPriority(1)
                }
                DottedLeader()
                Text("\(Fmt.int(food.calories))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
        }
    }

    // ── Antrenman (hafta şeridi + açılır program) ──
    private var dashWorkoutSection: some View {
        let selected = dashSelectedWorkout
        return VStack(alignment: .leading, spacing: 0) {
            flowSectionHeader("Antrenman") {
                Text("\(activeWorkouts.count) gün / hafta")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            dashWeekStrip
                .padding(.top, 10)
            Button {
                guard selected != nil else { return }
                withAnimation(.easeInOut(duration: 0.18)) { workoutExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(selected?.name ?? "Antrenman yok")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected == nil ? Palette.textTertiary : Palette.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let selected, selected.weekday == todayWeekday {
                        Text("BUGÜN")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(workoutSummaryText(selected))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize()
                    chevron(open: workoutExpanded)
                        .opacity(selected == nil ? 0 : 1)
                }
                .padding(.top, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if workoutExpanded, let selected {
                VStack(spacing: 0) {
                    let exercises = selected.sortedTemplateExercises
                    if exercises.isEmpty {
                        rowEmpty("Egzersizler senkronda — Mac'ten gelecek.")
                    } else {
                        ForEach(exercises, id: \.persistentModelID) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
                .padding(.top, 3)
            }
        }
    }

    private var dashWeekStrip: some View {
        // Pazartesi→Pazar; etiketler takvimle birebir (Pz, "Pa" değil).
        let week: [(Int, String)] = [(2, "Pt"), (3, "Sa"), (4, "Ça"), (5, "Pe"), (6, "Cu"), (7, "Ct"), (1, "Pz")]
        return HStack(spacing: 0) {
            ForEach(week, id: \.0) { wd, label in
                let has = activeWorkouts.contains { $0.weekday == wd }
                let isToday = wd == todayWeekday
                let isSel = wd == dashSelectedWorkoutDay
                VStack(spacing: 5) {
                    Text(label)
                        .font(.system(size: 9, weight: isToday ? .bold : .semibold))
                        .tracking(0.6)
                        .foregroundStyle(isSel ? Palette.textPrimary : (isToday ? Palette.textSecondary : Palette.textTertiary))
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(isSel ? Palette.accent : .clear)
                                .frame(height: 1)
                                .offset(y: 3)
                        }
                    Circle()
                        .fill(isToday ? Palette.accent : (has ? Palette.track : .clear))
                        .frame(width: 3.5, height: 3.5)
                        .overlay(
                            Circle().strokeBorder(isToday ? Palette.accentSoft : .clear, lineWidth: 1)
                        )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .opacity(isSel || has || isToday ? 1 : 0.5)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Her güne tıklanabilir. Dolu gün → programı aç; boş gün → seç ama açma
                    // (antrenman yok satırı görünür, egzersiz listesi çıkmaz).
                    selectedWorkoutDayState = wd
                    withAnimation(.easeInOut(duration: 0.18)) { workoutExpanded = has }
                }
            }
        }
    }

    private func exerciseRow(_ exercise: WorkoutTemplateExercise) -> some View {
        // İsim her zaman tam (öncelik 2), reçete kalanı alır ve uzunsa KISALIR (fixedSize yok —
        // yoksa uzun reçete satırı ekran genişliğini aşıp tüm sayfayı kaydırıyor). İsimsiz
        // (koç notu) hareketlerde isim+lider atlanır, reçete tam genişlik kullanır.
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            exerciseRowLink(exercise.sourceURL)
            if !name.isEmpty {
                Text(name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(2)
                DottedLeader()
            }
            Text(exercise.prescriptionText)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .padding(.vertical, 6.5)
    }

    /// Egzersiz satırının başındaki numara (1,2,3…) yerine teknik linki.
    /// URL varsa dokunulabilir zincir ikonu; yoksa hizayı koruyan soluk ikon.
    @ViewBuilder
    private func exerciseRowLink(_ raw: String?) -> some View {
        if let url = normalizedURL(raw) {
            Link(destination: url) {
                Lucide(sf: "link", size: 10)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 14, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hareket tekniği linkini aç")
        } else {
            Lucide(sf: "link", size: 10)
                .foregroundStyle(Palette.textQuaternary.opacity(0.6))
                .frame(width: 14, alignment: .leading)
        }
    }

    private func workoutSummaryText(_ workout: WorkoutSession?) -> String {
        guard let workout else { return "" }
        let count = workout.sortedTemplateExercises.count
        return count > 0 ? "\(count) hareket · \(workout.durationMinutes) dk" : "\(workout.durationMinutes) dk"
    }

    // ── Son ölçüm ──
    private var dashLastMeasurement: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowSectionHeader("Son ölçüm") {
                if let date = measurements.first?.date {
                    Text(Self.measureDateFmt.string(from: date))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            if let m = measurements.first {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(m.weight.map { Fmt.num($0, digits: 1) } ?? "—")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text("kg")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    measureSub("Yağ", m.bodyFat.map { "\(Fmt.num($0, digits: 1)) %" })
                    measureSub("Bel", m.waist.map { "\(Fmt.num($0, digits: 1)) cm" })
                    Spacer(minLength: 0)
                }
                .padding(.top, 10)

                if let flow = dashWeightFlow {
                    TrendSpark(
                        values: flow.values,
                        calloutValue: flow.deltaText,
                        showDropLine: false,
                        height: 76
                    )
                    .padding(.top, 6)
                }
            } else {
                rowEmpty("Ölçüm kaydı yok.")
                    .padding(.top, 6)
            }
        }
    }

    /// "Son ölçüm" altındaki kilo akışı: son 30 günün kiloları (eskiden yeniye) +
    /// çizginin ucuna yazılacak pencere farkı. 30 günde 2 kayda ulaşılamazsa tüm seri.
    private var dashWeightFlow: (values: [Double], deltaText: String)? {
        let asc = measurements.sorted { $0.date < $1.date }
        let all = asc.compactMap(\.weight)
        guard all.count >= 2 else { return nil }

        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let recent = asc.filter { $0.date >= cutoff }.compactMap(\.weight)
        let values = recent.count >= 2 ? recent : all

        let delta = values[values.count - 1] - values[0]
        let window = recent.count >= 2 ? "30 gün" : "tüm kayıt"
        let sign = delta < 0 ? "−" : "+"
        let text = abs(delta) < 0.05
            ? "\(window) · sabit"
            : "\(window) · \(sign)\(Fmt.num(abs(delta), digits: 1)) kg"
        return (values, text)
    }

    private func measureSub(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textSecondary)
            Text(value ?? "—")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(value == nil ? Palette.textQuaternary : Palette.textTertiary)
        }
    }

    // ── ortak V1 parçaları ──
    private func flowSectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Typography.label)
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textQuaternary)
                .fixedSize()
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            trailing()
                .fixedSize()
        }
    }

    private func chevron(open: Bool) -> some View {
        Lucide(sf: "chevron.right", size: 10)
            .foregroundStyle(Palette.textTertiary)
            .rotationEffect(.degrees(open ? 90 : 0))
    }

    private func rowEmpty(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private var todayWeekday: Int { Calendar.current.component(.weekday, from: .now) }

    /// Varsayılan seçili antrenman günü: bugün plan varsa bugün, yoksa ilk plan günü.
    private var defaultWorkoutDay: Int {
        if activeWorkouts.contains(where: { $0.weekday == todayWeekday }) { return todayWeekday }
        return activeWorkouts.first?.weekday ?? todayWeekday
    }

    private var dashSelectedWorkoutDay: Int { selectedWorkoutDayState ?? defaultWorkoutDay }

    private var dashSelectedWorkout: WorkoutSession? {
        activeWorkouts.first { $0.weekday == dashSelectedWorkoutDay }
    }

    // MARK: - Ölçümler (V1 — swipe'lı 7 serili trend karuseli + defter kayıtları)

    private var measurementsPage: some View {
        VStack(spacing: 0) {
            measurementsHeader
            measurementCadenceReminder
            measurementCarousel
            measurementRecordsHeader
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if measurements.isEmpty {
                        Text("Ölçüm kaydı yok. ＋ EKLE ile başla.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 28)
                    } else {
                        ForEach(measurements.prefix(60), id: \.persistentModelID) { m in
                            measurementNotebookRow(m)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 2)
                .padding(.bottom, MobileChrome.dockClearance)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }

    private var measurementsHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 5) {
                    Text("Defter").foregroundStyle(Palette.textSecondary)
                    Text("— \(measurementSeries.count) seri · \(measurements.count) kayıt").foregroundStyle(Palette.textQuaternary)
                }
                .font(Typography.label)
                .tracking(1.4)
                Spacer(minLength: 8)
                headerActions
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Ölçümler")
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    // Cumartesi → Tam ölçümle başla; editör içinde segmentle değiştirilebilir.
                    measurementFullCheckIn = MeasurementCadence.isFullCheckInDay()
                    showAddMeasurement = true
                } label: {
                    Text("＋ EKLE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    private var measurementCadenceReminder: some View {
        let isFullDay = MeasurementCadence.isFullCheckInDay()
        let nextFull = MeasurementCadence.nextFullCheckIn()
        let body: Text = {
            if isFullDay {
                return Text("Bugün tam ölçüm günü — ")
                    + Text("yağ %, bel, göğüs, boyun").foregroundStyle(Palette.textPrimary).fontWeight(.semibold)
                    + Text(" da gir.")
            } else {
                return Text("Bugün hızlı tartı yeterli — sıradaki ")
                    + Text("tam ölçüm \(Self.weekdayUpperFmt.string(from: nextFull))").foregroundStyle(Palette.textPrimary).fontWeight(.semibold)
                    + Text(", ")
                    + Text(Fmt.date.string(from: nextFull)).font(.system(size: 11, design: .monospaced))
            }
        }()
        return HStack(alignment: .top, spacing: 8) {
            Circle().fill(Palette.accent).frame(width: 5, height: 5).padding(.top, 5)
            body
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 13)
    }

    @ViewBuilder
    private var measurementCarousel: some View {
        let series = measurementSeries
        if series.isEmpty {
            Text("Trend için en az bir ölçüm ekle.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 18)
        } else {
            let idx = min(selectedSeriesIndex, series.count - 1)
            VStack(spacing: 0) {
                TabView(selection: Binding(
                    get: { min(selectedSeriesIndex, series.count - 1) },
                    set: { selectedSeriesIndex = $0 }
                )) {
                    ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                        seriesCarouselPage(s).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 180)
                seriesDots(count: series.count, index: idx)
                    .padding(.top, 2)
                seriesStatStrip(series[idx])
                    .padding(.top, 11)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
        }
    }

    private func seriesCarouselPage(_ s: MeasurementSeries) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Text(s.grup.uppercased(with: Locale(identifier: "tr_TR")))
                        .foregroundStyle(Palette.textTertiary)
                    Text("— \(s.kind.label)")
                        .foregroundStyle(Palette.textSecondary)
                }
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.0)
                Spacer()
                if let last = s.lastDate {
                    Text(Fmt.date.string(from: last))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(Fmt.num(s.current ?? 0, digits: 1))
                    .font(.system(size: 42, weight: .semibold))
                    .tracking(-1.4)
                    .foregroundStyle(Palette.textPrimary)
                Text(s.kind.unit)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textQuaternary)
                Spacer()
                seriesDeltaChip(s)
            }
            .padding(.top, 8)
            MeasurementLineChart(values: s.values)
                .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seriesDeltaChip(_ s: MeasurementSeries) -> some View {
        let color = measurementTrendColor(s.improving)
        let val = s.deltaAbs.map { Fmt.num($0, digits: 1) } ?? "0,0"
        return Text("\(s.isDown ? "▼" : "▲") \(val)")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(s.improving == nil ? Palette.track : color.opacity(0.14)))
    }

    private func seriesDots(count: Int, index: Int) -> some View {
        HStack(spacing: 7) {
            Button { selectedSeriesIndex = max(0, index - 1) } label: {
                Text("‹")
                    .font(.system(size: 14))
                    .foregroundStyle(index > 0 ? Palette.textSecondary : Palette.textQuaternary.opacity(0.4))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            ForEach(Array(0..<count), id: \.self) { j in
                Capsule()
                    .fill(j == index ? Palette.accent : Palette.track)
                    .frame(width: j == index ? 14 : 4.5, height: 4.5)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { selectedSeriesIndex = j } }
            }
            Button { selectedSeriesIndex = min(count - 1, index + 1) } label: {
                Text("›")
                    .font(.system(size: 14))
                    .foregroundStyle(index < count - 1 ? Palette.textSecondary : Palette.textQuaternary.opacity(0.4))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(index >= count - 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func seriesStatStrip(_ s: MeasurementSeries) -> some View {
        HStack(spacing: 0) {
            statCell("HAFTALIK", weeklyText(s), color: measurementTrendColor(s.weeklyImproving))
            counterDivider
            statCell("ORTALAMA", s.average.map { Fmt.num($0, digits: 1) } ?? "—", color: Palette.textPrimary)
            counterDivider
            statCell("ARALIK", rangeText(s), color: Palette.textPrimary)
        }
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
    }

    private func statCell(_ key: String, _ value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Palette.textTertiary)
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func weeklyText(_ s: MeasurementSeries) -> String {
        guard let wk = s.weeklyChange else { return "—" }
        return "\(Fmt.signed(wk, digits: 2)) \(s.kind.unit)/hf"
    }

    private func rangeText(_ s: MeasurementSeries) -> String {
        guard let mn = s.minValue, let mx = s.maxValue else { return "—" }
        return "\(Fmt.num(mn, digits: 1))–\(Fmt.num(mx, digits: 1))"
    }

    private var measurementRecordsHeader: some View {
        flowSectionHeader("Son kayıtlar") {
            if let goal = goalDistanceText {
                Text(goal)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private var goalDistanceText: String? {
        guard let target = profiles.first?.targetWeight, let current = measurements.first?.weight else { return nil }
        return "hedefe \(Fmt.num(abs(current - target), digits: 1)) kg"
    }

    private func measurementNotebookRow(_ m: Measurement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.date.string(from: m.date))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 46, alignment: .leading)
                Text(m.isFullCheckIn ? "TAM" : "TARTI")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(m.isFullCheckIn ? Palette.accent : Palette.textQuaternary)
                Text(Fmt.timeShort.string(from: m.date))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textQuaternary)
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(m.weight.map { Fmt.num($0, digits: 1) } ?? "—")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                    Text("kg")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textQuaternary)
                }
                Button {
                    measurementToDelete = m
                } label: {
                    Lucide(sf: "trash", size: 10.5)
                        .foregroundStyle(Palette.textQuaternary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ölçümü sil")
            }
            if m.isFullCheckIn {
                Text(measurementDetailLine(m))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.leading, 54)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
    }

    private func measurementDetailLine(_ m: Measurement) -> String {
        [m.bodyFat.map { "Yağ \(Fmt.num($0, digits: 1))%" },
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

    private var profilePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                profileHeader
                profileIdentityStrip
                profileDailyPlan
                profileSystemSection
                profileAppearanceSection
                profileDataCount
            }
            .padding(.bottom, MobileChrome.dockClearance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 5) {
                    Text("Profil").foregroundStyle(Palette.textSecondary)
                    if let p = profiles.first {
                        Text("— \(p.goal.label) · \(p.activity.label)").foregroundStyle(Palette.textQuaternary)
                    }
                }
                .font(Typography.label).tracking(1.2).textCase(.uppercase).lineLimit(1)
                Spacer(minLength: 8)
                headerActions
            }
            HStack(alignment: .firstTextBaseline) {
                Text(profileName.isEmpty ? "İsimsiz" : profileName)
                    .font(.system(size: 25, weight: .semibold)).tracking(-0.5)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button { showProfileEditor = true } label: {
                    Text("✎ DÜZENLE")
                        .font(.system(size: 11, weight: .bold)).tracking(0.6)
                        .foregroundStyle(Palette.accent).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22).padding(.top, 6)
    }

    private var profileIdentityStrip: some View {
        HStack(spacing: 0) {
            counterCell("YAŞ", profiles.first.map { "\($0.age)" } ?? "—", "")
            counterDivider
            counterCell("BOY", profiles.first.map { Fmt.int($0.height) } ?? "—", "cm")
            counterDivider
            counterCell("HEDEF", profiles.first?.targetWeight.map { Fmt.num($0, digits: 1) } ?? "—", "kg")
        }
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
        .padding(.horizontal, 22).padding(.top, 14)
    }

    private var profileDailyPlan: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowSectionHeader("Günlük plan") {
                Text("hedefler").font(Typography.caption).foregroundStyle(Palette.textTertiary)
            }
            if let plan = calorieResult {
                HStack(alignment: .top, spacing: 0) {
                    planCell("Günlük", Fmt.int(plan.goalCalories), "kcal", dot: nil, divider: false)
                    planCell("Protein", Fmt.int(plan.protein.grams), "g", dot: Palette.macroProtein, divider: true)
                    planCell("Karb", Fmt.int(plan.carbs.grams), "g", dot: Palette.macroCarbs, divider: true)
                    planCell("Yağ", Fmt.int(plan.fat.grams), "g", dot: Palette.macroFat, divider: true)
                }
                .padding(.top, 11)
            } else {
                Text("Profilini doldur — günlük kalori ve makro hedefi burada görünür.")
                    .font(Typography.caption).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
        }
        .padding(.horizontal, 22).padding(.top, 16)
    }

    private func planCell(_ key: String, _ value: String, _ unit: String, dot: Color?, divider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 5, height: 5) }
                Text(key).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(Palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 15, design: .monospaced)).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(unit).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.textQuaternary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, divider ? 12 : 0)
        .overlay(alignment: .leading) {
            if divider { Rectangle().fill(Palette.border).frame(width: 1, height: 28) }
        }
    }

    private var profileSystemSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowSectionHeader("Sistem") { EmptyView() }
            profileAIBlock.padding(.top, 12)
            profileHealthBlock.padding(.top, 16)
            profileSyncStatusBlock.padding(.top, 16)
        }
        .padding(.horizontal, 22).padding(.top, 18)
    }

    private var profileSyncStatusBlock: some View {
        let statusColor: Color = {
            switch cloudSync.state {
            case .ready: return Palette.positive
            case .checking, .syncing: return Palette.warning
            case .unavailable, .error: return Palette.negative
            }
        }()

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Senkron").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("● \(cloudSync.statusText)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            Text(cloudSync.detailText)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2).padding(.top, 4).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var profileHealthBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Apple Health")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(health.statusText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(healthStatusColor)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                Text("Bugün \(Fmt.int(Double(todaySteps))) adım")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                Button {
                    Task { @MainActor in await health.requestAccessAndSync(into: ctx) }
                } label: {
                    Text("Yenile")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(health.status == .syncing)
            }
            .padding(.top, 4)
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

    private var profileAIBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Koç bağlantısı").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(remoteAIChecking ? "… Kontrol" : (remoteAIHealth != nil ? "● Bağlı" : "○ Ulaşılamıyor"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(remoteAIHealth != nil ? Palette.positive : (remoteAIChecking ? Palette.warning : Palette.negative))
            }
            Text(remoteAIStatusText)
                .font(.system(size: 10.5)).foregroundStyle(Palette.textQuaternary)
                .padding(.top, 2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer()
                Button {
                    Task { await refreshRemoteAIHealth() }
                } label: {
                    Text("Bağlantıyı kontrol et")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(remoteAIChecking)
            }
            .padding(.top, 10).padding(.bottom, 7)
            .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
        }
    }

    private var profileAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowSectionHeader("Görünüm") {
                Text(appearance == .light ? "Fildişi" : "Mürekkep")
                    .font(Typography.caption).foregroundStyle(Palette.textTertiary)
            }
            HStack(spacing: 18) {
                appearanceCap(.dark, "Koyu", swatch: Charcoal.bg)
                appearanceCap(.light, "Açık", swatch: Color(hex: 0xF2EFE8))
                Spacer(minLength: 0)
            }
            .padding(.top, 11)
        }
        .padding(.horizontal, 22).padding(.top, 18)
    }

    private func appearanceCap(_ mode: AppAppearance, _ label: String, swatch: Color) -> some View {
        let on = appearance == mode
        return Button {
            ThemeSettings.appearance = mode
            withAnimation(.easeInOut(duration: 0.2)) { appearance = mode }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(swatch).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: 1))
                Text(label).font(.system(size: 9.5, weight: .bold)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(on ? Palette.textPrimary : Palette.textTertiary)
            }
            .padding(.bottom, 4)
            .overlay(Rectangle().fill(on ? Palette.accent : Color.clear).frame(height: 1.5), alignment: .bottom)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var profileDataCount: some View {
        let total = (profiles.first != nil ? 1 : 0) + measurements.count + foods.count + recipes.count + activeWorkouts.count + steps.count + archives.count
        return VStack(alignment: .leading, spacing: 0) {
            flowSectionHeader("Veri sayımı") {
                Text("\(total) kayıt").font(Typography.caption).foregroundStyle(Palette.textTertiary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), spacing: 12) {
                dataCell("Profil", profiles.first != nil ? "1" : "0")
                dataCell("Ölçüm", "\(measurements.count)")
                dataCell("Yemek", "\(foods.count)")
                dataCell("Tarif", "\(recipes.count)")
                dataCell("Antrenman", "\(activeWorkouts.count)")
                dataCell("Adım günü", "\(steps.count)")
                dataCell("Arşiv", "\(archives.count)")
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 22).padding(.top, 18)
    }

    private func dataCell(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.system(size: 8.5, weight: .bold)).tracking(0.9).textCase(.uppercase)
                .foregroundStyle(Palette.textQuaternary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 14, design: .monospaced)).foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Yemek sekmesi başında bugünkü kalori/makro özeti (Dashboard hero'sunun kompakt hali).
    /// "Öğün ekle" — Bugün/Yemek sekmesinden açılan AI yemek hesaplama penceresi (sheet).
    private var foodAIEstimatorSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    aiSheetIntro
                    aiSheetInputSection
                    if aiFoodResult == nil {
                        aiSheetSuggestions
                    }
                    aiSheetCTA
                    if let result = aiFoodResult {
                        aiFoodResultCard(result)
                    }
                    aiSheetStatus
                    if aiFoodResult == nil && aiFoodError == nil {
                        aiSheetTip
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Öğün ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { showFoodAIEstimator = false }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        aiInputFocused = false
                        Task { await estimateFoodWithAI() }
                    } label: {
                        Label { Text("Hesapla") } icon: { Lucide(sf: "wand.and.stars") }
                    }
                    .disabled((aiFoodInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && aiFoodImages.isEmpty) || isEstimatingFood)
                }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }

    /// Dostça başlık — nav title "Öğün ekle" ile tekrar etmesin diye "Ne yedin?" sorusu.
    private var aiSheetIntro: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.accentSoft)
                Lucide(sf: "sparkles", size: 24)
                    .foregroundStyle(Palette.accent)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ne yedin?")
                    .font(Typography.hero(26))
                    .foregroundStyle(Palette.textPrimary)
                Text("Doğal dille yaz; AI kcal ve makroyu hesaplayıp bugüne eklesin.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Büyük, odaklanınca accent çerçeveli giriş + bugünkü kalan bütçe çipleri.
    private var aiSheetInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("örn: 160g pişmiş pirinç + 500g tavuk göğsü", text: $aiFoodInput, axis: .vertical)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(3...7)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($aiInputFocused)
                .padding(14)
                .frame(minHeight: 104, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(aiInputFocused ? Palette.accent : Palette.borderStrong, lineWidth: aiInputFocused ? 1.5 : 0.5)
                )
                .animation(.easeInOut(duration: 0.15), value: aiInputFocused)

            HStack(spacing: 8) {
                PhotosPicker(selection: $aiFoodPickerItems, maxSelectionCount: 2, matching: .images) {
                    HStack(spacing: 6) {
                        Lucide(sf: "camera.fill", size: 12)
                        Text(aiFoodImages.isEmpty ? "Fotoğraf ekle" : "\(aiFoodImages.count) foto")
                            .font(Typography.captionBold)
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Palette.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }

            if !aiFoodImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(aiFoodImages.enumerated()), id: \.offset) { idx, data in
                            if let image = mobileImage(from: data) {
                                ZStack(alignment: .topTrailing) {
                                    image.resizable().scaledToFill()
                                        .frame(width: 66, height: 66)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Button {
                                        if aiFoodImages.indices.contains(idx) { aiFoodImages.remove(at: idx) }
                                    } label: {
                                        Lucide(sf: "xmark.circle.fill", size: 16)
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .buttonStyle(.plain).padding(2)
                                }
                            }
                        }
                    }
                }
            }

            if let plan = calorieResult {
                HStack(spacing: 8) {
                    aiBudgetPill(icon: "flame.fill", label: "Kalan", value: "\(Fmt.int(max(0, plan.goalCalories - todayCalories))) kcal")
                    aiBudgetPill(icon: "bolt.fill", label: "Protein", value: "\(Fmt.int(todayProtein))/\(Fmt.int(plan.protein.grams))g")
                    Spacer(minLength: 0)
                }
            }
        }
        .onChange(of: aiFoodPickerItems) { _, items in loadFoodImages(items) }
    }

    private func mobileImage(from data: Data) -> Image? {
        UIImage(data: data).map { Image(uiImage: $0) }
    }

    private func loadFoodImages(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var datas: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
            }
            await MainActor.run {
                aiFoodImages.append(contentsOf: datas)
                aiFoodPickerItems = []
            }
        }
    }

    private func aiBudgetPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Lucide(sf: icon, size: 10)
                .foregroundStyle(Palette.accent)
            Text(label)
                .font(Typography.label)
                .foregroundStyle(Palette.textQuaternary)
            Text(value)
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Palette.surfaceElevated))
    }

    /// 2 sütunlu örnek öğün ızgarası — dokununca girişi doldurup odaklar.
    private var aiSheetSuggestions: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("HIZLI ÖRNEKLER")
                .font(Typography.label)
                .foregroundStyle(Palette.textQuaternary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(foodAISuggestions, id: \.self) { suggestion in
                    Button {
                        aiFoodInput = suggestion
                        aiInputFocused = true
                    } label: {
                        HStack(spacing: 7) {
                            Lucide(sf: "plus.circle.fill", size: 13)
                                .foregroundStyle(Palette.accent)
                            Text(suggestion)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surfaceElevated))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Tam genişlik büyük hesapla butonu.
    private var aiSheetCTA: some View {
        Button {
            aiInputFocused = false
            Task { await estimateFoodWithAI() }
        } label: {
            HStack(spacing: 8) {
                if isEstimatingFood {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Lucide(sf: "wand.and.stars")
                }
                Text(isEstimatingFood ? "Hesaplanıyor..." : "Hesapla")
            }
            .font(Typography.bodyBold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled((aiFoodInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && aiFoodImages.isEmpty) || isEstimatingFood)
    }

    @ViewBuilder
    private var aiSheetStatus: some View {
        if let aiFoodStatus {
            HStack(spacing: 7) {
                if isEstimatingFood { ProgressView().controlSize(.small) }
                Text(aiFoodStatus)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        if let aiFoodError {
            HStack(alignment: .top, spacing: 7) {
                Lucide(sf: "exclamationmark.triangle.fill", size: 12)
                    .foregroundStyle(Palette.negative)
                Text(aiFoodError)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.negative)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    /// Alttaki boşluğu dolduran kısa ipucu (sonuç/hata yokken).
    private var aiSheetTip: some View {
        HStack(alignment: .top, spacing: 9) {
            Lucide(sf: "lightbulb.fill", size: 12)
                .foregroundStyle(Palette.warning)
            Text("İpucu: pişmiş mi çiğ mi belirt, markayı yaz. Birden fazla yiyeceği + ile ayır — AI tek kayıtta toplar.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    /// Tek dokunuşla giriş kutusunu dolduran örnek yemekler.
    private var foodAISuggestions: [String] {
        [
            "2 yumurta + 1 dilim tam buğday ekmek",
            "100g yulaf + 1 muz",
            "200g ızgara tavuk + 150g pirinç",
            "1 kase mercimek çorbası"
        ]
    }

    private func aiFoodResultCard(_ result: AIFoodResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI TAHMİNİ")
                        .font(Typography.label)
                        .foregroundStyle(Palette.accent)
                    Text(result.name?.nilIfBlank ?? "Yemek tahmini")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = result.message.nilIfBlank {
                        Text(message)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Fmt.int(result.calories ?? 0))")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text("kcal")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            HStack(spacing: 6) {
                macroPill("P", result.protein_g, color: Palette.accent)
                macroPill("K", result.carbs_g, color: Palette.positive)
                macroPill("Y", result.fat_g, color: Palette.warning)
                if let grams = result.grams {
                    macroPill("g", grams, color: Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }

            Button {
                addAIFoodResult(result)
            } label: {
                Label { Text("Bugüne ekle") } icon: { Lucide(sf: "plus.circle.fill") }
                    .font(Typography.bodyBold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled((result.calories ?? 0) <= 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.accent.opacity(0.4), lineWidth: 1))
    }

    private var presetCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Presetler")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Text("\(presets.count)")
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textTertiary)
                }

                ForEach(presetItems) { item in
                    presetRow(item.preset)
                }
            }
        }
    }

    // MARK: - Tarifler sekmesi (Mac paritesi: özet + arama + kategori filtresi + favori + detay)

    // MARK: - Tarifler (V1 defter dili — sabit başlık + arama/filtre, kayan liste)

    private var recipesPage: some View {
        VStack(spacing: 0) {
            recipesHeader
            recipesCounterStrip
            recipesSearchField
            recipesCategoryFilter
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filteredRecipes.isEmpty {
                        Text(recipes.isEmpty
                             ? "Tarif kaydı yok. Mac Hercules'ten ekle ya da AI koçtan iste — senkronla buraya gelir."
                             : "Bu aramada tarif yok.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 28)
                    } else {
                        ForEach(filteredRecipes, id: \.persistentModelID) { recipe in
                            recipeNotebookRow(recipe)
                        }
                    }
                    recipeVideosSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, MobileChrome.dockClearance)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }

    private var recipesHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 5) {
                    Text("Defter").foregroundStyle(Palette.textSecondary)
                    Text("— \(recipes.count) tarif").foregroundStyle(Palette.textQuaternary)
                }
                .font(Typography.label)
                .tracking(1.4)
                Spacer(minLength: 8)
                headerActions
            }
            Text("Tarifler")
                .font(.system(size: 25, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    private var recipesCounterStrip: some View {
        let favorites = recipes.filter(\.isFavorite).count
        let detailed = recipes.filter(\.hasDetail).count
        return HStack(spacing: 0) {
            counterCell("TOPLAM", "\(recipes.count)", "")
            counterDivider
            counterCell("FAVORİ", "\(favorites)", "")
            counterDivider
            counterCell("DETAYLI", "\(detailed)", "")
        }
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    private var recipesSearchField: some View {
        HStack(spacing: 9) {
            Lucide(sf: "magnifyingglass", size: 12)
                .foregroundStyle(Palette.textTertiary)
            TextField("Tarif, malzeme veya özet ara", text: $recipeSearch)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !recipeSearch.isEmpty {
                Button { recipeSearch = "" } label: {
                    Lucide(sf: "xmark", size: 10)
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private var recipesCategoryFilter: some View {
        HStack(spacing: 18) {
            recipeFilterCap("Tümü", active: selectedRecipeCategory == nil) { selectedRecipeCategory = nil }
            ForEach(RecipeCategory.allCases) { category in
                recipeFilterCap(category == .dinner ? "Akşam" : category.label, active: selectedRecipeCategory == category) {
                    selectedRecipeCategory = (selectedRecipeCategory == category) ? nil : category
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    private func recipeFilterCap(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(active ? Palette.textPrimary : Palette.textTertiary)
                .padding(.bottom, 4)
                .overlay(Rectangle().fill(active ? Palette.accent : Color.clear).frame(height: 1.5), alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recipeNotebookRow(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let summary = recipe.summary?.nilIfBlank {
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Button {
                    toggleRecipeFavorite(recipe)
                } label: {
                    Lucide(sf: recipe.isFavorite ? "heart.fill" : "heart", size: 13)
                        .foregroundStyle(recipe.isFavorite ? Palette.warning : Palette.textQuaternary)
                        .frame(width: 26, height: 22, alignment: .top)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recipe.isFavorite ? "Favoriden çıkar" : "Favoriye ekle")
            }
            recipeMetaLine(recipe)
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture { recipeToView = recipe }
    }

    private func recipeMetaLine(_ recipe: Recipe) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Text(recipe.calories.map(Fmt.int) ?? "—").foregroundStyle(Palette.textPrimary)
                Text(" kcal").foregroundStyle(Palette.textQuaternary)
            }
            Text("·").foregroundStyle(Palette.textQuaternary)
            Text("P \(recipe.protein.map(Fmt.int) ?? "—")").foregroundStyle(Palette.textSecondary)
            Text("·").foregroundStyle(Palette.textQuaternary)
            Text(recipe.prepMinutes.map { "\($0)′" } ?? "—").foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 6)
            Text((recipe.category == .dinner ? "Akşam" : recipe.category.label).uppercased(with: Locale(identifier: "tr_TR")))
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.textQuaternary)
            Text(Fmt.date.string(from: recipe.createdAt)).foregroundStyle(Palette.textQuaternary)
        }
        .font(.system(size: 10, design: .monospaced))
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

    /// "Videolar" rafı — sadece isim + link. Mac ile senkron; telefonda bulduğun
    /// tarifli videoyu isimlendirip sakla, tıkla aç, uzun bas → sil.
    private var recipeVideosSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Text("Videolar").foregroundStyle(Palette.textSecondary)
                Text("— \(recipeVideos.count)").foregroundStyle(Palette.textQuaternary)
                Spacer(minLength: 8)
            }
            .font(Typography.label)
            .tracking(1.4)
            .padding(.top, 22)
            .padding(.bottom, 4)

            Text("Sadece isim + video linki. Mac ve telefon senkron.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textQuaternary)
                .padding(.bottom, 12)

            VStack(spacing: 8) {
                TextField("İsim (ör: Fırında tavuk)", text: $newVideoTitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surfaceElevated))
                HStack(spacing: 8) {
                    TextField("Video linki", text: $newVideoURL)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .onSubmit { addRecipeVideo() }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surfaceElevated))
                    Button { addRecipeVideo() } label: {
                        Lucide(sf: "plus", size: 15)
                            .foregroundStyle(canAddVideo ? Palette.btnFg : Palette.textQuaternary)
                            .frame(width: 46, height: 42)
                            .background(RoundedRectangle(cornerRadius: Radius.md).fill(canAddVideo ? Palette.accent : Palette.surfaceElevated))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAddVideo)
                }
            }
            .padding(.bottom, 14)

            if recipeVideos.isEmpty {
                Text("Henüz video yok.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, 10)
            } else {
                ForEach(recipeVideos, id: \.persistentModelID) { video in
                    recipeVideoRow(video)
                }
            }
        }
    }

    @ViewBuilder
    private func recipeVideoRow(_ video: RecipeVideo) -> some View {
        let row = HStack(spacing: 10) {
            Lucide(sf: "link", size: 12)
                .foregroundStyle(Palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                Text(video.sourceHost ?? video.urlString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Lucide(sf: "arrow.up.right", size: 11)
                .foregroundStyle(Palette.textQuaternary)
        }
        .padding(.vertical, 11)
        .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
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
                Text("\(Fmt.int(preset.calories(for: preset.defaultServings))) kcal")
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

    @MainActor
    private func estimateFoodWithAI() async {
        let raw = aiFoodInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = aiFoodImages
        guard (!raw.isEmpty || !images.isEmpty), !isEstimatingFood else { return }
        let outboundImages = images.compactMap { ChatImageStore.downscaledJPEG(from: $0) ?? $0 }

        aiFoodResult = nil
        aiFoodError = nil
        aiFoodStatus = images.isEmpty ? "AI yemeği hesaplıyor..." : "AI fotoğrafı analiz ediyor..."
        isEstimatingFood = true
        defer { isEstimatingFood = false }

        let prompt = """
        MOBIL YEMEK HESAPLAMA KARTI:
        \(images.isEmpty ? "Aşağıdaki metni" : "Ekteki fotoğraf(lar)daki yemeği (varsa metinle birlikte)") tek bir yemek kaydı olarak hesapla.
        Sadece YEMEK MODU top-level JSON dön: name, grams, calories, protein_g, carbs_g, fat_g, message.
        actions üretme; kaydı kullanıcı mobil UI'daki "Bugüne ekle" butonuyla yapacak.
        Eğer birden fazla yiyecek varsa aynı kayıtta toplamla. Fotoğraftan porsiyon/gramajı makul tahmin et.

        \(raw.isEmpty ? "(Metin yok — yalnız fotoğraf)" : "Kullanıcı metni: \(raw)")
        """

        do {
            let (result, searchEvidence) = try await RemoteAIClient().send(
                history: [],
                newUserText: prompt,
                userContext: mobileFoodAIContext,
                images: outboundImages,
                onSearchStart: { query in
                    aiFoodStatus = "Aranıyor: \(query)"
                },
                onMessageUpdate: { _ in }
            )

            if let normalized = normalizedFoodResult(from: result) {
                aiFoodResult = normalized
                aiFoodStatus = searchEvidence.map { "Arama ile güncellendi: \($0.query)" } ?? "Tahmin hazır."
            } else {
                aiFoodError = result.message.nilIfBlank ?? "AI yemek tahmini çıkaramadı. Miktarı biraz daha net yaz."
                aiFoodStatus = nil
            }
        } catch {
            aiFoodError = mobileAIErrorMessage(error)
            aiFoodStatus = nil
        }
    }

    private var mobileFoodAIContext: String {
        let profile = profiles.first
        let latestWeight = measurements.first?.weight.map { "\(Fmt.num($0, digits: 1)) kg" } ?? "yok"
        let latestBodyFat = measurements.first?.bodyFat.map { "\(Fmt.num($0, digits: 1))%" } ?? "yok"
        let target = profile?.targetWeight.map { "\(Fmt.num($0, digits: 1)) kg" } ?? "yok"
        let supplements = profile?.effectiveSupplements
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " + ")
        let supplementLine = supplements?.isEmpty == false ? (supplements ?? "yok") : "yok"
        let todaySummary = "\(Fmt.int(todayCalories)) kcal, \(Fmt.int(todayProtein))g protein"
        return """
        MOBIL FOOD AI CONTEXT:
        - Bu istek sadece yemek/makro tahmini icin. App action üretme.
        - Kullanici hedefi: \(profile?.goal.label ?? "bilinmiyor"), hedef kilo: \(target)
        - Kullanici supplementleri: \(supplementLine)
        - Son kilo: \(latestWeight), son yag orani: \(latestBodyFat)
        - Bugun simdiye kadar: \(todaySummary)
        - Çiğ/pişmiş ayrımına dikkat et. Kullanıcı pişmiş diyorsa pişmiş değerleri kullan.
        - Emin olmadığın marka/üründe web_search kullanabilirsin; temel yiyeceklerde hızlı tahmin yap.
        """
    }

    /// Telefonun o an gördüğü taze özet. Mac sunucusu bunu kendi SwiftData
    /// snapshot'ı ve agent skill context'iyle birleştirir.
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

    private func normalizedFoodResult(from result: AIFoodResult) -> AIFoodResult? {
        if result.isFood {
            return result
        }
        guard let action = result.actionList.first(where: { $0.tool == .logFood }) else {
            return nil
        }
        return AIFoodResult(
            name: action.name ?? action.summary ?? "AI yemek",
            grams: action.grams ?? action.amount,
            calories: action.calories,
            protein_g: action.proteinG,
            carbs_g: action.carbsG,
            fat_g: action.fatG,
            message: result.message.nilIfBlank ?? action.summary ?? "Tahmini değerler hazır."
        )
    }

    private func addAIFoodResult(_ result: AIFoodResult) {
        let entry = FoodEntry(
            date: .now,
            name: result.name?.nilIfBlank ?? "AI yemek",
            grams: result.grams,
            calories: result.calories ?? 0,
            protein: result.protein_g,
            carbs: result.carbs_g,
            fat: result.fat_g
        )
        ctx.insert(entry)
        ctx.saveOrReport()
        aiFoodInput = ""
        aiFoodResult = nil
        aiFoodError = nil
        aiFoodStatus = "Bugüne eklendi."
        // Bugün sekmesinin + sheet'inden eklendiyse kapat; inline kartta no-op.
        showFoodAIEstimator = false
    }

    private func mobileAIErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut].contains(urlError.code) {
            return "Koç'a ulaşılamadı. Tailscale bağlantını kontrol edip tekrar dene."
        }
        return "Koç hatası: \(message)"
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
            macroBox("Kalori", recipe.calories.map { Fmt.int($0) } ?? "—", "kcal")
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
