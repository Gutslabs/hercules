import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \MonthlyGoal.anchorDate) private var goals: [MonthlyGoal]
    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodEntry.date, order: .reverse) private var allFoods: [FoodEntry]

    @State private var showingSetup = false
    @State private var editing: MonthlyGoal? = nil
    @State private var showingClearConfirm = false
    @State private var currentMonth: Date = Self.startOfMonth(.now)
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)

    private var profile: UserProfile? { profiles.first }
    private var latestMeasurement: Measurement? { measurements.first }
    private var currentWeight: Double? { latestMeasurement?.weight }

    /// Bütün takvim günleri için kullanılacak tek günlük kalori hedefi.
    /// Profil + son ölçüm + (varsa) ek değişkenlerden CalorieCalculator ile üretiyoruz.
    private var dailyTarget: Double {
        guard let profile, let weight = currentWeight else { return 2000 }
        let bf = latestMeasurement?.bodyFat ?? profile.manualBodyFat
        let result = CalorieCalculator.compute(
            weight: weight,
            height: profile.height,
            age: profile.age,
            sex: profile.sex,
            bodyFat: bf,
            activity: profile.activity,
            goal: profile.goal,
            manualOffset: profile.manualCalorieOffset
        )
        return result.goalCalories
    }

    /// Tüm allFoods'u tek pass'te startOfDay → toplam kcal dict'ine indir.
    /// 42 hücrelik grid render başına 42 kez filter yerine tek scan + O(1) lookup.
    private var consumedByDay: [Date: Double] {
        let cal = Calendar.current
        var dict: [Date: Double] = [:]
        for f in allFoods {
            let key = cal.startOfDay(for: f.date)
            dict[key, default: 0] += f.calories
        }
        return dict
    }

    var body: some View {
        let consumedDict = consumedByDay
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                statsStrip
                monthNavBar
                calendarGridBody(consumed: consumedDict)
                selectedDayDetail
                if !goals.isEmpty {
                    monthlyGoalsStrip
                } else {
                    emptyState
                }
                Spacer(minLength: 24)
            }
            .padding(Spacing.xxl)
        }
        .toolbar {
            if !goals.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showingClearConfirm = true
                    } label: {
                        Label("Sıfırla", systemImage: "trash")
                    }
                    .help("Tüm aylık hedefleri sil")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingSetup = true } label: {
                    Label(goals.isEmpty ? "Plan Oluştur" : "Yeni Plan",
                          systemImage: goals.isEmpty ? "plus" : "arrow.clockwise")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help(goals.isEmpty ? "Aylık plan oluştur (⌘N)" : "Mevcut planı değiştir (⌘N)")
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .sheet(isPresented: $showingSetup) {
            PlanSetupSheet(
                startWeight: currentWeight ?? 80,
                onCreate: { plan in
                    applyPlan(plan)
                    showingSetup = false
                },
                onCancel: { showingSetup = false }
            )
        }
        .sheet(item: $editing) { goal in
            GoalEditorSheet(
                goal: goal,
                onSave: {
                    try? ctx.save()
                    editing = nil
                },
                onDelete: {
                    ctx.delete(goal)
                    try? ctx.save()
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
        .alert("Tüm hedefleri sil?", isPresented: $showingClearConfirm) {
            Button("İptal", role: .cancel) { }
            Button("Hepsini Sil", role: .destructive) { clearAll() }
        } message: {
            Text("Bu işlem geri alınamaz. Yeni bir plan oluşturmak için yeniden kuracaksın.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Takvim").eyebrow()
            Text("Aylık Hedefler")
                .font(Typography.display(40))
                .foregroundStyle(Palette.textPrimary)
            Text("Her ay için kilo hedefi koy, gidişatı takip et.")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Palette.accent)
            }
            VStack(spacing: 6) {
                Text("Henüz plan yok")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Text("12 aylık takvim oluştur, her ayın hedefini belirle.\nÖrnek: 8 Mayıs · 94 kg → 8 Haziran · 90 kg")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: "Plan Oluştur", systemImage: "wand.and.stars") {
                showingSetup = true
            }
            .frame(width: 220)
        }
        .padding(Spacing.xxxl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        let today = CalorieStats.stats(for: CalorieStats.today(), foods: allFoods, dailyTarget: dailyTarget)
        let week = CalorieStats.stats(for: CalorieStats.thisWeek(), foods: allFoods, dailyTarget: dailyTarget)
        let month = CalorieStats.stats(for: CalorieStats.thisMonth(), foods: allFoods, dailyTarget: dailyTarget)
        let last30 = CalorieStats.stats(for: CalorieStats.last(days: 30), foods: allFoods, dailyTarget: dailyTarget)

        return HStack(spacing: Spacing.md) {
            statCard(
                eyebrow: "Bugün",
                primary: "\(Fmt.int(today.totalConsumed)) kcal",
                secondaryLeft: "/ \(Fmt.int(dailyTarget))",
                balance: today.netBalance,
                detail: "hedef günlük"
            )
            statCard(
                eyebrow: "Bu Hafta",
                primary: "\(Fmt.int(week.totalConsumed)) kcal",
                secondaryLeft: "\(week.loggedDays) gün",
                balance: week.netBalance,
                detail: "ort. \(Fmt.int(week.averageDailyKcal))/gün"
            )
            statCard(
                eyebrow: "Bu Ay",
                primary: "\(Fmt.int(month.totalConsumed)) kcal",
                secondaryLeft: "\(month.loggedDays) gün",
                balance: month.netBalance,
                detail: "ort. \(Fmt.int(month.averageDailyKcal))/gün"
            )
            statCard(
                eyebrow: "Son 30 Gün",
                primary: "\(Fmt.signed(last30.averageDailyBalance, digits: 0)) kcal/gün",
                secondaryLeft: "ort. net",
                balance: last30.netBalance,
                detail: "toplam \(Fmt.signed(last30.netBalance, digits: 0))"
            )
        }
    }

    private func statCard(
        eyebrow: String,
        primary: String,
        secondaryLeft: String,
        balance: Double,
        detail: String
    ) -> some View {
        let balanceTint: Color = {
            if balance > 200 { return Palette.warning }
            if balance < -200 { return Palette.positive }
            return Palette.textSecondary
        }()
        let balanceLabel: String = {
            if balance > 0 { return "+\(Fmt.int(balance)) fazla" }
            if balance < 0 { return "\(Fmt.int(balance)) açık" }
            return "dengeli"
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(eyebrow.uppercased()).eyebrow()
                Spacer(minLength: 0)
            }
            Text(primary)
                .font(Typography.hero(20))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.snappy, value: primary)
            HStack(spacing: 6) {
                Text(secondaryLeft)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
                Text(balanceLabel)
                    .font(Typography.captionBold)
                    .foregroundStyle(balanceTint)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: balanceLabel)
            }
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
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

    // MARK: - Month navigation

    private var monthNavBar: some View {
        HStack(spacing: Spacing.md) {
            navButton(icon: "chevron.left") { jumpMonth(by: -1) }
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.monthTitleFormatter.string(from: currentMonth))
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Text("\(daysInMonthLogged) gün kayıtlı · ort. \(Fmt.int(monthAverageKcal)) kcal")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            navButton(icon: "chevron.right") { jumpMonth(by: 1) }

            Spacer()

            // "Bugün"
            Button {
                let today = Calendar.current.startOfDay(for: .now)
                currentMonth = Self.startOfMonth(.now)
                selectedDay = today
            } label: {
                Text("Bugün")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .trailing, spacing: 1) {
                Text("Günlük hedef")
                    .font(Typography.label)
                    .tracking(0.6)
                    .foregroundStyle(Palette.textQuaternary)
                Text("\(Fmt.int(dailyTarget)) kcal")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calendar grid

    /// Grid hesaplamasını body'de pre-build edilmiş `consumed` dict üzerinden yap.
    private func calendarGridBody(consumed: [Date: Double]) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let cal = Calendar.current
        return VStack(spacing: 6) {
            // Weekday headers
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Self.weekdayHeaders, id: \.self) { wd in
                    Text(wd)
                        .font(Typography.label)
                        .tracking(0.8)
                        .foregroundStyle(Palette.textQuaternary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            // Day cells
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(monthGridDays(), id: \.self) { date in
                    DayCell(
                        date: date,
                        inMonth: cal.isDate(date, equalTo: currentMonth, toGranularity: .month),
                        isToday: cal.isDateInToday(date),
                        isSelected: cal.isDate(date, inSameDayAs: selectedDay),
                        consumed: consumed[cal.startOfDay(for: date)] ?? 0,
                        target: dailyTarget,
                        monthlyGoal: goalAnchored(on: date),
                        onTap: {
                            selectedDay = cal.startOfDay(for: date)
                            if !cal.isDate(date, equalTo: currentMonth, toGranularity: .month) {
                                currentMonth = Self.startOfMonth(date)
                            }
                        },
                        onGoalTap: { goal in
                            editing = goal
                        }
                    )
                }
            }
        }
    }

    // MARK: - Selected day detail

    private var selectedDayDetail: some View {
        let foods = foodsFor(day: selectedDay)
        let consumed = foods.reduce(0) { $0 + $1.calories }
        let p = foods.compactMap(\.protein).reduce(0, +)
        let c = foods.compactMap(\.carbs).reduce(0, +)
        let f = foods.compactMap(\.fat).reduce(0, +)

        return Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.fullDayFormatter.string(from: selectedDay))
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                    if Calendar.current.isDateInToday(selectedDay) {
                        PillTag(text: "Bugün", tint: Palette.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(Fmt.int(consumed))")
                            .font(Typography.hero(26))
                            .foregroundStyle(targetColor(consumed: consumed, target: dailyTarget))
                            .contentTransition(.numericText())
                            .animation(.snappy, value: consumed)
                        Text("/ \(Fmt.int(dailyTarget)) kcal")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                if !foods.isEmpty {
                    HStack(spacing: Spacing.lg) {
                        macroChip(label: "Protein", value: p, tint: Palette.macroProtein)
                        macroChip(label: "Karb", value: c, tint: Palette.macroCarbs)
                        macroChip(label: "Yağ", value: f, tint: Palette.macroFat)
                        Spacer()
                    }
                    Hairline()
                    VStack(spacing: 6) {
                        ForEach(foods) { entry in
                            HStack(spacing: Spacing.md) {
                                Text(Self.timeFormatter.string(from: entry.date))
                                    .font(Typography.mono)
                                    .foregroundStyle(Palette.textTertiary)
                                    .frame(width: 56, alignment: .leading)
                                if let g = entry.grams {
                                    Text("\(Fmt.int(g))g")
                                        .font(Typography.mono)
                                        .foregroundStyle(Palette.textSecondary)
                                        .frame(width: 60, alignment: .leading)
                                }
                                Text(entry.name)
                                    .font(Typography.body)
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Text("\(Fmt.int(entry.calories)) kcal")
                                    .font(Typography.mono)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                } else {
                    Text("Bu gün için kayıt yok.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private func macroChip(label: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text("\(label) \(Fmt.int(value))g")
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: - Monthly goals strip

    private var monthlyGoalsStrip: some View {
        Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Aylık hedefler").eyebrow()
                    Spacer()
                    Text("\(goals.count) hedef")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(goals.enumerated()), id: \.element.id) { idx, g in
                            GoalChip(
                                goal: g,
                                index: idx + 1,
                                isReached: g.anchorDate <= .now,
                                currentWeight: currentWeight
                            ) {
                                currentMonth = Self.startOfMonth(g.anchorDate)
                                selectedDay = Calendar.current.startOfDay(for: g.anchorDate)
                            }
                        }
                    }
                }
            }
        }
    }

    private func applyPlan(_ plan: PlanSetupSheet.Plan) {
        // Mevcut hedefleri temizle (önce snapshot al — @Query array mutate ediliyor)
        let toDelete = Array(goals)
        for g in toDelete { ctx.delete(g) }

        let cal = Calendar.current
        let startDay = cal.startOfDay(for: plan.startDate)
        for i in 1...plan.months {
            guard let anchor = cal.date(byAdding: .month, value: i, to: startDay) else { continue }
            let target: Double
            if let firstTarget = plan.firstMonthTarget, plan.months > 1 {
                if i == 1 {
                    target = firstTarget
                } else {
                    let progress = Double(i - 1) / Double(plan.months - 1)
                    target = firstTarget + (plan.endWeight - firstTarget) * progress
                }
            } else if let firstTarget = plan.firstMonthTarget {
                // Tek ay → ilk ay = final
                target = firstTarget
            } else {
                let progress = Double(i) / Double(plan.months)
                target = plan.startWeight + (plan.endWeight - plan.startWeight) * progress
            }
            let goal = MonthlyGoal(anchorDate: anchor, targetWeight: roundToHalf(target))
            ctx.insert(goal)
        }
        try? ctx.save()
    }

    private func clearAll() {
        let toDelete = Array(goals)
        for g in toDelete { ctx.delete(g) }
        try? ctx.save()
    }

    private func roundToHalf(_ v: Double) -> Double {
        (v * 2).rounded() / 2
    }

    // MARK: - Calendar grid helpers

    /// 7 × 6 grid of dates that cover `currentMonth`. Includes leading/trailing
    /// days from the adjacent months so the grid is always a full block.
    private func monthGridDays() -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday-first
        cal.locale = Locale(identifier: "tr_TR")

        guard let interval = cal.dateInterval(of: .month, for: currentMonth) else { return [] }
        let monthStart = interval.start
        let weekday = cal.component(.weekday, from: monthStart)
        let leadingOffset = (weekday - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -leadingOffset, to: monthStart) else { return [] }

        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func jumpMonth(by step: Int) {
        guard let new = Calendar.current.date(byAdding: .month, value: step, to: currentMonth) else { return }
        currentMonth = Self.startOfMonth(new)
    }

    private func consumedKcal(for date: Date) -> Double {
        let cal = Calendar.current
        return allFoods.filter { cal.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.calories }
    }

    private func foodsFor(day: Date) -> [FoodEntry] {
        let cal = Calendar.current
        return allFoods.filter { cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    private func goalAnchored(on date: Date) -> MonthlyGoal? {
        goals.first { Calendar.current.isDate($0.anchorDate, inSameDayAs: date) }
    }

    private var daysInMonthLogged: Int {
        let cal = Calendar.current
        return monthGridDays().filter {
            cal.isDate($0, equalTo: currentMonth, toGranularity: .month) && consumedKcal(for: $0) > 0
        }.count
    }

    private var monthAverageKcal: Double {
        let cal = Calendar.current
        let logged = monthGridDays()
            .filter { cal.isDate($0, equalTo: currentMonth, toGranularity: .month) }
            .map { consumedKcal(for: $0) }
            .filter { $0 > 0 }
        guard !logged.isEmpty else { return 0 }
        return logged.reduce(0, +) / Double(logged.count)
    }

    fileprivate func targetColor(consumed: Double, target: Double) -> Color {
        guard target > 0 else { return Palette.textPrimary }
        if consumed == 0 { return Palette.textTertiary }
        let ratio = consumed / target
        if ratio < 0.85 { return Palette.macroCarbs }
        if ratio <= 1.10 { return Palette.positive }
        if ratio <= 1.30 { return Palette.warning }
        return Palette.accent
    }

    fileprivate static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    fileprivate static let weekdayHeaders: [String] = ["PZT", "SAL", "ÇAR", "PER", "CUM", "CMT", "PAZ"]

    fileprivate static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    fileprivate static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM EEEE"
        return f
    }()

    fileprivate static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - DayCell (calendar grid)

private struct DayCell: View {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let consumed: Double
    let target: Double
    let monthlyGoal: MonthlyGoal?
    let onTap: () -> Void
    let onGoalTap: (MonthlyGoal) -> Void

    @State private var hovering = false

    private var dayNumber: String {
        Fmt.dayNumber.string(from: date)
    }

    private var ratio: Double {
        guard target > 0 else { return 0 }
        return min(1.0, consumed / target)
    }

    private var barColor: Color {
        guard target > 0, consumed > 0 else { return Palette.border }
        let r = consumed / target
        if r < 0.85 { return Palette.macroCarbs }
        if r <= 1.10 { return Palette.positive }
        if r <= 1.30 { return Palette.warning }
        return Palette.accent
    }

    private var consumedColor: Color {
        guard consumed > 0 else { return Palette.textQuaternary }
        return Palette.textPrimary
    }

    private var borderColor: Color {
        if isSelected { return Palette.borderStrong }
        if isToday { return Palette.accent.opacity(0.55) }
        return Palette.border
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(dayNumber)
                        .font(Typography.bodyBold)
                        .foregroundStyle(isToday ? Palette.accent : (inMonth ? Palette.textPrimary : Palette.textQuaternary))
                    if isToday {
                        Text("BUGÜN")
                            .font(.system(size: 8.5, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.accent.opacity(0.14)))
                    }
                    Spacer(minLength: 0)
                    if let g = monthlyGoal {
                        Button { onGoalTap(g) } label: {
                            Text("\(Fmt.num(g.targetWeight, digits: 1)) kg")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Palette.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Palette.surfaceElevated))
                                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        if consumed > 0 {
                            Text("\(Fmt.int(consumed))")
                                .font(.system(size: 14, weight: .medium, design: .default))
                                .monospacedDigit()
                                .foregroundStyle(consumedColor)
                        } else {
                            Text("—")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Palette.textQuaternary)
                        }
                        Text("kcal")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textQuaternary)
                    }
                    // mini progress
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Palette.border)
                                .frame(height: 2.5)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(barColor)
                                .frame(width: max(0, geo.size.width * ratio), height: 2.5)
                        }
                    }
                    .frame(height: 2.5)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? Palette.surfaceElevated : (hovering ? Palette.surface.opacity(0.7) : Palette.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isToday && !isSelected ? 1.0 : 0.5)
            )
            .opacity(inMonth ? 1.0 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - GoalChip (monthly goal scroller)

private struct GoalChip: View {
    let goal: MonthlyGoal
    let index: Int
    let isReached: Bool
    let currentWeight: Double?
    let onTap: () -> Void
    @State private var hovering = false

    private var monthLabel: String {
        Fmt.monthShort.string(from: goal.anchorDate).uppercased()
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text("\(index). AY")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Palette.textQuaternary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(monthLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                    Text("\(Fmt.num(goal.targetWeight, digits: 1)) kg")
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                }
                if let w = currentWeight {
                    let diff = w - goal.targetWeight
                    Text(diff > 0 ? "−\(Fmt.num(diff, digits: 1))" : "+\(Fmt.num(abs(diff), digits: 1))")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(hovering ? Palette.surfaceElevated : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}


// MARK: - Plan setup sheet

struct PlanSetupSheet: View {
    struct Plan {
        var startDate: Date
        var startWeight: Double
        var endWeight: Double
        var months: Int
        /// nil ise eşit dağıtım. Doluysa: ilk ay bu kiloya iner, sonraki aylar firstMonthTarget→endWeight arası eşit dağıtılır.
        var firstMonthTarget: Double?
    }

    enum PaceMode: String, CaseIterable {
        case even, customFirst
        var label: String {
            switch self {
            case .even: return "Eşit Dağıt"
            case .customFirst: return "İlk Ay Özel"
            }
        }
        var detail: String {
            switch self {
            case .even: return "Her ay aynı miktar"
            case .customFirst: return "İlk ay farklı, sonrası eşit"
            }
        }
    }

    let startWeight: Double
    let onCreate: (Plan) -> Void
    let onCancel: () -> Void

    @State private var startDate: Date = .now
    @State private var startWeightInput: Double
    @State private var endWeightInput: Double
    @State private var monthsInput: Int = 12
    @State private var paceMode: PaceMode = .even
    @State private var firstMonthTarget: Double = 0
    @State private var firstMonthTargetEdited: Bool = false

    init(startWeight: Double, onCreate: @escaping (Plan) -> Void, onCancel: @escaping () -> Void) {
        self.startWeight = startWeight
        self.onCreate = onCreate
        self.onCancel = onCancel
        _startWeightInput = State(initialValue: startWeight)
        _endWeightInput = State(initialValue: max(50, startWeight - 12))
    }

    private var totalDelta: Double { endWeightInput - startWeightInput }
    private var perMonth: Double { totalDelta / Double(max(1, monthsInput)) }
    private var perWeek: Double { perMonth / 4.345 }

    /// Linear projection ile ilk ayın varsayılan hedef kilosu.
    private var defaultFirstMonthTarget: Double {
        startWeightInput + totalDelta / Double(max(1, monthsInput))
    }

    private var firstMonthDelta: Double {
        if paceMode == .customFirst {
            return firstMonthTarget - startWeightInput
        }
        return perMonth
    }

    private var subsequentMonthDelta: Double {
        if paceMode == .customFirst, monthsInput > 1 {
            let remaining = endWeightInput - firstMonthTarget
            return remaining / Double(monthsInput - 1)
        }
        return perMonth
    }

    private var subsequentPerWeek: Double { subsequentMonthDelta / 4.345 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Başlangıç tarihi", selection: $startDate, displayedComponents: .date)
                    LabeledContent("Başlangıç (kg)") {
                        TextField("", value: $startWeightInput, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    LabeledContent("Final hedef (kg)") {
                        TextField("", value: $endWeightInput, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                } header: {
                    Text("Plan")
                } footer: {
                    Text("Başlangıç ve final kilonu gir; ayları doğrusal böler, sonradan tek tek düzenleyebilirsin.")
                        .font(Typography.caption)
                }

                Section("Süre") {
                    Stepper(value: $monthsInput, in: 1...36) {
                        LabeledContent("Ay sayısı") {
                            Text("\(monthsInput)")
                                .font(Typography.mono)
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach([3, 6, 12], id: \.self) { m in
                            Button("\(m) ay") { monthsInput = m }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(monthsInput == m ? Palette.accent : Palette.textSecondary)
                        }
                        Spacer()
                    }
                }

                Section("Tempo") {
                    Picker("Mod", selection: $paceMode) {
                        ForEach(PaceMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(paceMode.detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)

                    if paceMode == .customFirst {
                        LabeledContent("İlk ay sonu (kg)") {
                            TextField("", value: Binding(
                                get: { firstMonthTarget },
                                set: { firstMonthTarget = $0; firstMonthTargetEdited = true }
                            ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                Section("Önizleme") {
                    LabeledContent("Toplam değişim") {
                        Text("\(Fmt.signed(totalDelta, digits: 1)) kg")
                            .font(Typography.mono)
                    }
                    if paceMode == .customFirst {
                        LabeledContent("İlk ay") {
                            Text("\(Fmt.signed(firstMonthDelta, digits: 1)) kg")
                                .font(Typography.mono)
                        }
                        LabeledContent("Sonraki aylar") {
                            Text("\(Fmt.signed(subsequentMonthDelta, digits: 2)) kg / ay")
                                .font(Typography.mono)
                        }
                    } else {
                        LabeledContent("Aylık tempo") {
                            Text("\(Fmt.signed(perMonth, digits: 2)) kg")
                                .font(Typography.mono)
                        }
                        LabeledContent("Haftalık tempo") {
                            Text("\(Fmt.signed(perWeek, digits: 2)) kg")
                                .font(Typography.mono)
                        }
                    }
                    if let warning = paceWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.warning)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Plan Oluştur")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Planı Oluştur") {
                        onCreate(Plan(
                            startDate: startDate,
                            startWeight: startWeightInput,
                            endWeight: endWeightInput,
                            months: monthsInput,
                            firstMonthTarget: paceMode == .customFirst ? firstMonthTarget : nil
                        ))
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 560, height: 680)
        .onChange(of: paceMode) { _, newMode in
            if newMode == .customFirst, !firstMonthTargetEdited {
                firstMonthTarget = roundedHalf(defaultFirstMonthTarget)
            }
        }
        .onChange(of: monthsInput) { _, _ in
            if !firstMonthTargetEdited {
                firstMonthTarget = roundedHalf(defaultFirstMonthTarget)
            }
        }
        .onChange(of: startWeightInput) { _, _ in
            if !firstMonthTargetEdited {
                firstMonthTarget = roundedHalf(defaultFirstMonthTarget)
            }
        }
        .onChange(of: endWeightInput) { _, _ in
            if !firstMonthTargetEdited {
                firstMonthTarget = roundedHalf(defaultFirstMonthTarget)
            }
        }
    }

    private func roundedHalf(_ v: Double) -> Double {
        (v * 2).rounded() / 2
    }

    private var paceModePicker: some View {
        HStack(spacing: 6) {
            ForEach(PaceMode.allCases, id: \.self) { mode in
                Button {
                    paceMode = mode
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.label)
                            .font(Typography.bodyBold)
                            .foregroundStyle(paceMode == mode ? Palette.textPrimary : Palette.textSecondary)
                        Text(mode.detail)
                            .font(Typography.caption)
                            .foregroundStyle(paceMode == mode ? Palette.textSecondary : Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(paceMode == mode ? Color.white.opacity(0.07) : Palette.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(paceMode == mode ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var monthsPicker: some View {
        HStack(spacing: Spacing.sm) {
            stepperControl
            HStack(spacing: 6) {
                ForEach([3, 6, 12], id: \.self) { m in
                    Button {
                        monthsInput = m
                    } label: {
                        Text("\(m)")
                            .font(Typography.captionBold)
                            .foregroundStyle(monthsInput == m ? Palette.textPrimary : Palette.textSecondary)
                            .frame(width: 32, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                    .fill(monthsInput == m ? Color.white.opacity(0.07) : Palette.surfaceElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                    .strokeBorder(monthsInput == m ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var stepperControl: some View {
        HStack(spacing: 0) {
            stepperButton(systemImage: "minus", enabled: monthsInput > 1) {
                if monthsInput > 1 { monthsInput -= 1 }
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                TextField("", value: Binding(
                    get: { monthsInput },
                    set: { monthsInput = max(1, min(36, $0)) }
                ), format: .number)
                    .textFieldStyle(.plain)
                    .font(Typography.monoLarge)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                Text("ay")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)

            stepperButton(systemImage: "plus", enabled: monthsInput < 36) {
                if monthsInput < 36 { monthsInput += 1 }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func stepperButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? Palette.textPrimary : Palette.textQuaternary)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Önizleme").eyebrow()
            HStack(spacing: Spacing.lg) {
                previewStat(label: "Toplam", value: "\(Fmt.signed(totalDelta, digits: 1)) kg")
                Divider().frame(height: 32).background(Palette.border)
                if paceMode == .customFirst {
                    previewStat(label: "İlk Ay", value: "\(Fmt.signed(firstMonthDelta, digits: 1)) kg")
                    Divider().frame(height: 32).background(Palette.border)
                    previewStat(label: "Sonraki Ay", value: "\(Fmt.signed(subsequentMonthDelta, digits: 2)) kg")
                } else {
                    previewStat(label: "Aylık", value: "\(Fmt.signed(perMonth, digits: 2)) kg")
                    Divider().frame(height: 32).background(Palette.border)
                    previewStat(label: "Haftalık", value: "\(Fmt.signed(perWeek, digits: 2)) kg")
                }
                Spacer()
            }
            if let warning = paceWarning {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.warning)
                    Text(warning)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.warning)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var paceWarning: String? {
        if paceMode == .customFirst {
            // İlk ay totalDelta'yı geçtiyse / yön ters dönüyorsa uyarı
            if totalDelta != 0, firstMonthDelta != 0,
               firstMonthDelta.sign != totalDelta.sign {
                return "İlk ay yönü genel hedefin tersine. Final hedefe ulaşmak için sonraki aylarda tempo artar."
            }
            if abs(firstMonthDelta) > abs(totalDelta) {
                return "İlk ay değişimi toplam hedefi aşıyor. Sonraki aylar ters yönde ilerler."
            }
            if abs(firstMonthDelta / 4.345) > 1.0 {
                return "İlk hafta 1 kg üstü tempo agresif olabilir."
            }
            if abs(subsequentPerWeek) > 1.0 {
                return "Sonraki haftalarda 1 kg üstü tempo agresif olabilir."
            }
        } else {
            if abs(perWeek) > 1.0 {
                return "Haftalık 1 kg üstü tempo agresif olabilir."
            }
        }
        return nil
    }

    private func previewStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow()
            Text(value)
                .font(Typography.monoLarge)
                .foregroundStyle(Palette.textPrimary)
        }
    }
}

// MARK: - Goal editor sheet

struct GoalEditorSheet: View {
    @Bindable var goal: MonthlyGoal
    let onSave: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var weightInput: Double
    @State private var dateInput: Date
    @State private var noteInput: String
    @State private var showDeleteConfirm = false

    init(
        goal: MonthlyGoal,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.goal = goal
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _weightInput = State(initialValue: goal.targetWeight)
        _dateInput = State(initialValue: goal.anchorDate)
        _noteInput = State(initialValue: goal.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hedef") {
                    DatePicker("Tarih", selection: $dateInput, displayedComponents: .date)
                    LabeledContent("Hedef kilo (kg)") {
                        TextField("", value: $weightInput, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                Section("Not") {
                    TextField("ör: yaza hazır", text: $noteInput, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Aylık Hedef")
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        goal.targetWeight = weightInput
                        goal.anchorDate = dateInput
                        let trimmed = noteInput.trimmingCharacters(in: .whitespaces)
                        goal.note = trimmed.isEmpty ? nil : trimmed
                        onSave()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 460, height: 380)
        .alert("Hedefi sil?", isPresented: $showDeleteConfirm) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) { onDelete() }
        }
    }
}
