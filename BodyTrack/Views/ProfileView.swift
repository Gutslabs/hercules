import SwiftUI
import SwiftData

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

    @State private var saved = false
    @State private var hasInitialized = false

    private var latest: Measurement? { measurements.first }
    private var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
    }

    /// Yağ oranı: önce son ölçüm, sonra manuel değer.
    private var displayedBodyFat: Double? {
        latest?.bodyFat ?? manualBodyFat
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                hero
                inputsRow
                goalsSection
                WorkoutScheduleCard()
                HealthKitCard()
                AIProviderCard()
                BackupCard()
                saveBar
                Spacer(minLength: 24)
            }
            .padding(Spacing.xxl)
        }
        .background(Palette.background.ignoresSafeArea())
        .onAppear { initializeFromProfile() }
    }

    // MARK: - Hero (büyük üst kart)

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .center, spacing: Spacing.lg) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Palette.accent, Palette.accent.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .shadow(color: Palette.accent.opacity(0.4), radius: 12, y: 4)
                    Text(initial)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.black.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Adın", text: $name)
                        .textFieldStyle(.plain)
                        .font(Typography.display(32))
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(ageYears) yaş · \(Fmt.int(height)) cm")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                }

                Spacer()

                SexSwitch(sex: $sex)
            }

            Hairline()

            // Mevcut + Hedef stats — büyük, prominent
            HStack(spacing: Spacing.xl) {
                statBlock(
                    accent: Palette.accent,
                    label: "MEVCUT",
                    primary: latest?.weight.map { "\(Fmt.num($0, digits: 1)) kg" } ?? "—",
                    secondary: bodyFatLine
                )
                Divider().frame(height: 50).background(Palette.border)
                statBlock(
                    accent: Palette.positive,
                    label: "HEDEF",
                    primary: targetWeight.map { "\(Fmt.int($0)) kg" } ?? "—",
                    secondary: targetRemainingLine
                )
                Divider().frame(height: 50).background(Palette.border)
                statBlock(
                    accent: Palette.warning,
                    label: "İLERLEME",
                    primary: progressLine.value,
                    secondary: progressLine.detail
                )
                Spacer()
            }
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Palette.surface,
                            Palette.surface.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            // Subtle accent decoration
            Circle()
                .fill(Palette.accent.opacity(0.08))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: 60, y: -60)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
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

    // MARK: - Inputs

    private var inputsRow: some View {
        HStack(spacing: Spacing.md) {
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
            inputTile(label: "Hedef Ağırlık", icon: "target") {
                NumberField(value: $targetWeight, unit: "kg", digits: 0, placeholder: "—")
            }
            inputTile(label: "Manuel Yağ %", icon: "drop") {
                NumberField(
                    value: $manualBodyFat,
                    unit: "%",
                    digits: 1,
                    placeholder: latest?.bodyFat.map { "ölçüm: \(Fmt.num($0, digits: 1))" } ?? "—"
                )
            }
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
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    // MARK: - Goals

    private var goalsSection: some View {
        HStack(spacing: Spacing.md) {
            ActivityPicker(selection: $activity)
            GoalPicker(selection: $goal)
        }
    }

    // MARK: - Save

    private var saveBar: some View {
        HStack {
            if saved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.positive)
                    Text("Kaydedildi")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            PrimaryButton(title: "Profili Kaydet", systemImage: "checkmark") { save() }
                .frame(width: 200)
        }
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
        try? ctx.save()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            saved = false
        }
    }
}

// MARK: - Reusable

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
                                .fill(sex == s ? Palette.accent.opacity(0.18) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(sex == s ? Palette.accent.opacity(0.4) : Color.clear, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.accent.opacity(0.15)))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.accent.opacity(0.15)))
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
                    .fill(isToday ? Palette.accent.opacity(0.2) : (workout != nil ? Palette.surfaceElevated : Color.white.opacity(0.03)))
                    .frame(width: 28, height: 28)
                Text(WorkoutSession.weekdayShort[weekday])
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isToday ? Palette.accent : (workout != nil ? Palette.textPrimary : Palette.textTertiary))
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
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(WorkoutSession.weekdayNames[workout.weekday])
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Antrenman").eyebrow()
                TextField("ör: Sırt + Göğüs", text: $nameEdit)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tahmini Kalori").eyebrow()
                HStack(spacing: 8) {
                    TextField("300", value: $caloriesEdit, format: .number)
                        .textFieldStyle(.plain)
                        .font(Typography.monoLarge)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))
                    Text("kcal")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            HStack {
                GhostButton(title: "İptal", action: { dismiss() })
                PrimaryButton(title: "Kaydet", systemImage: "checkmark") {
                    workout.name = nameEdit.trimmingCharacters(in: .whitespaces)
                    workout.estimatedCalories = caloriesEdit
                    onDone()
                    dismiss()
                }
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 420)
        .background(Palette.background.ignoresSafeArea())
        .onAppear {
            nameEdit = workout.name
            caloriesEdit = workout.estimatedCalories
        }
    }
}

// MARK: - HealthKit card

struct HealthKitCard: View {
    @Environment(\.modelContext) private var ctx
    @StateObject private var health = HealthService.shared
    @Query(sort: \StepEntry.date, order: .reverse) private var allSteps: [StepEntry]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @State private var requesting = false
    @State private var stepInput: Int = 0
    @State private var inputFocused: Bool = false

    private var todaysEntry: StepEntry? {
        let cal = Calendar.current
        return allSteps.first { cal.isDateInToday($0.date) }
    }

    private var weight: Double {
        measurements.first?.weight ?? 80
    }

    private var todaysCalorieBurn: Double {
        guard let s = todaysEntry?.steps else { return 0 }
        return StepEntry.calorieBurn(steps: s, weightKg: weight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("Adım Sayısı").eyebrow()
                }
                Spacer()
                if case .authorized = health.status {
                    Text("HealthKit · senkron")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.positive)
                }
            }

            // Auto (HealthKit) öncelikli, yoksa manuel input
            if case .authorized = health.status {
                healthKitView
            } else {
                manualEntryView
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
        .task {
            if case .authorized = health.status { await health.refresh() }
            stepInput = todaysEntry?.steps ?? 0
        }
        .onChange(of: todaysEntry?.steps) { _, new in
            if !inputFocused, let n = new { stepInput = n }
        }
    }

    private var healthKitView: some View {
        HStack(spacing: Spacing.lg) {
            metric(label: "Adım", value: Fmt.int(Double(health.stepsToday)), unit: "")
            metric(label: "Aktif Kalori", value: Fmt.int(health.activeCaloriesToday), unit: "kcal")
            Spacer()
            Button {
                Task { await health.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.surfaceElevated))
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
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
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.accent))
                }
                .buttonStyle(.plain)
                .disabled(stepInput == (todaysEntry?.steps ?? 0))
                .opacity(stepInput == (todaysEntry?.steps ?? 0) ? 0.5 : 1)
            }
            Text("iPhone Health'inden bak ya da pedometre uygulamandan kopyala. Kalori bütçene eklenir.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func saveSteps() {
        if let entry = todaysEntry {
            entry.steps = stepInput
            entry.source = "manual"
        } else {
            let new = StepEntry(date: .now, steps: stepInput, source: "manual")
            ctx.insert(new)
        }
        try? ctx.save()
    }

    private func metric(label: String, value: String, unit: String) -> some View {
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
        }
    }
}

// MARK: - AI Provider Card

struct AIProviderCard: View {
    @State private var provider: AIProvider = AIKeyStore.shared.provider
    @State private var model: String = AIKeyStore.shared.model
    @State private var apiKey: String = ""
    @State private var codexStatus: CodexAuth.Status = .noCodexCLI
    @State private var importing = false

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
                                .fill(provider == p ? Palette.accent.opacity(0.18) : Palette.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm - 2)
                                .strokeBorder(provider == p ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 0.5)
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
        switch codexStatus {
        case .noCodexCLI:
            statusRow(icon: "exclamationmark.triangle", color: Palette.warning,
                      title: "Codex CLI bulunamadı",
                      detail: "Terminal: codex login")
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
                }
                .buttonStyle(.plain)
                .disabled(importing)
            }
        case .error(let m):
            statusRow(icon: "xmark.circle.fill", color: Palette.negative, title: "Hata", detail: m)
        }
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
        defer { importing = false }
        do {
            _ = try CodexAuth.shared.importFromCodexCLI()
            refreshCodexStatus()
            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
        } catch {
            // sessizce yut
        }
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
    @State private var statusMessage: String? = nil
    @State private var showRestoreConfirm = false
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
                    Text("~/Documents/Hercules/hercules-backup.json")
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

                Text("App silinse bile bu dosya kalır. iCloud Drive / Dropbox'a kopyala, dilediğin Mac'te geri yükle.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(action: backupNow) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Şimdi Yedekle").font(Typography.caption)
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(Palette.surfaceElevated))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm - 2).strokeBorder(Palette.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Button(action: revealInFinder) {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Finder'da Göster").font(Typography.caption)
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(Palette.surfaceElevated))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm - 2).strokeBorder(Palette.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(!BackupService.shared.backupExists)
                .opacity(BackupService.shared.backupExists ? 1 : 0.4)

                Spacer()

                Button {
                    showRestoreConfirm = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Geri Yükle").font(Typography.caption)
                    }
                    .foregroundStyle(Palette.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(Palette.warning.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm - 2).strokeBorder(Palette.warning.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(!BackupService.shared.backupExists || importing)
                .opacity(BackupService.shared.backupExists ? 1 : 0.4)
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
            try BackupService.shared.restore(from: BackupService.shared.backupURL, into: ctx, mode: .replaceAll)
            statusMessage = "✓ Geri yüklendi"
        } catch {
            statusMessage = "Hata: \(error.localizedDescription)"
        }
        refreshInfo()
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([BackupService.shared.backupURL])
    }

    private func refreshInfo() {
        lastBackup = BackupService.shared.lastBackupDate
        backupSize = BackupService.shared.backupSizeBytes
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}
