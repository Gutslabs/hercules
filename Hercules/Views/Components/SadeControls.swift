import SwiftUI
import LucideKit

// MARK: - Sade pencere kontrolleri
//
// SadeSheet'in devamı — "Hercules Mac Tasarımı" tuvali ▸ Pencereler satırları (az yazı): parçalı
// seçim, hap düğmesi, anahtar satırı, tarih/saat kutuları, uyarı satırı, küçük etiket, referans
// göstergesi ve Grafikler dilindeki küçük çizgi grafik.

/// Sayılar tipografik eksiyle ("−1,2"); Fmt'nin tr_TR biçimi üstüne.
enum SadeFormat {
    static func num(_ v: Double, digits: Int = 1) -> String {
        Fmt.num(v, digits: digits).replacingOccurrences(of: "-", with: "−")
    }

    static func signed(_ v: Double, digits: Int = 1) -> String {
        (v > 0 ? "+" : "") + num(v, digits: digits)
    }

    /// Kilo: tam sayıysa ondalıksız ("80"), değilse bir hane ("85,3").
    static func kg(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : num(v, digits: 1)
    }
}

/// Parçalı seçim: kutu içinde eşit parçalar, seçili parça beyaz %9.
struct SadeSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(on ? Palette.textPrimary : Palette.textTertiary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.textPrimary.opacity(on ? 0.09 : 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .sadeBox(radius: 11)
    }
}

/// Küçük hap düğmesi (hızlı seçenekler: "3", "6", "12" ay; "‹ 1 gün").
struct SadePill: View {
    let title: String
    var leading: String? = nil
    var trailing: String? = nil
    var selected = false
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let leading { Lucide(sf: leading, size: 12) }
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium).monospacedDigit())
                    .lineLimit(1)
                if let trailing { Lucide(sf: trailing, size: 12) }
            }
            .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.textPrimary.opacity(selected ? 0.10 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.textPrimary.opacity(selected ? 0.14 : 0.06), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Kutu içinde ad + anahtar.
struct SadeToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Palette.positive)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 42)
        .sadeBox(radius: 11)
    }
}

/// Kutu içinde kare onay + kısa ad ("IG'den çıkar").
struct SadeCheckRow: View {
    let title: String
    @Binding var isOn: Bool
    var help = ""

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isOn ? Palette.positive : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(isOn ? Color.clear : Palette.textTertiary, lineWidth: 1.5))
                    .overlay {
                        if isOn {
                            Lucide(sf: "checkmark", size: 11)
                                .foregroundStyle(Palette.background)
                        }
                    }
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .sadeBox(radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Renkli ikon + kısa satır (uyarılar pirinç, hatalar kırmızı).
struct SadeNote: View {
    let text: String
    var icon = "exclamationmark.triangle"
    var color: Color = Palette.warning

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Lucide(sf: icon, size: 13)
            Text(text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
    }
}

/// Küçük gri etiket ("oto", "Diğer").
struct SadeChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
            .lineLimit(1)
    }
}

/// Yuvarlak −/+ düğmesi (büyük sayı girişinin iki yanı).
struct SadeRoundButton: View {
    let icon: String
    var help = ""
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Lucide(sf: icon, size: 15)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: size, height: size)
                .background(Circle().fill(Palette.textPrimary.opacity(0.04)))
                .overlay(Circle().strokeBorder(Palette.textPrimary.opacity(0.08), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Tarih kutusu: "22 Eylül 2026" + takvim ikonu; tıklayınca takvim açılır.
struct SadeDateField: View {
    let label: String
    @Binding var date: Date
    var range: ClosedRange<Date>? = nil
    var text: String? = nil

    @State private var open = false

    var body: some View {
        SadeField(label: label) {
            Button { open = true } label: {
                HStack(spacing: 8) {
                    Text(text ?? Fmt.dateLong.string(from: date))
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Lucide(sf: "calendar", size: 13)
                        .foregroundStyle(Palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                Group {
                    if let range {
                        DatePicker("", selection: $date, in: range, displayedComponents: [.date])
                    } else {
                        DatePicker("", selection: $date, displayedComponents: [.date])
                    }
                }
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .padding(12)
            }
        }
    }
}

/// Saat kutusu: "08:10" + saat ikonu; tıklayınca saat/dakika seçici açılır.
struct SadeTimeField: View {
    let label: String
    @Binding var date: Date
    var range: ClosedRange<Date>? = nil

    @State private var open = false

    var body: some View {
        SadeField(label: label) {
            Button { open = true } label: {
                HStack(spacing: 8) {
                    Text(Self.formatter.string(from: date))
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 4)
                    Lucide(sf: "clock", size: 13)
                        .foregroundStyle(Palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                Group {
                    if let range {
                        DatePicker("", selection: $date, in: range, displayedComponents: [.hourAndMinute])
                    } else {
                        DatePicker("", selection: $date, displayedComponents: [.hourAndMinute])
                    }
                }
                .datePickerStyle(.stepperField)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .padding(12)
            }
        }
    }

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// Tahlil referans göstergesi: iz + yeşil referans bandı + değer düğmesi (durum renginde).
struct SadeBandGauge: View {
    let value: Double
    let low: Double?
    let high: Double?
    let color: Color
    var width: CGFloat = 84

    var body: some View {
        let lo = low ?? 0
        let hi = high ?? max(value * 1.6, lo + 1)
        let d0 = min(lo, value) * 0.7
        let d1 = max(hi, value) * 1.15
        let x: (Double) -> CGFloat = { v in
            guard d1 > d0 else { return 0 }
            return CGFloat(max(0, min(1, (v - d0) / (d1 - d0)))) * width
        }
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Palette.textPrimary.opacity(0.06))
                .frame(width: width, height: 6)
            Capsule()
                .fill(Palette.positive.opacity(0.28))
                .frame(width: max(0, x(hi) - x(lo)), height: 6)
                .offset(x: x(lo))
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .background(Circle().fill(Palette.surface).frame(width: 14, height: 14))
                .offset(x: x(value) - 5)
        }
        .frame(width: width, height: 14, alignment: .leading)
    }
}

// MARK: - Grafikler dili: küçük çizgi grafik

/// Grafikler'deki grafiğin (GraphChartDrawing) pencere boyu: tek yumuşak çizgi (3pt, değişimin
/// renginde), altında renk %12 → 0 geçiş, ızgara/eksen yok, uçta parlayan nokta. İmleçte solu
/// renkli, sağı gri, noktalı dikey çizgi + nokta; `onHover` o noktayı (ya da nil) bildirir.
struct SadeLineChart: View {
    let points: [TrendPoint]
    var tint: Color = Palette.positive
    var onHover: ((TrendPoint?) -> Void)? = nil

    @State private var hover: TrendPoint?
    private let gray = Palette.textPrimary.opacity(0.22)

    var body: some View {
        GeometryReader { geo in
            if points.count >= 2 {
                drawing(geo.size)
            }
        }
    }

    private func drawing(_ size: CGSize) -> some View {
        let x0: CGFloat = 8, x1 = size.width - 8
        let y0: CGFloat = 14, y1 = size.height - 10
        let first = points[0].date
        let total = max(1, points[points.count - 1].date.timeIntervalSince(first))
        let values = points.map(\.value)
        let range = (values.max() ?? 1) - (values.min() ?? 0)
        let pad = range > 0 ? range * 0.12 : 1
        let lo = (values.min() ?? 0) - pad
        let hi = (values.max() ?? 1) + pad
        let x: (Date) -> CGFloat = { x0 + (x1 - x0) * CGFloat($0.timeIntervalSince(first) / total) }
        let y: (Double) -> CGFloat = { y1 - (y1 - y0) * CGFloat(($0 - lo) / (hi - lo)) }
        let pts = points.map { CGPoint(x: x($0.date), y: y($0.value)) }
        let line = WatchlistPaths.smooth(pts)
        let shown = hover
        let sx = shown.map { x($0.date) } ?? size.width
        let sy = shown.map { y($0.value) } ?? pts[pts.count - 1].y

        return ZStack {
            Canvas { ctx, canvas in
                var area = line
                area.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: y1))
                area.addLine(to: CGPoint(x: pts[0].x, y: y1))
                area.closeSubpath()
                let top = line.boundingRect.minY
                let style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                ctx.drawLayer { left in
                    left.clip(to: Path(CGRect(x: 0, y: 0, width: sx, height: canvas.height)))
                    left.fill(area, with: .linearGradient(Gradient(colors: [tint.opacity(0.12), tint.opacity(0)]),
                                                          startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: y1)))
                    left.stroke(line, with: .color(tint), style: style)
                }
                if shown != nil {
                    ctx.drawLayer { right in
                        right.clip(to: Path(CGRect(x: sx, y: 0, width: max(0, canvas.width - sx), height: canvas.height)))
                        right.stroke(line, with: .color(gray), style: style)
                    }
                    var guide = Path()
                    guide.move(to: CGPoint(x: sx, y: 0))
                    guide.addLine(to: CGPoint(x: sx, y: canvas.height))
                    ctx.stroke(guide, with: .color(Palette.textPrimary.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [1.5, 3.5]))
                    ctx.fill(Path(ellipseIn: CGRect(x: sx - 5, y: sy - 5, width: 10, height: 10)), with: .color(tint))
                } else {
                    let end = pts[pts.count - 1]
                    ctx.drawLayer { glow in
                        glow.addFilter(.blur(radius: 5))
                        glow.fill(Path(ellipseIn: CGRect(x: end.x - 12.1, y: end.y - 12.1, width: 24.2, height: 24.2)),
                                  with: .color(tint.opacity(0.22)))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: end.x - 5.5, y: end.y - 5.5, width: 11, height: 11)), with: .color(tint))
                }
            }
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        let t = min(1, max(0, (p.x - x0) / max(1, x1 - x0)))
                        let date = first.addingTimeInterval(Double(t) * total)
                        let nearest = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                        hover = nearest
                        onHover?(nearest)
                    case .ended:
                        hover = nil
                        onHover?(nil)
                    }
                }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Kilo değişiminin rengi: hedef yönündeyse adaçayı, tersiyse kırmızı, ~0 ise gri.
    static func tint(change: Double, lowerIsBetter: Bool, threshold: Double = 0.05) -> Color {
        guard abs(change) >= threshold else { return Palette.textTertiary }
        return (change < 0) == lowerIsBetter ? Palette.positive : Palette.negative
    }
}

// MARK: - Makro çubuğu

/// Protein · karbonhidrat · yağ kalori payları (P 4, K 4, Y 9 kcal/g) yan yana üç parça.
struct SadeMacroBar: View {
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    var height: CGFloat = 8

    var body: some View {
        let parts = [(protein ?? 0) * 4, (carbs ?? 0) * 4, (fat ?? 0) * 9]
        let colors = [Palette.macroProtein, Palette.macroCarbs, Palette.macroFat]
        let total = parts.reduce(0, +)
        GeometryReader { geo in
            HStack(spacing: 3) {
                if total > 0 {
                    ForEach(0..<3, id: \.self) { i in
                        if parts[i] > 0 {
                            Capsule()
                                .fill(colors[i])
                                .frame(width: max(2, (geo.size.width - 6) * parts[i] / total))
                        }
                    }
                } else {
                    Capsule().fill(Palette.textPrimary.opacity(0.06))
                }
            }
        }
        .frame(height: height)
    }
}

/// "● P 58 g  ● K 52 g  ● Y 18 g"
struct SadeMacroLegend: View {
    let protein: Double?
    let carbs: Double?
    let fat: Double?

    var body: some View {
        HStack(spacing: 14) {
            item("P", protein, Palette.macroProtein)
            item("K", carbs, Palette.macroCarbs)
            item("Y", fat, Palette.macroFat)
        }
        .font(.system(size: 12.5).monospacedDigit())
        .foregroundStyle(Palette.textSecondary)
    }

    @ViewBuilder private func item(_ letter: String, _ value: Double?, _ color: Color) -> some View {
        if let value {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text("\(letter) \(Fmt.int(value)) g")
            }
        }
    }
}
