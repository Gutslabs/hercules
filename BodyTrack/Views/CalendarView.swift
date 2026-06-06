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
    @State private var editingFoodDate: FoodEntry? = nil
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
            manualOffset: profile.manualCalorieOffset,
            manualOffsetMacro: profile.manualCalorieOffsetMacro,
            manualProteinGrams: profile.manualProteinGrams,
            manualCarbsGrams: profile.manualCarbsGrams,
            manualFatGrams: profile.manualFatGrams
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
        return GeometryReader { proxy in
            let contentWidth = proxy.size.width
            let compact = contentWidth < 860
            let expansive = contentWidth >= 1500

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? Spacing.xl : Spacing.xxl) {
                    header(compact: compact)
                    statsStrip
                    calendarDesk(consumed: consumedDict)
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, compact ? Spacing.lg : (expansive ? 44 : Spacing.xxl))
                .padding(.vertical, compact ? Spacing.lg : Spacing.xxl)
            }
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
                    ctx.saveOrReport()
                    editing = nil
                },
                onDelete: {
                    ctx.delete(goal)
                    ctx.saveOrReport()
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
        .sheet(item: $editingFoodDate) { food in
            FoodDateEditorSheet(
                food: food,
                selectedDay: selectedDay,
                onSave: { newDate in
                    food.date = newDate
                    ctx.saveOrReport()
                    selectedDay = Calendar.current.startOfDay(for: newDate)
                    currentMonth = Self.startOfMonth(newDate)
                    editingFoodDate = nil
                },
                onCancel: { editingFoodDate = nil }
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

    private func header(compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    headerCopy
                    calendarTargetBadge
                }
            } else {
                HStack(alignment: .bottom, spacing: Spacing.xxxl) {
                    headerCopy
                    Spacer(minLength: Spacing.xxxl)
                    calendarTargetBadge
                        .frame(width: 360)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("BESLENME TAKİBİ").eyebrow()
            Text("Takvim")
                .font(Typography.display(42))
                .foregroundStyle(Palette.textPrimary)
            Text("Günlük kayıtları, ay içi kalori ritmini ve kilo hedeflerini tek panoda gör.")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var calendarTargetBadge: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "scope")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 5) {
                Text("GÜNLÜK HEDEF")
                    .font(Typography.label)
                    .tracking(0.8)
                    .foregroundStyle(Palette.textTertiary)
                Text("\(Fmt.int(dailyTarget)) kcal")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text(profile == nil || latestMeasurement == nil ? "Profil ve son ölçüm bekleniyor" : "Profildeki hedeften okunuyor")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.6)
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.accent.opacity(0.12))
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Hedef rotası yok")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Aylık kilo hedeflerini ekleyince takvimde hedef günleri işaretlenir.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(3)
                }
            }

            PrimaryButton(title: "Plan Oluştur", systemImage: "wand.and.stars") {
                showingSetup = true
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        let today = CalorieStats.stats(for: CalorieStats.today(), foods: allFoods, dailyTarget: dailyTarget)
        let week = CalorieStats.stats(for: CalorieStats.thisWeek(), foods: allFoods, dailyTarget: dailyTarget)
        let month = CalorieStats.stats(for: CalorieStats.thisMonth(), foods: allFoods, dailyTarget: dailyTarget)
        let last30 = CalorieStats.stats(for: CalorieStats.last(days: 30), foods: allFoods, dailyTarget: dailyTarget)

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.lg) {
                todaySpotlight(today)
                    .frame(width: 390)
                VStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.md) {
                        periodLine("Bu hafta", stats: week, mode: .total)
                        periodLine("Bu ay", stats: month, mode: .total)
                    }
                    periodLine("Son 30 gün", stats: last30, mode: .average)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                todaySpotlight(today)
                periodLine("Bu hafta", stats: week, mode: .total)
                periodLine("Bu ay", stats: month, mode: .total)
                periodLine("Son 30 gün", stats: last30, mode: .average)
            }
        }
    }

    private enum PeriodDisplayMode {
        case total, average
    }

    private func todaySpotlight(_ stats: CaloriePeriodStats) -> some View {
        let consumed = stats.totalConsumed
        let balance = consumed - dailyTarget
        let remaining = dailyTarget - consumed
        let progress = dailyTarget > 0 ? min(1, max(0, consumed / dailyTarget)) : 0
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BUGÜN").eyebrow()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Fmt.int(consumed))")
                            .font(Typography.hero(38))
                            .foregroundStyle(targetColor(consumed: consumed, target: dailyTarget))
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("kcal")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Spacing.sm)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(balanceText(balance))
                        .font(Typography.captionBold)
                        .foregroundStyle(balanceTint(balance))
                        .lineLimit(1)
                    Text(remaining >= 0 ? "\(Fmt.int(remaining)) kcal kaldı" : "\(Fmt.int(abs(remaining))) kcal geçti")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Palette.border)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(targetColor(consumed: consumed, target: dailyTarget))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)

            HStack(spacing: Spacing.md) {
                miniStat(label: "Hedef", value: "\(Fmt.int(dailyTarget))")
                miniStat(label: "Kayıt", value: "\(stats.loggedDays)")
                miniStat(label: "Net", value: Fmt.signed(balance, digits: 0))
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.7)
        )
        .overlay(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(Palette.accent)
                .frame(width: 84, height: 2)
                .padding(.leading, Spacing.lg)
        }
    }

    private func periodLine(_ title: String, stats: CaloriePeriodStats, mode: PeriodDisplayMode) -> some View {
        let primary = mode == .total
            ? "\(Fmt.int(stats.totalConsumed)) kcal"
            : "\(Fmt.signed(stats.averageDailyBalance, digits: 0)) kcal/gün"
        let subtitle = mode == .total
            ? "\(stats.loggedDays) gün kayıtlı · ort. \(Fmt.int(stats.averageDailyKcal)) kcal"
            : "toplam \(Fmt.signed(stats.netBalance, digits: 0)) · \(stats.loggedDays) gün"
        return HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased()).eyebrow()
                Text(primary)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            Text(balanceText(stats.netBalance))
                .font(Typography.captionBold)
                .foregroundStyle(balanceTint(stats.netBalance))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(balanceTint(stats.netBalance).opacity(0.12)))
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Typography.label)
                .tracking(0.8)
                .foregroundStyle(Palette.textQuaternary)
            Text(value)
                .font(Typography.mono)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func balanceText(_ balance: Double) -> String {
        if abs(balance) < 1 { return "dengeli" }
        return balance > 0 ? "+\(Fmt.int(balance)) fazla" : "\(Fmt.int(balance)) açık"
    }

    private func balanceTint(_ balance: Double) -> Color {
        if balance > 200 { return Palette.warning }
        if balance < -200 { return Palette.positive }
        return Palette.textSecondary
    }

    // MARK: - Month navigation

    private var monthNavBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) {
                monthPickerGroup
                Spacer()
                monthActionsGroup
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                monthPickerGroup
                monthActionsGroup
            }
        }
    }

    private var monthPickerGroup: some View {
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
        }
    }

    private var monthActionsGroup: some View {
        HStack(spacing: Spacing.md) {
            todayButton
            VStack(alignment: .trailing, spacing: 1) {
                Text("Günlük hedef")
                    .font(Typography.label)
                    .tracking(0.6)
                    .foregroundStyle(Palette.textQuaternary)
                Text("\(Fmt.int(dailyTarget)) kcal")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var todayButton: some View {
        Button {
            let today = Calendar.current.startOfDay(for: .now)
            currentMonth = Self.startOfMonth(.now)
            selectedDay = today
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("Bugün")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textSecondary)
            }
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

    // MARK: - Calendar desk

    private func calendarDesk(consumed: [Date: Double]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                calendarPanel(consumed: consumed)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    selectedDayDetail
                    if !goals.isEmpty {
                        monthlyGoalsStrip
                    } else {
                        emptyState
                    }
                }
                .frame(width: 390, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: Spacing.lg) {
                calendarPanel(consumed: consumed)
                selectedDayDetail
                if !goals.isEmpty {
                    monthlyGoalsStrip
                } else {
                    emptyState
                }
            }
        }
    }

    private func calendarPanel(consumed: [Date: Double]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            monthNavBar
            calendarGridBody(consumed: consumed)
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.65)
        )
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
        let remaining = dailyTarget - consumed
        let progress = dailyTarget > 0 ? min(1, max(0, consumed / dailyTarget)) : 0

        return VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: Spacing.sm) {
                        Text("SEÇİLİ GÜN").eyebrow()
                        if Calendar.current.isDateInToday(selectedDay) {
                            PillTag(text: "BUGÜN", tint: Palette.accent)
                        }
                    }
                    Text(Self.fullDayFormatter.string(from: selectedDay))
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(Fmt.int(consumed))")
                    .font(Typography.hero(36))
                    .foregroundStyle(targetColor(consumed: consumed, target: dailyTarget))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: consumed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("/ \(Fmt.int(dailyTarget)) kcal")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Palette.border)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(targetColor(consumed: consumed, target: dailyTarget))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)

            Text(remaining >= 0 ? "\(Fmt.int(remaining)) kcal alan kaldı" : "\(Fmt.int(abs(remaining))) kcal hedef üstü")
                .font(Typography.captionBold)
                .foregroundStyle(remaining >= 0 ? Palette.textSecondary : Palette.warning)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if !foods.isEmpty {
                HStack(spacing: Spacing.sm) {
                    macroChip(label: "Protein", value: p, tint: Palette.macroProtein)
                    macroChip(label: "Karb", value: c, tint: Palette.macroCarbs)
                    macroChip(label: "Yağ", value: f, tint: Palette.macroFat)
                }

                Hairline()

                VStack(spacing: 8) {
                    ForEach(foods) { entry in
                        HStack(alignment: .top, spacing: Spacing.md) {
                            Text(Self.timeFormatter.string(from: entry.date))
                                .font(Typography.mono)
                                .foregroundStyle(Palette.textTertiary)
                                .frame(width: 46, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name)
                                    .font(Typography.bodyBold)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(2)
                                foodEntryMeta(entry)
                            }
                            .layoutPriority(1)
                            Spacer(minLength: Spacing.sm)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(Fmt.int(entry.calories))")
                                    .font(Typography.mono)
                                    .foregroundStyle(Palette.textSecondary)
                                Text("kcal")
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textQuaternary)
                            }
                            .lineLimit(1)
                            .fixedSize()
                            Button {
                                editingFoodDate = entry
                            } label: {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.textTertiary)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Palette.surfaceElevated.opacity(0.75)))
                                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help("Yemeğin gününü veya saatini değiştir")
                        }
                        .contextMenu {
                            Button {
                                editingFoodDate = entry
                            } label: {
                                Label("Tarih ve Saati Değiştir", systemImage: "calendar.badge.clock")
                            }
                            Button {
                                moveFood(entry, byDays: -1)
                            } label: {
                                Label("1 Gün Geri Al", systemImage: "arrow.left")
                            }
                            Button {
                                moveFood(entry, byDays: 1)
                            } label: {
                                Label("1 Gün İleri Al", systemImage: "arrow.right")
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Kayıt yok")
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Bu güne yemek eklenince satır satır burada görünür.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.surfaceElevated.opacity(0.55))
                )
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private func foodEntryMeta(_ entry: FoodEntry) -> some View {
        let hasMacroData = entry.protein != nil || entry.carbs != nil || entry.fat != nil

        if entry.grams != nil || hasMacroData {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    foodGramText(entry)
                    if hasMacroData {
                        foodMacroBit(label: "P", value: entry.protein, tint: Palette.macroProtein)
                        foodMacroBit(label: "K", value: entry.carbs, tint: Palette.macroCarbs)
                        foodMacroBit(label: "Y", value: entry.fat, tint: Palette.macroFat)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    foodGramText(entry)
                    if hasMacroData {
                        HStack(spacing: 8) {
                            foodMacroBit(label: "P", value: entry.protein, tint: Palette.macroProtein)
                            foodMacroBit(label: "K", value: entry.carbs, tint: Palette.macroCarbs)
                            foodMacroBit(label: "Y", value: entry.fat, tint: Palette.macroFat)
                        }
                    }
                }
            }
        } else {
            Text("Makro yok")
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
        }
    }

    @ViewBuilder
    private func foodGramText(_ entry: FoodEntry) -> some View {
        if let g = entry.grams {
            Text("\(Fmt.int(g))g")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func foodMacroBit(label: String, value: Double?, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 4, height: 4)
            Text("\(label) \(value.map { Fmt.int($0) } ?? "-")g")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
    }

    private func moveFood(_ entry: FoodEntry, byDays days: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: entry.date) else { return }
        entry.date = newDate
        ctx.saveOrReport()
        selectedDay = Calendar.current.startOfDay(for: newDate)
        currentMonth = Self.startOfMonth(newDate)
    }

    private func macroChip(label: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text("\(label) \(Fmt.int(value))g")
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Monthly goals strip

    private var monthlyGoalsStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hedef rotası").eyebrow()
                Spacer()
                Text("\(goals.count) hedef")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(goals.enumerated()), id: \.element.id) { idx, g in
                        GoalRoadmapRow(
                            goal: g,
                            index: idx + 1,
                            isReached: g.anchorDate <= .now,
                            currentWeight: currentWeight
                        ) {
                            // Satıra tıkla → düzenle (kilo/tarih/not/sil).
                            editing = g
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 360)
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.55)
        )
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
        ctx.saveOrReport()
    }

    private func clearAll() {
        let toDelete = Array(goals)
        for g in toDelete { ctx.delete(g) }
        ctx.saveOrReport()
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

    static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    static let weekdayHeaders: [String] = ["PZT", "SAL", "ÇAR", "PER", "CUM", "CMT", "PAZ"]

    static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM EEEE"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - DayCell (calendar grid)
