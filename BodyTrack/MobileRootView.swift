import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Charts

struct MobileRootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \UserProfile.name) private var profiles: [UserProfile]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \StepEntry.date, order: .reverse) private var steps: [StepEntry]
    @Query(sort: \WorkoutSession.weekday) private var workouts: [WorkoutSession]
    @Query(sort: \WorkoutProgramArchive.archivedAt, order: .reverse) private var archives: [WorkoutProgramArchive]
    @Query(sort: \WorkoutLog.date, order: .reverse) private var workoutLogs: [WorkoutLog]
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \FoodPreset.sortOrder) private var presets: [FoodPreset]

    /// Mac'ten gelen "Telefona gönder" feed'i (@Observable → akış/badge reaktif).
    private let feedStore = FeedStore.shared

    @State private var selectedTab: MobileTab = .dashboard
    @State private var showVaultImporter = false
    @State private var showRestoreConfirm = false
    @State private var showAddMeasurement = false
    @State private var showFoodAIEstimator = false
    @State private var showAllFoods = false
    @State private var statusMessage: String? = nil
    @State private var saveErrors = SaveErrorReporter.shared
    @State private var openRouterKey = ""
    /// Keychain'den geri okunarak doğrulanan gerçek kalıcılık durumu (text kutusu değil).
    @State private var keyPersisted = false
    @State private var showProfileEditor = false
    @State private var showRecipeEditor = false
    @State private var recipeToEdit: Recipe?
    @State private var recipeToView: Recipe?
    @State private var selectedRecipeCategory: RecipeCategory?
    @State private var recipeSearch = ""
    @State private var showFavoriteRecipesOnly = false
    @State private var foodToDelete: FoodEntry?
    @State private var measurementToDelete: Measurement?
    @State private var workoutToDelete: WorkoutSession?
    /// Mutation sonrası debounce'lı vault push (force-quit'e güvenmeden, foreground'da).
    @State private var pendingSyncTask: Task<Void, Never>?
    @State private var calendarMonth: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var calendarSelectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var isWorking = false
    @State private var refreshTick = UUID()

    @State private var aiFoodInput = ""
    @State private var aiFoodResult: AIFoodResult?
    @State private var aiFoodStatus: String?
    @State private var aiFoodError: String?
    @State private var isEstimatingFood = false
    @FocusState private var aiInputFocused: Bool

    @State private var measurementWeight = ""
    @State private var measurementBodyFat = ""
    @State private var measurementWaist = ""
    @State private var measurementChest = ""
    @State private var measurementNeck = ""
    @State private var measurementFullCheckIn = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()

            selectedPage

            mobileBottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dynamicTypeSize(.small ... .xLarge)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showVaultImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleVaultImport(result)
        }
        .alert("iCloud vault içeri alınsın mı?", isPresented: $showRestoreConfirm) {
            Button("İptal", role: .cancel) { }
            Button("İçeri al", role: .destructive) { restoreVault() }
        } message: {
            Text("Bu cihazdaki local veri değişmeden önce safety backup alınır. Sonra seçili klasördeki Hercules snapshot içeri aktarılır.")
        }
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
        .sheet(isPresented: $showAllFoods) {
            foodHistorySheet
        }
        .sheet(isPresented: $showAddMeasurement) {
            measurementForm
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showProfileEditor) {
            if let profile = profiles.first {
                MobileProfileEditor(profile: profile) {
                    ctx.saveOrReport()
                    refreshTick = UUID()
                }
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
        .onAppear {
            restoreIfNewer()
            // Getter Keychain'den okur — boş değilse key gerçekten kalıcı kayıtlı demektir.
            openRouterKey = AIKeyStore.shared.apiKey
            keyPersisted = !openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Merge sync güvenli (union) → foreground'da oto pull-merge + push,
            // background'da local yedek + vault push (best-effort). Throttle'lı.
            switch newPhase {
            case .active:
                Task { @MainActor in await BackupService.shared.autoSyncWithVault(into: ctx) }
            case .background:
                BackupService.shared.exportAsync(from: ctx)
                Task { @MainActor in await BackupService.shared.autoSyncWithVault(into: ctx) }
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selectedTab {
        case .dashboard:
            mobilePage { dashboardPage }
        case .feed:
            mobilePage { feedPage }
        case .nutrition:
            mobilePage { nutritionPage }
        case .workout:
            mobilePage { workoutPage }
        case .measurements:
            mobilePage { measurementsPage }
        case .recipes:
            mobilePage { recipesPage }
        case .calendar:
            mobilePage { calendarPage }
        case .profile:
            mobilePage { profilePage }
        }
    }

    private var mobileBottomBar: some View {
        HStack(spacing: 4) {
            ForEach(MobileTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .overlay(alignment: .topTrailing) {
                                if tab == .feed, feedStore.unseenCount > 0 {
                                    Text("\(min(feedStore.unseenCount, 9))")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(minWidth: 15, minHeight: 15)
                                        .background(Circle().fill(Palette.accent))
                                        .offset(x: 9, y: -6)
                                }
                            }
                        Text(tab.shortTitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(selectedTab == tab ? Palette.accent : Palette.textSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selectedTab == tab ? Palette.surfaceElevated : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func mobilePage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 104)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }

    // MARK: - Akış (Mac'ten gelen feed)

    private var feedPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if feedStore.items.isEmpty {
                feedEmpty
            } else {
                ForEach(feedStore.items) { feedCard($0) }
            }
        }
        .task {
            await BackupService.shared.autoSyncWithVault(into: ctx)
            feedStore.markAllSeen()
        }
    }

    private func feedCard(_ item: FeedItem) -> some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: item.kind == "recipe" ? "fork.knife" : "laptopcomputer")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.accent)
                    Text(item.source == "Mac" ? "Mac Hercules" : item.source)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.accent)
                    Spacer(minLength: 0)
                    Text(Fmt.relative(item.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.body)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var feedEmpty: some View {
        MobileCard {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Palette.textTertiary)
                Text("Akış boş")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text("Mac Hercules'te bir sohbet mesajında \"Telefona gönder\"e bas — burada feed gibi belirir.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private var dashboardPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroCard
            todayFoodCard
            latestMeasurementCard
            nextWorkoutCard
        }
    }

    private var nutritionPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Yemek", action: "Öğün ekle", systemImage: "plus") {
                showFoodAIEstimator = true
            }
            nutritionSummaryCard
            calorieTrendCard
            todayFoodCard
            recentFoodsCard
        }
    }

    private var workoutPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            workoutWeekStrip
            summaryStrip([
                ("Program", "\(activeWorkouts.count) gün"),
                ("Log", "\(workoutLogs.count)"),
                ("Arşiv", "\(archives.count)")
            ])

            // Haftalık program şablonu — Mac'teki "Aktif Program" gibi (ısınma + hareketler
            // + link + set×tekrar·RIR·dinlenme + progression + not).
            if !activeWorkouts.isEmpty {
                mobileSectionHeader("Haftalık program")
                ForEach(activeWorkouts, id: \.persistentModelID) { workout in
                    MobileCard {
                        workoutContent(workout, compact: false)
                    }
                }
            }

            // Loglanmış seanslar (set/tekrar/kg).
            if !workoutLogs.isEmpty {
                mobileSectionHeader("Son antrenmanlar")
                ForEach(workoutLogs.prefix(12), id: \.persistentModelID) { log in
                    MobileCard {
                        workoutLogContent(log)
                    }
                }
            }

            if activeWorkouts.isEmpty && workoutLogs.isEmpty {
                MobileCard {
                    emptyText("Antrenman kaydı yok. Mac'tan loglayabilir ya da AI koçtan program ekleyebilirsin.")
                }
            }
        }
        // Spor sekmesi açılınca vault'tan çek → Mac'ten gelen program/loglar güncel olsun.
        .task {
            await BackupService.shared.autoSyncWithVault(into: ctx)
        }
    }

    /// Haftalık gün şeridi: bugünü vurgular, antrenman olan günleri nokta ile işaretler.
    private var workoutWeekStrip: some View {
        let today = Calendar.current.component(.weekday, from: .now)
        return MobileCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bu hafta")
                    .font(Typography.label)
                    .foregroundStyle(Palette.textQuaternary)
                    .textCase(.uppercase)
                HStack(spacing: 6) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                        let has = activeWorkouts.contains { $0.weekday == wd }
                        let isToday = wd == today
                        VStack(spacing: 6) {
                            Text(WorkoutSession.weekdayShortName(wd))
                                .font(isToday ? Typography.captionBold : Typography.label)
                                .foregroundStyle(isToday ? Palette.accent : (has ? Palette.textSecondary : Palette.textTertiary))
                            Circle()
                                .fill(has ? Palette.accent : Palette.borderStrong)
                                .frame(width: isToday ? 8 : 7, height: isToday ? 8 : 7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(isToday ? Palette.accent.opacity(0.16) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(isToday ? Palette.accent : .clear, lineWidth: 1.2)
                        )
                    }
                }
            }
        }
    }

    private var measurementsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Ölçümler", action: "Ekle", systemImage: "plus") {
                seedMeasurementForm()
                showAddMeasurement = true
            }
            measurementCadenceCard
            measurementHeroCard
            weightTrendCard
            MobileCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Son kayıtlar")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                    ForEach(measurements.prefix(16), id: \.persistentModelID) { measurement in
                        measurementRow(measurement)
                    }
                    if measurements.isEmpty {
                        emptyText("Ölçüm kaydı yok.")
                    }
                }
            }
        }
    }

    private var measurementCadenceCard: some View {
        let isFullDay = MeasurementCadence.isFullCheckInDay()
        let hasThisWeekFull = MeasurementCadence.hasFullCheckInThisWeek(measurements)
        let nextFull = MeasurementCadence.nextFullCheckIn()

        return MobileCard {
            HStack(alignment: .top, spacing: 12) {
                icon(isFullDay ? "ruler.fill" : "calendar.badge.clock", color: isFullDay ? Palette.accent : Palette.textSecondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(isFullDay ? "Bugün tam ölçüm günü" : "Cumartesi tam ölçüm")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                    Text(mobileMeasurementCadenceText(isFullDay: isFullDay, hasThisWeekFull: hasThisWeekFull, nextFull: nextFull))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    seedMeasurementForm(forceFull: true)
                    showAddMeasurement = true
                } label: {
                    Text("Tam")
                        .font(Typography.captionBold)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func mobileMeasurementCadenceText(isFullDay: Bool, hasThisWeekFull: Bool, nextFull: Date) -> String {
        if isFullDay {
            return hasThisWeekFull
                ? "Bu haftanın tam ölçümü girilmiş. Gerekirse yeni tam ölçümle düzelt."
                : "Kilo dışında yağ %, bel, göğüs ve boyun da gir."
        }
        return "Bugün hızlı tartı yeterli. Sıradaki tam ölçüm: \(Fmt.dateLong.string(from: nextFull))."
    }

    private var calendarPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            calendarGridCard
            calendarDaySummaryCard
        }
    }

    private var calendarGridCard: some View {
        let days = calendarDays(for: calendarMonth)
        return MobileCard {
            VStack(spacing: 12) {
                HStack {
                    Button { shiftMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Palette.surfaceElevated))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Text(monthTitle(calendarMonth))
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Button { shiftMonth(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Palette.surfaceElevated))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textPrimary)
                }
                HStack(spacing: 4) {
                    ForEach(["Pt", "Sa", "Ça", "Pe", "Cu", "Ct", "Pz"], id: \.self) { d in
                        Text(d)
                            .font(Typography.label)
                            .foregroundStyle(Palette.textQuaternary)
                            .frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        calendarDayCell(day)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func calendarDayCell(_ date: Date?) -> some View {
        if let date {
            let cal = Calendar.current
            let isSelected = cal.isDate(date, inSameDayAs: calendarSelectedDay)
            let isToday = cal.isDateInToday(date)
            let kcal = dayCalories(date)
            let hasWorkout = activeWorkouts.contains { $0.weekday == cal.component(.weekday, from: date) }
            let hasMeasure = measurements.contains { cal.isDate($0.date, inSameDayAs: date) }
            Button {
                calendarSelectedDay = date
            } label: {
                VStack(spacing: 3) {
                    Text("\(cal.component(.day, from: date))")
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isSelected ? Palette.background : (isToday ? Palette.accent : Palette.textPrimary))
                    HStack(spacing: 2) {
                        if kcal > 0 { Circle().fill(isSelected ? Palette.background : Palette.warning).frame(width: 4, height: 4) }
                        if hasWorkout { Circle().fill(isSelected ? Palette.background : Palette.accent).frame(width: 4, height: 4) }
                        if hasMeasure { Circle().fill(isSelected ? Palette.background : Palette.positive).frame(width: 4, height: 4) }
                    }
                    .frame(height: 5)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? Palette.accent : (isToday ? Palette.surfaceElevated : Color.clear))
                )
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 42)
        }
    }

    private var calendarDaySummaryCard: some View {
        let cal = Calendar.current
        let day = calendarSelectedDay
        let dayFoods = foods.filter { cal.isDate($0.date, inSameDayAs: day) }
        let kcal = dayFoods.reduce(0) { $0 + $1.calories }
        let protein = dayFoods.reduce(0) { $0 + ($1.protein ?? 0) }
        let workout = activeWorkouts.first { $0.weekday == cal.component(.weekday, from: day) }
        let measure = measurements.first { cal.isDate($0.date, inSameDayAs: day) }
        return MobileCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(daySummaryTitle(day))
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                HStack(spacing: 10) {
                    metric("Kalori", value: Fmt.int(kcal), unit: "kcal")
                    metric("Protein", value: Fmt.int(protein), unit: "g")
                    metric("Öğün", value: "\(dayFoods.count)", unit: "")
                }
                if let workout {
                    Button {
                        selectedTab = .workout
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("ANTRENMAN")
                                    .font(Typography.label)
                                    .foregroundStyle(Palette.textQuaternary)
                                Text(workout.name)
                                    .font(Typography.captionBold)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 4)
                            Text("Programı aç")
                                .font(Typography.label)
                                .foregroundStyle(Palette.accent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.accent)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Spor sayfasına gider")
                }
                if let measure, let w = measure.weight {
                    heroStat("Kilo", value: "\(Fmt.num(w, digits: 1)) kg", systemImage: "scalemass")
                }
                if dayFoods.isEmpty && workout == nil && measure == nil {
                    emptyText("Bu gün için kayıt yok.")
                }
            }
        }
    }

    private func calendarDays(for month: Date) -> [Date?] {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthStart)   // 1=Paz..7=Cmt
        let leading = (firstWeekday + 5) % 7                            // Pazartesi bazlı boşluk sayısı
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            cells.append(cal.date(byAdding: .day, value: day - 1, to: monthStart))
        }
        return cells
    }

    private func shiftMonth(_ delta: Int) {
        if let m = Calendar.current.date(byAdding: .month, value: delta, to: calendarMonth) {
            calendarMonth = m
        }
    }

    private func dayCalories(_ date: Date) -> Double {
        let cal = Calendar.current
        return foods.filter { cal.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.calories }
    }

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date).capitalized
    }

    private func daySummaryTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM EEEE"
        return f.string(from: date)
    }

    private var profilePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            profileSummaryCard
            mobileAICard
            syncNowButton
            syncPanel
            dataPanel
        }
    }

    private var profileSummaryCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Profil")
                            .font(Typography.label)
                            .foregroundStyle(Palette.textQuaternary)
                            .textCase(.uppercase)
                        Text(profileName.isEmpty ? "İsimsiz" : profileName)
                            .font(Typography.hero(24))
                            .foregroundStyle(Palette.textPrimary)
                        if let p = profiles.first {
                            Text("\(p.goal.label) · \(p.activity.label)")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    Spacer()
                    Button {
                        showProfileEditor = true
                    } label: {
                        Label("Düzenle", systemImage: "pencil")
                            .font(Typography.captionBold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                if let p = profiles.first {
                    HStack(spacing: 10) {
                        heroStat("Yaş", value: "\(p.age)", systemImage: "calendar")
                        heroStat("Boy", value: "\(Fmt.int(p.height)) cm", systemImage: "ruler")
                        heroStat("Hedef", value: p.targetWeight.map { "\(Fmt.num($0, digits: 1)) kg" } ?? "—", systemImage: "target")
                    }
                    if let plan = calorieResult {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            metric("Günlük", value: Fmt.int(plan.goalCalories), unit: "kcal")
                            metric("Protein", value: Fmt.int(plan.protein.grams), unit: "g")
                            metric("Karb", value: Fmt.int(plan.carbs.grams), unit: "g")
                            metric("Yağ", value: Fmt.int(plan.fat.grams), unit: "g")
                        }
                    }
                }
            }
        }
    }

    private var syncNowButton: some View {
        Button {
            syncNow()
        } label: {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(isWorking ? "Senkronize ediliyor..." : "Şimdi Senkronize Et")
                    .font(Typography.body)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isWorking)
    }

    /// Mobilde AI sağlayıcı: OpenRouter API key (Codex/Terminal telefonda yok).
    /// Key girilince yemek tahmini bu istemciyle çalışır (makeClient() taze okur).
    private var mobileAICard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    icon("sparkles", color: aiKeyConfigured ? Palette.positive : (keyHasText ? Palette.warning : Palette.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Sağlayıcı — OpenRouter")
                            .font(Typography.titleSmall)
                            .foregroundStyle(Palette.textPrimary)
                        Text(keyStatusText)
                            .font(Typography.caption)
                            .foregroundStyle(keyStatusColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if aiKeyConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Palette.positive)
                    } else if keyHasText {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.warning)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "key")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                    SecureField("sk-or-...", text: $openRouterKey)
                        .textFieldStyle(.plain)
                        .font(Typography.mono)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: openRouterKey) { _, value in
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            AIKeyStore.shared.apiKey = value
                            if !trimmed.isEmpty {
                                AIKeyStore.shared.provider = .openRouter
                            }
                            // Geri oku: getter Keychain'den döner. Eşleşiyorsa yazma TUTTU
                            // demektir; tutmadıysa (sessiz Keychain hatası) rozet "Bağlı" demez.
                            keyPersisted = !trimmed.isEmpty
                                && AIKeyStore.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
                        }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))

                Text("openrouter.ai/keys adresinden API key al. Bir kere yapıştır — Keychain'e kalıcı kaydedilir, uygulamayı kapatsan da durur. Telefonda Codex/Terminal gerekmez.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Kutuda metin var mı (henüz kalıcı olup olmadığından bağımsız).
    private var keyHasText: Bool {
        !openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// "Bağlı ✓" yalnızca key GERÇEKTEN Keychain'e yazılıp geri okunabildiyse true.
    private var aiKeyConfigured: Bool { keyHasText && keyPersisted }

    private var keyStatusText: String {
        if aiKeyConfigured { return "Bağlı — Keychain'e kaydedildi, kalıcı" }
        if keyHasText { return "Kaydedilemedi — key'i tekrar yapıştır" }
        return "API key gir, yemek tahmini çalışsın"
    }

    private var keyStatusColor: Color {
        if aiKeyConfigured { return Palette.positive }
        if keyHasText { return Palette.warning }
        return Palette.textTertiary
    }

    /// Tek dokunuşla iki-yönlü senkron: önce vault daha yeni/zenginse çek (Mac verisi),
    /// sonra yerel veriyi vault'a yaz (Mac sonra çekebilsin). Vault yoksa klasör seçtirir.
    private func syncNow() {
        guard vaultConfigured else {
            statusMessage = "Önce iCloud Drive/Hercules klasörünü seç."
            showVaultImporter = true
            return
        }
        // Bloklamayan tam senkron: pull-merge (vault'tan kat) + push (birleşmişi yaz).
        // Ağır iCloud okuması arka planda ısıtılır; merge ezmez, katar.
        Task { @MainActor in
            isWorking = true
            statusMessage = "Senkronize ediliyor..."
            await BackupService.shared.syncWithVaultNonBlocking(into: ctx)
            FoodPresetSeed.upsertDefaults(ctx)
            statusMessage = BackupService.shared.syncDiagnostics(ctx: ctx)
            isWorking = false
            refreshTick = UUID()
        }
    }

    private var heroCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bugün")
                            .font(Typography.label)
                            .foregroundStyle(Palette.textQuaternary)
                            .textCase(.uppercase)
                        Text(profileName.isEmpty ? "Hercules" : "Selam, \(profileName)")
                            .font(Typography.hero(26))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Spacer()
                    icon("bolt.heart", color: Palette.accent)
                }

                if let plan = calorieResult {
                    HStack(spacing: 18) {
                        MobileProgressRing(progress: todayCalories / max(1, plan.goalCalories)) {
                            VStack(spacing: 1) {
                                Text(Fmt.int(max(0, plan.goalCalories - todayCalories)))
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundStyle(Palette.textPrimary)
                                Text("kcal kaldı")
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 11) {
                            heroMacroBar("Protein", todayProtein, plan.protein.grams, Palette.accent)
                            heroMacroBar("Karb", todayCarbs, plan.carbs.grams, Palette.warning)
                            heroMacroBar("Yağ", todayFat, plan.fat.grams, Palette.positive)
                        }
                    }
                    Text("\(Fmt.int(todayCalories)) / \(Fmt.int(plan.goalCalories)) kcal alındı")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    HStack(spacing: 10) {
                        metric("Kalori", value: Fmt.int(todayCalories), unit: "kcal")
                        metric("Protein", value: Fmt.int(todayProtein), unit: "g")
                        metric("Adım", value: Fmt.int(Double(todaySteps)), unit: "")
                    }
                    Text("Profilini doldurunca (Mac'tan ya da Profil sekmesinden) günlük kalori/makro hedefi ve halka burada görünür.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    heroStat("Adım", value: Fmt.int(Double(todaySteps)), systemImage: "figure.walk")
                    heroStat("Kilo", value: measurements.first?.weight.map { "\(Fmt.num($0, digits: 1)) kg" } ?? "—", systemImage: "scalemass")
                    heroStat("Su", value: calorieResult.map { "\(Fmt.num($0.water, digits: 1)) L" } ?? "—", systemImage: "drop.fill")
                }
            }
        }
    }

    private func heroMacroBar(_ label: String, _ value: Double, _ target: Double, _ color: Color) -> some View {
        let pct = target > 0 ? min(value / target, 1) : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textTertiary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(Fmt.int(value))/\(Fmt.int(target))g")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceElevated).frame(height: 6)
                    Capsule().fill(color).frame(width: max(0, geo.size.width * pct), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func heroStat(_ label: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
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
    private var nutritionSummaryCard: some View {
        MobileCard {
            if let plan = calorieResult {
                HStack(spacing: 16) {
                    MobileProgressRing(progress: todayCalories / max(1, plan.goalCalories), lineWidth: 10, size: 108) {
                        VStack(spacing: 0) {
                            Text(Fmt.int(todayCalories))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.textPrimary)
                            Text("/ \(Fmt.int(plan.goalCalories))")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        heroMacroBar("Protein", todayProtein, plan.protein.grams, Palette.accent)
                        heroMacroBar("Karb", todayCarbs, plan.carbs.grams, Palette.warning)
                        heroMacroBar("Yağ", todayFat, plan.fat.grams, Palette.positive)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    metric("Bugün", value: Fmt.int(todayCalories), unit: "kcal")
                    metric("Protein", value: Fmt.int(todayProtein), unit: "g")
                    metric("Öğün", value: "\(todayFoods.count)", unit: "")
                }
            }
        }
    }

    private var todayFoodCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Bugünkü yemekler")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    HStack(spacing: 8) {
                        Text("\(todayFoods.count) kayıt")
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.textTertiary)
                        Button {
                            showFoodAIEstimator = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.textPrimary)
                        .background(Circle().fill(Palette.surfaceElevated))
                        .accessibilityLabel("AI ile yemek ekle")
                    }
                }

                if todayFoods.isEmpty {
                    emptyText("Bugün yemek kaydı yok.")
                } else {
                    ForEach(todayFoods.prefix(8), id: \.persistentModelID) { food in
                        foodRow(food)
                    }
                }
            }
        }
    }

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
                        Label("Hesapla", systemImage: "wand.and.stars")
                    }
                    .disabled(aiFoodInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEstimatingFood)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Dostça başlık — nav title "Öğün ekle" ile tekrar etmesin diye "Ne yedin?" sorusu.
    private var aiSheetIntro: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.accentSoft)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
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

            if let plan = calorieResult {
                HStack(spacing: 8) {
                    aiBudgetPill(icon: "flame.fill", label: "Kalan", value: "\(Fmt.int(max(0, plan.goalCalories - todayCalories))) kcal")
                    aiBudgetPill(icon: "bolt.fill", label: "Protein", value: "\(Fmt.int(todayProtein))/\(Fmt.int(plan.protein.grams))g")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func aiBudgetPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
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
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13))
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
                    Image(systemName: "wand.and.stars")
                }
                Text(isEstimatingFood ? "Hesaplanıyor..." : "Hesapla")
            }
            .font(Typography.bodyBold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(aiFoodInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEstimatingFood)
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
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
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
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
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
                Label("Bugüne ekle", systemImage: "plus.circle.fill")
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

    private var recipesPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Tarifler", action: "Ekle", systemImage: "plus") {
                recipeToEdit = nil
                showRecipeEditor = true
            }
            recipeSummaryStrip
            recipeSearchField
            recipeCategoryChips
            if filteredRecipes.isEmpty {
                MobileCard {
                    emptyText(recipes.isEmpty
                        ? "Tarif kaydı yok. + ile ekle ya da AI koçtan iste."
                        : "Bu filtreye uyan tarif yok.")
                }
            } else {
                ForEach(filteredRecipes, id: \.persistentModelID) { recipe in
                    recipeListCard(recipe)
                }
            }
        }
    }

    private var recipeSummaryStrip: some View {
        let favorites = recipes.filter(\.isFavorite).count
        let detailed = recipes.filter(\.hasDetail).count
        return MobileCard {
            HStack(spacing: 10) {
                metric("Toplam", value: "\(recipes.count)", unit: "")
                metric("Favori", value: "\(favorites)", unit: "")
                metric("Detaylı", value: "\(detailed)", unit: "")
            }
        }
    }

    private var recipeSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
            TextField("Tarif, malzeme veya özet ara", text: $recipeSearch)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !recipeSearch.isEmpty {
                Button {
                    recipeSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textQuaternary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.borderStrong, lineWidth: 0.5))
    }

    private var recipeCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                recipeChip(title: "Tümü", icon: "square.grid.2x2", isSelected: selectedRecipeCategory == nil && !showFavoriteRecipesOnly) {
                    selectedRecipeCategory = nil
                    showFavoriteRecipesOnly = false
                }
                ForEach(RecipeCategory.allCases) { category in
                    recipeChip(title: category.label, icon: category.icon, isSelected: selectedRecipeCategory == category) {
                        selectedRecipeCategory = (selectedRecipeCategory == category) ? nil : category
                    }
                }
                recipeChip(
                    title: "Favoriler",
                    icon: showFavoriteRecipesOnly ? "heart.fill" : "heart",
                    isSelected: showFavoriteRecipesOnly,
                    tint: Palette.warning
                ) {
                    showFavoriteRecipesOnly.toggle()
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func recipeChip(title: String, icon: String, isSelected: Bool, tint: Color = Palette.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(Typography.captionBold)
            }
            .foregroundStyle(isSelected ? Palette.background : Palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(isSelected ? tint : Palette.surfaceElevated))
        }
        .buttonStyle(.plain)
    }

    private func recipeListCard(_ recipe: Recipe) -> some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: recipe.category.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.accentSoft))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.title)
                            .font(Typography.bodyBold)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(2)
                        Text(recipe.summary?.nilIfBlank ?? recipe.category.label)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button {
                        toggleRecipeFavorite(recipe)
                    } label: {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(recipe.isFavorite ? Palette.warning : Palette.textQuaternary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(recipe.isFavorite ? "Favoriden çıkar" : "Favoriye ekle")
                }

                HStack(spacing: 6) {
                    if let kcal = recipe.calories {
                        recipeTag("\(Fmt.int(kcal)) kcal", icon: "flame.fill")
                    }
                    if let protein = recipe.protein {
                        recipeTag("P \(Fmt.int(protein))g", icon: "bolt.fill")
                    }
                    if let prep = recipe.prepMinutes {
                        recipeTag("\(prep) dk", icon: "clock")
                    }
                    recipeTag(Fmt.date.string(from: recipe.createdAt), icon: "calendar")
                    Spacer(minLength: 0)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { recipeToView = recipe }
    }

    private func recipeTag(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(Typography.label)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.surfaceElevated))
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
        BackupService.shared.exportAsync(from: ctx)
        scheduleVaultPush()
        refreshTick = UUID()
    }

    private var recentFoodsCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Son yemek kayıtları")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    if foods.count > 3 {
                        Button {
                            showAllFoods = true
                        } label: {
                            HStack(spacing: 3) {
                                Text("Tümünü gör")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tüm yemek kayıtlarını gör")
                    }
                }
                if foods.isEmpty {
                    emptyText("Yemek kaydı yok.")
                } else {
                    ForEach(foods.prefix(3), id: \.persistentModelID) { food in
                        foodRow(food)
                    }
                }
            }
        }
    }

    /// "Tümünü gör" ile açılan tam yemek geçmişi — güne göre gruplu (yeni sayfa, sheet).
    private var foodHistorySheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if foods.isEmpty {
                        MobileCard { emptyText("Yemek kaydı yok.") }
                    } else {
                        ForEach(foodsByDay, id: \.day) { group in
                            MobileCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(foodDayTitle(group.day))
                                            .font(Typography.titleSmall)
                                            .foregroundStyle(Palette.textPrimary)
                                        Spacer()
                                        Text("\(Fmt.int(group.totalCalories)) kcal")
                                            .font(Typography.captionBold)
                                            .foregroundStyle(Palette.textTertiary)
                                    }
                                    ForEach(group.items, id: \.persistentModelID) { food in
                                        foodRow(food)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Tüm yemek kayıtları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { showAllFoods = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private struct FoodDayGroup {
        let day: Date
        let items: [FoodEntry]
        var totalCalories: Double { items.reduce(0) { $0 + $1.calories } }
    }

    /// Yemekleri güne göre grupla (yeni → eski), gün içinde de yeni → eski.
    private var foodsByDay: [FoodDayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: foods) { cal.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            FoodDayGroup(day: day, items: (grouped[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    private func foodDayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInYesterday(date) { return "Dün" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM EEEE"
        return f.string(from: date)
    }

    /// Ölçüm sekmesi hero'su: büyük kilo + önceki ölçüme göre delta + mini trend + yağ/bel/hedef.
    private var measurementHeroCard: some View {
        let weights = measurements.compactMap { $0.weight }                    // DESC
        let series = Array(measurements.prefix(24).reversed().compactMap { $0.weight })  // eski→yeni
        return MobileCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Son Ölçüm")
                            .font(Typography.label)
                            .foregroundStyle(Palette.textQuaternary)
                            .textCase(.uppercase)
                        if let date = measurements.first?.date {
                            Text(date, style: .date)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    Spacer()
                    icon("scalemass", color: Palette.accent)
                }

                if let m = measurements.first {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(m.weight.map { Fmt.num($0, digits: 1) } ?? "—")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                        Text("kg")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textTertiary)
                        Spacer()
                        if weights.count >= 2 {
                            deltaBadge(weights[0] - weights[1], unit: "kg")
                        }
                    }

                    if series.count >= 2 {
                        MobileSparkline(values: series, tint: Palette.accent)
                            .frame(height: 46)
                    }

                    HStack(spacing: 10) {
                        heroStat("Yağ", value: m.bodyFat.map { "\(Fmt.num($0, digits: 1))%" } ?? "—", systemImage: "drop.triangle")
                        heroStat("Bel", value: m.waist.map { "\(Fmt.num($0, digits: 1)) cm" } ?? "—", systemImage: "ruler")
                        heroStat("Hedef", value: profiles.first?.targetWeight.map { "\(Fmt.num($0, digits: 1)) kg" } ?? "—", systemImage: "target")
                    }
                } else {
                    emptyText("Henüz ölçüm yok. Sağ üstteki Ekle ile başla.")
                }
            }
        }
    }

    private func deltaBadge(_ delta: Double, unit: String) -> some View {
        let flat = abs(delta) < 0.05
        return HStack(spacing: 3) {
            Image(systemName: flat ? "minus" : (delta < 0 ? "arrow.down.right" : "arrow.up.right"))
                .font(.system(size: 10, weight: .bold))
            Text("\(Fmt.num(abs(delta), digits: 1)) \(unit)")
                .font(Typography.captionBold)
        }
        .foregroundStyle(flat ? Palette.textTertiary : Palette.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.surfaceElevated))
    }

    private var weightTrendCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Kilo Trendi")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                if weightTrendPoints.count >= 2 {
                    MobileTrendChart(points: weightTrendPoints, tint: Palette.accent, target: profiles.first?.targetWeight)
                } else {
                    emptyText("Trend için en az 2 kilo ölçümü gerekli.")
                }
            }
        }
    }

    private var calorieTrendCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Kalori — Son 14 Gün")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    if let plan = calorieResult {
                        Text("Hedef \(Fmt.int(plan.goalCalories))")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                MobileTrendChart(points: calorieTrendPoints, tint: Palette.warning, target: calorieResult?.goalCalories, bars: true)
            }
        }
    }

    private var latestMeasurementCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Son ölçüm")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    if let date = measurements.first?.date {
                        Text(date, style: .date)
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                if let measurement = measurements.first {
                    HStack(spacing: 10) {
                        metric("Kilo", value: measurement.weight.map { Fmt.num($0, digits: 1) } ?? "-", unit: "kg")
                        metric("Yağ", value: measurement.bodyFat.map { Fmt.num($0, digits: 1) } ?? "-", unit: "%")
                        metric("Bel", value: measurement.waist.map { Fmt.num($0, digits: 1) } ?? "-", unit: "cm")
                    }
                    if measurement.isFullCheckIn {
                        HStack(spacing: 10) {
                            metric("Göğüs", value: measurement.chest.map { Fmt.num($0, digits: 1) } ?? "-", unit: "cm")
                            metric("Boyun", value: measurement.neck.map { Fmt.num($0, digits: 1) } ?? "-", unit: "cm")
                            metric("Tip", value: "Tam", unit: "")
                        }
                    }
                } else {
                    emptyText("Ölçüm kaydı yok.")
                }
            }
        }
    }

    private var nextWorkoutCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sıradaki antrenman")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)

                if let workout = nextWorkout {
                    workoutContent(workout, compact: false)
                } else {
                    emptyText("Aktif program yok.")
                }
            }
        }
    }

    private var syncPanel: some View {
        MobileCard {
            HStack(alignment: .top, spacing: 12) {
                icon("externaldrive.connected.to.line.below", color: vaultConfigured ? Palette.positive : Palette.warning)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vaultConfigured ? "iCloud vault aktif" : "Vault seçilmedi")
                                .font(Typography.titleSmall)
                                .foregroundStyle(Palette.textPrimary)
                            Text(BackupService.shared.vaultDisplayPath)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Text(statusMessage ?? "İlk mobil kurulumda önce aynı iCloud Drive/Hercules klasörünü seç, sonra Al ile Mac verisini çek.")
                        .font(Typography.caption)
                        .foregroundStyle((statusMessage ?? "").hasPrefix("Hata") ? Palette.negative : Palette.textSecondary)

                    HStack(spacing: 8) {
                        Button {
                            showVaultImporter = true
                        } label: {
                            Label(vaultConfigured ? "Değiştir" : "Klasör", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            showRestoreConfirm = true
                        } label: {
                            Label("Al", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!BackupService.shared.vaultBackupExists || isWorking)

                        Button {
                            exportVault()
                        } label: {
                            Label("Yaz", systemImage: "arrow.up.doc")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!vaultConfigured || isWorking)
                    }
                    .font(Typography.captionBold)
                }
            }
        }
        .id(refreshTick)
    }

    private var dataPanel: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Veri sayımı")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metric("Profil", value: profiles.first?.name.isEmpty == false ? "1" : "0", unit: "")
                    metric("Ölçüm", value: "\(measurements.count)", unit: "")
                    metric("Yemek", value: "\(foods.count)", unit: "")
                    metric("Tarif", value: "\(recipes.count)", unit: "")
                    metric("Antrenman", value: "\(activeWorkouts.count)", unit: "")
                    metric("Adım günü", value: "\(steps.count)", unit: "")
                    metric("Arşiv", value: "\(archives.count)", unit: "")
                }
            }
        }
    }

    private var measurementForm: some View {
        NavigationStack {
            Form {
                Section("Mod") {
                    Toggle("Tam ölçüm", isOn: $measurementFullCheckIn)
                    Text(measurementFullCheckIn ? "Kilo + yağ + bel + göğüs + boyun. Cumartesi ana takip kaydı." : "Günlük hızlı tartı. Sadece kilo girmen yeterli.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }

                Section("Tartı") {
                    TextField("Kilo", text: $measurementWeight)
                        .keyboardType(.decimalPad)
                }

                if measurementFullCheckIn {
                    Section("Tam ölçüm") {
                        TextField("Yağ %", text: $measurementBodyFat)
                            .keyboardType(.decimalPad)
                        TextField("Bel", text: $measurementWaist)
                            .keyboardType(.decimalPad)
                        TextField("Göğüs", text: $measurementChest)
                            .keyboardType(.decimalPad)
                        TextField("Boyun", text: $measurementNeck)
                            .keyboardType(.decimalPad)
                        Link(destination: URL(string: "https://www.agirsaglam.com/vucut-yag-orani-hesaplama/")!) {
                            Label("Yağ oranı hesapla", systemImage: "arrow.up.right")
                        }
                    }
                }
            }
            .navigationTitle(measurementFullCheckIn ? "Tam Ölçüm" : "Tartı Ekle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { showAddMeasurement = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { addMeasurement() }
                        .disabled(!measurementFormHasValue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var measurementFormHasValue: Bool {
        number(measurementWeight) != nil
            || (measurementFullCheckIn && (
                number(measurementBodyFat) != nil
                    || number(measurementWaist) != nil
                    || number(measurementChest) != nil
                    || number(measurementNeck) != nil
            ))
    }

    private func sectionHeader(_ title: String, action: String, systemImage: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Button(action: perform) {
                Label(action, systemImage: systemImage)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func summaryStrip(_ items: [(String, String)]) -> some View {
        MobileCard {
            HStack(spacing: 10) {
                ForEach(items, id: \.0) { item in
                    metric(item.0, value: item.1, unit: "")
                }
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
                Label("+ \(preset.servingCountText(preset.defaultServings))", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surfaceElevated))
    }

    private func mobileSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.label)
            .foregroundStyle(Palette.textQuaternary)
            .textCase(.uppercase)
            .padding(.top, 4)
            .padding(.leading, 2)
    }

    /// Loglanmış bir antrenman seansı: tarih + hareketler + set özetleri (3×10 @ 80 kg).
    private func workoutLogContent(_ log: WorkoutLog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.name.isEmpty ? "Antrenman" : log.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(Fmt.date.string(from: log.date)) · \(log.durationMinutes) dk")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                Text("\(log.exercises.count) hareket")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Palette.accent.opacity(0.14)))
            }
            if !log.exercises.isEmpty {
                Rectangle().fill(Palette.border).frame(height: 0.5)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(log.exercises.sorted(by: { $0.order < $1.order }), id: \.persistentModelID) { ex in
                        HStack(alignment: .top, spacing: 10) {
                            Text(ex.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(ex.summary)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Palette.textTertiary)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let notes = log.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func workoutContent(_ workout: WorkoutSession, compact: Bool) -> some View {
        let visibleExercises = Array(workout.sortedTemplateExercises.prefix(compact ? 5 : 50).enumerated())

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.weekdayName)
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.accent)
                    Text(workout.name)
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text("\(workout.durationMinutes) dk")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textTertiary)
                if !compact {
                    Button {
                        workoutToDelete = workout
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.leading, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Antrenman gününü sil")
                }
            }

            if let focus = workout.focus, !focus.isEmpty {
                Text(focus)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            ForEach(visibleExercises, id: \.element.persistentModelID) { index, exercise in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(index + 1).")
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textQuaternary)
                        .frame(width: 26, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(exercise.name)
                                .font(Typography.bodyBold)
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            exerciseLink(exercise.sourceURL)
                        }
                        Text(exercise.prescriptionText)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !compact, let notes = exercise.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                            Text(notes)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textQuaternary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if compact && workout.sortedTemplateExercises.count > 5 {
                Text("+\(workout.sortedTemplateExercises.count - 5) hareket daha")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.positive)
            }

            if !compact {
                if let warmup = workout.warmup?.trimmingCharacters(in: .whitespacesAndNewlines), !warmup.isEmpty {
                    detailNote(title: "Isınma", text: warmup)
                }
                if let progression = workout.progression?.trimmingCharacters(in: .whitespacesAndNewlines), !progression.isEmpty {
                    detailNote(title: "Progression", text: progression)
                }
                if let notes = workout.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    detailNote(title: "Not", text: notes)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseLink(_ rawURL: String?) -> some View {
        if let url = normalizedURL(rawURL) {
            Link(destination: url) {
                Label("Teknik", systemImage: "link")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.surfaceElevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hareket linkini aç")
        }
    }

    private func detailNote(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Typography.label)
                .foregroundStyle(Palette.textQuaternary)
                .textCase(.uppercase)
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    /// Yemek satırı — sola kaydırınca Sil çıkar, basınca "emin misin" alert'i açılır.
    private func foodRow(_ food: FoodEntry) -> some View {
        MobileSwipeToDelete(onDelete: { foodToDelete = food }) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(food.grams.map { "\(Fmt.num($0, digits: 0)) g" } ?? food.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Text("\(Fmt.int(food.calories)) kcal")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
        }
    }

    private func measurementRow(_ measurement: Measurement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(measurement.date, style: .date)
                            .font(Typography.bodyBold)
                            .foregroundStyle(Palette.textPrimary)
                        Text(measurement.isFullCheckIn ? "Tam" : "Tartı")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(measurement.isFullCheckIn ? Palette.accent : Palette.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill((measurement.isFullCheckIn ? Palette.accent : Color.white).opacity(0.12)))
                    }
                    Text(measurement.date, style: .time)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Text(measurement.weight.map { "\(Fmt.num($0, digits: 1)) kg" } ?? "-")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
                Button {
                    measurementToDelete = measurement
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.leading, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ölçümü sil")
            }

            if measurement.isFullCheckIn {
                Text([
                    measurement.bodyFat.map { "Yağ \(Fmt.num($0, digits: 1))%" },
                    measurement.waist.map { "Bel \(Fmt.num($0, digits: 1)) cm" },
                    measurement.chest.map { "Göğüs \(Fmt.num($0, digits: 1)) cm" },
                    measurement.neck.map { "Boyun \(Fmt.num($0, digits: 1)) cm" }
                ].compactMap { $0 }.joined(separator: " · "))
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(2)
            }
        }
        .padding(.vertical, 5)
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
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
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

    private var vaultConfigured: Bool {
        _ = refreshTick
        return BackupService.shared.vaultIsConfigured
    }

    private var todayFoods: [FoodEntry] {
        let calendar = Calendar.current
        return foods.filter { calendar.isDateInToday($0.date) }
    }

    private var todayCalories: Double {
        todayFoods.reduce(0) { $0 + $1.calories }
    }

    private var todayProtein: Double {
        todayFoods.reduce(0) { $0 + ($1.protein ?? 0) }
    }

    private var todayCarbs: Double {
        todayFoods.reduce(0) { $0 + ($1.carbs ?? 0) }
    }

    private var todayFat: Double {
        todayFoods.reduce(0) { $0 + ($1.fat ?? 0) }
    }

    private var weightTrendPoints: [MobileChartPoint] {
        Array(measurements.prefix(30)).reversed().compactMap { m in
            m.weight.map { MobileChartPoint(date: m.date, value: $0) }
        }
    }

    private var calorieTrendPoints: [MobileChartPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var byDay: [Date: Double] = [:]
        for f in foods {
            byDay[cal.startOfDay(for: f.date), default: 0] += f.calories
        }
        return (0..<14).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return MobileChartPoint(date: d, value: byDay[d] ?? 0)
        }
    }

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
        let calendar = Calendar.current
        return steps.first(where: { calendar.isDateInToday($0.date) })?.steps ?? 0
    }

    private var activeWorkouts: [WorkoutSession] {
        workouts
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.weekday < $1.weekday }
    }

    private var presetItems: [MobilePresetItem] {
        presets.map { MobilePresetItem(id: $0.presetID, preset: $0) }
    }

    private var nextWorkout: WorkoutSession? {
        let weekday = Calendar.current.component(.weekday, from: .now)
        return activeWorkouts.first(where: { $0.weekday >= weekday }) ?? activeWorkouts.first
    }

    private func handleVaultImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            withVaultAccess(url) {
                do {
                    isWorking = true
                    _ = try BackupService.shared.configureVaultRoot(url, from: ctx)
                    statusMessage = BackupService.shared.vaultBackupExists
                        ? "Klasör seçildi. Vault bulundu; şimdi Al ile veriyi çek."
                        : "Klasör seçildi. Henüz snapshot yok."
                    showRestoreConfirm = BackupService.shared.vaultBackupExists
                } catch {
                    statusMessage = "Hata: \(error.localizedDescription)"
                }
                isWorking = false
                refreshTick = UUID()
            }
        case .failure(let error):
            statusMessage = "Hata: \(error.localizedDescription)"
        }
    }

    private func exportVault() {
        guard vaultConfigured else { return }
        do {
            isWorking = true
            let summary = try BackupService.shared.exportToVault(from: ctx)
            statusMessage = summary.didWriteConflictCopy
                ? "Vault yazıldı; çakışan eski snapshot conflicts içine alındı."
                : "Vault yazıldı."
        } catch {
            statusMessage = "Hata: \(error.localizedDescription)"
        }
        isWorking = false
        refreshTick = UUID()
    }

    private func restoreVault() {
        do {
            isWorking = true
            try BackupService.shared.restoreFromVault(into: ctx)
            FoodPresetSeed.upsertDefaults(ctx)
            statusMessage = "Vault içeri alındı."
        } catch {
            statusMessage = "Hata: \(error.localizedDescription)"
        }
        isWorking = false
        refreshTick = UUID()
    }

    private func restoreIfNewer() {
        guard vaultConfigured else { return }
        // Bloklamayan + throttle'lı oto-senkron (pull-merge + push). Ağır iCloud okuması
        // arka planda; UI ilk kareyi anında çizer. Merge ezmez, katar.
        Task { @MainActor in
            isWorking = true
            await BackupService.shared.autoSyncWithVault(into: ctx)
            FoodPresetSeed.upsertDefaults(ctx)
            isWorking = false
            refreshTick = UUID()
        }
    }

    private func addPreset(_ preset: FoodPreset, servings: Double) {
        ctx.insert(preset.makeFoodEntry(servings: servings))
        ctx.saveOrReport()
        BackupService.shared.exportAsync(from: ctx)
        scheduleVaultPush()
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
        BackupService.shared.exportAsync(from: ctx)
        scheduleVaultPush()
        refreshTick = UUID()
    }

    private func deleteRecipe(_ recipe: Recipe) {
        ctx.delete(recipe)
        ctx.saveOrReport()
        BackupService.shared.exportAsync(from: ctx)
        scheduleVaultPush()
        refreshTick = UUID()
    }

    /// Yemek kaydını sil. Silme bir sonraki sync'te tombstone üretir → diğer cihazdan
    /// da silinir, geri dirilmez (bkz. merge sync).
    private func deleteFood(_ food: FoodEntry) {
        ctx.delete(food)
        ctx.saveOrReport()
        BackupService.shared.exportAsync(from: ctx)
        scheduleVaultPush()
        refreshTick = UUID()
    }

    private func deleteMeasurement(_ m: Measurement) {
        ctx.delete(m)
        ctx.saveOrReport()
        BackupService.shared.exportAsync(from: ctx)
        scheduleVaultPush()
        refreshTick = UUID()
    }

    /// Antrenman programı gününü sil (hareketler cascade ile gider).
    private func deleteWorkout(_ w: WorkoutSession) {
        ctx.delete(w)
        ctx.saveOrReport()
        BackupService.shared.exportAsync(from: ctx)
        scheduleVaultPush()
        refreshTick = UUID()
    }

    /// Veri değişince ~1.5 sn sonra vault'a push et (ardışık değişiklikleri birleştirir).
    /// Foreground'da çalışır → uygulamayı force-quit etsen bile değişiklik zaten gitmiştir.
    private func scheduleVaultPush() {
        guard vaultConfigured else { return }
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await BackupService.shared.syncWithVaultNonBlocking(into: ctx)
        }
    }

    @MainActor
    private func estimateFoodWithAI() async {
        let raw = aiFoodInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isEstimatingFood else { return }

        aiFoodResult = nil
        aiFoodError = nil
        aiFoodStatus = "AI yemeği hesaplıyor..."
        isEstimatingFood = true
        defer { isEstimatingFood = false }

        let prompt = """
        MOBIL YEMEK HESAPLAMA KARTI:
        Aşağıdaki metni tek bir yemek kaydı olarak hesapla.
        Sadece YEMEK MODU top-level JSON dön: name, grams, calories, protein_g, carbs_g, fat_g, message.
        actions üretme; kaydı kullanıcı mobil UI'daki "Bugüne ekle" butonuyla yapacak.
        Eğer birden fazla yiyecek varsa aynı kayıtta toplamla.

        Kullanıcı metni: \(raw)
        """

        do {
            let (result, searchQuery) = try await AIKeyStore.shared.makeClient().send(
                history: [],
                newUserText: prompt,
                userContext: mobileFoodAIContext,
                onSearchStart: { query in
                    aiFoodStatus = "Aranıyor: \(query)"
                },
                onMessageUpdate: { _ in }
            )

            if let normalized = normalizedFoodResult(from: result) {
                aiFoodResult = normalized
                aiFoodStatus = searchQuery.map { "Arama ile güncellendi: \($0)" } ?? "Tahmin hazır."
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
        BackupService.shared.exportAsync(from: ctx)
        scheduleVaultPush()
        aiFoodInput = ""
        aiFoodResult = nil
        aiFoodError = nil
        aiFoodStatus = "Bugüne eklendi."
        // Bugün sekmesinin + sheet'inden eklendiyse kapat; inline kartta no-op.
        showFoodAIEstimator = false
    }

    private func mobileAIErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("auth dosyası")
            || message.localizedCaseInsensitiveContains("token")
            || message.localizedCaseInsensitiveContains("account ID") {
            return "AI login telefonda yok. Mac'te Profil > Vault'a Yaz, telefonda Sync > Al yapıp tekrar dene."
        }
        return "AI hata: \(message)"
    }

    private func seedMeasurementForm(forceFull: Bool = false) {
        let shouldOpenFull = forceFull || MeasurementCadence.isFullCheckInDay()
        let latestFull = measurements.first(where: \.isFullCheckIn)

        measurementWeight = measurements.first?.weight.map { Fmt.num($0, digits: 1) } ?? ""
        measurementFullCheckIn = shouldOpenFull
        measurementBodyFat = shouldOpenFull ? (latestFull?.bodyFat.map { Fmt.num($0, digits: 1) } ?? "") : ""
        measurementWaist = shouldOpenFull ? (latestFull?.waist.map { Fmt.num($0, digits: 1) } ?? "") : ""
        measurementChest = shouldOpenFull ? (latestFull?.chest.map { Fmt.num($0, digits: 1) } ?? "") : ""
        measurementNeck = shouldOpenFull ? (latestFull?.neck.map { Fmt.num($0, digits: 1) } ?? "") : ""
    }

    private func addMeasurement() {
        ctx.insert(Measurement(
            date: .now,
            weight: number(measurementWeight),
            bodyFat: measurementFullCheckIn ? number(measurementBodyFat) : nil,
            waist: measurementFullCheckIn ? number(measurementWaist) : nil,
            chest: measurementFullCheckIn ? number(measurementChest) : nil,
            neck: measurementFullCheckIn ? number(measurementNeck) : nil,
            note: measurementFullCheckIn ? "Haftalık tam ölçüm" : nil
        ))
        ctx.saveOrReport()
        BackupService.shared.exportAsync(from: ctx)
        scheduleVaultPush()
        showAddMeasurement = false
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

    private func withVaultAccess(_ url: URL, perform: () -> Void) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        perform()
    }
}

/// Mobil profil editörü — kişisel bilgi, hedef, manuel makro ve supplement.
/// Sayı alanları string ayna ile tutulur (opsiyonel Double bağlama kolaylığı için).
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
                heightStr = profile.height > 0 ? Fmt.num(profile.height, digits: 0) : ""
                targetStr = profile.targetWeight.map { Fmt.num($0, digits: 1) } ?? ""
                bodyFatStr = profile.manualBodyFat.map { Fmt.num($0, digits: 1) } ?? ""
                proteinStr = profile.manualProteinGrams.map { Fmt.num($0, digits: 0) } ?? ""
                carbsStr = profile.manualCarbsGrams.map { Fmt.num($0, digits: 0) } ?? ""
                fatStr = profile.manualFatGrams.map { Fmt.num($0, digits: 0) } ?? ""
            }
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
                        ForEach(RecipeCategory.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
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
        calories = r.calories.map { Fmt.num($0, digits: 0) } ?? ""
        protein = r.protein.map { Fmt.num($0, digits: 0) } ?? ""
        carbs = r.carbs.map { Fmt.num($0, digits: 0) } ?? ""
        fat = r.fat.map { Fmt.num($0, digits: 0) } ?? ""
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
                            Label("Kaynağı aç", systemImage: "arrow.up.right.square")
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
                        Label("Düzenle", systemImage: "pencil")
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
        .preferredColorScheme(.dark)
    }

    private var hasMacros: Bool {
        recipe.calories != nil || recipe.protein != nil || recipe.carbs != nil || recipe.fat != nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: recipe.category.icon)
                    .font(.system(size: 16, weight: .semibold))
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
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .semibold))
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
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
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

struct MobileChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Swift Charts tabanlı trend grafiği (çizgi+alan ya da bar) + opsiyonel hedef çizgisi.
struct MobileTrendChart: View {
    let points: [MobileChartPoint]
    var tint: Color = Palette.accent
    var target: Double? = nil
    var bars: Bool = false

    var body: some View {
        Chart {
            ForEach(points) { p in
                if bars {
                    BarMark(
                        x: .value("Gün", p.date, unit: .day),
                        y: .value("Değer", p.value)
                    )
                    .foregroundStyle(tint.gradient)
                    .cornerRadius(3)
                } else {
                    AreaMark(
                        x: .value("Tarih", p.date),
                        y: .value("Değer", p.value)
                    )
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Tarih", p.date),
                        y: .value("Değer", p.value)
                    )
                    .foregroundStyle(tint)
                    .interpolationMethod(.catmullRom)
                }
            }
            if let target {
                RuleMark(y: .value("Hedef", target))
                    .foregroundStyle(Palette.warning.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Palette.border)
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 150)
    }
}
