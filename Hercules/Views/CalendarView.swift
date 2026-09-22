import SwiftUI
import LucideKit
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
        // Üst şerit yok: sayfa adı ve metası sidebar'da; içerik doğrudan başlar.
        return VStack(spacing: 0) {
            // Viewport yüksekliğini ölç: masa (esnek bölüm) kalan boşluğu yutabilsin.
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        calendarDesk(consumed: consumedDict, weights: weightDict, available: geo.size.height)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                }
            }
        }
        .background(DashboardBackground().ignoresSafeArea())
        .sheet(isPresented: $showingSetup) {
            PlanSetupSheet(
                startWeight: currentWeight ?? 80,
                replacesExisting: !goals.isEmpty,
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

    // MARK: - Header (ince üst şerit: yalnız günlük hedef metası)

    private var headerTargetMeta: some View {
        HStack(spacing: 7) {
            Circle().fill(Palette.accent).frame(width: 6, height: 6)
            Text("Günlük Hedef")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Palette.textTertiary)
            Text("\(Fmt.int(dailyTarget)) kalori")
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .help(profile == nil || latestMeasurement == nil ? "Profil ve son ölçüm bekleniyor" : "Profildeki hedeften okunuyor")
    }

    /// Buzz kanal-başlığı aksiyonları: sayfanın eylemleri toolbar'da değil,
    /// başlığın sağında outline buton olarak durur (ChatHeader.tsx dili).
    private var headerActions: some View {
        HStack(spacing: 6) {
            if !goals.isEmpty {
                Button(role: .destructive) { showingClearConfirm = true } label: {
                    Lucide(sf: "trash", size: 14)
                        .foregroundStyle(Palette.negative)
                        .frame(width: 32, height: 32)
                        .flatButtonChrome()
                }
                .buttonStyle(.plain)
                .help("Tüm aylık hedefleri sil")
            }

            Button { showingSetup = true } label: {
                HStack(spacing: 6) {
                    Lucide(sf: goals.isEmpty ? "plus" : "arrow.clockwise", size: 13)
                    Text(goals.isEmpty ? "Plan Oluştur" : "Yeni Plan")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .flatButtonChrome()
            }
            .buttonStyle(.plain)
            .help(goals.isEmpty ? "Aylık plan oluştur" : "Mevcut planı değiştir")
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
                unit: "kalori",
                sub: "\(balanceText(todayBalance)) · kayıt \(todayMeals)",
                badge: nil
            ),
            PeriodItem(
                label: "Bu Hafta",
                value: Fmt.int(week.totalConsumed),
                unit: "kalori",
                sub: "\(week.loggedDays) gün kayıtlı · ort. \(Fmt.int(week.averageDailyKcal))",
                badge: (balanceText(week.netBalance), balanceTint(week.netBalance))
            ),
            PeriodItem(
                label: "Bu Ay",
                value: Fmt.int(month.totalConsumed),
                unit: "kalori",
                sub: "\(month.loggedDays) gün kayıtlı · ort. \(Fmt.int(month.averageDailyKcal))",
                badge: (balanceText(month.netBalance), balanceTint(month.netBalance))
            ),
            PeriodItem(
                label: "Son 30 Gün",
                value: Fmt.signed(last30.averageDailyBalance, digits: 0),
                unit: "kalori/gün",
                sub: "toplam \(Fmt.signed(last30.netBalance, digits: 0)) · \(last30.loggedDays) gün",
                badge: (balanceText(last30.netBalance), balanceTint(last30.netBalance))
            ),
        ]
    }

    /// Buzz tarzı düz KPI şeridi: kutu yok, kolonlar dikey hairline'larla ayrılır.
    /// Dar kolon sürümü: dört dönem alt alta, tek satırlık kompakt gruplar.
    private var periodSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(periodItems.enumerated()), id: \.offset) { idx, item in
                if idx > 0 { Hairline() }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.label)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 74, alignment: .leading)
                    Text(item.value)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(item.unit)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textQuaternary)
                    Spacer(minLength: 6)
                    if let badge = item.badge {
                        Text(badge.text)
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(badge.tint)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // Masa geometrisi — esneklik hesabı ile çizim aynı sayıları kullansın.
    private static let dayRowMin: CGFloat = 78      // gün fayansının tabanı (DayCell kendi minHeight'ı 74)
    private static let gridGap: CGFloat = 7         // grid satır/kolon aralığı
    private static let weekdayRowH: CGFloat = 28    // PZT…PAZ başlık kapsülü
    private static let panelChromeH: CGFloat = 54   // panel üst boşluğu 6 + ay başlığı 32 (butonlu) + başlık altı 16
    private static let deskColumnGap: CGFloat = 10  // Seçili Gün ile dönem özeti arası

    /// Viewport'u doldur: takvim masası kalan boşluğu yutar, Hedef Rotası dibe.
    /// Sabit kalemler viewport'tan düşülür, ARTAN yükseklik grid satırlarına
    /// (gün fayansları uzar) ve Seçili Gün paneline dağıtılır. Esnek frame yerine
    /// açık matematik: ScrollView dikey öneri vermediği için `maxHeight: .infinity`
    /// zinciri ideal boya çöker (ve eski kabukta layout döngüsü yapıyordu).
    private func calendarDesk(consumed: [Date: Double], weights: [Date: Double], available: CGFloat) -> some View {
        let weeks = max(1, monthGridDays().count / 7)
        // Sabit kalan: yalnız sayfa dikey padding'i. (Dönem özeti sağ kolonun
        // dibine indi; Hedef Rotası bölümü kaldırıldı.)
        let fixedRest = 18 * 2 as CGFloat
        // Masanın doğal tabanı: panel kabuğu + gün adları satırı + aralıklar + 104'lük satırlar.
        let deskChrome = Self.panelChromeH + Self.weekdayRowH + Self.gridGap * CGFloat(weeks)
        let deskMin = deskChrome + Self.dayRowMin * CGFloat(weeks)
        // Kısa pencerede max(...) doğal boyu korur; sayfa eskisi gibi kayar.
        let elastic = max(deskMin, available - fixedRest)
        let rowH = max(Self.dayRowMin, (elastic - deskChrome) / CGFloat(weeks))
        // Sağ kolon: panel + hairline + dönem özeti TAM masa boyunda bitsin
        // (yoksa özet viewport'un altında kesiliyordu).
        //   özet = 4 satır × 17 + 3 hairline + 6 × 10 aralık = 131
        //   kolon = panel + 2 × kolonAralığı + 1pt hairline + özet
        let summaryH: CGFloat = 131
        let detailMin = max(0, elastic - Self.deskColumnGap * 2 - 1 - summaryH)

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                calendarPanel(consumed: consumed, weights: weights, rowHeight: rowH)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle()
                    .fill(Palette.border.opacity(0.6))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .trailing, spacing: Self.deskColumnGap) {
                    selectedDayDetail(minHeight: detailMin)
                    // Dönem özeti (Bugün/Bu Hafta/Bu Ay/Son 30 Gün) sayfanın üstünde
                    // tam genişlik şerit olarak gereksiz yer kaplıyordu; seçili günün
                    // altında, bağlamının yanında duruyor.
                    Hairline()
                    periodSummary
                }
                .frame(width: 392, alignment: .topLeading)
            }
            // Çok öğünlü günde sağ kolon daha uzun olabilir: minHeight sıkıştırmaz, büyütür.
            .frame(minHeight: elastic, alignment: .top)

            // Dar pencere: kolonlar alt alta düştüğü için sayfa zaten viewport'u aşar —
            // fayanslar doğal boyunda kalır, esneme yalnız yan yana düzende anlamlı.
            VStack(alignment: .leading, spacing: 12) {
                calendarPanel(consumed: consumed, weights: weights, rowHeight: Self.dayRowMin)
                selectedDayDetail(minHeight: 0)
                Hairline()
                periodSummary
            }
        }
    }

    private func calendarPanel(consumed: [Date: Double], weights: [Date: Double], rowHeight: CGFloat) -> some View {
        let monthStats = monthLoggedStats(consumed: consumed)
        // Referans başlık: solda daire chevron çifti, büyük ay adı + soluk yıl.
        let titleParts: (month: String, year: String) = {
            let full = Self.monthTitleFormatter.string(from: currentMonth)
            let comps = full.split(separator: " ")
            guard comps.count >= 2 else { return (full, "") }
            return (comps.dropLast().joined(separator: " "), String(comps.last!))
        }()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                monthNavButton(icon: "chevron.left") { jumpMonth(by: -1) }
                monthNavButton(icon: "chevron.right") { jumpMonth(by: 1) }

                Text("\(Text(titleParts.month).foregroundStyle(Palette.textPrimary)) \(Text(titleParts.year).foregroundStyle(Palette.textQuaternary))")
                    .font(.system(size: 25, weight: .bold))
                    .tracking(-0.3)
                    .lineLimit(1)

                // İçinde bulunulan ay için aynı satır zaten dönem şeridinin
                // "Bu Ay" kolonunda duruyor — özet yalnızca başka aya gezinince görünür.
                if !Calendar.current.isDate(currentMonth, equalTo: .now, toGranularity: .month) {
                    Text(monthStats.days > 0
                         ? "\(monthStats.days) gün kayıtlı · ort. \(Fmt.int(monthStats.avg)) kalori"
                         : "kayıt yok")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .padding(.leading, 2)
                }
                Spacer(minLength: Spacing.sm)
                todayButton
                // Plan eylemleri ay başlığında: aylık hedefler bu takvimin
                // günlerinde çip olarak yaşıyor, eylemleri de burada dursun.
                headerActions
            }
            .padding(.bottom, Spacing.lg)

            calendarGridBody(consumed: consumed, weights: weights, rowHeight: rowHeight)
        }
        // Referans: fayanslar kart içinde değil, doğrudan kanvasta yüzer.
        // Üst boşluk + başlık satırı (30) + başlık altı (16) = panelChromeH.
        .padding(.top, 6)
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
            .flatButtonChrome()
        }
        .buttonStyle(.plain)
        .help("Bugüne dön")
    }

    private func monthNavButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Lucide(sf: icon, size: 12)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.surfaceElevated))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calendar grid

    /// Grid hesaplamasını body'de pre-build edilmiş `consumed`/`weights` dict'leri üzerinden yap.
    private func calendarGridBody(consumed: [Date: Double], weights: [Date: Double], rowHeight: CGFloat) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: Self.gridGap), count: 7)
        let days = monthGridDays()
        // Haftalara böl (7'şer). LazyVGrid satırlara dikey alan dağıtmadığı için
        // manuel HStack satırları kullanıyoruz: her satır masanın esnek yüksekliğinden
        // pay alır, böylece grid kanvasın dibine kadar uzar (altta boşluk kalmaz).
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        return VStack(spacing: Self.gridGap) {
            // Weekday headers
            LazyVGrid(columns: cols, spacing: Self.gridGap) {
                ForEach(Self.weekdayHeaders, id: \.self) { wd in
                    Text(wd)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.weekdayRowH)
                        .background(Capsule().fill(Palette.surfaceElevated.opacity(0.6)))
                }
            }
            // Day cells — masadan gelen AÇIK satır boyu (dayRowMin tabanlı, viewport'a göre uzar).
            // Esnek frame değil sayı: ScrollView içinde maxHeight:.infinity greedy-fill
            // zinciri hem ideale çöküyor hem de layout döngüsü yapıyordu.
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: Self.gridGap) {
                    ForEach(week, id: \.self) { date in
                        dayCell(date, consumed: consumed, weights: weights)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
            }
        }
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
        .frame(maxWidth: .infinity)
    }

    // MARK: - Selected day detail

    /// `minHeight`: masanın esnek boyundan gelen taban — kart kolonun dibine iner,
    /// içerik üstte kalır. Öğün listesi daha uzunsa kart doğal boyunda büyür (sıkışmaz).
    private func selectedDayDetail(minHeight: CGFloat) -> some View {
        // Panel Genel Bakış hero'sundakiyle aynı bileşen; buradaki fark satır
        // aksiyonları (tarih/saat düzenleme + gün kaydırma).
        DayMealsPanel(
            day: selectedDay,
            foods: foodsFor(day: selectedDay),
            dailyTarget: dailyTarget,
            title: "Seçili Gün",
            // Düz zemin (Genel Bakış dili): kart kabuğu yok.
            showsCard: false,
            minHeight: minHeight,
            onEditDate: { editingFoodDate = $0 },
            onMove: { entry, days in moveFood(entry, byDays: days) }
        )
    }

    /// Sağ tık menüsünden gün kaydırma: yemeği taşı, seçimi ve ayı da oraya al.
    private func moveFood(_ entry: FoodEntry, byDays days: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: entry.date) else { return }
        entry.date = newDate
        ctx.saveOrReport()
        selectedDay = Calendar.current.startOfDay(for: newDate)
        currentMonth = Self.startOfMonth(newDate)
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

}

// MARK: - DayCell (calendar grid)
