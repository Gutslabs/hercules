import SwiftUI
import LucideKit
import SwiftData

// İlerleme ▸ Dönemler: dönem · ara · dönem … şeridi ve düzenleme sheet'leri.
// Hesap `DietTimeline`'da, saklama `DietEpochStore`'da; burası yalnız arayüz.

private enum EpochFmt {
    /// "18 May – 3 Ağu" / süren parça için "22 Eyl – sürüyor".
    static func range(_ segment: DietTimeline.Segment) -> String {
        let first = Fmt.date.string(from: segment.firstDay)
        return segment.isOngoing
            ? "\(first) – sürüyor"
            : "\(first) – \(Fmt.date.string(from: segment.lastDay))"
    }

    /// "−6,6 kg" / "+0,8 kg" — tipografik eksi, sayfanın geri kalanıyla aynı.
    static func delta(_ value: Double) -> String {
        "\(value < 0 ? "−" : "+")\(Fmt.num(abs(value), digits: 1)) kg"
    }
}

// MARK: - Şerit

/// Dönemler şeridi (tasarım: İlerleme · V1 Rota): tek zaman ekseninde dönem · ara · dönem
/// bantları; süren dönemin ardından varışa kadar kesikli "tahmini" bant. Dönem bandına
/// tıklanınca düzenleyici açılır; ara türetilmiş veridir, düzenlenmez.
struct EpochTimelineStrip: View {
    let segments: [DietTimeline.Segment]
    /// Kilo verme hedefinde eksi delta "iyi"dir; alma hedefinde artı.
    let isLoss: Bool
    /// Varış tahmini — son parça süren bir dönemse kesikli bant bu güne uzanır.
    let eta: Date?
    let onStartNew: () -> Void
    let onEdit: (UUID) -> Void
    var now: Date = .now

    private let barY: CGFloat = 70
    private let barHeight: CGFloat = 34
    /// Komşu bantlar arası yarım boşluk.
    private let gap: CGFloat = 3

    var body: some View {
        RingsPanel(title: "Dönemler") { size in
            ZStack(alignment: .topLeading) {
                timeline(size)
                newButton
                    .ringsPin(size.width - 18, 14, .topTrailing)
            }
        }
    }

    private var newButton: some View {
        Button(action: onStartNew) {
            HStack(spacing: 5) {
                Lucide(sf: "plus", size: 10)
                Text("Yeni dönem")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
        }
        .buttonStyle(FlatButtonStyle(cornerRadius: 8))
        .help("Süren dönemi kapatıp sıfırdan yeni bir dönem başlat")
    }

    private func days(_ from: Date, _ to: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to)).day ?? 0
    }

    private func timeline(_ size: CGSize) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let x0: CGFloat = 24
        let x1 = size.width - 24
        let first = segments.first.map { cal.startOfDay(for: $0.firstDay) } ?? today
        let ongoingEpoch = segments.last.map { $0.isEpoch && $0.isOngoing } ?? false
        let future = ongoingEpoch ? eta.map { cal.startOfDay(for: $0) } : nil
        // Eksenin sonu: varış varsa o gün; yoksa bugünden biraz ileri (şerit nefes alsın).
        let pastDays = max(1, days(first, today, cal) + 1)
        let end = future ?? (cal.date(byAdding: .day, value: max(7, pastDays / 8), to: today) ?? today)
        let total = Double(max(1, days(first, end, cal)))
        let x: (Date) -> CGFloat = { d in
            x0 + (x1 - x0) * CGFloat(Double(days(first, d, cal)) / total)
        }
        let labelY = barY + barHeight + 12
        let todayX = x(today)
        let showToday = todayX - x0 > 56 && (future == nil || x1 - todayX > 96)
        // Taze dönem (ör. 10 günlük Dönem 2) uzun bir tahmini bandın yanında çok dar kalır:
        // etiketi bandın başından tahmini bölgeye taşar, "tahmini" sağa çekilir.
        let last = segments.last
        let lastStart = last.map { x($0.firstDay) + ($0.id == segments.first?.id ? 0 : gap) } ?? x0
        let floatLabel = future != nil && (last.map { $0.isEpoch && $0.isOngoing } ?? false)
            && todayX - gap - lastStart < 190
        return ZStack(alignment: .topLeading) {
            ForEach(segments) { seg in
                let isFirst = seg.id == segments.first?.id
                let endDay = seg.isOngoing ? today : (cal.date(byAdding: .day, value: 1, to: seg.lastDay) ?? seg.lastDay)
                let sx0 = x(seg.firstDay) + (isFirst ? 0 : gap)
                let sx1 = x(endDay) - gap
                segmentView(seg, width: max(0, sx1 - sx0), showLabel: !(floatLabel && seg.id == last?.id))
                    .position(x: (sx0 + sx1) / 2, y: barY + barHeight / 2)
            }
            if let future {
                let fx0 = todayX + gap
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.textPrimary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: max(0, x1 - fx0), height: barHeight)
                    .position(x: (fx0 + x1) / 2, y: barY + barHeight / 2)
                if floatLabel, let last {
                    label(last, showDays: true, showDelta: true)
                        .allowsHitTesting(false)
                        .ringsPin(max(lastStart + 16, todayX + gap + 12), barY + barHeight / 2, .leading)
                }
                Text("tahmini")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textQuaternary)
                    .ringsPin(floatLabel ? x1 - 16 : (fx0 + x1) / 2, barY + 9, floatLabel ? .topTrailing : .top)
                Text(Fmt.dateLong.string(from: future))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.warning)
                    .ringsPin(x1, labelY, .topTrailing)
            }
            Text(Fmt.dateMonthAxis.string(from: first))
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
                .ringsPin(x0, labelY)
            if showToday {
                Text("bugün")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .ringsPin(todayX, labelY, .top)
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ seg: DietTimeline.Segment, width: CGFloat, showLabel: Bool) -> some View {
        if case .epoch(_, let id) = seg.kind {
            Button { onEdit(id) } label: { band(seg, width: width, showLabel: showLabel) }
                .buttonStyle(.plain)
                .help("Dönemi düzenle · \(EpochFmt.range(seg))")
        } else {
            band(seg, width: width, showLabel: showLabel)
                .help("Ara · \(EpochFmt.range(seg))")
        }
    }

    private func band(_ seg: DietTimeline.Segment, width: CGFloat, showLabel: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack(alignment: .leading) {
            if seg.isEpoch {
                shape.fill(Palette.chart.opacity(seg.isOngoing ? 0.14 : 0.08))
                shape.strokeBorder(Palette.chart.opacity(seg.isOngoing ? 0.45 : 0.28), lineWidth: 1)
            } else {
                // Ara, dönemlerden bir ton geride durur: veri değil, boşluk.
                shape.fill(Palette.textPrimary.opacity(0.03))
                shape.strokeBorder(Palette.textPrimary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            if showLabel {
                ViewThatFits(in: .horizontal) {
                    label(seg, showDays: true, showDelta: true)
                    label(seg, showDays: true, showDelta: false)
                    label(seg, showDays: false, showDelta: false)
                    Color.clear.frame(width: 0, height: 0)
                }
                .padding(.horizontal, 16)
                .frame(width: width, alignment: .leading)
            }
        }
        .frame(width: width, height: barHeight)
        .contentShape(shape)
    }

    private func label(_ seg: DietTimeline.Segment, showDays: Bool, showDelta: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title(seg))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(seg.isEpoch ? Palette.textPrimary : Palette.textSecondary)
            if showDays {
                Text("\(seg.days) gün")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
            }
            if showDelta, let delta = seg.delta, abs(delta) >= 0.05 {
                Text(EpochFmt.delta(delta))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(deltaColor(delta))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func title(_ segment: DietTimeline.Segment) -> String {
        if case .epoch(let number, _) = segment.kind { return "Dönem \(number)" }
        return "Ara"
    }

    private func deltaColor(_ delta: Double) -> Color {
        let towardGoal = isLoss ? delta < 0 : delta > 0
        return towardGoal ? Palette.positive : Palette.negative
    }
}

// MARK: - Yeni dönem

/// "Sıfırdan başla": süren dönemi seçilen günde kapatır, yenisini açar. Tasarım: tuval ▸ Pencereler ·
/// İlerleme (az yazı). Üstte canlı şerit (dönem · ara · yeni dönem), altında iki tarih, veriden iki
/// öneri (son öğün kaydı, dönemin en düşük tartısı), başlangıç kilosu ve not.
struct EpochStartSheet: View {
    let store: DietEpochStore
    /// Tarihe göre artan kilo ölçümleri (varsayılan başlangıç kilosu + öneri için).
    let weights: [TrendPoint]
    let onClose: () -> Void

    @Environment(\.modelContext) private var ctx
    @State private var previousLastDay: Date
    @State private var start: Date
    @State private var startWeight: Double?
    @State private var note = ""
    /// En son öğün kaydının günü — "diyeti en son ne zaman tuttum?" için ipucu.
    @State private var lastFoodLogDay: Date?

    private let cal = Calendar.current

    init(store: DietEpochStore, weights: [TrendPoint], onClose: @escaping () -> Void) {
        self.store = store
        self.weights = weights
        self.onClose = onClose
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        _start = State(initialValue: today)
        _previousLastDay = State(initialValue: max(store.active?.start ?? yesterday, yesterday))
        _startWeight = State(initialValue: weights.last?.value)
    }

    private var closing: DietEpoch? { store.active }
    private var closingNumber: Int { store.epochs.count }
    private var newNumber: Int { store.epochs.count + 1 }

    /// Yeni dönem, son dönemin bittiği (ya da başladığı) günden sonra başlamalı.
    private var earliestStart: Date {
        let last = store.epochs.last
        let floor = last?.lastDay ?? last?.start ?? .distantPast
        return cal.date(byAdding: .day, value: 1, to: floor) ?? floor
    }

    private var latestPreviousLastDay: Date {
        cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: start)) ?? start
    }

    private var canSave: Bool {
        guard cal.startOfDay(for: start) >= earliestStart else { return false }
        if let closing {
            let last = cal.startOfDay(for: previousLastDay)
            guard last >= closing.start, last <= latestPreviousLastDay else { return false }
        }
        return startWeight.map { $0.isFinite && $0 > 0 } ?? true
    }

    var body: some View {
        SadeSheet(title: "Dönem \(newNumber)'\(Self.dativeSuffix(newNumber)) başla", onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                timeline
                HStack(alignment: .bottom, spacing: 12) {
                    if let closing {
                        SadeDateField(label: "Dönem \(closingNumber) bitiş", date: $previousLastDay,
                                      range: closing.start...max(closing.start, latestPreviousLastDay))
                    }
                    SadeDateField(label: "Dönem \(newNumber) başlangıç", date: $start,
                                  range: earliestStart...max(earliestStart, cal.startOfDay(for: .now)))
                }
                .padding(.top, 22)
                if let closing {
                    suggestionRow(for: closing)
                        .padding(.top, 10)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    SadeField(label: "Başlangıç kilosu") {
                        TextField("", value: $startWeight, format: .number, prompt: Text("son ölçüm").foregroundStyle(Palette.textTertiary))
                            .textFieldStyle(.plain)
                            .font(.system(size: 14).monospacedDigit())
                        Text("kg")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .frame(width: 200)
                    SadeTextArea(label: "Not", text: $note, prompt: "ör: tatil sonrası, 75'e kadar", lines: 1...3, minHeight: 38)
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 24)
        } footerLeading: {
            EmptyView()
        } footerTrailing: {
            SadeButton(title: "Vazgeç", action: onClose)
            SadeButton(title: "Dönemi başlat", role: .primary, enabled: canSave) {
                store.startNewEpoch(
                    on: start,
                    startWeight: startWeight,
                    note: note,
                    previousLastDay: closing == nil ? nil : previousLastDay
                )
                onClose()
            }
        }
        .frame(width: 620)
        .onChange(of: start) { _, _ in
            // Başlangıç geri çekilirse son gün onun önünde kalsın.
            if previousLastDay > latestPreviousLastDay { previousLastDay = latestPreviousLastDay }
        }
        .task { loadLastFoodLogDay() }
    }

    // MARK: Canlı şerit

    /// Kaydetmeden önce sonucu gösterir: kapanan dönemin gün sayısı, aradaki boşluk ve yeni dönem.
    /// Sayılar kayıttan sonra İlerleme şeridinde görünecek olanla aynı hesaptan (`DietTimeline`).
    @ViewBuilder private var timeline: some View {
        let preview = previewDays
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let preview {
                    EpochSegmentLabel(title: "Dönem \(closingNumber)", detail: "\(preview.epoch) gün")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let rest = preview.rest {
                        EpochSegmentLabel(title: "Ara", detail: "\(rest)", color: Palette.textTertiary)
                            .frame(width: 60, alignment: .leading)
                    }
                }
                EpochSegmentLabel(title: "Dönem \(newNumber)", color: Palette.positive)
                    .frame(width: preview == nil ? nil : 110, alignment: .leading)
                    .frame(maxWidth: preview == nil ? .infinity : nil, alignment: .leading)
            }
            HStack(spacing: 8) {
                if let preview {
                    Capsule().fill(Palette.chart.opacity(0.75)).frame(height: 10)
                    if preview.rest != nil {
                        EpochHatch().frame(width: 60, height: 10)
                    }
                }
                EpochOpenEnd(color: Palette.positive)
                    .frame(width: preview == nil ? nil : 110)
                    .frame(maxWidth: preview == nil ? .infinity : nil)
            }
            HStack(spacing: 8) {
                if let closing, preview != nil {
                    HStack {
                        Text(Fmt.dateMonthAxis.string(from: closing.start))
                        Spacer(minLength: 4)
                        Text(Fmt.dateMonthAxis.string(from: previousLastDay))
                    }
                    if preview?.rest != nil { Color.clear.frame(width: 60, height: 1) }
                }
                Text(Fmt.dateMonthAxis.string(from: start))
                    .frame(width: preview == nil ? nil : 110, alignment: .leading)
                    .frame(maxWidth: preview == nil ? .infinity : nil, alignment: .leading)
            }
            .font(.system(size: 11.5).monospacedDigit())
            .foregroundStyle(Palette.textTertiary)
        }
    }

    /// (kapanan dönemin gün sayısı, ara gün sayısı ya da nil = ara yok); süren dönem yoksa nil.
    private var previewDays: (epoch: Int, rest: Int?)? {
        guard let closing,
              let index = store.epochs.firstIndex(where: { $0.id == closing.id })
        else { return nil }
        var preview = store.epochs
        preview[index].lastDay = previousLastDay
        preview.append(DietEpoch(start: start))
        let segments = DietTimeline.segments(epochs: preview, weights: [])
        guard let closedAt = segments.firstIndex(where: { $0.id == closing.id.uuidString }) else { return nil }
        let after = segments.indices.contains(closedAt + 1) ? segments[closedAt + 1] : nil
        let rest = after.flatMap { $0.isEpoch ? nil : $0 }
        return (segments[closedAt].days, rest?.days)
    }

    // MARK: Öneriler

    /// "Diyeti ne zaman bıraktım?" çoğu zaman net hatırlanmaz; veriden iki çapa:
    /// en son öğün kaydı ve dönemin en düşük tartısı. Tıklayınca bitiş tarihini doldurur.
    @ViewBuilder private func suggestionRow(for closing: DietEpoch) -> some View {
        let lowest = DietTimeline.weights(in: closing, from: weights).min { $0.value < $1.value }
        let picks: [(label: String, help: String, day: Date)] = [
            lastFoodLogDay.map { ("Son öğün · \(Fmt.dateMonthAxis.string(from: $0))", "Son öğün kaydı", $0) },
            lowest.map { ("En düşük · \(Fmt.dateMonthAxis.string(from: $0.date))",
                          "En düşük kilo · \(Fmt.num($0.value, digits: 1)) kg", $0.date) },
        ]
        .compactMap { $0 }
        .filter { cal.startOfDay(for: $0.day) >= closing.start && cal.startOfDay(for: $0.day) <= latestPreviousLastDay }

        if !picks.isEmpty {
            HStack(spacing: 6) {
                ForEach(picks, id: \.label) { pick in
                    SadePill(title: pick.label,
                             selected: cal.isDate(previousLastDay, inSameDayAs: pick.day),
                             help: pick.help) {
                        previousLastDay = cal.startOfDay(for: pick.day)
                    }
                }
            }
        }
    }

    private func loadLastFoodLogDay() {
        var descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        lastFoodLogDay = (try? ctx.fetch(descriptor))?.first?.date
    }

    /// "Dönem 2'ye", "Dönem 3'e", "Dönem 6'ya" … sayının okunuşuna göre yönelme eki.
    static func dativeSuffix(_ number: Int) -> String {
        switch number % 10 {
        case 1, 5, 8: return "e"       // bir, beş, sekiz
        case 2, 7: return "ye"         // iki, yedi
        case 3, 4: return "e"          // üç, dört
        case 6: return "ya"            // altı
        case 9: return "a"             // dokuz
        default:                        // on, yirmi, otuz …
            switch (number / 10) % 10 {
            case 1, 3, 4, 6, 9: return "a"   // on, otuz, kırk, altmış, doksan
            case 2, 5: return "ye"           // yirmi, elli
            case 7, 8: return "e"            // yetmiş, seksen
            default: return "e"
            }
        }
    }
}

// MARK: - Dönem düzenleyici

/// Tek bir dönemin tarihleri / başlangıç kilosu / notu. Yalnız SON dönem "sürüyor"
/// olabilir; öncekilerin bitişi zorunludur (sonraki dönem onları zaten sınırlar).
struct EpochEditorSheet: View {
    let store: DietEpochStore
    let epoch: DietEpoch
    let onClose: () -> Void

    @State private var start: Date
    @State private var lastDay: Date
    @State private var isOngoing: Bool
    @State private var startWeight: Double?
    @State private var note: String
    @State private var confirmingDelete = false

    private let cal = Calendar.current

    init(store: DietEpochStore, epoch: DietEpoch, onClose: @escaping () -> Void) {
        self.store = store
        self.epoch = epoch
        self.onClose = onClose
        _start = State(initialValue: epoch.start)
        _lastDay = State(initialValue: epoch.lastDay ?? Calendar.current.startOfDay(for: .now))
        _isOngoing = State(initialValue: epoch.lastDay == nil)
        _startWeight = State(initialValue: epoch.startWeight)
        _note = State(initialValue: epoch.note ?? "")
    }

    private var index: Int? { store.epochs.firstIndex { $0.id == epoch.id } }
    private var number: Int { (index ?? 0) + 1 }
    private var isLatest: Bool { index == store.epochs.indices.last }
    private var previous: DietEpoch? { index.flatMap { $0 > 0 ? store.epochs[$0 - 1] : nil } }
    private var next: DietEpoch? {
        index.flatMap { store.epochs.indices.contains($0 + 1) ? store.epochs[$0 + 1] : nil }
    }

    private var today: Date { cal.startOfDay(for: .now) }

    /// Önceki dönemin son gününden sonra, sonraki dönemin başlangıcından önce.
    private var startRange: ClosedRange<Date> {
        let floor = previous.map { cal.date(byAdding: .day, value: 1, to: $0.lastDay ?? $0.start) ?? $0.start }
            ?? .distantPast
        let ceiling = isOngoing ? today : min(today, cal.startOfDay(for: lastDay))
        return floor...max(floor, ceiling)
    }

    private var lastDayRange: ClosedRange<Date> {
        let floor = cal.startOfDay(for: start)
        let ceiling = next.map { cal.date(byAdding: .day, value: -1, to: $0.start) ?? $0.start } ?? today
        return floor...max(floor, ceiling)
    }

    private var canSave: Bool {
        startRange.contains(cal.startOfDay(for: start))
            && (isOngoing || lastDayRange.contains(cal.startOfDay(for: lastDay)))
            && (startWeight.map { $0.isFinite && $0 > 0 } ?? true)
    }

    /// "128. gün" (sürüyor) ya da "18 May – 20 Eyl".
    private var subtitle: String {
        if isOngoing {
            let days = (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: today).day ?? 0) + 1
            return "\(max(1, days)). gün"
        }
        return "\(Fmt.dateMonthAxis.string(from: start)) – \(Fmt.dateMonthAxis.string(from: lastDay))"
    }

    var body: some View {
        SadeSheet(title: "Dönem \(number)", subtitle: subtitle, onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Capsule().fill(Palette.chart.opacity(0.75)).frame(height: 10)
                        if isOngoing {
                            EpochOpenEnd(color: Palette.chart).frame(width: 80)
                        }
                    }
                    HStack {
                        Text(Fmt.dateMonthAxis.string(from: start))
                        Spacer(minLength: 8)
                        Text(isOngoing ? "bugün" : Fmt.dateMonthAxis.string(from: lastDay))
                    }
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    SadeDateField(label: "Başlangıç", date: $start, range: startRange)
                    if !isOngoing {
                        SadeDateField(label: "Bitiş", date: $lastDay, range: lastDayRange)
                    }
                }
                .padding(.top, 20)
                if isLatest {
                    SadeToggleRow(title: "Sürüyor", isOn: $isOngoing)
                        .padding(.top, 14)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    SadeField(label: "Başlangıç kilosu") {
                        TextField("", value: $startWeight, format: .number, prompt: Text("ölçümden").foregroundStyle(Palette.textTertiary))
                            .textFieldStyle(.plain)
                            .font(.system(size: 14).monospacedDigit())
                        Text("kg")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .frame(width: 170)
                    SadeTextArea(label: "Not", text: $note, prompt: "ör: yaz cut'ı", lines: 1...3, minHeight: 38)
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 24)
        } footerLeading: {
            // Yıkıcı eylem SOLDA; tek kalan dönem silinemez (İlerleme'nin bir başlangıcı olmalı).
            if store.epochs.count > 1 {
                SadeButton(title: "Sil", role: .destructive) { confirmingDelete = true }
            }
        } footerTrailing: {
            SadeButton(title: "İptal", action: onClose)
            SadeButton(title: "Kaydet", role: .primary, enabled: canSave) {
                var updated = epoch
                updated.start = start
                updated.lastDay = isOngoing ? nil : lastDay
                updated.startWeight = startWeight
                updated.note = note
                store.update(updated)
                onClose()
            }
        }
        .frame(width: 520)
        .onChange(of: start) { _, newStart in
            if lastDay < newStart { lastDay = newStart }
        }
        .alert("Dönem \(number) silinsin mi?", isPresented: $confirmingDelete) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) {
                store.delete(id: epoch.id)
                onClose()
            }
        } message: {
            Text("Ölçümlerin ve öğünlerin silinmez; yalnız bu dönemin sınırları kalkar ve komşu ara buna göre yeniden hesaplanır.")
        }
    }
}

// MARK: - Şerit parçaları

/// "Dönem 1  126 gün" etiketi.
private struct EpochSegmentLabel: View {
    let title: String
    var detail: String? = nil
    var color: Color = Palette.textSecondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            if let detail {
                Text(detail)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .lineLimit(1)
    }
}

/// Ara: çizgili kapsül.
private struct EpochHatch: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2))
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.textPrimary.opacity(0.03)))
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(stripe, with: .color(Palette.textPrimary.opacity(0.14)), lineWidth: 3)
                x += 7
            }
        }
    }
}

/// Açık uç: dolu nokta + kesikli çizgi ("sürüyor" / "başlıyor").
private struct EpochOpenEnd: View {
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 14, height: 14)
            Line()
                .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(height: 2)
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}
