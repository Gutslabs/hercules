import SwiftUI
import LucideKit

// MARK: - Antrenman · V2 "Hafta"
//
// Tasarım: "Hercules Mac Tasarımı" tuvali ▸ Antrenman · V2 Hafta (artboard 1829×1147; koordinatlar
// tasarım betiği mac_antrenman_v2.py ile birebir). Üstte haftanın 7 günü (seans · süre · durum
// işareti; seçili gün vurgulu), altta seçili günün seansı (hareketler + son üst set; kayıtlı günde
// yapılan setler) ve sağda ayın tutarlılığı (sayı + gün noktaları) ile program eylemleri.
// Kabuk RingsPanel (DashboardRings.swift).

enum WorkoutDayStatus {
    case done, today, planned, missed, rest
}

/// Gün işareti: yapıldı = dolu yeşil + tik · bugün = pirinç halka · planlı = gri halka ·
/// kaçtı = soluk kırmızı kesik halka · dinlenme = küçük nokta.
struct WorkoutDayMark: View {
    let status: WorkoutDayStatus
    let radius: CGFloat

    var body: some View {
        let d = radius * 2
        switch status {
        case .done:
            ZStack {
                Circle().fill(Palette.positive.opacity(0.9))
                WorkoutCheckShape()
                    .stroke(Palette.background, style: StrokeStyle(lineWidth: max(1.8, radius * 0.14),
                                                                  lineCap: .round, lineJoin: .round))
            }
            .frame(width: d, height: d)
        case .today:
            ZStack {
                Circle().strokeBorder(Palette.warning, lineWidth: 2.5)
                Circle().fill(Palette.warning).frame(width: radius * 0.56, height: radius * 0.56)
            }
            .frame(width: d, height: d)
        case .planned:
            Circle()
                .strokeBorder(Palette.textPrimary.opacity(0.22), lineWidth: 1.5)
                .frame(width: d, height: d)
        case .missed:
            Circle()
                .strokeBorder(Palette.negative.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: d, height: d)
        case .rest:
            let dot = 2 * max(2.5, radius * 0.14)
            Circle()
                .fill(Palette.textPrimary.opacity(0.16))
                .frame(width: dot, height: dot)
                .frame(width: d, height: d)
        }
    }
}

private struct WorkoutCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        var p = Path()
        p.move(to: CGPoint(x: r - r * 0.36, y: r + r * 0.02))
        p.addLine(to: CGPoint(x: r - r * 0.08, y: r + r * 0.3))
        p.addLine(to: CGPoint(x: r + r * 0.4, y: r - r * 0.28))
        return p
    }
}

/// Düz düğme (7×11 dolgu, 9 köşe, beyaz %5) ve birincil düğme (8×14, btnBg).
struct WorkoutPanelButton: View {
    let title: String
    var icon: String? = nil
    var primary = false
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Lucide(sf: icon, size: 13)
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: primary ? .semibold : .medium))
                }
            }
            .foregroundStyle(primary ? Palette.btnFg : Palette.textSecondary)
            .padding(.horizontal, primary ? 14 : 11)
            .padding(.vertical, primary ? 8 : 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(primary ? Palette.btnBg : Palette.textPrimary.opacity(0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help ?? title)
    }
}

// MARK: - Üst: hafta

/// Generic görünümlerde statik saklı özellik olamadığı için biçimleyiciler burada.
private enum WorkoutWeekFormat {
    static let caps: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEE"
        return f
    }()
}

struct WorkoutWeekDay: Identifiable {
    let date: Date
    let status: WorkoutDayStatus
    /// Seans (ya da kayıt) adı; nil → dinlenme.
    let title: String?
    let meta: String?
    let isToday: Bool
    var id: Date { date }
}

struct WorkoutWeekPanel<MenuItems: View>: View {
    let days: [WorkoutWeekDay]
    let selected: Date
    /// "21–27 Eylül"
    let rangeLabel: String
    let done: Int
    let planned: Int
    /// Görünen hafta bu hafta değilse "Bugün" düğmesi çıkar.
    let showsToday: Bool
    let onSelect: (Date) -> Void
    let onShift: (Int) -> Void
    let onToday: () -> Void
    @ViewBuilder let menuItems: (Date) -> MenuItems

    private static var gap: CGFloat { 12 }

    var body: some View {
        RingsPanel(title: "Bu hafta", sub: rangeLabel) { size in
            let cw = (size.width - 48 - Self.gap * 6) / 7
            ZStack(alignment: .topLeading) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    column(day, width: cw)
                        .position(x: 24 + CGFloat(index) * (cw + Self.gap) + cw / 2, y: 60 + 83)
                }
                HStack(spacing: 10) {
                    if showsToday {
                        WorkoutPanelButton(title: "Bugün", help: "Bu haftaya dön", action: onToday)
                    }
                    (Text("\(done)/\(planned)")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                     + Text(" seans")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary))
                        .lineLimit(1)
                    navButton("chevron.left", help: "Önceki hafta") { onShift(-1) }
                    navButton("chevron.right", help: "Sonraki hafta") { onShift(1) }
                }
                .ringsPin(size.width - 24, 14, .topTrailing)
            }
        }
    }

    private func column(_ day: WorkoutWeekDay, width cw: CGFloat) -> some View {
        let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selected)
        return Button { onSelect(day.date) } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.textPrimary.opacity(isSelected ? 0.075 : 0.028))
                Text(Self.weekdayCaps(day.date))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(day.isToday ? Palette.warning : Palette.textTertiary)
                    .ringsPin(16, 16)
                Text(Fmt.dayNumber.string(from: day.date))
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(day.status == .rest ? Palette.textTertiary : Palette.textPrimary)
                    .ringsPin(16, 34)
                WorkoutDayMark(status: day.status, radius: 13)
                    .position(x: cw - 28, y: 30)
                if let title = day.title {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineSpacing(1)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .frame(width: max(0, cw - 32), alignment: .topLeading)
                        .ringsPin(16, 96)
                    if let meta = day.meta {
                        Text(meta)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                            .frame(width: max(0, cw - 32), alignment: .leading)
                            .ringsPin(16, 138)
                    }
                } else {
                    Text("dinlenme")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .ringsPin(16, 96)
                }
            }
            .frame(width: cw, height: 166)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { menuItems(day.date) }
    }

    private func navButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Lucide(sf: icon, size: 14)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    static func weekdayCaps(_ date: Date) -> String {
        WorkoutWeekFormat.caps.string(from: date).uppercased(with: Locale(identifier: "tr_TR"))
    }
}

// MARK: - Sol alt: seçili gün

struct WorkoutDayRow: Identifiable {
    let id: Int
    let name: String
    /// "4 × 6–8" · kayıtlı günde "81 × 12 · 80 × 8 …"
    let primary: String
    let load: String?
    /// "RIR 2 · 150 sn"
    let extra: String?
    /// Sağ sütun: en ağır set ("75 kg", 12) ve altındaki etiket ("son · 15 Eyl").
    let best: (weight: String, reps: Int)?
    let bestLabel: String?
    let link: URL?
    let note: String?
}

struct WorkoutDayPlan {
    let name: String
    let chips: [String]
    let focus: String?
    let rows: [WorkoutDayRow]
    let notes: [(label: String, text: String)]
}

struct WorkoutDayPanel<Actions: View>: View {
    /// "Salı"
    let title: String
    /// "bugün" ya da "24 Eylül"
    let subtitle: String
    /// nil → dinlenme günü.
    let plan: WorkoutDayPlan?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        RingsPanel(title: title, sub: subtitle) { size in
            if let plan {
                Text(plan.name)
                    .font(.system(size: 32, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .frame(width: max(0, size.width - 48), alignment: .leading)
                    .ringsPin(24, 50)
                HStack(alignment: .center, spacing: 8) {
                    ForEach(plan.chips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
                    }
                    if let focus = plan.focus, !focus.isEmpty {
                        Text(focus)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .lineLimit(1)
                .ringsPin(24, 100)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(plan.rows) { row in
                            WorkoutExerciseRowView(row: row, width: size.width)
                        }
                        if !plan.notes.isEmpty {
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, note in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(note.label.uppercased(with: Locale(identifier: "tr_TR")))
                                            .font(.system(size: 11, weight: .semibold))
                                            .tracking(0.6)
                                            .foregroundStyle(Palette.textTertiary)
                                        Text(note.text)
                                            .font(.system(size: 13.5))
                                            .foregroundStyle(Palette.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(width: 400, alignment: .topLeading)
                                }
                            }
                            .padding(.leading, 24)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                    }
                    .padding(.top, 10)
                    .frame(width: size.width, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: size.width, height: max(0, size.height - 150), alignment: .top)
                .padding(.top, 150)
            } else {
                VStack(spacing: 6) {
                    Text("Dinlenme günü")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Text("Bu güne program yok. Yine de antrenman yaptıysan kaydedebilirsin.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textTertiary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: max(0, size.width - 96))
                .position(x: size.width / 2, y: size.height / 2)
            }
            actions()
                .ringsPin(size.width - 24, 16, .topTrailing)
        }
    }
}

/// Satır: sıra · ad (+ kaynak bağlantısı) · hedef ya da yapılan setler · en ağır set.
private struct WorkoutExerciseRowView: View {
    let row: WorkoutDayRow
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .strokeBorder(Palette.textPrimary.opacity(0.16), lineWidth: 1.5)
                .frame(width: 26, height: 26)
                .position(x: 37, y: 20)
            Text("\(row.id + 1)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
                .ringsPin(37, 13, .top)
            HStack(alignment: .center, spacing: 8) {
                Text(row.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if let link = row.link {
                    Link(destination: link) {
                        Lucide(sf: "link", size: 10)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Hareket videosunu / kaynağını aç")
                }
            }
            .ringsPin(66, 8)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.primary)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                if let load = row.load, !load.isEmpty {
                    Text(load)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                }
                if let extra = row.extra, !extra.isEmpty {
                    Text(extra)
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .lineLimit(1)
            .ringsPin(66, 36)
            if let best = row.best {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(best.weight)
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Text("× \(best.reps)")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                }
                .lineLimit(1)
                .ringsPin(width - 24, 8, .topTrailing)
                if let label = row.bestLabel {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                        .ringsPin(width - 24, 32, .topTrailing)
                }
            }
        }
        .frame(width: width, height: 100, alignment: .topLeading)
        .contentShape(Rectangle())
        .help(row.note ?? "")
    }
}

// MARK: - Sağ alt: ay + program

struct WorkoutMonthPanel<Footer: View>: View {
    /// "Eylül"
    let monthTitle: String
    let count: Int
    /// Ayın günleri (1…son) ve durumları.
    let days: [(date: Date, status: WorkoutDayStatus)]
    let onSelect: (Date) -> Void
    @ViewBuilder let footer: () -> Footer

    private static var weekdays: [String] { ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"] }

    var body: some View {
        RingsPanel(title: monthTitle, sub: "tutarlılık") { size in
            let cell = (size.width - 48) / 7
            let top: CGFloat = 150
            let rows = Self.rowCount(days)
            ZStack(alignment: .topLeading) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(count)")
                        .font(.system(size: 56, weight: .semibold).monospacedDigit())
                        .tracking(-1.4)
                        .foregroundStyle(Palette.textPrimary)
                    Text("seans")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textTertiary)
                }
                .ringsPin(24, 46)
                ForEach(Array(Self.weekdays.enumerated()), id: \.offset) { index, name in
                    Text(name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                        .ringsPin(24 + cell * CGFloat(index) + cell / 2, top, .top)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    let index = Self.cellIndex(day.date, in: days)
                    let cx = 24 + cell * CGFloat(index.0) + cell / 2
                    let cy = top + 34 + 64 * CGFloat(index.1) + 13
                    Button { onSelect(day.date) } label: {
                        ZStack(alignment: .top) {
                            WorkoutDayMark(status: day.status, radius: 13)
                            Text(Fmt.dayNumber.string(from: day.date))
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(Palette.textQuaternary)
                                .padding(.top, 30)
                        }
                        .frame(width: 44, height: 48, alignment: .top)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Fmt.dateLong.string(from: day.date))
                    .position(x: cx, y: cy - 13 + 24)
                }
                legend
                    .ringsPin(24, top + 34 + 64 * CGFloat(rows) + 36)
                Rectangle()
                    .fill(Palette.textPrimary.opacity(0.06))
                    .frame(width: max(0, size.width - 48), height: 1)
                    .position(x: size.width / 2, y: size.height - 92 + 0.5)
                footer()
                    .frame(width: max(0, size.width - 48))
                    .ringsPin(24, size.height - 70)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            item(Circle().fill(Palette.positive).frame(width: 10, height: 10), "yapıldı")
            item(Circle().strokeBorder(Palette.warning, lineWidth: 2).frame(width: 11, height: 11), "bugün")
            item(Circle().strokeBorder(Palette.textPrimary.opacity(0.22), lineWidth: 1.5).frame(width: 11, height: 11), "planlı")
            item(Circle().strokeBorder(Palette.negative.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2])).frame(width: 11, height: 11), "kaçtı")
        }
    }

    private func item<M: View>(_ mark: M, _ label: String) -> some View {
        HStack(spacing: 6) {
            mark
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    /// Pazartesi başlangıçlı ızgarada (sütun, satır).
    private static func cellIndex(_ date: Date, in days: [(date: Date, status: WorkoutDayStatus)]) -> (Int, Int) {
        let cal = Calendar.current
        let col = (cal.component(.weekday, from: date) + 5) % 7
        guard let first = days.first?.date else { return (col, 0) }
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let index = (cal.dateComponents([.day], from: cal.startOfDay(for: first), to: cal.startOfDay(for: date)).day ?? 0) + lead
        return (col, index / 7)
    }

    private static func rowCount(_ days: [(date: Date, status: WorkoutDayStatus)]) -> Int {
        guard let last = days.last?.date else { return 0 }
        return cellIndex(last, in: days).1 + 1
    }
}
