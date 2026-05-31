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
        ctx.saveOrReport()
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
