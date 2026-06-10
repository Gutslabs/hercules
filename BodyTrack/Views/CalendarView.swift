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

    /// Gün → o günkü tartı (aynı güne birden çok ölçüm varsa en yenisi kazanır;
    /// measurements zaten tarihçe ters sıralı geldiği için ilk görülen kalır).
    private var weightByDay: [Date: Double] {
        let cal = Calendar.current
        var dict: [Date: Double] = [:]
        for m in measurements {
            guard let w = m.weight else { continue }
            let key = cal.startOfDay(for: m.date)
            if dict[key] == nil { dict[key] = w }
        }
        return dict
    }

    var body: some View {
        let consumedDict = consumedByDay
        let weightDict = weightByDay
        return GeometryReader { proxy in
            let contentWidth = proxy.size.width
            let compact = contentWidth < 860

            // Viewport'u doldur: takvim masası kalan boşluğu yutar, Hedef Rotası dibe
            // yapışır; pencere kısaysa sayfa yine kayar.
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(compact: compact)
                    periodStrip
                    calendarDesk(consumed: consumedDict, weights: weightDict)
                        .frame(maxHeight: .infinity)
                    goalRouteCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, compact ? Spacing.lg : Spacing.xxxl)
                .padding(.vertical, compact ? Spacing.lg : Spacing.xxl)
                .frame(minHeight: proxy.size.height, alignment: .topLeading)
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

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: Spacing.md) {
                headerCopy
                headerTargetBlock(alignment: .leading)
            }
        } else {
            HStack(alignment: .bottom) {
                headerCopy
                Spacer(minLength: Spacing.xl)
                headerTargetBlock(alignment: .trailing)
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Beslenme Takibi").eyebrow()
            Text("Takvim")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
            Text("Günlük kayıtları, ay içi kalori ritmini ve kilo hedeflerini tek panoda gör.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, 2)
        }
    }

    private func headerTargetBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            HStack(spacing: 8) {
                Circle().fill(Palette.accent).frame(width: 6, height: 6)
                Text("Günlük Hedef").eyebrow()
                Text("\(Fmt.int(dailyTarget)) kcal")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
            }
            Text(profile == nil || latestMeasurement == nil ? "Profil ve son ölçüm bekleniyor" : "Profildeki hedeften okunuyor")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Dönem şeridi (Bugün / Bu Hafta / Bu Ay / Son 30 Gün)

    private struct PeriodItem {
        let label: String
        let value: String
        let unit: String
        let sub: String
        let badge: (text: String, tint: Color)?
    }

    private var periodItems: [PeriodItem] {
        let today = CalorieStats.stats(for: CalorieStats.today(), foods: allFoods, dailyTarget: dailyTarget)
        let week = CalorieStats.stats(for: CalorieStats.thisWeek(), foods: allFoods, dailyTarget: dailyTarget)
        let month = CalorieStats.stats(for: CalorieStats.thisMonth(), foods: allFoods, dailyTarget: dailyTarget)
        let last30 = CalorieStats.stats(for: CalorieStats.last(days: 30), foods: allFoods, dailyTarget: dailyTarget)

        let todayBalance = today.totalConsumed - dailyTarget
        let todayMeals = foodsFor(day: Calendar.current.startOfDay(for: .now)).count

        return [
            PeriodItem(
                label: "Bugün",
                value: Fmt.int(today.totalConsumed),
                unit: "kcal",
                sub: "\(balanceText(todayBalance)) · kayıt \(todayMeals)",
                badge: nil
            ),
            PeriodItem(
                label: "Bu Hafta",
                value: Fmt.int(week.totalConsumed),
                unit: "kcal",
                sub: "\(week.loggedDays) gün kayıtlı · ort. \(Fmt.int(week.averageDailyKcal))",
                badge: (balanceText(week.netBalance), balanceTint(week.netBalance))
            ),
            PeriodItem(
                label: "Bu Ay",
                value: Fmt.int(month.totalConsumed),
                unit: "kcal",
                sub: "\(month.loggedDays) gün kayıtlı · ort. \(Fmt.int(month.averageDailyKcal))",
                badge: (balanceText(month.netBalance), balanceTint(month.netBalance))
            ),
            PeriodItem(
                label: "Son 30 Gün",
                value: Fmt.signed(last30.averageDailyBalance, digits: 0),
                unit: "kcal/gün",
                sub: "toplam \(Fmt.signed(last30.netBalance, digits: 0)) · \(last30.loggedDays) gün",
                badge: (balanceText(last30.netBalance), balanceTint(last30.netBalance))
            ),
        ]
    }

    private var periodStrip: some View {
        let items = periodItems
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 {
                        Rectangle().fill(Palette.border).frame(width: 0.5)
                    }
                    periodColumn(item)
                        .frame(minWidth: 196, maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .dashboardCard(radius: 14)

            VStack(spacing: 0) {
                ForEach([0, 2], id: \.self) { row in
                    if row > 0 {
                        Rectangle().fill(Palette.border).frame(height: 0.5)
                    }
                    HStack(spacing: 0) {
                        periodColumn(items[row])
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Rectangle().fill(Palette.border).frame(width: 0.5)
                        periodColumn(items[row + 1])
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .dashboardCard(radius: 14)
        }
    }

    private func periodColumn(_ item: PeriodItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(item.label).eyebrow()
                Spacer(minLength: 4)
                if let badge = item.badge {
                    Text(badge.text)
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(badge.tint)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(item.value)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.4)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(item.unit)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
            }
            Text(item.sub)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    private func balanceText(_ balance: Double) -> String {
        if abs(balance) < 1 { return "dengeli" }
        return balance > 0 ? "+\(Fmt.int(balance)) fazla" : "\(Fmt.int(balance)) açık"
    }

    private func balanceTint(_ balance: Double) -> Color {
        if balance > 0 { return Palette.warning }
        if balance < 0 { return Palette.positive }
        return Palette.textTertiary
    }

    // MARK: - Calendar desk (ay grid'i + seçili gün)

    private func calendarDesk(consumed: [Date: Double], weights: [Date: Double]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.lg) {
                calendarPanel(consumed: consumed, weights: weights)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                selectedDayDetail
                    .frame(width: 392, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: Spacing.lg) {
                calendarPanel(consumed: consumed, weights: weights)
                selectedDayDetail
            }
        }
    }

    private func calendarPanel(consumed: [Date: Double], weights: [Date: Double]) -> some View {
        let monthStats = monthLoggedStats(consumed: consumed)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                monthNavButton(icon: "chevron.left") { jumpMonth(by: -1) }
                Text(Self.monthTitleFormatter.string(from: currentMonth))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                monthNavButton(icon: "chevron.right") { jumpMonth(by: 1) }
                Text(monthStats.days > 0
                     ? "\(monthStats.days) gün kayıtlı · ort. \(Fmt.int(monthStats.avg)) kcal"
                     : "kayıt yok")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.sm)
                todayButton
            }
            .padding(.bottom, Spacing.lg)

            calendarGridBody(consumed: consumed, weights: weights)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard()
    }

    private var todayButton: some View {
        Button {
            let today = Calendar.current.startOfDay(for: .now)
            currentMonth = Self.startOfMonth(.now)
            selectedDay = today
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Palette.accent).frame(width: 5, height: 5)
                Text("Bugün")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 0.75)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Bugüne dön")
    }

    private func monthNavButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calendar grid

    /// Grid hesaplamasını body'de pre-build edilmiş `consumed`/`weights` dict'leri üzerinden yap.
    private func calendarGridBody(consumed: [Date: Double], weights: [Date: Double]) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)
        let days = monthGridDays()
        // Haftalara böl (7'şer). LazyVGrid satırlara dikey alan dağıtmadığı için
        // manuel HStack satırları kullanıyoruz: her satır kalan yüksekliği eşit paylaşır,
        // böylece grid kartın dibine kadar uzar (altta boşluk kalmaz).
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        return VStack(spacing: 7) {
            // Weekday headers
            LazyVGrid(columns: cols, spacing: 7) {
                ForEach(Self.weekdayHeaders, id: \.self) { wd in
                    Text(wd).eyebrow()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 11)
                }
            }
            // Day cells — esneyen satırlar
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 7) {
                    ForEach(week, id: \.self) { date in
                        dayCell(date, consumed: consumed, weights: weights)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func dayCell(_ date: Date, consumed: [Date: Double], weights: [Date: Double]) -> some View {
        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: date)
        return DayCell(
            date: date,
            inMonth: cal.isDate(date, equalTo: currentMonth, toGranularity: .month),
            isToday: cal.isDateInToday(date),
            isSelected: cal.isDate(date, inSameDayAs: selectedDay),
            consumed: consumed[dayKey] ?? 0,
            target: dailyTarget,
            weight: weights[dayKey],
            monthlyGoal: goalAnchored(on: date),
            onTap: {
                selectedDay = dayKey
                if !cal.isDate(date, equalTo: currentMonth, toGranularity: .month) {
                    currentMonth = Self.startOfMonth(date)
                }
            },
            onGoalTap: { goal in
                editing = goal
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selected day detail

    private var selectedDayDetail: some View {
        let foods = foodsFor(day: selectedDay)
        let consumed = foods.reduce(0) { $0 + $1.calories }
        let p = foods.compactMap(\.protein).reduce(0, +)
        let c = foods.compactMap(\.carbs).reduce(0, +)
        let f = foods.compactMap(\.fat).reduce(0, +)
        let remaining = dailyTarget - consumed
        let isOver = remaining < 0
        let hasFood = !foods.isEmpty
        let progress = dailyTarget > 0 ? min(1, max(0, consumed / dailyTarget)) : 0
        let statusColor: Color = hasFood ? (isOver ? Palette.warning : Palette.positive) : Palette.textTertiary

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Seçili Gün").eyebrow()
                Spacer()
                Text("\(foods.count) öğün")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
            }

            HStack(spacing: Spacing.sm) {
                Text(Self.fullDayFormatter.string(from: selectedDay))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                if Calendar.current.isDateInToday(selectedDay) {
                    Text("BUGÜN")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.top, 6)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.int(consumed))
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .foregroundStyle(hasFood ? statusColor : Palette.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: consumed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("/ \(Fmt.int(dailyTarget)) kcal")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.top, 10)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Palette.track)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(statusColor)
                        .opacity(0.85)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 3)
            .padding(.top, 10)

            Text(isOver
                 ? "\(Fmt.int(abs(remaining))) kcal hedef üstü"
                 : "\(Fmt.int(remaining)) kcal alan kaldı")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(isOver ? Palette.warning : (hasFood ? Palette.positive : Palette.textTertiary))
                .padding(.top, 7)

            if hasFood {
                HStack(spacing: Spacing.lg) {
                    macroChip(label: "Protein", value: p, tint: Palette.macroProtein)
                    macroChip(label: "Karb", value: c, tint: Palette.macroCarbs)
                    macroChip(label: "Yağ", value: f, tint: Palette.macroFat)
                }
                .padding(.top, 12)
                .padding(.bottom, 14)

                Hairline()

                VStack(spacing: 0) {
                    ForEach(Array(foods.enumerated()), id: \.element.id) { idx, entry in
                        if idx > 0 { Hairline() }
                        mealRow(entry)
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
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.fieldFill.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.75)
                )
                .padding(.top, 14)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard()
    }

    private func mealRow(_ entry: FoodEntry) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineSpacing(2)
                    .lineLimit(2)
                Text(mealMetaText(entry))
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: Spacing.sm)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.int(entry.calories))
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                Text("kcal")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
            }
            .lineLimit(1)
            .fixedSize()
            Button {
                editingFoodDate = entry
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textQuaternary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Yemeğin gününü veya saatini değiştir")
        }
        .padding(.vertical, 12)
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

    /// "265g · P 34g · K 43g · Y 5g" — tek satır, kayıt eksikse "Makro yok".
    private func mealMetaText(_ entry: FoodEntry) -> String {
        var parts: [String] = []
        if let g = entry.grams { parts.append("\(Fmt.int(g))g") }
        if let p = entry.protein { parts.append("P \(Fmt.int(p))g") }
        if let c = entry.carbs { parts.append("K \(Fmt.int(c))g") }
        if let f = entry.fat { parts.append("Y \(Fmt.int(f))g") }
        return parts.isEmpty ? "Makro yok" : parts.joined(separator: " · ")
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
            Text(label)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
            Text("\(Fmt.int(value))g")
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Hedef rotası (yatay zaman çizgisi)

    @ViewBuilder
    private var goalRouteCard: some View {
        if goals.isEmpty {
            goalRouteEmpty
        } else {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Hedef Rotası").eyebrow()
                    Text(routeMetaText)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(goals.enumerated()), id: \.element.id) { index, g in
                        GoalRouteNode(
                            // Dinamik: düğüme ULAŞTIK mı? Tarih değil, gerçek kilo ilerlemesi.
                            goal: g,
                            isReached: routeProgress >= Double(index) - 0.001,
                            delta: currentWeight.map { g.targetWeight - $0 }
                        ) {
                            // Düğüme tıkla → düzenle (kilo/tarih/not/sil).
                            editing = g
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .background {
                    GeometryReader { geo in
                        let count = max(1, goals.count)
                        let cellW = geo.size.width / CGFloat(count)
                        let fullW = cellW * CGFloat(max(0, count - 1))
                        let fillW = min(fullW, cellW * CGFloat(routeProgress))
                        ZStack(alignment: .leading) {
                            // Tüm rota — soluk ray
                            Rectangle()
                                .fill(Palette.border)
                                .frame(width: fullW, height: 1)
                            // Kat edilen mesafe — hedefe yaklaştıkça uzar
                            Rectangle()
                                .fill(Palette.positive)
                                .frame(width: fillW, height: 1.5)
                        }
                        .offset(x: cellW / 2, y: 8)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 22)
            .dashboardCard()
        }
    }

    /// Rota üzerindeki sürekli konum [0 … n-1]: güncel kilonun aylık hedef
    /// dizisinde nereye düştüğü. Örn. 1.4 = 1. ve 2. düğüm arası %40 yol alınmış.
    /// Hedefe yaklaştıkça büyür; bağlayıcı çizgiyi ve düğüm tiklerini bu besler.
    private var routeProgress: Double {
        let targets = goals.map(\.targetWeight)
        guard targets.count > 1, let cw = currentWeight else { return 0 }
        // Aralıkları gez: cw iki ardışık hedef arasındaysa kesirli konum üret.
        for i in 0..<(targets.count - 1) {
            let a = targets[i], b = targets[i + 1]
            let lo = min(a, b), hi = max(a, b)
            if cw >= lo && cw <= hi {
                let span = a - b
                guard abs(span) > 0.0001 else { return Double(i) }
                return Double(i) + min(max((a - cw) / span, 0), 1)
            }
        }
        // Aralık dışı: başlangıçtan önce mi (henüz 0. düğüm yolunda) yoksa son hedefi geçti mi?
        let descending = (targets.last ?? 0) <= (targets.first ?? 0)
        let beyondStart = descending ? cw <= targets[0] : cw >= targets[0]
        return beyondStart ? Double(targets.count - 1) : 0
    }

    private var routeMetaText: String {
        guard let first = goals.first, let last = goals.last else { return "" }
        let span = max(1, (Calendar.current.dateComponents([.month], from: first.anchorDate, to: last.anchorDate).month ?? 0) + 1)
        let totalKg = abs((currentWeight ?? first.targetWeight) - last.targetWeight)
        return "\(span) aylık plan · \(goals.count) hedef · \(Fmt.num(totalKg, digits: 1)) kg"
    }

    private var goalRouteEmpty: some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hedef Rotası").eyebrow()
                Text("Hedef rotası yok")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text("Aylık kilo hedeflerini ekleyince rota burada ay ay işaretlenir.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: Spacing.lg)
            PrimaryButton(title: "Plan Oluştur", systemImage: "wand.and.stars") {
                showingSetup = true
            }
            .frame(width: 180)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .dashboardCard()
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

    /// 7 × n grid of dates that cover `currentMonth`. Includes leading/trailing
    /// days from the adjacent months; row count adapts (5 hafta yetiyorsa 6. satır yok).
    private func monthGridDays() -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday-first
        cal.locale = Locale(identifier: "tr_TR")

        guard let interval = cal.dateInterval(of: .month, for: currentMonth) else { return [] }
        let monthStart = interval.start
        let weekday = cal.component(.weekday, from: monthStart)
        let leadingOffset = (weekday - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -leadingOffset, to: monthStart) else { return [] }

        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let totalCells = Int((Double(leadingOffset + daysInMonth) / 7.0).rounded(.up)) * 7
        return (0..<totalCells).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func jumpMonth(by step: Int) {
        guard let new = Calendar.current.date(byAdding: .month, value: step, to: currentMonth) else { return }
        currentMonth = Self.startOfMonth(new)
    }

    private func foodsFor(day: Date) -> [FoodEntry] {
        let cal = Calendar.current
        return allFoods.filter { cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    private func goalAnchored(on date: Date) -> MonthlyGoal? {
        goals.first { Calendar.current.isDate($0.anchorDate, inSameDayAs: date) }
    }

    /// Görünen ayın kayıtlı gün sayısı + ortalaması — pre-build edilmiş dict'ten.
    private func monthLoggedStats(consumed: [Date: Double]) -> (days: Int, avg: Double) {
        let cal = Calendar.current
        let logged = consumed.filter {
            cal.isDate($0.key, equalTo: currentMonth, toGranularity: .month) && $0.value > 0
        }.map(\.value)
        guard !logged.isEmpty else { return (0, 0) }
        return (logged.count, logged.reduce(0, +) / Double(logged.count))
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
