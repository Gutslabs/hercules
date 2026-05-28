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
        .sheet(item: $editingFoodDate) { food in
            FoodDateEditorSheet(
                food: food,
                selectedDay: selectedDay,
                onSave: { newDate in
                    food.date = newDate
                    try? ctx.save()
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
                        Text("kcal")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(balanceText(balance))
                        .font(Typography.captionBold)
                        .foregroundStyle(balanceTint(balance))
                    Text(remaining >= 0 ? "\(Fmt.int(remaining)) kcal kaldı" : "\(Fmt.int(abs(remaining))) kcal geçti")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
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
                Text("/ \(Fmt.int(dailyTarget)) kcal")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
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
                            Text("\(Fmt.int(entry.calories))")
                                .font(Typography.mono)
                                .foregroundStyle(Palette.textSecondary)
                            Text("kcal")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textQuaternary)
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
        try? ctx.save()
        selectedDay = Calendar.current.startOfDay(for: newDate)
        currentMonth = Self.startOfMonth(newDate)
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
                            currentMonth = Self.startOfMonth(g.anchorDate)
                            selectedDay = Calendar.current.startOfDay(for: g.anchorDate)
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

    private var hasFood: Bool {
        consumed > 0
    }

    private var barColor: Color {
        guard target > 0, consumed > 0 else { return Palette.border }
        let r = consumed / target
        if r < 0.85 { return Palette.macroCarbs }
        if r <= 1.10 { return Palette.positive }
        if r <= 1.30 { return Palette.warning }
        return Palette.accent
    }

    private var dayColor: Color {
        if isToday { return Palette.accent }
        if inMonth { return Palette.textPrimary }
        return Palette.textQuaternary
    }

    private var borderColor: Color {
        if isSelected { return Palette.accent.opacity(0.62) }
        if isToday { return Palette.accent.opacity(0.55) }
        if hovering { return Palette.borderStrong }
        return Palette.border.opacity(inMonth ? 1 : 0.65)
    }

    private var fillColor: Color {
        if isSelected { return Palette.surfaceElevated.opacity(0.92) }
        if hovering { return Palette.surfaceElevated.opacity(0.72) }
        return Palette.surface.opacity(inMonth ? 0.70 : 0.34)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: 6) {
                    Text(dayNumber)
                        .font(.system(size: isToday ? 15 : 13, weight: isToday ? .semibold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(dayColor)

                    if isToday {
                        Text("BUGÜN")
                            .font(.system(size: 8.5, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.accent.opacity(0.14)))
                    }
                }

                Spacer(minLength: 0)

                if let g = monthlyGoal {
                    Button { onGoalTap(g) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "scope")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("\(Fmt.num(g.targetWeight, digits: 1)) kg")
                                .font(.system(size: 9.5, weight: .medium))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.surfaceElevated.opacity(0.78)))
                        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        if hasFood {
                            Text("\(Fmt.int(consumed))")
                                .font(.system(size: 14, weight: .medium, design: .default))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
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
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Palette.accent)
                        .frame(width: 2.5)
                        .padding(.vertical, 10)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected || isToday ? 0.85 : 0.5)
            )
            .opacity(inMonth ? 1.0 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.004 : 1)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct GoalRoadmapRow: View {
    let goal: MonthlyGoal
    let index: Int
    let isReached: Bool
    let currentWeight: Double?
    let onTap: () -> Void
    @State private var hovering = false

    private var monthLabel: String {
        Fmt.monthShort.string(from: goal.anchorDate).uppercased()
    }

    private var deltaText: String? {
        guard let currentWeight else { return nil }
        let diff = currentWeight - goal.targetWeight
        if abs(diff) < 0.05 { return "hedefte" }
        return diff > 0 ? "−\(Fmt.num(diff, digits: 1)) kg" : "+\(Fmt.num(abs(diff), digits: 1)) kg"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(isReached ? Palette.positive.opacity(0.16) : Palette.surfaceElevated)
                    Text("\(index)")
                        .font(Typography.captionBold)
                        .foregroundStyle(isReached ? Palette.positive : Palette.textSecondary)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(monthLabel)
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.textTertiary)
                        if isReached {
                            Text("GEÇTİ")
                                .font(.system(size: 8.5, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Palette.positive)
                        }
                    }
                    Text("\(Fmt.num(goal.targetWeight, digits: 1)) kg")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                }

                Spacer(minLength: Spacing.sm)

                if let deltaText {
                    Text(deltaText)
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(hovering ? Palette.surfaceElevated.opacity(0.76) : Palette.surface.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(hovering ? Palette.borderStrong : Palette.border, lineWidth: 0.55)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.004 : 1)
        .animation(.easeOut(duration: 0.16), value: hovering)
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

// MARK: - Food date editor sheet

struct FoodDateEditorSheet: View {
    let food: FoodEntry
    let selectedDay: Date
    let onSave: (Date) -> Void
    let onCancel: () -> Void

    @State private var dateInput: Date

    init(
        food: FoodEntry,
        selectedDay: Date,
        onSave: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.food = food
        self.selectedDay = selectedDay
        self.onSave = onSave
        self.onCancel = onCancel
        _dateInput = State(initialValue: food.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Yemek") {
                    LabeledContent("Kayıt") {
                        Text(food.name)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                    LabeledContent("Kalori") {
                        Text("\(Fmt.int(food.calories)) kcal")
                    }
                }

                Section("Tarih") {
                    DatePicker(
                        "Tarih ve saat",
                        selection: $dateInput,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Hızlı düzeltme") {
                    Button("Seçili güne taşı: \(CalendarView.fullDayFormatter.string(from: selectedDay))") {
                        dateInput = Self.merged(day: selectedDay, time: dateInput)
                    }
                    Button("1 gün geri al") {
                        shiftDay(-1)
                    }
                    Button("1 gün ileri al") {
                        shiftDay(1)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Yemek Tarihi")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        onSave(dateInput)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 460, height: 360)
    }

    private func shiftDay(_ days: Int) {
        dateInput = Calendar.current.date(byAdding: .day, value: days, to: dateInput) ?? dateInput
    }

    private static func merged(day: Date, time: Date) -> Date {
        let cal = Calendar.current
        let timeParts = cal.dateComponents([.hour, .minute, .second], from: time)
        let dayStart = cal.startOfDay(for: day)
        return cal.date(
            bySettingHour: timeParts.hour ?? 0,
            minute: timeParts.minute ?? 0,
            second: timeParts.second ?? 0,
            of: dayStart
        ) ?? day
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
