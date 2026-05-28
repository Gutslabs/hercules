import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ProfileView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [UserProfile]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]

    @State private var name: String = ""
    @State private var sex: Sex = .male
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now
    @State private var height: Double = 178
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: Goal = .maintain
    @State private var targetWeight: Double? = nil
    @State private var manualBodyFat: Double? = nil
    @State private var about: String = ""
    @State private var supplements: String = UserProfile.defaultSupplements
    @State private var manualCalorieOffset: Double = 0
    @State private var manualCalorieOffsetMacro: CalorieOffsetMacro = .carbs
    @State private var manualProteinGrams: Double? = nil
    @State private var manualCarbsGrams: Double? = nil
    @State private var manualFatGrams: Double? = nil

    @State private var saved = false
    @State private var hasInitialized = false
    @State private var autosaveTask: Task<Void, Never>? = nil
    @State private var revealContent = false

    private var latest: Measurement? { measurements.first }
    private var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
    }

    /// Yağ oranı: önce son ölçüm, sonra manuel değer.
    private var displayedBodyFat: Double? {
        latest?.bodyFat ?? manualBodyFat
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 980
            let horizontalPadding = compact ? Spacing.xl : Spacing.xxl
            let availableWidth = max(0, proxy.size.width - (horizontalPadding * 2))

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? Spacing.xl : Spacing.xxl) {
                    profileActions(compact: compact)
                        .profileReveal(revealContent, delay: 0.02)
                    profileMosaic(compact: compact, availableWidth: availableWidth)
                        .profileReveal(revealContent, delay: 0.08)
                    integrationsSection(compact: compact)
                        .profileReveal(revealContent, delay: 0.14)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, compact ? Spacing.xl : Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(profileBackground)
        .onAppear {
            initializeFromProfile()
            revealContent = true
        }
        .onChange(of: about) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: supplements) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: manualCalorieOffset) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: manualCalorieOffsetMacro) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: manualProteinGrams) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: manualCarbsGrams) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: manualFatGrams) { _, _ in
            scheduleAutosave()
        }
        .onDisappear {
            autosaveTask?.cancel()
            save()
        }
    }

    private var profileBackground: some View {
        ZStack(alignment: .topLeading) {
            Palette.background.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Palette.surfaceElevated.opacity(0.48),
                    Palette.background.opacity(0.0)
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
            ProfileBackgroundLines()
                .stroke(Palette.borderStrong.opacity(0.42), lineWidth: 0.6)
                .frame(width: 620, height: 340)
                .offset(x: -92, y: -48)
                .allowsHitTesting(false)
        }
    }

    private func profileActions(compact: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.md) {
                profileTitleBlock
                Spacer(minLength: Spacing.lg)
                saveButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: Spacing.md) {
                profileTitleBlock
                saveButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileTitleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                ProfileBreathingStatusDot(color: calorieResult == nil ? Palette.warning : Palette.positive)
                Text(calorieResult == nil ? "Profil kurulumu bekliyor" : "Profil canlı")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
            }
            Text("Profil")
                .font(Typography.display(44))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text("Kimlik, hedef ve AI hafızası tek yerde; bu sayfa günlük planın kaynak ayarı gibi çalışır.")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            HStack(spacing: 8) {
                Image(systemName: saved ? "checkmark.circle.fill" : "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolEffect(.bounce, value: saved)
                Text(saved ? "Kaydedildi" : "Kaydet")
                    .font(Typography.bodyBold)
            }
            .foregroundStyle(saved ? Palette.positive : Palette.background)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(saved ? Palette.positive.opacity(0.14) : Palette.accent)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(saved ? Palette.positive.opacity(0.5) : Color.white.opacity(0.10), lineWidth: 0.6)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(ProfilePressButtonStyle())
        .keyboardShortcut("s", modifiers: .command)
        .help("Profili kaydet (⌘S)")
    }

    @ViewBuilder
    private func profileMosaic(compact: Bool, availableWidth: CGFloat) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: Spacing.md) {
                hero
                identityCard
                activityGoalCards
                aboutCard
                supplementsCard
                calorieGoalCard
                HealthKitCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let sideWidth = min(max(availableWidth * 0.30, 360), 520)
            let planWidth = min(max(availableWidth * 0.36, 500), 680)

            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    hero
                        .frame(maxWidth: .infinity, minHeight: 330)
                        .layoutPriority(1)
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        identityCard
                        activityGoalCards
                    }
                    .frame(width: sideWidth)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        aboutCard
                        supplementsCard
                        HealthKitCard()
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    calorieGoalCard
                        .frame(width: planWidth)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func integrationsSection(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: Spacing.md) {
                AIProviderCard()
                BackupCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 420), spacing: Spacing.md, alignment: .top)],
                alignment: .leading,
                spacing: Spacing.md
            ) {
                AIProviderCard()
                BackupCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kimlik").eyebrow()
                    Text("Temel veriler")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text("\(ageYears) yaş")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 142), spacing: Spacing.md, alignment: .top)],
                alignment: .leading,
                spacing: Spacing.md
            ) {
                inputTile(label: "Doğum", icon: "calendar") {
                    DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .controlSize(.small)
                        .colorScheme(.dark)
                }
                inputTile(label: "Boy", icon: "ruler") {
                    NumberField(value: .init(get: { height }, set: { height = $0 ?? 178 }), unit: "cm", digits: 0)
                }
                inputTile(label: "Hedef", icon: "target") {
                    NumberField(value: $targetWeight, unit: "kg", digits: 0, placeholder: "opsiyonel")
                }
                inputTile(label: "Yağ", icon: "drop") {
                    NumberField(
                        value: $manualBodyFat,
                        unit: "%",
                        digits: 1,
                        placeholder: latest?.bodyFat.map { "ölçüm \(Fmt.num($0, digits: 1))" } ?? "opsiyonel"
                    )
                }
            }

            if latest == nil && targetWeight == nil {
                ProfileNudgeRow(
                    icon: "scalemass",
                    title: "Kalori hesabı için ağırlık gerekli",
                    detail: "Ölçüm ekle veya hedef ağırlık alanını doldur."
                )
            }
        }
        .padding(Spacing.lg)
        .profilePanel(cornerRadius: Radius.xl, fill: Palette.surface)
    }

    private var activityGoalCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ActivityPicker(selection: $activity)
                GoalPicker(selection: $goal)
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                ActivityPicker(selection: $activity)
                GoalPicker(selection: $goal)
            }
        }
    }

    /// Hakkında — kullanıcının kendi geçmişini özetlediği, AI'ya her sohbette
    /// kalıcı context olarak verilen serbest metin.
    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Profilim").eyebrow()
                    Text("Hakkımda")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: about.isEmpty ? "text.badge.plus" : "checkmark.seal")
                        .font(.system(size: 10, weight: .semibold))
                    Text(aboutCharCount)
                        .font(Typography.captionBold)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(about.isEmpty ? Palette.textTertiary : Palette.positive)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill((about.isEmpty ? Palette.textSecondary : Palette.positive).opacity(0.10))
                )
            }

            Text("Geçmiş, sakatlık, rutin, beslenme tercihi ve hedeflerini yaz. @Ölçümler, @Antrenman veya @Beslenme etiketleriyle sohbet bağlamını genişletebilirsin.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $about)
                .scrollContentBackground(.hidden)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .frame(minHeight: 178)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.surfaceElevated.opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    if about.isEmpty {
                        Text("ör: 28 yaşındayım, masa başı çalışıyorum, diz hassasiyetim var. Haftada 4 gün ağırlık antrenmanı yapıyorum; hedefim kas kaybetmeden yağ oranını düşürmek.")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textQuaternary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: Spacing.sm) {
                contextChip("@Ölçümler")
                contextChip("@Antrenman")
                contextChip("@Beslenme")
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.lg)
        .profilePanel(cornerRadius: Radius.xl, fill: Palette.surface)
    }

    /// Supplements — kullanıcının düzenli aldığı destekler, AI'ya kalıcı
    /// context olarak verilen ayrı profil bilgisi.
    private var supplementsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Supplements").eyebrow()
                    Text("Kullandıklarım")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: supplementItems.isEmpty ? "pills" : "pills.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(supplementStatus)
                        .font(Typography.captionBold)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(supplementItems.isEmpty ? Palette.textTertiary : Palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill((supplementItems.isEmpty ? Palette.textSecondary : Palette.accent).opacity(0.10))
                )
            }

            if !supplementItems.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: 7, alignment: .leading)],
                    alignment: .leading,
                    spacing: 7
                ) {
                    ForEach(Array(supplementItems.enumerated()), id: \.offset) { _, item in
                        supplementChip(item)
                    }
                }
            }

            TextEditor(text: $supplements)
                .scrollContentBackground(.hidden)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .frame(minHeight: 118)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.surfaceElevated.opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    if supplements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Kreatin\nProtein tozu")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textQuaternary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: Spacing.sm) {
                Button {
                    supplements = UserProfile.defaultSupplements
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("Kreatin + protein tozu")
                            .font(Typography.captionBold)
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help("Varsayılan supplement listesini doldur")
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.lg)
        .profilePanel(cornerRadius: Radius.xl, fill: Palette.surface)
    }

    private var supplementItems: [String] {
        supplements
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var supplementStatus: String {
        let count = supplementItems.count
        if count == 0 { return "boş" }
        return "\(count) kayıt"
    }

    private func supplementChip(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(Typography.captionBold)
                .lineLimit(1)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.accent.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Palette.accent.opacity(0.28), lineWidth: 0.5)
        )
    }

    private var aboutCharCount: String {
        let chars = about.count
        if chars == 0 { return "boş" }
        return "\(chars) karakter"
    }

    private func contextChip(_ text: String) -> some View {
        Text(text)
            .font(Typography.captionBold)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
    }

    // MARK: - Calorie goal card (eski Kalori sayfasından merge)

    /// Profil + son ölçüm + manuel offset'ten CalorieCalculator ile günlük hedef.
    private var calorieResult: CalorieResult? {
        guard let weight = latest?.weight ?? targetWeight else { return nil }
        let bf = latest?.bodyFat ?? manualBodyFat
        let ageInt = Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 28
        return CalorieCalculator.compute(
            weight: weight,
            height: height,
            age: ageInt,
            sex: sex,
            bodyFat: bf,
            activity: activity,
            goal: goal,
            manualOffset: manualCalorieOffset,
            manualOffsetMacro: manualCalorieOffsetMacro,
            manualProteinGrams: manualProteinGrams,
            manualCarbsGrams: manualCarbsGrams,
            manualFatGrams: manualFatGrams
        )
    }

    private var calorieGoalCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Günlük Plan").eyebrow()
                    Text("Kalori ve makro hedefi")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                if let r = calorieResult {
                    Text(r.formula)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textQuaternary)
                }
            }

            if let r = calorieResult {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(Fmt.int(r.goalCalories))")
                            .font(Typography.display(52))
                            .foregroundStyle(Palette.textPrimary)
                            .contentTransition(.numericText(value: r.goalCalories))
                            .animation(.snappy, value: r.goalCalories)
                        Text("kcal/gün")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textTertiary)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104), spacing: Spacing.lg, alignment: .leading)],
                        alignment: .leading,
                        spacing: Spacing.md
                    ) {
                        breakdownStat("BMR", "\(Fmt.int(r.bmr)) kcal", tint: Palette.textSecondary)
                        breakdownStat("TDEE", "\(Fmt.int(r.tdee)) kcal", tint: Palette.textSecondary)
                        breakdownStat("Hedef adj", goalAdjString, tint: goalAdjTint)
                    }
                    .padding(.top, 2)
                }

                Hairline()

                macroTargetControls(r)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 126), spacing: Spacing.md, alignment: .leading)],
                    alignment: .leading,
                    spacing: Spacing.md
                ) {
                    extraTile(label: "Su", value: "\(Fmt.num(r.water, digits: 1)) L", icon: "drop.fill", tint: Color(red: 0.50, green: 0.74, blue: 0.92))
                    extraTile(label: "Lif", value: "\(Fmt.int(r.fiber)) g", icon: "leaf.fill", tint: Palette.macroCarbs)
                    extraTile(label: "Yağsız", value: "\(Fmt.num(r.leanMass, digits: 1)) kg", icon: "figure.strengthtraining.traditional", tint: Palette.accent)
                }
            } else {
                ProfileEmptyState(
                    icon: "flame",
                    title: "Kalori hedefi hazır değil",
                    detail: "En az bir ağırlık verisi gerekli. Ölçüm ekle veya hedef ağırlık alanını doldur."
                )
            }
        }
        .padding(Spacing.lg)
        .profilePanel(cornerRadius: Radius.xl, fill: Palette.surface)
    }

    private func breakdownStat(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow()
            Text(value)
                .font(Typography.mono)
                .foregroundStyle(tint)
        }
    }

    private func macroRow(_ r: CalorieResult) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: Spacing.md, alignment: .leading)],
            alignment: .leading,
            spacing: Spacing.md
        ) {
            macroTile(label: "Protein", grams: r.protein.grams, percent: r.protein.percent, tint: Palette.macroProtein)
            macroTile(label: "Karbonhidrat", grams: r.carbs.grams, percent: r.carbs.percent, tint: Palette.macroCarbs)
            macroTile(label: "Yağ", grams: r.fat.grams, percent: r.fat.percent, tint: Palette.macroFat)
        }
    }

    private func macroTile(label: String, grams: Double, percent: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(label).eyebrow()
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(Fmt.int(grams))")
                    .font(Typography.hero(22))
                    .foregroundStyle(Palette.textPrimary)
                Text("g")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("%\(Fmt.int(percent))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var hasManualMacroTargets: Bool {
        manualProteinGrams != nil || manualCarbsGrams != nil || manualFatGrams != nil
    }

    private func macroTargetControls(_ r: CalorieResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Makro hedefleri").eyebrow()
                    Text("Kalori hedefi bu üç makrodan hesaplanır.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                if hasManualMacroTargets {
                    Button("Otomatiğe dön") {
                        manualProteinGrams = nil
                        manualCarbsGrams = nil
                        manualFatGrams = nil
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: Spacing.md, alignment: .top)],
                alignment: .leading,
                spacing: Spacing.md
            ) {
                macroTargetStepper(
                    label: "Protein",
                    value: $manualProteinGrams,
                    automatic: r.protein.grams,
                    caloriesPerGram: 4,
                    totalCalories: r.goalCalories,
                    tint: Palette.macroProtein
                )
                macroTargetStepper(
                    label: "Karbonhidrat",
                    value: $manualCarbsGrams,
                    automatic: r.carbs.grams,
                    caloriesPerGram: 4,
                    totalCalories: r.goalCalories,
                    tint: Palette.macroCarbs
                )
                macroTargetStepper(
                    label: "Yağ",
                    value: $manualFatGrams,
                    automatic: r.fat.grams,
                    caloriesPerGram: 9,
                    totalCalories: r.goalCalories,
                    tint: Palette.macroFat
                )
            }
        }
    }

    private func macroTargetStepper(
        label: String,
        value: Binding<Double?>,
        automatic: Double,
        caloriesPerGram: Double,
        totalCalories: Double,
        tint: Color
    ) -> some View {
        let grams = max(0, value.wrappedValue ?? automatic)
        let calories = grams * caloriesPerGram
        let share = totalCalories > 0 ? min(max(calories / totalCalories, 0), 1) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(label).eyebrow()
                Spacer()
                Text("\(Fmt.int(calories)) kcal")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.055))
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: geo.size.width * share)
                }
            }
            .frame(height: 6)

            HStack(spacing: 8) {
                macroAdjustButton(systemName: "minus", disabled: grams <= 0) {
                    value.wrappedValue = max(0, round(grams) - 1)
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(Fmt.int(grams))")
                        .font(Typography.hero(24))
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText(value: grams))
                    Text("g")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity)

                macroAdjustButton(systemName: "plus", disabled: false) {
                    value.wrappedValue = round(grams) + 1
                }
            }

            Text(value.wrappedValue == nil ? "otomatikten başlat" : "%\(Fmt.int(share * 100))")
                .font(Typography.caption)
                .foregroundStyle(value.wrappedValue == nil ? Palette.textQuaternary : tint)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func macroAdjustButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(disabled ? 0.035 : 0.075))
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(disabled ? Palette.textQuaternary : Palette.textPrimary)
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func extraTile(label: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).eyebrow()
                Text(value)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var goalAdjString: String {
        let v = goal.calorieAdjustment
        if v == 0 { return "0 kcal" }
        return "\(v > 0 ? "+" : "")\(Fmt.int(v)) kcal"
    }

    private var goalAdjTint: Color {
        let v = goal.calorieAdjustment
        if v == 0 { return Palette.textSecondary }
        return v < 0 ? Palette.positive : Palette.warning
    }

    private var manualOffsetDisplay: String {
        if manualCalorieOffset == 0 { return "0 kcal" }
        return "\(manualCalorieOffset > 0 ? "+" : "")\(Fmt.int(manualCalorieOffset)) kcal"
    }

    private var manualOffsetControls: some View {
        HStack(spacing: Spacing.sm) {
            Text(manualOffsetDisplay)
                .font(Typography.mono)
                .foregroundStyle(manualOffsetTint)
                .contentTransition(.numericText(value: manualCalorieOffset))
            Stepper(
                "",
                value: $manualCalorieOffset,
                in: -500...500,
                step: 50
            )
            .labelsHidden()
            if manualCalorieOffset != 0 {
                Button("Sıfırla") { manualCalorieOffset = 0 }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
    }

    private var manualOffsetTint: Color {
        if manualCalorieOffset == 0 { return Palette.textTertiary }
        return manualCalorieOffset < 0 ? Palette.positive : Palette.warning
    }

    private var manualOffsetMacroTint: Color {
        switch manualCalorieOffsetMacro {
        case .protein: return Palette.macroProtein
        case .carbs: return Palette.macroCarbs
        case .fat: return Palette.macroFat
        }
    }

    private var manualOffsetSourceDetail: String {
        guard manualCalorieOffset != 0 else {
            return "Offset eklenirse \(manualCalorieOffsetMacro.label.lowercased()) gramı değişir."
        }
        let grams = abs(manualCalorieOffset) / manualCalorieOffsetMacro.caloriesPerGram
        let verb = manualCalorieOffset > 0 ? "eklenir" : "düşülür"
        return "\(Fmt.int(grams)) g \(manualCalorieOffsetMacro.label.lowercased()) \(verb)."
    }

    // MARK: - Hero (büyük üst kart)

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    profileIdentityBlock
                    Spacer(minLength: Spacing.xl)
                    planSummaryBlock
                }
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    profileIdentityBlock
                    planSummaryBlock
                }
            }

            Hairline()

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 148), spacing: Spacing.xl, alignment: .leading)],
                alignment: .leading,
                spacing: Spacing.lg
            ) {
                statBlock(
                    accent: Palette.accent,
                    label: "MEVCUT",
                    primary: latest?.weight.map { "\(Fmt.num($0, digits: 1)) kg" } ?? "—",
                    secondary: bodyFatLine
                )
                statBlock(
                    accent: Palette.positive,
                    label: "HEDEF",
                    primary: targetWeight.map { "\(Fmt.int($0)) kg" } ?? "—",
                    secondary: targetRemainingLine
                )
                statBlock(
                    accent: Palette.warning,
                    label: "İLERLEME",
                    primary: progressLine.value,
                    secondary: progressLine.detail
                )
            }
        }
        .padding(Spacing.xxl)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(Palette.surface.opacity(0.82))
                ProfileHeroLines()
                    .stroke(Palette.borderStrong.opacity(0.55), lineWidth: 0.7)
                    .frame(width: 300, height: 260)
                    .offset(x: 36, y: -28)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        }
        .shadow(color: Palette.accent.opacity(0.08), radius: 34, x: 0, y: 22)
    }

    private var profileIdentityBlock: some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            ProfileAvatar(initial: initial, color: Palette.accent)

            VStack(alignment: .leading, spacing: 9) {
                TextField("Adın", text: $name)
                    .textFieldStyle(.plain)
                    .font(Typography.display(38))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.sm) {
                        profileFact("Yaş", "\(ageYears)")
                        profileFact("Boy", "\(Fmt.int(height)) cm")
                        profileFact("Cinsiyet", sex.label)
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        profileFact("Yaş", "\(ageYears)")
                        profileFact("Boy", "\(Fmt.int(height)) cm")
                        profileFact("Cinsiyet", sex.label)
                    }
                }
                SexSwitch(sex: $sex)
            }
        }
    }

    private var planSummaryBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: 8) {
                ProfileBreathingStatusDot(color: calorieResult == nil ? Palette.warning : Palette.accent)
                Text(calorieResult == nil ? "Kurulum eksik" : "Plan hesaplandı")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
            }

            if let result = calorieResult {
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(Fmt.int(result.goalCalories))")
                        .font(Typography.display(42))
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText(value: result.goalCalories))
                    Text("kcal")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.bottom, 6)
                }
                Text("\(activity.label) · \(goal.detail)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Ağırlık verisi girildiğinde günlük hedef ve makrolar burada canlı hesaplanır.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 250, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func profileFact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
            Text(value)
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.first.map { String($0).uppercased() } ?? "H"
    }

    private var bodyFatLine: String {
        guard let bf = displayedBodyFat else { return "yağ ölçümü yok" }
        return "%\(Fmt.num(bf, digits: 1)) yağ"
    }

    private var targetRemainingLine: String {
        guard let t = targetWeight, let cur = latest?.weight else { return goal.label }
        let diff = cur - t
        if abs(diff) < 0.2 { return "Hedefte" }
        if diff > 0 { return "\(Fmt.num(diff, digits: 1)) kg kalan" }
        return "+\(Fmt.num(abs(diff), digits: 1)) kg geçildi"
    }

    private var progressLine: (value: String, detail: String) {
        let pts = TrendAnalysis.points(measurements, for: .weight)
        let stats = TrendAnalysis.stats(pts)
        guard let weekly = stats.weeklyChange else {
            return ("—", "veri yetersiz")
        }
        return (
            "\(Fmt.signed(weekly, digits: 2)) kg",
            "haftalık tempo"
        )
    }

    private func statBlock(accent: Color, label: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(accent).frame(width: 5, height: 5)
                Text(label).eyebrow()
            }
            Text(primary)
                .font(Typography.hero(24))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text(secondary)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
    }

    private func inputTile<C: View>(label: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text(label).eyebrow()
            }
            content()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func initializeFromProfile() {
        guard !hasInitialized else { return }
        hasInitialized = true
        guard let p = profiles.first else { return }
        name = p.name
        sex = p.sex
        birthDate = p.birthDate
        height = p.height
        activity = p.activity
        goal = p.goal
        targetWeight = p.targetWeight
        manualBodyFat = p.manualBodyFat
        about = p.about
        supplements = p.supplements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? UserProfile.defaultSupplements
            : p.supplements
        manualCalorieOffset = 0
        manualCalorieOffsetMacro = .carbs
        manualProteinGrams = p.manualProteinGrams
        manualCarbsGrams = p.manualCarbsGrams
        manualFatGrams = p.manualFatGrams
    }

    private func save() {
        let profile = profiles.first ?? {
            let p = UserProfile()
            ctx.insert(p)
            return p
        }()
        profile.name = name
        profile.sex = sex
        profile.birthDate = birthDate
        profile.height = height
        profile.activity = activity
        profile.goal = goal
        profile.targetWeight = targetWeight
        profile.manualBodyFat = manualBodyFat
        profile.about = about
        profile.supplements = supplements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? UserProfile.defaultSupplements
            : supplements
        profile.manualCalorieOffset = 0
        profile.manualCalorieOffsetMacro = .carbs
        profile.manualProteinGrams = manualProteinGrams
        profile.manualCarbsGrams = manualCarbsGrams
        profile.manualFatGrams = manualFatGrams
        try? ctx.save()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            saved = false
        }
    }

    private func scheduleAutosave() {
        guard hasInitialized else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 700_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            save()
        }
    }
}

// MARK: - Reusable

private struct ProfileAvatar: View {
    let initial: String
    let color: Color
    @State private var active = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.32), Palette.surfaceElevated],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .strokeBorder(Color.white.opacity(active ? 0.18 : 0.08), lineWidth: 0.8)
                    .scaleEffect(active ? 1.04 : 0.98)
                Text(initial)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: 74, height: 74)

            Circle()
                .fill(Palette.positive)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                .offset(x: -4, y: -4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

private struct ProfileBreathingStatusDot: View {
    let color: Color
    @State private var active = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(active ? 0.22 : 0.08))
                .frame(width: 20, height: 20)
                .scaleEffect(active ? 1.08 : 0.82)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                active = true
            }
        }
    }
}

private struct ProfileNudgeRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.warning)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Palette.warning.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.warning.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

private struct ProfileEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.warning)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.warning.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

private struct ProfilePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private struct ProfilePanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var fill: Color
    var accent: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
    }
}

private struct ProfileHeroLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rowHeight = rect.height / 5
        for index in 0...5 {
            let y = CGFloat(index) * rowHeight
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: y))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: y + rowHeight * 0.34),
                control1: CGPoint(x: rect.midX * 0.72, y: y - 24),
                control2: CGPoint(x: rect.midX * 1.28, y: y + 38)
            )
        }
        return path
    }
}

private struct ProfileBackgroundLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let columns = 7
        for index in 0...columns {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(columns)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.width * 0.18, y: rect.maxY))
        }
        let rows = 5
        for index in 0...rows {
            let y = rect.minY + rect.height * CGFloat(index) / CGFloat(rows)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y + rect.height * 0.08))
        }
        return path
    }
}

private struct SexSwitch: View {
    @Binding var sex: Sex
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Sex.allCases) { s in
                Button { sex = s } label: {
                    Text(s.label)
                        .font(.system(size: 12, weight: sex == s ? .semibold : .medium))
                        .foregroundStyle(sex == s ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(sex == s ? Color.white.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(ProfilePressButtonStyle())
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

private extension View {
    func profilePanel(
        cornerRadius: CGFloat = Radius.lg,
        fill: Color = Palette.surface,
        accent: Color = Palette.border
    ) -> some View {
        modifier(ProfilePanelModifier(cornerRadius: cornerRadius, fill: fill, accent: accent))
    }

    func profileReveal(_ visible: Bool, delay: Double) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 10)
            .animation(.spring(response: 0.44, dampingFraction: 0.86).delay(delay), value: visible)
    }
}

private struct NumberField: View {
    @Binding var value: Double?
    var unit: String
    var digits: Int = 1
    var placeholder: String = "0"

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, value: $value, format: .number.precision(.fractionLength(0...digits)).locale(Locale(identifier: "tr_TR")))
                .textFieldStyle(.plain)
                .font(Typography.monoLarge)
                .foregroundStyle(Palette.textPrimary)
            Text(unit)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

private struct ActivityPicker: View {
    @Binding var selection: ActivityLevel

    var body: some View {
        Menu {
            ForEach(ActivityLevel.allCases) { a in
                Button {
                    selection = a
                } label: {
                    if a == selection {
                        Label("\(a.label) · ×\(Fmt.num(a.multiplier, digits: 2))", systemImage: "checkmark")
                    } else {
                        Text("\(a.label) · ×\(Fmt.num(a.multiplier, digits: 2))")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.surfaceElevated))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aktivite").eyebrow()
                    Text(selection.label)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text("×\(Fmt.num(selection.multiplier, digits: 2)) çarpan")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

private struct GoalPicker: View {
    @Binding var selection: Goal

    var body: some View {
        Menu {
            ForEach(Goal.allCases) { g in
                Button {
                    selection = g
                } label: {
                    if g == selection {
                        Label("\(g.label) · \(g.detail)", systemImage: "checkmark")
                    } else {
                        Text("\(g.label) · \(g.detail)")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "target")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.surfaceElevated))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hedef").eyebrow()
                    Text(selection.label)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text(selection.detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

// MARK: - Workout schedule

struct WorkoutScheduleCard: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutSession.weekday) private var workouts: [WorkoutSession]
    @State private var editing: WorkoutSession? = nil

    private var totalCalories: Double {
        workouts.reduce(0) { $0 + $1.estimatedCalories }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("Antrenman Programı").eyebrow()
                }
                Spacer()
                Text("\(workouts.count) gün · \(Fmt.int(totalCalories)) kcal/hafta")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            VStack(spacing: 1) {
                ForEach(1...7, id: \.self) { weekday in
                    WorkoutRow(
                        weekday: weekday,
                        workout: workouts.first(where: { $0.weekday == weekday })
                    ) { existing in
                        if let existing { editing = existing }
                        else {
                            let new = WorkoutSession(weekday: weekday, name: "Antrenman", estimatedCalories: 300)
                            ctx.insert(new)
                            try? ctx.save()
                            editing = new
                        }
                    } onDelete: { w in
                        ctx.delete(w)
                        try? ctx.save()
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .sheet(item: $editing) { w in
            WorkoutEditor(workout: w) {
                try? ctx.save()
                editing = nil
            }
        }
    }
}

private struct WorkoutRow: View {
    let weekday: Int
    let workout: WorkoutSession?
    var onTap: (WorkoutSession?) -> Void
    var onDelete: (WorkoutSession) -> Void
    @State private var hovering = false

    private var isToday: Bool {
        Calendar.current.component(.weekday, from: Date()) == weekday
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(workout != nil ? Palette.surfaceElevated : Color.white.opacity(0.03))
                    .frame(width: 28, height: 28)
                if isToday {
                    Circle()
                        .strokeBorder(Palette.borderStrong, lineWidth: 1)
                        .frame(width: 28, height: 28)
                }
                Text(WorkoutSession.weekdayShort[weekday])
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(workout != nil || isToday ? Palette.textPrimary : Palette.textTertiary)
            }

            Text(WorkoutSession.weekdayNames[weekday])
                .font(Typography.body)
                .foregroundStyle(workout != nil ? Palette.textPrimary : Palette.textTertiary)
                .frame(width: 90, alignment: .leading)

            if let w = workout {
                Text(w.name)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(Fmt.int(w.estimatedCalories)) kcal")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
                Button {
                    onDelete(w)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Palette.surfaceElevated))
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
            } else {
                Spacer(minLength: 0)
                Text(hovering ? "+ ekle" : "—")
                    .font(Typography.caption)
                    .foregroundStyle(hovering ? Palette.accent : Palette.textQuaternary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Radius.sm - 2)
                .fill(hovering ? Color.white.opacity(0.025) : Color.clear)
        )
        .onHover { hovering = $0 }
        .onTapGesture { onTap(workout) }
    }
}

private struct WorkoutEditor: View {
    @Bindable var workout: WorkoutSession
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var nameEdit: String = ""
    @State private var caloriesEdit: Double = 300

    var body: some View {
        NavigationStack {
            Form {
                Section(WorkoutSession.weekdayNames[workout.weekday]) {
                    TextField("Antrenman", text: $nameEdit, prompt: Text("ör: Sırt + Göğüs"))
                    LabeledContent("Tahmini kcal") {
                        TextField("", value: $caloriesEdit, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Antrenman")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        workout.name = nameEdit.trimmingCharacters(in: .whitespaces)
                        workout.estimatedCalories = caloriesEdit
                        onDone()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 420, height: 260)
        .onAppear {
            nameEdit = workout.name
            caloriesEdit = workout.estimatedCalories
        }
    }
}

// MARK: - Activity sync card

struct HealthKitCard: View {
    @Environment(\.modelContext) private var ctx
    private var sync = ShortcutHealthSyncService.shared
    @Query(sort: \StepEntry.date, order: .reverse) private var allSteps: [StepEntry]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @State private var stepInput: Int = 0
    @FocusState private var inputFocused: Bool

    private var todaysEntry: StepEntry? {
        let cal = Calendar.current
        return allSteps.first { cal.isDateInToday($0.date) }
    }

    private var weight: Double {
        measurements.first?.weight ?? 80
    }

    private var todaysCalorieBurn: Double {
        guard let entry = todaysEntry else { return 0 }
        return StepEntry.calorieBurn(for: entry, weightKg: weight)
    }

    private var weekEntries: [StepEntry] { entries(days: 7) }
    private var monthEntries: [StepEntry] { entries(days: 30) }

    private var weekSteps: Int { weekEntries.reduce(0) { $0 + $1.steps } }
    private var monthSteps: Int { monthEntries.reduce(0) { $0 + $1.steps } }
    private var weekDistance: Double { weekEntries.compactMap(\.distanceMeters).reduce(0, +) }
    private var monthDistance: Double { monthEntries.compactMap(\.distanceMeters).reduce(0, +) }
    private var weekCalories: Double { weekEntries.reduce(0) { $0 + StepEntry.calorieBurn(for: $1, weightKg: weight) } }
    private var monthCalories: Double { monthEntries.reduce(0) { $0 + StepEntry.calorieBurn(for: $1, weightKg: weight) } }

    private var weeklyAverageSteps: Int {
        Int((Double(weekSteps) / 7.0).rounded())
    }

    private var monthlyAverageSteps: Int {
        Int((Double(monthSteps) / 30.0).rounded())
    }

    private var syncBadgeText: String {
        sync.syncFileExists ? "Shortcuts sync aktif" : "Dosya bekleniyor"
    }

    private var syncBadgeIcon: String {
        sync.syncFileExists ? "checkmark.icloud" : "icloud.and.arrow.down"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("Adım & Aktivite").eyebrow()
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: syncBadgeIcon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(syncBadgeText)
                        .font(Typography.captionBold)
                }
                .foregroundStyle(sync.syncFileExists ? Palette.positive : Palette.textTertiary)
            }

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: Spacing.lg, alignment: .leading)
            ], alignment: .leading, spacing: Spacing.md) {
                activityMetric(
                    label: "Bugün",
                    value: Fmt.int(Double(todaysEntry?.steps ?? 0)),
                    unit: "adım",
                    detail: "\(Fmt.int(todaysCalorieBurn)) kcal · \(formatDistance(todaysEntry?.distanceMeters ?? 0))"
                )
                activityMetric(
                    label: "7 gün",
                    value: Fmt.int(Double(weekSteps)),
                    unit: "adım",
                    detail: "\(Fmt.int(Double(weeklyAverageSteps))) / gün · \(formatDistance(weekDistance))"
                )
                activityMetric(
                    label: "30 gün",
                    value: Fmt.int(Double(monthSteps)),
                    unit: "adım",
                    detail: "\(Fmt.int(Double(monthlyAverageSteps))) / gün · \(formatDistance(monthDistance))"
                )
                activityMetric(
                    label: "Yakım",
                    value: Fmt.int(monthCalories),
                    unit: "kcal",
                    detail: "30 gün · 7 gün \(Fmt.int(weekCalories)) kcal"
                )
            }

            syncStatusRow
            manualEntryView
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .task {
            sync.importIfAvailable(into: ctx)
            stepInput = todaysEntry?.steps ?? 0
        }
        .onChange(of: todaysEntry?.steps) { _, new in
            if !inputFocused, let n = new { stepInput = n }
        }
    }

    private var syncStatusRow: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)

            VStack(alignment: .leading, spacing: 3) {
                Text(sync.displayPath)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sync.lastMessage)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                sync.importIfAvailable(into: ctx)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.surfaceElevated))
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Shortcut sync dosyasını şimdi oku")
        }
    }

    private var manualEntryView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bugünün adımı").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        TextField("0", value: $stepInput, format: .number)
                            .textFieldStyle(.plain)
                            .font(Typography.hero(28))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: 140)
                            .focused($inputFocused)
                            .onSubmit { saveSteps() }
                        Text("adım")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Divider().frame(height: 40).background(Palette.border)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yakım").eyebrow()
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(Fmt.int(StepEntry.calorieBurn(steps: stepInput, weightKg: weight)))
                            .font(Typography.hero(28))
                            .foregroundStyle(Palette.accent)
                        Text("kcal")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer()
                Button(action: saveSteps) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Kaydet")
                            .font(Typography.bodyBold)
                    }
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.accent))
                }
                .buttonStyle(.plain)
                .disabled(stepInput == (todaysEntry?.steps ?? 0))
                .opacity(stepInput == (todaysEntry?.steps ?? 0) ? 0.5 : 1)
            }
            Text("iPhone Shortcuts her gün \(sync.displayPath) dosyasını günceller. Mac app açıkken dosyayı otomatik içeri alır; burası acil durum manuel giriş.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func saveSteps() {
        if let entry = todaysEntry {
            entry.steps = stepInput
            entry.source = "manual"
            entry.distanceMeters = nil
            entry.activeEnergyKcal = nil
            entry.syncedAt = nil
        } else {
            let new = StepEntry(date: .now, steps: stepInput, source: "manual")
            ctx.insert(new)
        }
        try? ctx.save()
    }

    private func activityMetric(label: String, value: String, unit: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow()
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(Typography.hero(22))
                    .foregroundStyle(Palette.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func entries(days: Int) -> [StepEntry] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? .now

        var byDay: [Date: StepEntry] = [:]
        for entry in allSteps where entry.date >= start && entry.date < end {
            let day = calendar.startOfDay(for: entry.date)
            if let existing = byDay[day] {
                if entry.date > existing.date {
                    byDay[day] = entry
                }
            } else {
                byDay[day] = entry
            }
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters <= 0 { return "0 km" }
        return "\(Fmt.num(meters / 1000, digits: 1)) km"
    }
}

// MARK: - AI Provider Card

struct AIProviderCard: View {
    @State private var provider: AIProvider = AIKeyStore.shared.provider
    @State private var model: String = AIKeyStore.shared.model
    @State private var apiKey: String = ""
    @State private var codexStatus: CodexAuth.Status = .noCodexCLI
    @State private var importing = false
    @State private var importResult: String? = nil       // başarı/hata mesajı
    @State private var importSuccess: Bool = false       // ikon rengi için
    @State private var showLoginHelp: Bool = false       // yardım panelini aç/kapat

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("AI Sağlayıcı").eyebrow()
                }
                Spacer()
                Text(model)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }

            HStack(spacing: Spacing.sm) {
                ForEach(AIProvider.selectable) { p in
                    Button {
                        provider = p
                        AIKeyStore.shared.provider = p
                        model = AIKeyStore.shared.model
                        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: p.systemImage)
                                .font(.system(size: 10, weight: .semibold))
                            Text(p.label).font(Typography.body)
                        }
                        .foregroundStyle(provider == p ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm - 2)
                                .fill(provider == p ? Color.white.opacity(0.08) : Palette.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm - 2)
                                .strokeBorder(provider == p ? Palette.borderStrong : Palette.border, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            if provider == .codex {
                codexSection
            } else {
                openRouterSection
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .onAppear { refreshCodexStatus() }
    }

    private var openRouterSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "key")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
            SecureField("sk-or-...", text: $apiKey)
                .textFieldStyle(.plain)
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .onSubmit {
                    AIKeyStore.shared.apiKey = apiKey
                    NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    @ViewBuilder
    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch codexStatus {
            case .noCodexCLI:
                statusRow(icon: "exclamationmark.triangle", color: Palette.warning,
                          title: "Codex CLI bulunamadı",
                          detail: "Terminal'de: codex login")
            case .ready(let acct):
                HStack(spacing: 10) {
                    statusRow(icon: "checkmark.circle.fill", color: Palette.positive,
                              title: "Bağlandı",
                              detail: acct.map { "Hesap: \($0.prefix(8))…" } ?? "Token hazır")
                    Button {
                        Task { await reimport() }
                    } label: {
                        Image(systemName: importing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Palette.surfaceElevated))
                            .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                            .symbolEffect(.rotate, value: importing)
                    }
                    .buttonStyle(.plain)
                    .disabled(importing)
                    .help("auth.json'dan token'ı yeniden yükle")
                }
            case .error(let m):
                statusRow(icon: "xmark.circle.fill", color: Palette.negative, title: "Hata", detail: m)
            }

            // Import sonucu (başarı/hata mesajı)
            if let msg = importResult {
                HStack(spacing: 5) {
                    Image(systemName: importSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(msg)
                        .font(Typography.caption)
                        .lineLimit(2)
                }
                .foregroundStyle(importSuccess ? Palette.positive : Palette.warning)
            }

            // Yardım butonu (toggle)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showLoginHelp.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showLoginHelp ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Token expire oldu / 401 hatası alıyorsan")
                        .font(Typography.caption)
                }
                .foregroundStyle(Palette.textTertiary)
            }
            .buttonStyle(.plain)

            if showLoginHelp {
                loginHelpPanel
            }
        }
    }

    /// Codex login yardım paneli — token süresi dolduğunda yapılacaklar.
    private var loginHelpPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token expire olunca üç adım:")
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textSecondary)

            helpStep(num: "1", text: "Terminal'i aç ve şu komutu çalıştır:")
            HStack(spacing: 6) {
                Text("codex login")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Palette.background))

                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("codex login", forType: .string)
                    importResult = "✓ Komut panoya kopyalandı"
                    importSuccess = true
                    #else
                    importResult = "Bu kopyalama aksiyonu şu an Mac tarafında kullanılabiliyor"
                    importSuccess = false
                    #endif
                } label: {
                    Label("Kopyala", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    openTerminal()
                } label: {
                    Label("Terminal'i Aç", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            helpStep(num: "2", text: "Browser açılacak — ChatGPT hesabınla giriş yap.")

            helpStep(num: "3", text: "Buraya dön, üstteki ↻ butonuna bas — yeni token yüklenir.")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func helpStep(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(num)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Palette.accent.opacity(0.15)))
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func openTerminal() {
        #if os(macOS)
        // Terminal.app'i aç
        if let url = URL(string: "file:///System/Applications/Utilities/Terminal.app") {
            NSWorkspace.shared.open(url)
        }
        #else
        importResult = "Terminal aksiyonu iPhone tarafında kullanılmaz"
        importSuccess = false
        #endif
    }

    private func statusRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func refreshCodexStatus() {
        codexStatus = CodexAuth.shared.currentStatus()
    }

    @MainActor
    private func reimport() async {
        importing = true
        importResult = nil
        defer { importing = false }

        // 1) auth.json'dan token yükle
        let tokens: CodexTokens
        do {
            tokens = try CodexAuth.shared.importFromCodexCLI()
        } catch {
            importResult = "Token dosyası okunamadı: \(error.localizedDescription). Terminal'de 'codex login' çalıştır."
            importSuccess = false
            showLoginHelp = true
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            importResult = nil
            return
        }

        // 2) Gerçek test — refresh endpoint'ine post et. Bu sunucunun token'ı
        //    hala kabul edip etmediğini canlı doğrular.
        do {
            _ = try await CodexAuth.shared.refresh(tokens)
            refreshCodexStatus()
            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
            importResult = "✓ Token doğrulandı — chat hazır"
            importSuccess = true
            showLoginHelp = false
        } catch {
            // Refresh API'den hata geldi — token sunucuda invalidated, yeniden login gerek
            let msg = error.localizedDescription
            if msg.contains("401") || msg.lowercased().contains("invalid") || msg.lowercased().contains("reused") {
                importResult = "Token sunucuda geçersiz — 'codex login' çalıştırman gerekiyor."
            } else {
                importResult = "Doğrulama başarısız: \(msg)"
            }
            importSuccess = false
            showLoginHelp = true
        }

        try? await Task.sleep(nanoseconds: 6_000_000_000)
        importResult = nil
    }
}

extension Notification.Name {
    static let aiClientChanged = Notification.Name("hercules.ai.client.changed")
}

// MARK: - Backup card

struct BackupCard: View {
    @Environment(\.modelContext) private var ctx
    @State private var lastBackup: Date? = nil
    @State private var backupSize: Int? = nil
    @State private var vaultLastSync: Date? = nil
    @State private var vaultConfigured = false
    @State private var vaultBackupExists = false
    @State private var statusMessage: String? = nil
    @State private var showRestoreConfirm = false
    @State private var showVaultRestoreConfirm = false
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("Yedekleme").eyebrow()
                }
                Spacer()
                if let date = lastBackup {
                    Text("Son: \(Fmt.dateLong.string(from: date))")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    Text("Henüz yedek yok")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.warning)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                    Text(backupLocationText)
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let size = backupSize {
                        Text("· \(formatSize(size))")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    Image(systemName: BackupService.shared.iCloudMirrorAvailable ? "icloud" : "icloud.slash")
                        .font(.system(size: 11, weight: .semibold))
                    Text(BackupService.shared.iCloudMirrorAvailable ? "iCloud Drive mirror aktif" : "iCloud Drive klasörü bulunamadı")
                        .font(Typography.captionBold)
                    if BackupService.shared.iCloudBackupExists {
                        Text("· yedek var")
                            .font(Typography.caption)
                    }
                }
                .foregroundStyle(BackupService.shared.iCloudMirrorAvailable ? Palette.positive : Palette.textTertiary)

                vaultStatusBlock

                Text("Ölçümler, antrenmanlar, takvim, tarifler, profil, Hakkında, chat geçmişi, memory, research cache ve presetler bu sisteme girer. Restore öncesi otomatik safety backup alınır; vault yazarken çakışma yakalanırsa eski dosya conflicts klasörüne kopyalanır.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                Button(action: backupNow) {
                    backupActionLabel("Yedekle", systemImage: "arrow.up.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .help("Şimdi yedekle (⌘⇧B)")

                Button(action: revealInFinder) {
                    backupActionLabel("Finder", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!BackupService.shared.backupExists)
                .help("Yedek klasörünü Finder'da göster")

                Button(action: selectVaultFolder) {
                    backupActionLabel("Klasör", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(vaultConfigured ? "Vault klasörünü değiştir" : "Veri klasörü seç")

                Button(action: exportVaultNow) {
                    backupActionLabel("Vault Yaz", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!vaultConfigured)
                .help("Vault klasörüne yaz")

                Button(role: .destructive) {
                    showRestoreConfirm = true
                } label: {
                    backupActionLabel("Geri Al", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Palette.warning)
                .disabled(!BackupService.shared.backupExists || importing)
                .help("Local yedekten geri yükle")

                Button(role: .destructive) {
                    showVaultRestoreConfirm = true
                } label: {
                    backupActionLabel("Vault Al", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Palette.warning)
                .disabled(!vaultBackupExists || importing)
                .help("Vault snapshot'ını içeri al")
            }

            if let msg = statusMessage {
                Text(msg)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.positive)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .onAppear { refreshInfo() }
        .alert("Geri Yükle?", isPresented: $showRestoreConfirm) {
            Button("İptal", role: .cancel) { }
            Button("Tüm veriyi değiştir", role: .destructive) { restoreNow() }
        } message: {
            Text("Mevcut tüm veri silinip yedekteki veriyle değiştirilecek. Önce bir yedek aldığından emin ol.")
        }
        .alert("Vault'tan Geri Yükle?", isPresented: $showVaultRestoreConfirm) {
            Button("İptal", role: .cancel) { }
            Button("Tüm veriyi değiştir", role: .destructive) { restoreVaultNow() }
        } message: {
            Text("Seçili veri klasöründeki snapshot içeri alınacak. Mevcut local verinin safety backup'ı önce hem local yedeklere hem vault/backups içine yazılır.")
        }
    }

    private var vaultStatusBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: vaultConfigured ? "externaldrive.connected.to.line.below" : "externaldrive.badge.questionmark")
                    .font(.system(size: 11, weight: .semibold))
                Text(vaultConfigured ? "Dosya tabanlı vault aktif" : "Dosya tabanlı vault seçilmedi")
                    .font(Typography.captionBold)
                if let vaultLastSync {
                    Text("· \(Fmt.dateLong.string(from: vaultLastSync))")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .foregroundStyle(vaultConfigured ? Palette.positive : Palette.warning)

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                Text(BackupService.shared.vaultDisplayPath)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            if vaultConfigured {
                Text("Klasör yapısı: manifest.json, data/hercules-backup.json, support/, backups/, conflicts/. iPhone tarafında aynı klasör seçildiğinde bu snapshot okunacak.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func backupActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(Typography.captionBold)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func backupNow() {
        let ok = BackupService.shared.export(from: ctx)
        statusMessage = ok ? "✓ Yedek alındı" : "Yedek alınamadı"
        refreshInfo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            statusMessage = nil
        }
    }

    private func restoreNow() {
        importing = true
        defer { importing = false }
        do {
            try BackupService.shared.restore(from: BackupService.shared.latestBackupURL, into: ctx, mode: .replaceAll)
            statusMessage = "✓ Geri yüklendi"
        } catch {
            statusMessage = "Hata: \(error.localizedDescription)"
        }
        refreshInfo()
    }

    private func selectVaultFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Hercules veri klasörünü seç"
        panel.message = "iCloud Drive/Hercules gibi cihazların arasında sync olacak bir klasör seç."
        panel.prompt = "Bu Klasörü Kullan"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let summary = try BackupService.shared.configureVaultRoot(url, from: ctx)
                statusMessage = summary.didWriteConflictCopy
                    ? "✓ Vault seçildi, mevcut uzak kopya conflicts içine korundu"
                    : "✓ Vault seçildi ve tüm veri yazıldı"
            } catch {
                statusMessage = "Vault hata: \(error.localizedDescription)"
            }
            refreshInfo()
        }
        #endif
    }

    private func exportVaultNow() {
        do {
            let summary = try BackupService.shared.exportToVault(from: ctx)
            statusMessage = summary.didWriteConflictCopy
                ? "✓ Vault yazıldı, eski uzak kopya conflicts içine alındı"
                : "✓ Vault yazıldı"
        } catch {
            statusMessage = "Vault hata: \(error.localizedDescription)"
        }
        refreshInfo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            statusMessage = nil
        }
    }

    private func restoreVaultNow() {
        importing = true
        defer { importing = false }
        do {
            try BackupService.shared.restoreFromVault(into: ctx)
            statusMessage = "✓ Vault'tan geri yüklendi"
        } catch {
            statusMessage = "Vault hata: \(error.localizedDescription)"
        }
        refreshInfo()
    }

    private func revealInFinder() {
        #if os(macOS)
        if let vaultURL = BackupService.shared.selectedVaultRootURL {
            NSWorkspace.shared.activateFileViewerSelecting([vaultURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([BackupService.shared.latestBackupURL])
        }
        #endif
    }

    private func refreshInfo() {
        lastBackup = BackupService.shared.lastBackupDate
        backupSize = BackupService.shared.backupSizeBytes
        vaultLastSync = BackupService.shared.vaultLastSyncDate
        vaultConfigured = BackupService.shared.vaultIsConfigured
        vaultBackupExists = BackupService.shared.vaultBackupExists
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    private var backupLocationText: String {
        if BackupService.shared.iCloudMirrorAvailable {
            return "~/Documents/Hercules + iCloud Drive/Hercules"
        }
        return "~/Documents/Hercules/hercules-backup.json"
    }
}
