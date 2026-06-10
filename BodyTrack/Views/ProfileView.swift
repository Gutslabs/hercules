import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Profil sekmeleri — Genel (kimlik/plan), Promptlar (AI sistem promptları),
/// Hafıza (öğrenilenler + research). Ayrı Hafıza ve System sayfaları kalktı.
enum ProfileTab: String, CaseIterable, Identifiable {
    case genel, promptlar, hafiza, gorunum
    var id: String { rawValue }

    var label: String {
        switch self {
        case .genel:     return "Genel"
        case .promptlar: return "Promptlar"
        case .hafiza:    return "Hafıza"
        case .gorunum:   return "Görünüm"
        }
    }

    var subtitle: String {
        switch self {
        case .genel:     return "Kimlik, hedef ve AI hafızası tek yerde; günlük planın kaynak ayarı."
        case .promptlar: return "Uygulamadaki tüm AI promptları — kim okur, ne zaman çalışır, tek yerden düzenle."
        case .hafiza:    return "AI'ın senin hakkında öğrendikleri ve cevaplarını dayandırdığı araştırma kütüphanesi."
        case .gorunum:   return "Tema, semantik renk dili ve grafik rengi — değişiklik anında tüm sayfalara uygulanır."
        }
    }
}

/// Profil — V1 "Tek Akış" dili.
/// Katmanlar: ① Kimlik + kilo durumu (hero) ② Hakkımda + Günlük Plan (tek ev)
/// ③ Adım & Aktivite şeridi ④ Sistem (AI Sağlayıcı + Yedekleme tek kartta).
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

    @FocusState private var focusedField: ProfileField?
    @State private var newSupplement = ""

    private enum ProfileField: Hashable { case name, height, target, bodyFat, protein, carbs, fat }

    @State private var saved = false
    @State private var hasInitialized = false
    @State private var autosaveTask: Task<Void, Never>? = nil
    @State private var revealContent = false
    // Tema değişimi ContentView'da .id(epoch) ile ağacı tazeler — sekme seçimi
    // @State olsaydı Görünüm'de tema seçince Genel'e fırlardı; AppStorage dayanıklı.
    @AppStorage("hercules.profile.tab") private var tabRaw: String = ProfileTab.genel.rawValue

    private var tab: ProfileTab {
        get { ProfileTab(rawValue: tabRaw) ?? .genel }
        nonmutating set { tabRaw = newValue.rawValue }
    }

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

            // Promptlar: sayfa kaymaz, editör kutusu viewport'u doldurur ve KENDİ içinde
            // kayar. Diğer sekmeler normal sayfa scroll'u kullanır.
            if tab == .promptlar {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(compact: compact)
                    ProfilePromptsPane(compact: compact)
                        .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, compact ? Spacing.lg : Spacing.xxxl)
                .padding(.vertical, compact ? Spacing.lg : Spacing.xxl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = nil }
            } else {
                // Viewport'u doldur: içerik kısaysa esneyen bölüm (Hakkımda/Plan ya da
                // Hafıza kartları) kalan boşluğu yutar; pencere kısaysa sayfa yine kayar.
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        header(compact: compact)
                            .profileReveal(revealContent, delay: 0.02)
                        switch tab {
                        case .genel:
                            heroCard(compact: compact)
                                .profileReveal(revealContent, delay: 0.06)
                            memoryAndPlan(compact: compact)
                                .frame(maxHeight: .infinity)
                                .profileReveal(revealContent, delay: 0.10)
                            HealthKitCard()
                                .profileReveal(revealContent, delay: 0.14)
                            systemCard(compact: compact)
                                .profileReveal(revealContent, delay: 0.18)
                        case .hafiza:
                            ProfileMemoryPane(compact: compact)
                                .frame(maxHeight: .infinity)
                        case .gorunum:
                            ProfileAppearancePane(compact: compact)
                                .frame(maxHeight: .infinity)
                        case .promptlar:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, compact ? Spacing.lg : Spacing.xxxl)
                    .padding(.vertical, compact ? Spacing.lg : Spacing.xxl)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(minHeight: proxy.size.height, alignment: .topLeading)
                    // Input DIŞINDA herhangi bir yere tıklayınca focus'u bırak (cursor kalmasın).
                    // Buton/TextField'lar kendi tıklamasını tüketir; non-interaktif her yer burayı tetikler.
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = nil }
                }
            }
        }
        .background(
            Palette.background.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { focusedField = nil }
        )
        .onAppear {
            initializeFromProfile()
            revealContent = true
        }
        .onChange(of: about) { _, _ in scheduleAutosave() }
        .onChange(of: supplements) { _, _ in scheduleAutosave() }
        .onChange(of: manualCalorieOffset) { _, _ in scheduleAutosave() }
        .onChange(of: manualCalorieOffsetMacro) { _, _ in scheduleAutosave() }
        .onChange(of: manualProteinGrams) { _, _ in scheduleAutosave() }
        .onChange(of: manualCarbsGrams) { _, _ in scheduleAutosave() }
        .onChange(of: manualFatGrams) { _, _ in scheduleAutosave() }
        .onDisappear {
            autosaveTask?.cancel()
            save()
        }
    }

    // MARK: - Header

    private func header(compact: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: Spacing.lg) {
                headerCopy
                Spacer(minLength: Spacing.lg)
                tabSwitcher
                saveButton
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                headerCopy
                HStack(spacing: Spacing.md) {
                    tabSwitcher
                    saveButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(calorieResult == nil ? "Profil kurulumu bekliyor" : "Profil canlı").eyebrow()
            Text("Profil")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
            Text(tab.subtitle)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, 2)
        }
    }

    /// Genel | Promptlar | Hafıza — V1 segment.
    private var tabSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(ProfileTab.allCases) { t in
                Button {
                    tab = t
                    focusedField = nil
                } label: {
                    Text(t.label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tab == t ? Palette.btnFg : Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(tab == t ? Palette.btnBg : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    private var saveButton: some View {
        Button { save() } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .symbolEffect(.bounce, value: saved)
                Text(saved ? "Kaydedildi" : "Kaydet")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(saved ? Palette.positive : Palette.btnFg)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(saved ? Palette.positive.opacity(0.14) : Palette.accent)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(ProfilePressButtonStyle())
        .keyboardShortcut("s", modifiers: .command)
        .help("Profili kaydet (⌘S)")
    }

    // MARK: - Hero (kimlik + kilo durumu)

    @ViewBuilder
    private func heroCard(compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    identityBlock
                    statChipsRow(compact: true)
                }
                .padding(.horizontal, Spacing.xl).padding(.vertical, Spacing.xl)
            } else {
                HStack(alignment: .center, spacing: 28) {
                    identityBlock
                    Spacer(minLength: Spacing.lg)
                    statChipsRow(compact: false)
                }
                .padding(.horizontal, 32).padding(.vertical, 26)
            }
        }
        .dashboardCard()
    }

    private var identityBlock: some View {
        HStack(alignment: .center, spacing: 22) {
            ZStack {
                Circle().fill(Palette.accent.opacity(0.14))
                Circle().strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1)
                Text(initial)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    TextField("Adın", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = nil }
                    Circle()
                        .fill(calorieResult == nil ? Palette.warning : Palette.positive)
                        .frame(width: 6, height: 6)
                }
                ChatHintFlow(spacing: 14) {
                    metaItem("Yaş") {
                        Text("\(ageYears)").font(metaValueFont).foregroundStyle(Palette.textPrimary)
                    }
                    metaItem("Doğum") {
                        DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    metaItem("Boy") {
                        HStack(spacing: 3) {
                            TextField("—", value: Binding(
                                get: { Optional(height) },
                                set: { height = $0 ?? height }
                            ), format: .number.precision(.fractionLength(0)))
                                .textFieldStyle(.plain)
                                .font(metaValueFont)
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize()
                                .focused($focusedField, equals: .height)
                                .onSubmit { focusedField = nil }
                            Text("cm").font(metaValueFont).foregroundStyle(Palette.textPrimary)
                        }
                    }
                    metaItem("Cinsiyet") {
                        Menu {
                            ForEach(Sex.allCases) { s in
                                Button {
                                    sex = s
                                } label: {
                                    if s == sex { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(sex.label).font(metaValueFont).foregroundStyle(Palette.textPrimary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(Palette.textQuaternary)
                            }
                            .contentShape(Rectangle())
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var metaValueFont: Font { .system(size: 12.5, weight: .semibold) }

    private func metaItem<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).eyebrow()
            content()
        }
    }

    private func statChipsRow(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 26) {
            statChip(dot: Palette.accent, label: "Mevcut", divider: !compact) {
                Text(latest?.weight.map { "\(Fmt.num($0, digits: 1)) kg" } ?? "—")
                    .font(chipValueFont).foregroundStyle(Palette.textPrimary)
            } sub: { bodyFatSubline }
            statChip(dot: Palette.positive, label: "Hedef", divider: true) {
                targetField
            } sub: {
                Text(targetRemainingLine).font(chipSubFont).foregroundStyle(Palette.textTertiary)
            }
            statChip(dot: Palette.warning, label: "İlerleme", divider: true) {
                Text(progressLine.value).font(chipValueFont).foregroundStyle(Palette.textPrimary)
            } sub: {
                Text(progressLine.detail).font(chipSubFont).foregroundStyle(Palette.textTertiary)
            }
            if compact {
                Spacer(minLength: 0)
            }
        }
    }

    private var chipValueFont: Font { .system(size: 17, weight: .bold).monospacedDigit() }
    private var chipSubFont: Font { .system(size: 11) }

    private func statChip<V: View, S: View>(
        dot: Color,
        label: String,
        divider: Bool,
        @ViewBuilder value: () -> V,
        @ViewBuilder sub: () -> S
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if divider {
                Rectangle().fill(Palette.border).frame(width: 0.5)
                    .padding(.trailing, 26)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(dot).frame(width: 5, height: 5)
                    Text(label).eyebrow()
                }
                value()
                sub()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Mevcut chip alt satırı — ölçümden yağ varsa metin, yoksa manuel girilebilir alan.
    @ViewBuilder
    private var bodyFatSubline: some View {
        if let bf = latest?.bodyFat {
            Text("%\(Fmt.num(bf, digits: 1)) yağ").font(chipSubFont).foregroundStyle(Palette.textTertiary)
        } else {
            HStack(spacing: 3) {
                Text("%").font(chipSubFont).foregroundStyle(Palette.textTertiary)
                TextField("—", value: $manualBodyFat, format: .number.precision(.fractionLength(0...1)).locale(Locale(identifier: "tr_TR")))
                    .textFieldStyle(.plain)
                    .font(chipSubFont)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize()
                    .focused($focusedField, equals: .bodyFat)
                    .onSubmit { focusedField = nil }
                Text("yağ").font(chipSubFont).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var targetField: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            TextField("—", value: $targetWeight, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.plain)
                .font(chipValueFont)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize()
                .focused($focusedField, equals: .target)
                .onSubmit { focusedField = nil }
            Text("kg").font(chipValueFont).foregroundStyle(Palette.textPrimary)
        }
    }

    // MARK: - Hafıza (Hakkımda) + Günlük Plan

    @ViewBuilder
    private func memoryAndPlan(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                aboutCard
                planCard
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.lg) {
                aboutCard
                    .frame(maxWidth: .infinity)
                planCard
                    .frame(width: 432)
            }
        }
    }

    /// Hakkında — kullanıcının kendi geçmişini özetlediği, AI'ya her sohbette
    /// kalıcı context olarak verilen serbest metin.
    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Hakkımda").eyebrow()
                Text("AI hafızasının kaynağı")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.leading, 10)
                Spacer(minLength: Spacing.md)
                Text("\(aboutCharCount) · AI her sohbette okur")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }

            TextEditor(text: $about)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12.5))
                .lineSpacing(4)
                .foregroundStyle(Palette.textSecondary)
                .frame(minHeight: 220, maxHeight: .infinity)
                .padding(.top, 8)
                .overlay(alignment: .topLeading) {
                    if about.isEmpty {
                        Text("ör: 28 yaşındayım, masa başı çalışıyorum, diz hassasiyetim var. Haftada 4 gün ağırlık antrenmanı yapıyorum; hedefim kas kaybetmeden yağ oranını düşürmek.")
                            .font(.system(size: 12.5))
                            .lineSpacing(4)
                            .foregroundStyle(Palette.textQuaternary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

            Hairline().padding(.top, 13)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    contextChip("@Ölçümler")
                    contextChip("@Antrenman")
                    contextChip("@Beslenme")
                    Spacer(minLength: Spacing.xl)
                    supplementsCluster
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        contextChip("@Ölçümler")
                        contextChip("@Antrenman")
                        contextChip("@Beslenme")
                    }
                    ChatHintFlow(spacing: 8) {
                        supplementsClusterItems
                    }
                }
            }
            .padding(.top, 13)
        }
        .padding(.init(top: 22, leading: 28, bottom: 18, trailing: 28))
        .dashboardCard()
    }

    /// Destekler — Hakkımda kartının alt şeridinde sağda (AI'ya kalıcı context).
    private var supplementsCluster: some View {
        HStack(alignment: .center, spacing: 8) {
            supplementsClusterItems
        }
    }

    @ViewBuilder
    private var supplementsClusterItems: some View {
        Text("Destekler").eyebrow()
        ForEach(Array(supplementItems.enumerated()), id: \.offset) { _, item in
            removableSupplementChip(item)
        }
        if supplementItems.isEmpty {
            Button {
                supplements = UserProfile.defaultSupplements
            } label: {
                Text("Varsayılanları ekle")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Kreatin + protein tozu")
        }
        addSupplementField
    }

    private func contextChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
    }

    private func removableSupplementChip(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Button {
                removeSupplement(text)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Kaldır")
        }
        .padding(.leading, 11).padding(.trailing, 8).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.track)
        )
    }

    private var addSupplementField: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Palette.textTertiary)
            TextField("ekle", text: $newSupplement)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 56)
                .onSubmit { addSupplement() }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        )
    }

    private func addSupplement() {
        let t = newSupplement.trimmingCharacters(in: .whitespacesAndNewlines)
        newSupplement = ""
        guard !t.isEmpty else { return }
        var items = supplementItems
        guard !items.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        items.append(t)
        supplements = items.joined(separator: "\n")
    }

    private func removeSupplement(_ text: String) {
        supplements = supplementItems.filter { $0 != text }.joined(separator: "\n")
    }

    private var supplementItems: [String] {
        supplements
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var aboutCharCount: String {
        let chars = about.count
        if chars == 0 { return "boş" }
        return "\(chars) karakter"
    }

    // MARK: - Günlük Plan

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

    private var hasManualMacroTargets: Bool {
        manualProteinGrams != nil || manualCarbsGrams != nil || manualFatGrams != nil
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Günlük Plan").eyebrow()
                Spacer(minLength: Spacing.md)
                if hasManualMacroTargets {
                    Button {
                        manualProteinGrams = nil
                        manualCarbsGrams = nil
                        manualFatGrams = nil
                    } label: {
                        Text("Otomatiğe dön")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Palette.border, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Makro hedeflerini otomatik hesaba döndür")
                }
            }

            if let r = calorieResult {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(Fmt.int(r.goalCalories))
                        .font(.system(size: 32, weight: .bold).monospacedDigit())
                        .tracking(-0.4)
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText(value: r.goalCalories))
                        .animation(.snappy, value: r.goalCalories)
                    Text("kcal/gün")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.top, 8)

                planSourceRow(r)
                    .padding(.top, 11)

                VStack(alignment: .leading, spacing: 11) {
                    macroEditRow(
                        name: "Protein", tint: Palette.macroProtein,
                        field: .protein, value: $manualProteinGrams,
                        automatic: r.protein.grams, caloriesPerGram: 4, totalCalories: r.goalCalories
                    )
                    macroEditRow(
                        name: "Karbonhidrat", tint: Palette.macroCarbs,
                        field: .carbs, value: $manualCarbsGrams,
                        automatic: r.carbs.grams, caloriesPerGram: 4, totalCalories: r.goalCalories
                    )
                    macroEditRow(
                        name: "Yağ", tint: Palette.macroFat,
                        field: .fat, value: $manualFatGrams,
                        automatic: r.fat.grams, caloriesPerGram: 9, totalCalories: r.goalCalories
                    )
                }
                .padding(.top, 14)

                Text("Kalori hedefi bu üç makrodan hesaplanır.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 9)

                Spacer(minLength: 14)

                planMicrosRow(r)
            } else {
                ProfileEmptyState(
                    icon: "flame",
                    title: "Kalori hedefi hazır değil",
                    detail: "En az bir ağırlık verisi gerekli. Ölçüm ekle veya hero'daki hedef alanını doldur."
                )
                .padding(.top, 12)
            }
        }
        .padding(.init(top: 22, leading: 28, bottom: 20, trailing: 28))
        .dashboardCard()
    }

    /// BMR · TDEE · Hedef adj — hairline'lı üç kolon.
    private func planSourceRow(_ r: CalorieResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(alignment: .top, spacing: 0) {
                planSourceCol("BMR", "\(Fmt.int(r.bmr))", tint: Palette.textPrimary, divider: false)
                planSourceCol("TDEE", "\(Fmt.int(r.tdee))", tint: Palette.textPrimary, divider: true)
                planSourceCol("Hedef adj", goalAdjString, tint: goalAdjTint, divider: true)
            }
            .padding(.top, 11)
        }
    }

    private func planSourceCol(_ label: String, _ value: String, tint: Color, divider: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if divider {
                Rectangle().fill(Palette.border).frame(width: 0.5)
                    .padding(.trailing, 16)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).eyebrow()
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(tint)
                    Text("kcal")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.textQuaternary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// V1 makro satırı: nokta + isim · − [gram] + · kcal·% · altta renkli pay barı.
    private func macroEditRow(
        name: String,
        tint: Color,
        field: ProfileField,
        value: Binding<Double?>,
        automatic: Double,
        caloriesPerGram: Double,
        totalCalories: Double
    ) -> some View {
        let grams = max(0, value.wrappedValue ?? automatic)
        let calories = grams * caloriesPerGram
        let share = totalCalories > 0 ? min(max(calories / totalCalories, 0), 1) : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Spacing.sm)

                Button {
                    value.wrappedValue = max(0, round(grams) - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(grams <= 0)

                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    // Tıklayıp elle değer yazılabilir (Enter / başka yere tıkla → uygulanır).
                    TextField("", value: Binding<Double>(
                        get: { (value.wrappedValue ?? automatic).rounded() },
                        set: { value.wrappedValue = max(0, min(2000, $0.rounded())) }
                    ), format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                        .focused($focusedField, equals: field)
                        .onSubmit { focusedField = nil }
                    Text("g")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                }

                Button {
                    value.wrappedValue = round(grams) + 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("\(Fmt.int(calories)) kcal · %\(Fmt.int(share * 100))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 92, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.track)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(0.85))
                        .frame(width: geo.size.width * share)
                }
            }
            .frame(height: 4)
        }
    }

    /// Su · Lif · Yağsız kütle — kart altı hairline kolonları.
    private func planMicrosRow(_ r: CalorieResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(alignment: .top, spacing: 0) {
                planMicroCol("Su", "\(Fmt.num(r.water, digits: 1)) L", divider: false)
                planMicroCol("Lif", "\(Fmt.int(r.fiber)) g", divider: true)
                planMicroCol("Yağsız kütle", "\(Fmt.num(r.leanMass, digits: 1)) kg", divider: true)
            }
            .padding(.top, 11)
        }
    }

    private func planMicroCol(_ label: String, _ value: String, divider: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if divider {
                Rectangle().fill(Palette.border).frame(width: 0.5)
                    .padding(.trailing, 16)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).eyebrow()
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var goalAdjString: String {
        let v = goal.calorieAdjustment
        if v == 0 { return "0" }
        return "\(v > 0 ? "+" : "−")\(Fmt.int(abs(v)))"
    }

    private var goalAdjTint: Color {
        let v = goal.calorieAdjustment
        if v == 0 { return Palette.textPrimary }
        return v < 0 ? Palette.positive : Palette.warning
    }

    // MARK: - Sistem (AI + Yedekleme tek kartta)

    @ViewBuilder
    private func systemCard(compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 0) {
                    AIProviderCard()
                    Hairline()
                    BackupCard()
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    AIProviderCard()
                        .frame(width: 390)
                    Rectangle().fill(Palette.border).frame(width: 0.5)
                    BackupCard()
                        .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .dashboardCard()
    }

    // MARK: - Veri

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.first.map { String($0).uppercased() } ?? "H"
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
            "\(Fmt.signed(weekly, digits: 2)) kg/hafta",
            "haftalık tempo"
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
        manualCalorieOffset = p.manualCalorieOffset
        manualCalorieOffsetMacro = p.manualCalorieOffsetMacro
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
        profile.manualCalorieOffset = manualCalorieOffset
        profile.manualCalorieOffsetMacro = manualCalorieOffsetMacro
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

// MARK: - Profil ▸ Görünüm sekmesi

/// Görünüm — üç karar tek ekranda: Tema (koyu/açık/sistem), Semantik şema (B/C),
/// Grafik rengi (bordo/adaçayı/mürekkep). Her seçenek canlı mini önizlemeyle;
/// seçim ThemeSettings'e yazılır → tüm ağaç anında tazelenir.
struct ProfileAppearancePane: View {
    var compact: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [UserProfile]

    private var isDark: Bool { colorScheme == .dark }

    /// Önizleme paletleri — seçili temadan bağımsız, sabit.
    private struct PreviewColors {
        let bg, card, text, sub, acc, c2, c3: Color
        static let dark = PreviewColors(
            bg: Color(hex: 0x121417), card: Color.white.opacity(0.05),
            text: Color(hex: 0xECE9E2), sub: Color(hex: 0x9A968D),
            acc: Color(hex: 0xECE9E2), c2: Color(hex: 0x6F9D83), c3: Color(hex: 0xC2A36B)
        )
        static let light = PreviewColors(
            bg: Color(hex: 0xF2EFE8), card: Color(hex: 0xFAF9F5),
            text: Color(hex: 0x26241F), sub: Color(hex: 0x6E6A60),
            acc: Color(hex: 0x26241F), c2: Color(hex: 0x4E7A60), c3: Color(hex: 0x96763C)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            temaCard
                .frame(maxHeight: .infinity)
            renkDiliCard
                .frame(maxHeight: .infinity)
            grafikCard
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: Tema

    private var temaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Tema").eyebrow()
                Text("zemin ve metin iskeleti")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
            }
            Group {
                if compact {
                    VStack(spacing: 14) { temaTiles }
                } else {
                    HStack(alignment: .top, spacing: 14) { temaTiles }
                }
            }
        }
        .padding(.init(top: 20, leading: 28, bottom: 22, trailing: 28))
        .frame(maxHeight: .infinity, alignment: .top)
        .dashboardCard()
    }

    @ViewBuilder
    private var temaTiles: some View {
        themeTile("Koyu — Mürekkep", note: nil, target: .dark) {
            themePreview(.dark)
        }
        themeTile("Açık — Fildişi", note: nil, target: .light) {
            themePreview(.light)
        }
        themeTile("Sistem", note: "macOS'u takip eder", target: .system) {
            HStack(spacing: 0) {
                themePreview(.dark)
                themePreview(.light)
            }
        }
    }

    private func themeTile<P: View>(
        _ title: String,
        note: String?,
        target: AppAppearance,
        @ViewBuilder preview: () -> P
    ) -> some View {
        let selected = ThemeSettings.appearance == target
        return Button {
            ThemeSettings.appearance = target
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                preview()
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                HStack(spacing: 8) {
                    selectionDot(selected)
                    Text(title)
                        .font(.system(size: 12.5, weight: selected ? .bold : .semibold))
                        .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                    if let note {
                        Text("· \(note)")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.fieldFill))
            .overlay(selectionRing(selected))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Mini sayfa önizlemesi: selamlama + kalori halkalı kart + makro barları.
    private func themePreview(_ p: PreviewColors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(p.acc).frame(width: 4, height: 4)
                Text(greetingText)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(p.sub.opacity(0.25), lineWidth: 2.4)
                    Circle()
                        .trim(from: 0, to: 0.65)
                        .stroke(p.acc, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("1.938 kcal")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(p.text)
                    previewBar(p.acc, fraction: 0.76)
                    previewBar(p.c2, fraction: 0.58)
                    previewBar(p.c3, fraction: 0.40)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(p.card))
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.bg)
    }

    private func previewBar(_ color: Color, fraction: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(0.8))
            .frame(height: 2.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(x: fraction, y: 1, anchor: .leading)
    }

    /// Saate göre selamlama + profil adı — önizlemeler kişisel hissettirir.
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let greeting: String
        switch hour {
        case 5..<11:  greeting = "Günaydın"
        case 11..<18: greeting = "İyi günler"
        case 18..<23: greeting = "İyi akşamlar"
        default:      greeting = "İyi geceler"
        }
        let name = profiles.first?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? greeting : "\(greeting), \(name)"
    }

    // MARK: Renk dili (semantik şema)

    private var renkDiliCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Renk Dili").eyebrow()
                Text("olumlu / olumsuz değerlerin nasıl konuşacağı")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
            }
            VStack(spacing: 12) {
                semTile(
                    .adacayiBordo,
                    name: "Adaçayı / Pirinç",
                    desc: "Olumlu yeşil, olumsuz pirinç — yön her zaman renkli."
                )
                semTile(
                    .sessizPirinc,
                    name: "Sessiz / Pirinç",
                    desc: "Yolunda olan soluk kalır; yalnızca dikkat gereken pirinç yanar."
                )
            }
        }
        .padding(.init(top: 20, leading: 28, bottom: 22, trailing: 28))
        .frame(maxHeight: .infinity, alignment: .top)
        .dashboardCard()
    }

    private func semGood(_ s: SemanticScheme) -> Color {
        switch s {
        case .adacayiBordo: return isDark ? Color(hex: 0x6F9D83) : Color(hex: 0x4E7A60)
        case .sessizPirinc: return isDark ? Color(hex: 0x8A867D) : Color(hex: 0x8D887C)
        }
    }

    private func semBad(_ s: SemanticScheme) -> Color {
        switch s {
        case .adacayiBordo: return isDark ? Color(hex: 0xC2A36B) : Color(hex: 0x96763C)
        case .sessizPirinc: return isDark ? Color(hex: 0xC2A36B) : Color(hex: 0x96763C)
        }
    }

    private func semTile(_ scheme: SemanticScheme, name: String, desc: String) -> some View {
        let selected = ThemeSettings.semantic == scheme
        return Button {
            ThemeSettings.semantic = scheme
        } label: {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        selectionDot(selected)
                        Text(name)
                            .font(.system(size: 12.5, weight: selected ? .bold : .semibold))
                            .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                    }
                    Text(desc)
                        .font(.system(size: 10.5))
                        .lineSpacing(2)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 190, alignment: .leading)

                Rectangle().fill(Palette.border).frame(width: 1)
                    .frame(maxHeight: 38)

                // Canlı örnek: hedefe göre semantik (kilo ▼ iyi, bel ▲ kötü)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 22) { semSamples(scheme) }
                    VStack(alignment: .leading, spacing: 6) { semSamples(scheme) }
                }
                Spacer(minLength: 0)
            }
            .padding(.init(top: 14, leading: 18, bottom: 14, trailing: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.fieldFill))
            .overlay(selectionRing(selected))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func semSamples(_ scheme: SemanticScheme) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 7) {
            Text("Ağırlık").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            Text("90,8").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Palette.textPrimary)
            Text("▼ 0,7").font(.system(size: 11, weight: .semibold)).foregroundStyle(semGood(scheme))
        }
        HStack(alignment: .lastTextBaseline, spacing: 7) {
            Text("Bel").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            Text("97,0").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Palette.textPrimary)
            Text("▲ 3,0").font(.system(size: 11, weight: .semibold)).foregroundStyle(semBad(scheme))
        }
        HStack(alignment: .lastTextBaseline, spacing: 7) {
            Text("7 gün").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            Text("5.409")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(scheme == .adacayiBordo ? semGood(scheme) : Palette.textPrimary)
            Text(scheme == .sessizPirinc ? "kcal açık · planda" : "kcal açık")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: Grafik rengi

    private var grafikCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Grafik Rengi").eyebrow()
                Text("halka, trend çizgileri ve sparkline'lar — semantikten bağımsız")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Spacing.md)
                Text("açık temada koyu tonlar kullanılır")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            // 7 ton — sığacak şekilde sarmalanır (geniş 3-4'lü, dar tek kolon).
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: compact ? 200 : 230), spacing: 14, alignment: .top)],
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(ChartTint.allCases) { tint in
                    chartTile(tint, name: tint.label)
                }
            }
        }
        .padding(.init(top: 20, leading: 28, bottom: 22, trailing: 28))
        .frame(maxHeight: .infinity, alignment: .top)
        .dashboardCard()
    }

    private func chartColor(_ t: ChartTint) -> Color {
        Color(hex: t.hex(dark: isDark))
    }

    private func chartHex(_ t: ChartTint) -> String {
        "#" + String(format: "%06x", t.hex(dark: isDark))
    }

    private func chartTile(_ tint: ChartTint, name: String) -> some View {
        let selected = ThemeSettings.chart == tint
        return Button {
            ThemeSettings.chart = tint
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    selectionDot(selected)
                    Text(name)
                        .font(.system(size: 12, weight: selected ? .bold : .semibold))
                        .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                    Spacer(minLength: 0)
                    Text(chartHex(tint))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                }
                AppearanceMiniSpark(color: chartColor(tint))
            }
            .padding(.init(top: 12, leading: 16, bottom: 10, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.fieldFill))
            .overlay(selectionRing(selected))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Ortak parçalar

    private func selectionDot(_ selected: Bool) -> some View {
        Group {
            if selected {
                Circle().fill(Palette.accent)
            } else {
                Circle().strokeBorder(Palette.borderStrong, lineWidth: 1)
            }
        }
        .frame(width: 5, height: 5)
    }

    private func selectionRing(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(selected ? Palette.accent.opacity(0.65) : Palette.border, lineWidth: selected ? 1.5 : 1)
    }
}

/// Deterministik mini trend çizgisi (hafif düşen, gürültülü) + uç noktası.
private struct AppearanceMiniSpark: View {
    let color: Color

    private static let ys: [CGFloat] = [
        0.46, 0.40, 0.50, 0.38, 0.44, 0.32, 0.38, 0.28, 0.36, 0.30,
        0.42, 0.34, 0.28, 0.38, 0.31, 0.25, 0.33, 0.24, 0.30, 0.22,
        0.28, 0.19, 0.25, 0.17, 0.23, 0.15
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let points = Self.ys.enumerated().map { idx, y in
                CGPoint(x: w * CGFloat(idx) / CGFloat(Self.ys.count - 1), y: h * (y + 0.25))
            }
            ZStack {
                Path { path in
                    path.addLines(points)
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .position(last)
                }
            }
        }
        .frame(height: 36)
    }
}
