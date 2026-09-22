import SwiftUI
import LucideKit
import SwiftData

struct DayCell: View {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let consumed: Double
    let target: Double
    /// O günkü tartı (varsa) — hücrenin sağ üstünde küçük chip olarak gösterilir.
    let weight: Double?
    let monthlyGoal: MonthlyGoal?
    let onTap: () -> Void
    let onGoalTap: (MonthlyGoal) -> Void

    @State private var hovering = false

    private var dayNumber: String {
        Fmt.dayNumber.string(from: date)
    }

    private var hasFood: Bool {
        consumed > 0
    }

    /// V1 dili: hedef üstü → amber, hedef altı → yeşil, kayıt yok → soluk çizgi.
    private var barColor: Color {
        guard target > 0, hasFood else { return Palette.track }
        return consumed > target ? Palette.warning : Palette.positive
    }

    /// Sidebar dili: seçili gün kenarlıkla değil PEÇEYLE ayrışır; yalnız "bugün"
    /// çok soluk bir halka taşır (aynı gün seçiliyse peçe zaten söylüyor).
    private var stateRing: Color {
        isToday && !isSelected ? Palette.accent.opacity(0.22) : .clear
    }

    private var fillColor: Color {
        if isSelected { return Palette.surface }   // peçe selectionRing'den gelir
        if hovering { return Palette.surfaceElevated }
        return Palette.surface
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 6) {
                    if let weight {
                        Text("\(Fmt.num(weight, digits: 1)) kg")
                            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Palette.track)
                            )
                    }

                    Spacer(minLength: 0)

                    if let g = monthlyGoal {
                        Button { onGoalTap(g) } label: {
                            HStack(spacing: 4) {
                                Lucide(sf: "scope", size: 8)
                                Text("\(Fmt.num(g.targetWeight, digits: 1))")
                                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Palette.accent.opacity(0.1))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Ay hedefi: \(Fmt.num(g.targetWeight, digits: 1)) kg — düzenlemek için tıkla")
                    }
                }

                Spacer(minLength: 4)

                // Kalori, renkli çizginin hemen üstünde ve YATAY ORTADA.
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(hasFood ? Fmt.int(consumed) : "—")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(hasFood ? Palette.textPrimary : Palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if hasFood {
                        Text("kalori")
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barColor)
                    .opacity(hasFood ? 0.9 : 1)
                    .frame(height: 3)
                    .padding(.bottom, 6)

                Text(dayNumber)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Palette.accent : (inMonth ? Palette.textPrimary : Palette.textQuaternary))
            }
            .padding(.top, 10)
            .padding(.horizontal, 11)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            // Referans fayansı: 18px köşe, tek kalkık dolgu, kenarlıksız;
            // yalnız seçili/bugün durumu halkayla işaretlenir (anlamlı state).
            .selectionRing(isSelected, cornerRadius: 18, base: fillColor, baseShadow: true)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(stateRing, lineWidth: 1)
            )
            .opacity(inMonth ? 1.0 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Hedef rotasının yatay zaman çizgisindeki tek ay düğümü:
/// işaret (geçti ✓ / bekliyor ○), ay etiketi, hedef kilo ve güncel kilodan farkı.
struct GoalRouteNode: View {
    let goal: MonthlyGoal
    let isReached: Bool
    /// Hedef − güncel kilo (negatif = verilecek kilo). Güncel tartı yoksa nil.
    let delta: Double?
    let onTap: () -> Void
    @State private var hovering = false

    private var monthLabel: String {
        Fmt.monthShort.string(from: goal.anchorDate).uppercased()
    }

    private var deltaText: String? {
        guard let delta else { return nil }
        if abs(delta) < 0.05 { return "hedefte" }
        return "\(Fmt.signed(delta, digits: 1)) kg"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                ZStack {
                    if isReached {
                        Circle()
                            .fill(Palette.positive)
                            .frame(width: 17, height: 17)
                        Lucide(sf: "checkmark", size: 8)
                            .foregroundStyle(Palette.background)
                    } else {
                        Circle()
                            .fill(Palette.background)
                            .overlay(Circle().strokeBorder(hovering ? Palette.textTertiary : Palette.borderStrong, lineWidth: 1.5))
                            .frame(width: 9, height: 9)
                    }
                }
                .frame(height: 17)

                HStack(spacing: 5) {
                    Text(monthLabel)
                        .font(Typography.label)
                        .tracking(0.9)
                        .foregroundStyle(isReached ? Palette.positive : Palette.textQuaternary)
                    if isReached {
                        Text("GEÇTİ")
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(Palette.positive)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.num(goal.targetWeight, digits: 1))
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("kg")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.top, -2)

                if let deltaText {
                    Text(deltaText)
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(hovering ? Palette.textPrimary : Palette.textSecondary)
                        .lineLimit(1)
                        .padding(.top, -3)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Düzenle: \(monthLabel) hedefi")
        .animation(.easeOut(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Plan setup sheet


// MARK: - Gün öğün paneli (Öğün Takip + Genel Bakış ortak)

/// Bir günün öğün dökümü: başlık + tüketilen/hedef + ilerleme çizgisi + makro
/// noktaları + saat saat öğün satırları. Öğün Takip'teki "Seçili Gün" paneli ile
/// Genel Bakış hero'sundaki "Bugün" paneli AYNI bileşendir; farkları yalnız
/// başlık metni, kart kabuğu ve satır aksiyonları.
struct DayMealsPanel: View {
    let day: Date
    let foods: [FoodEntry]
    let dailyTarget: Double
    /// Sol üstteki soluk etiket ("Seçili Gün" / "Bugün").
    var title: String = "Seçili Gün"
    /// Kendi kart zemini çizilsin mi? Zaten bir kartın içindeyse kapatılır.
    var showsCard: Bool = true
    var minHeight: CGFloat = 0
    /// Satırdaki takvim düğmesi — nil ise düğme çizilmez.
    var onEditDate: ((FoodEntry) -> Void)? = nil
    /// Sağ tık menüsünden gün kaydırma — nil ise menü çıkmaz.
    var onMove: ((FoodEntry, Int) -> Void)? = nil
    /// Satırdaki çöp düğmesi — nil ise düğme çizilmez.
    var onDelete: ((FoodEntry) -> Void)? = nil

    var body: some View {
        let consumed = foods.reduce(0) { $0 + $1.calories }
        let p = foods.compactMap(\.protein).reduce(0, +)
        let c = foods.compactMap(\.carbs).reduce(0, +)
        let f = foods.compactMap(\.fat).reduce(0, +)
        let remaining = dailyTarget - consumed
        let isOver = remaining < 0
        let hasFood = !foods.isEmpty
        let progress = dailyTarget > 0 ? min(1, max(0, consumed / dailyTarget)) : 0
        let statusColor: Color = hasFood ? (isOver ? Palette.warning : Palette.positive) : Palette.textTertiary

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).eyebrow()
                Spacer()
                Text("\(foods.count) öğün")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
            }

            HStack(spacing: Spacing.sm) {
                Text(Self.fullDayFormatter.string(from: day))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                if Calendar.current.isDateInToday(day) {
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
                Text("/ \(Fmt.int(dailyTarget)) kalori")
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
                Text("Kayıt yok")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
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
        }
        .padding(.horizontal, showsCard ? 26 : 0)
        .padding(.top, showsCard ? 22 : 0)
        .padding(.bottom, showsCard ? 20 : 0)
        // Taban yükseklik kabuktan ÖNCE: kart zemini de birlikte uzasın.
        .frame(minHeight: minHeight, alignment: .topLeading)
        .modifier(OptionalDashboardCard(enabled: showsCard))
    }

    private func mealRow(_ entry: FoodEntry) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)   // yanındaki yemek adı (layoutPriority 1)
                .padding(.top, 2)                                // saati sıkıştırıp "14:30"u alt alta kırmasın
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineSpacing(2)
                    .lineLimit(2)
                Text(Self.mealMetaText(entry))
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
                Text("kalori")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
            }
            .lineLimit(1)
            .fixedSize()
            if let onEditDate {
                Button { onEditDate(entry) } label: {
                    Lucide(sf: "calendar.badge.clock", size: 10)
                        .foregroundStyle(Palette.textQuaternary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Yemeğin gününü veya saatini değiştir")
            }
            if let onDelete {
                Button { onDelete(entry) } label: {
                    Lucide(sf: "trash", size: 10)
                        .foregroundStyle(Palette.textQuaternary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Öğünü sil")
            }
        }
        .padding(.vertical, 12)
        .contextMenu {
            if let onEditDate {
                Button { onEditDate(entry) } label: {
                    Label("Tarih ve Saati Değiştir", systemImage: "calendar.badge.clock")
                }
            }
            if let onMove {
                Button { onMove(entry, -1) } label: {
                    Label("1 Gün Geri Al", systemImage: "arrow.left")
                }
                Button { onMove(entry, 1) } label: {
                    Label("1 Gün İleri Al", systemImage: "arrow.right")
                }
            }
            if let onDelete {
                Button(role: .destructive) { onDelete(entry) } label: {
                    Label("Sil", systemImage: "trash")
                }
            }
        }
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

    /// "265g · P 34g · K 43g · Y 5g" — tek satır, kayıt eksikse "Makro yok".
    private static func mealMetaText(_ entry: FoodEntry) -> String {
        var parts: [String] = []
        if let g = entry.grams { parts.append("\(Fmt.int(g))g") }
        if let p = entry.protein { parts.append("P \(Fmt.int(p))g") }
        if let c = entry.carbs { parts.append("K \(Fmt.int(c))g") }
        if let f = entry.fat { parts.append("Y \(Fmt.int(f))g") }
        return parts.isEmpty ? "Makro yok" : parts.joined(separator: " · ")
    }

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

/// `dashboardCard()` kabuğunu koşullu uygular — panel kart içinde kullanılınca
/// ikinci bir zemin çizilmesin (kutu-içinde-kutu yok).
private struct OptionalDashboardCard: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.dashboardCard() } else { content }
    }
}
