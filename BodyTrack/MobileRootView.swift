import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MobileRootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \UserProfile.name) private var profiles: [UserProfile]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \StepEntry.date, order: .reverse) private var steps: [StepEntry]
    @Query(sort: \WorkoutSession.weekday) private var workouts: [WorkoutSession]
    @Query(sort: \WorkoutProgramArchive.archivedAt, order: .reverse) private var archives: [WorkoutProgramArchive]
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \FoodPreset.sortOrder) private var presets: [FoodPreset]

    @State private var selectedTab: MobileTab = .dashboard
    @State private var showVaultImporter = false
    @State private var showRestoreConfirm = false
    @State private var showAddFood = false
    @State private var showAddMeasurement = false
    @State private var statusMessage: String? = nil
    @State private var isWorking = false
    @State private var refreshTick = UUID()

    @State private var foodName = ""
    @State private var foodGrams = ""
    @State private var foodCalories = ""
    @State private var foodProtein = ""
    @State private var foodCarbs = ""
    @State private var foodFat = ""
    @State private var aiFoodInput = ""
    @State private var aiFoodResult: AIFoodResult?
    @State private var aiFoodStatus: String?
    @State private var aiFoodError: String?
    @State private var isEstimatingFood = false

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
                .safeAreaInset(edge: .top, spacing: 0) {
                    mobileHeader
                }

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
        .sheet(isPresented: $showAddFood) {
            foodForm
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddMeasurement) {
            measurementForm
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            restoreIfNewer()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                restoreIfNewer()
            } else if newPhase == .background {
                BackupService.shared.exportAsync(from: ctx)
            }
        }
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selectedTab {
        case .dashboard:
            mobilePage { dashboardPage }
        case .nutrition:
            mobilePage { nutritionPage }
        case .workout:
            mobilePage { workoutPage }
        case .measurements:
            mobilePage { measurementsPage }
        case .sync:
            mobilePage { syncPage }
        }
    }

    private var mobileHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab.eyebrow)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textQuaternary)
                    .textCase(.uppercase)
                Text(selectedTab.title)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                restoreIfNewer()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 0.5)
            )
            .disabled(isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(Palette.background.opacity(0.96))
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
            sectionHeader("Yemek", action: "Ekle", systemImage: "plus") {
                showAddFood = true
            }
            foodAIEstimatorCard
            foodQuickAddCard
            todayFoodCard
            recipeCard
            recentFoodsCard
        }
    }

    private var workoutPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryStrip([
                ("Gün", "\(activeWorkouts.count)"),
                ("Hareket", "\(activeWorkouts.reduce(0) { $0 + $1.sortedTemplateExercises.count })"),
                ("Arşiv", "\(archives.count)")
            ])
            ForEach(activeWorkouts, id: \.persistentModelID) { workout in
                MobileCard {
                    workoutContent(workout, compact: false)
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
            latestMeasurementCard
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

    private var syncPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            syncPanel
            dataPanel
        }
    }

    private var heroCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
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
                HStack(spacing: 10) {
                    metric("Kalori", value: Fmt.int(todayCalories), unit: "kcal")
                    metric("Protein", value: Fmt.int(todayProtein), unit: "g")
                    metric("Adım", value: Fmt.int(Double(todaySteps)), unit: "")
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
                            showAddFood = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.textPrimary)
                        .background(Circle().fill(Palette.surfaceElevated))
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

    private var foodQuickAddCard: some View {
        MobileCard {
            HStack(alignment: .center, spacing: 12) {
                icon("plus.circle.fill", color: Palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Yemek ekle")
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Kalori, gram ve makroları hızlıca bugüne kaydet.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 8)
                Button {
                    showAddFood = true
                } label: {
                    Text("Ekle")
                        .font(Typography.captionBold)
                        .frame(minWidth: 58)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var foodAIEstimatorCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    icon("sparkles", color: Palette.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI ile hesapla")
                            .font(Typography.titleSmall)
                            .foregroundStyle(Palette.textPrimary)
                        Text("Yemeği doğal yaz, kcal ve makroyu tahmin edip bugüne ekle.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if isEstimatingFood {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                TextField("örn: 160g pişmiş pirinç + 500g haşlanmış tavuk göğsü", text: $aiFoodInput, axis: .vertical)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceElevated))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(Palette.borderStrong, lineWidth: 0.5)
                    )

                HStack(spacing: 8) {
                    Button {
                        Task { await estimateFoodWithAI() }
                    } label: {
                        Label(isEstimatingFood ? "Hesaplanıyor" : "Hesapla", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(aiFoodInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEstimatingFood)

                    Button {
                        showAddFood = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Manuel yemek ekle")
                }
                .font(Typography.captionBold)

                if let result = aiFoodResult {
                    aiFoodResultCard(result)
                }

                if let aiFoodStatus {
                    Text(aiFoodStatus)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let aiFoodError {
                    Text(aiFoodError)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func aiFoodResultCard(_ result: AIFoodResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.name?.nilIfBlank ?? "AI yemek tahmini")
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(result.message.nilIfBlank ?? "Tahmini değerler hazır.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Fmt.int(result.calories ?? 0))")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
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
            }

            Button {
                addAIFoodResult(result)
            } label: {
                Label("Bugüne ekle", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled((result.calories ?? 0) <= 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceElevated))
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

    private var recipeCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tarifler")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                if recipes.isEmpty {
                    emptyText("Tarif kaydı yok.")
                } else {
                    ForEach(recipes.prefix(8), id: \.persistentModelID) { recipe in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.title)
                                .font(Typography.bodyBold)
                                .foregroundStyle(Palette.textPrimary)
                            Text(recipe.summary ?? recipe.category.rawValue)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var recentFoodsCard: some View {
        MobileCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Son yemek kayıtları")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                if foods.isEmpty {
                    emptyText("Yemek kaydı yok.")
                } else {
                    ForEach(foods.prefix(12), id: \.persistentModelID) { food in
                        foodRow(food)
                    }
                }
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

    private var foodForm: some View {
        NavigationStack {
            Form {
                TextField("Yemek", text: $foodName)
                TextField("Gram", text: $foodGrams)
                    .keyboardType(.decimalPad)
                TextField("Kalori", text: $foodCalories)
                    .keyboardType(.decimalPad)
                TextField("Protein", text: $foodProtein)
                    .keyboardType(.decimalPad)
                TextField("Karbonhidrat", text: $foodCarbs)
                    .keyboardType(.decimalPad)
                TextField("Yağ", text: $foodFat)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("Yemek Ekle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { showAddFood = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { addManualFood() }
                        .disabled(foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
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

    private func foodRow(_ food: FoodEntry) -> some View {
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
        .padding(.vertical, 3)
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
        isWorking = true
        BackupService.shared.restoreFromVaultIfNewer(into: ctx)
        FoodPresetSeed.upsertDefaults(ctx)
        isWorking = false
        refreshTick = UUID()
    }

    private func addPreset(_ preset: FoodPreset, servings: Double) {
        ctx.insert(preset.makeFoodEntry(servings: servings))
        try? ctx.save()
        BackupService.shared.exportAsync(from: ctx)
    }

    private func addManualFood() {
        let entry = FoodEntry(
            date: .now,
            name: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
            grams: number(foodGrams),
            calories: number(foodCalories) ?? 0,
            protein: number(foodProtein),
            carbs: number(foodCarbs),
            fat: number(foodFat)
        )
        ctx.insert(entry)
        try? ctx.save()
        BackupService.shared.exportAsync(from: ctx)
        foodName = ""
        foodGrams = ""
        foodCalories = ""
        foodProtein = ""
        foodCarbs = ""
        foodFat = ""
        showAddFood = false
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
        try? ctx.save()
        BackupService.shared.exportAsync(from: ctx)
        aiFoodInput = ""
        aiFoodResult = nil
        aiFoodError = nil
        aiFoodStatus = "Bugüne eklendi."
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
        try? ctx.save()
        BackupService.shared.exportAsync(from: ctx)
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
