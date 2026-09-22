import SwiftUI

// MARK: - Tahliller · V3 "Halka"
//
// Tasarım: "Hercules Mac Tasarımı" tuvali ▸ Tahliller · V3 Halka (artboard 1829×1147; koordinatlar
// tasarım betiği mac_tahliller_v3.py ile birebir). Solda tek halka: her değer bir dilim (kategori
// kategori, durum renginde), ortada kaç değerin hedefte olduğu, altında sınırdakiler; sağda bütün
// değerler sade liste (nokta · ad · değer · önceki tahlile göre değişim). Renkler uygulamanın sade
// üçlüsü: hedefte adaçayı, sınırda pirinç, referans dışı kırmızı. Kabuk RingsPanel (DashboardRings).

extension LabStatus {
    /// Halka ve listedeki nokta rengi.
    var ringColor: Color {
        switch self {
        case .optimal, .normal: return Palette.positive
        case .watch: return Palette.warning
        case .low, .high: return Palette.negative
        case .unknown: return Palette.textQuaternary
        }
    }

    var ringOpacity: Double {
        if needsAttention { return 0.95 }
        return self == .unknown ? 0.5 : 0.62
    }
}

extension LabCategory {
    /// Halkanın çevresindeki kısa ad.
    var ringLabel: String {
        switch self {
        case .hemogram: return "Kan"
        case .lipid: return "Lipid"
        case .metabolic: return "Şeker"
        case .hormone: return "Hormon"
        case .thyroid: return "Tiroit"
        case .liver: return "Karaciğer"
        case .kidney: return "Böbrek"
        case .mineral: return "Vitamin"
        case .urine: return "İdrar"
        case .other: return "Diğer"
        }
    }
}

extension LabFormat {
    /// "+92", "−3,0" — tipografik eksi; yuvarlanınca sıfırsa işaretsiz.
    static func signedDelta(_ delta: Double, decimals: Int) -> String {
        let text = Fmt.num(abs(delta), digits: decimals)
        guard (abs(delta) * pow(10, Double(decimals))).rounded() > 0 else { return text }
        return (delta < 0 ? "\u{2212}" : "+") + text
    }
}

// MARK: - Sol: halka

struct LabRingCard<Actions: View>: View {
    let panel: LabPanel
    let groups: [(category: LabCategory, items: [LabResult])]
    let summary: LabPanelSummary
    let flagged: [LabResult]
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        RingsPanel(title: "Son tahlil", sub: subtitle) { size in
            LabRingDrawing(size: size, groups: groups, summary: summary, flagged: flagged)
            actions()
                .ringsPin(24, size.height - 24 - 17, .leading)
        }
    }

    private var subtitle: String {
        let date = Fmt.dateLong.string(from: panel.date)
        guard let source = panel.source, !source.isEmpty else { return date }
        return "\(date) · \(source)"
    }
}

private struct LabRingDrawing: View {
    let size: CGSize
    let groups: [(category: LabCategory, items: [LabResult])]
    let summary: LabPanelSummary
    let flagged: [LabResult]

    private static let lineWidth: CGFloat = 30

    var body: some View {
        let lw = Self.lineWidth
        // Tasarım ölçüsünde (734 × 1070) merkez 452, yarıçap 214; başka ölçüde orantılı.
        let r = max(96, min(214, (size.width - 300) / 2, size.height * 0.2))
        let c = CGPoint(x: size.width / 2, y: (size.height * 452 / 1070).rounded())
        let scale = r / 214
        let segments = Self.segments(groups)
        let evaluated = max(summary.evaluated, 1)
        let inTarget = summary.optimal + summary.normal
        ZStack(alignment: .topLeading) {
            ForEach(segments.arcs) { arc in
                RingsArc(center: c, radius: r, from: arc.from, to: arc.to)
                    .stroke(arc.status.ringColor.opacity(arc.status.ringOpacity), lineWidth: lw)
            }
            ForEach(segments.labels) { label in
                let p = ringsPoint(c, r + lw / 2 + 22, label.mid)
                let align: Alignment = abs(label.mid) < 20 || abs(label.mid - 180) < 20 || label.mid > 340
                    ? .top : (label.mid < 180 ? .topLeading : .topTrailing)
                Text(label.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .ringsPin(p.x, p.y - 8, align)
            }
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(inTarget)")
                        .foregroundStyle(Palette.textPrimary)
                    Text("/\(evaluated)")
                        .foregroundStyle(Palette.textTertiary)
                }
                .font(.system(size: max(48, 76 * scale), weight: .semibold).monospacedDigit())
                .tracking(-2 * scale)
                Text("değer hedefte")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textTertiary)
            }
            .lineLimit(1)
            .ringsPin(c.x, c.y - 58 * scale, .top)

            if !flagged.isEmpty {
                Text(flaggedTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(summary.outOfRange > 0 ? Palette.negative : Palette.warning)
                    .ringsPin(c.x, c.y + r + 52, .top)
                flaggedChips
                    .ringsPin(c.x, c.y + r + 80, .top)
            }
        }
    }

    private var flaggedTitle: String {
        if summary.outOfRange > 0 && summary.watch > 0 {
            return "\(summary.outOfRange) referans dışı · \(summary.watch) sınırda"
        }
        return summary.outOfRange > 0 ? "\(summary.outOfRange) referans dışı" : "\(summary.watch) sınırda"
    }

    /// Sınırdaki / referans dışındaki değerler: kısa ad üstte, değer altta. En çok 4; fazlası "+N".
    private var flaggedChips: some View {
        let shown = flagged.count > 4 ? Array(flagged.prefix(3)) : flagged
        return HStack(alignment: .center, spacing: 48) {
            ForEach(shown) { result in
                VStack(spacing: 2) {
                    Text(result.displayName.replacingOccurrences(of: " Kolesterol", with: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(result.displayValue)
                            .font(.system(size: 26, weight: .semibold).monospacedDigit())
                            .foregroundStyle(result.status.ringColor)
                        if let unit = result.unit, !unit.isEmpty {
                            Text(unit)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
                .lineLimit(1)
                .help(LabFormat.tooltip(for: result))
            }
            if flagged.count > 4 {
                Text("+\(flagged.count - 3)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    // MARK: Dilimler

    struct Arc: Identifiable {
        let id: Int
        let from: Double
        let to: Double
        let status: LabStatus
    }

    struct Label: Identifiable {
        let id: Int
        let mid: Double
        let text: String
    }

    /// Her değer bir dilim; dilimler arası 2,2°, kategoriler arası ek 5,5° (değer çoksa daralır).
    static func segments(_ groups: [(category: LabCategory, items: [LabResult])]) -> (arcs: [Arc], labels: [Label]) {
        let count = groups.reduce(0) { $0 + $1.items.count }
        guard count > 0 else { return ([], []) }
        let segGap = count > 30 ? 1.2 : 2.2
        let catGap = count > 30 ? 3.5 : 5.5
        let seg = max(0.5, (360 - Double(count) * segGap - Double(groups.count) * catGap) / Double(count))
        var arcs: [Arc] = []
        var labels: [Label] = []
        var a = catGap / 2
        for (gi, group) in groups.enumerated() {
            let start = a
            for item in group.items {
                arcs.append(Arc(id: arcs.count, from: a, to: a + seg, status: item.status))
                a += seg + segGap
            }
            labels.append(Label(id: gi, mid: (start + a - segGap) / 2, text: group.category.ringLabel))
            a += catGap
        }
        return (arcs, labels)
    }
}

// MARK: - Sağ: değerler

struct LabValuesCard: View {
    let groups: [(category: LabCategory, items: [LabResult])]
    let previous: LabPanel?

    var body: some View {
        RingsPanel(title: "Değerler", sub: previous.map { "önceki tahlile göre · \(Fmt.dayMonth.string(from: $0.date))" }) { size in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.category) { group in
                        Text(group.category.label)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(height: 26, alignment: .topLeading)
                            .padding(.leading, 24)
                        ForEach(group.items) { item in
                            LabValueRow(result: item, previous: previous, width: size.width)
                        }
                        Color.clear.frame(height: 10)
                    }
                    Text("Referans aralıkları laboratuvarındır; hedef bantlar uygulamanın yorumudur — tanı değildir.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textQuaternary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                }
                .frame(width: size.width, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: size.width, height: max(0, size.height - 62), alignment: .top)
            .padding(.top, 62)
        }
    }
}

/// Satır: durum noktası · ad · değer (sınırdaysa renkli) · önceki tahlile göre değişim.
private struct LabValueRow: View {
    let result: LabResult
    let previous: LabPanel?
    let width: CGFloat

    private var delta: Double? {
        guard let now = result.value, !result.code.isEmpty,
              let before = previous?.value(result.code), abs(now - before) > 0.0001
        else { return nil }
        return now - before
    }

    var body: some View {
        let attention = result.status.needsAttention
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(result.status.ringColor)
                .frame(width: 8, height: 8)
                .ringsPin(24, 5)
            Text(result.displayName)
                .font(.system(size: 14))
                .foregroundStyle(attention ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: max(0, width - 42 - 200), alignment: .leading)
                .ringsPin(42, 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(result.displayValue)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(attention ? result.status.ringColor : Palette.textPrimary)
                if let unit = result.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .lineLimit(1)
            .ringsPin(width - 96, -1, .topTrailing)
            deltaText
                .ringsPin(width - 24, 0, .topTrailing)
        }
        .frame(width: width, height: 38, alignment: .topLeading)
        .contentShape(Rectangle())
        .help(LabFormat.tooltip(for: result))
    }

    @ViewBuilder
    private var deltaText: some View {
        if let delta {
            let way = LabFormat.deltaDirection(delta, analyte: result.analyte)
            Text(LabFormat.signedDelta(delta, decimals: result.analyte?.decimals ?? 1))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(way > 0 ? Palette.positive : (way < 0 ? Palette.negative : Palette.textTertiary))
        } else {
            Text("—")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textQuaternary)
        }
    }
}
