import SwiftUI
import LucideKit
import SwiftData

// DashboardBalancePeriod / DashboardBalanceSummary KALDIRILDI: haftalık net enerji
// dengesini yalnız Genel Bakış V2'nin "Bu hafta" paneli okuyordu; V3 "Sade"de o panel yok
// (enerji dengesi Analiz'in Yakım kartında).

/// Sayfa zemini: düz renk yerine sidebar'la aynı dilde kademeli gradient
/// (üstte seçili tonun soluk izi, altta saf zemin).
struct DashboardBackground: View {
    var body: some View {
        LinearGradient(
            colors: [BuzzTheme.contentGradientTop, BuzzTheme.contentGradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct CalorieProgressRing: View {
    let progress: Double
    let tint: Color
    let value: String
    let label: String
    let subtitle: String
    /// Center label color; defaults to `tint` so callers can keep a neutral
    /// caption while the stroke stays accented.
    var labelColor: Color? = nil

    var body: some View {
        // Günlük Plan barlarıyla (BoardStageBars) aynı dil: aynı ray tonu, aynı
        // dolgu opaklığı, yuvarlak uç, tabular rakam — yalnız şekli çember.
        ZStack {
            Circle()
                .stroke(Palette.track.opacity(0.55), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(
                    tint.opacity(0.9),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.55, dampingFraction: 0.86), value: progress)

            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 38, weight: .semibold).monospacedDigit())
                    .tracking(-0.6)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(labelColor ?? Palette.textTertiary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
        }
    }
}

struct DashboardInlineEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Lucide(sf: icon, size: 13)
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Palette.fieldFill))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - V1 "Tek Akış" building blocks

/// Card surface used by every overview section — flat fill, thin hairline border.
extension View {
    /// V1 kart kromu + derinlik: opak taban (koyu temada yarı saydam yüzeyin gölgesi
    /// kaybolmasın diye) üzerine çift gölge — yaygın ortam + sıkı temas — ve üstten
    /// alta sönen ışık rim'li kenarlık. Kart "zeminden hafif kalkık" okunur.
    /// Buzz kartı (card.tsx): 12px köşe, 1px border/70 hairline, shadow-xs.
    /// Koyu temada yükseklik gölgeyle değil, açık yüzey rengiyle taşınır.
    func dashboardCard(radius: CGFloat = Radius.md) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surface)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.border.opacity(0.7), lineWidth: 1)
            )
    }
}

/// Compact macro row for the hero plan column: dot + name, consumed/target + share %, thin progress.
struct HeroMacroRow: View {
    let name: String
    let consumed: Double
    let target: Double
    let percent: Double
    let tint: Color

    /// `GoalBar`'ın `overflowAt` eşiğiyle aynı tolerans — sayı ve bar birlikte dönsün.
    private var isOver: Bool { consumed > target * 1.05 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(name)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.int(consumed))
                        .font(Typography.mono)
                        .foregroundStyle(isOver ? Palette.negative : Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text("/ \(Fmt.int(target)) g")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                .lineLimit(1)
                Text("%\(Fmt.int(percent))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                    .frame(width: 34, alignment: .trailing)
            }
            // Board hap ilerleme: Palette.track ray + makro renkli kapsül dolgu, 6pt.
            GeometryReader { geo in
                let frac = target > 0 ? min(1, consumed / target) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    if frac > 0 {
                        Capsule()
                            .fill(isOver ? Palette.negative : tint)
                            .frame(width: max(6, geo.size.width * frac))
                    }
                }
            }
            .frame(height: 6)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: consumed)
        }
    }
}

/// Hero öğün satırı — saat + isim + makro özeti; hover'da silme butonu belirginleşir.
struct HeroMealRow: View {
    let food: FoodEntry
    var onDelete: () -> Void
    @State private var hovering = false

    private var detail: String {
        var parts = ["\(Fmt.int(food.calories)) kalori"]
        if let g = food.grams { parts.append("\(Fmt.int(g)) g") }
        if let p = food.protein { parts.append("P \(Fmt.int(p))g") }
        if let c = food.carbs { parts.append("K \(Fmt.int(c))g") }
        if let f = food.fat { parts.append("Y \(Fmt.int(f))g") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        // Board dili: hairline ayırıcı yok — hover'da yuvarlak fayans zemini.
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(Fmt.timeShort.string(from: food.date))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(food.name)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(detail)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Button(action: onDelete) {
                    Lucide(sf: "trash", size: 10)
                        .foregroundStyle(hovering ? Palette.negative : Palette.textQuaternary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(hovering ? Palette.negative.opacity(0.1) : Color.clear))
                }
                .buttonStyle(.plain)
                .help("Öğünü sil")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Palette.fieldFill : Color.clear)
        )
        .onHover { hovering = $0 }
    }
}

// DeltaBadge KALDIRILDI: hiçbir sayfa kullanmıyordu — yön çipi işini
// ChartsComponents'taki BoardDeltaChip görüyor.

/// Compact secondary metric row for the Vücut card — tap promotes it into the big slot.
struct BodyMetricRow: View {
    let name: String
    let value: String
    let unit: String
    let points: [TrendPoint]
    let delta: Double?
    let lowerIsBetter: Bool
    let accent: Color
    var onTap: () -> Void = {}
    @State private var hovering = false

    /// Board çipi yönü — hedef yönündeki değişim yeşil (1), tersi bordo (-1), sıfır nötr (0).
    private var chipDirection: Int {
        guard let d = delta, d != 0 else { return 0 }
        return (lowerIsBetter ? d < 0 : d > 0) ? 1 : -1
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 21, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Sparkline(points: points, accent: accent)
                .frame(width: 88, height: 30)
                .opacity(points.count >= 2 ? 0.9 : 0)

            Group {
                if let d = delta {
                    BoardDeltaChip(text: Fmt.signed(d, digits: 1), direction: chipDirection)
                }
            }
            .frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        // Esnek fayans: önerilen boy doğal boyundan büyükse fayans uzar (içerik
        // dikeyde ortalanır) — Vücut kolonu yanındaki grafik pencereyle büyürken
        // satırlar onunla aynı hizada kalsın diye. Doğal boyda hiçbir şey değişmez.
        .frame(maxHeight: .infinity)
        // Board fayans kromu: surfaceElevated zemin, 10px köşe — hover'da koyulaşır.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(hovering ? 1 : 0.6))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
    }
}

/// Buzz KPI grubu: fayans zemini olmayan çıplak stat — renk noktası + soluk
/// etiket + tabular değer (+ opsiyonel birim/alt satır). Gruplar satırda
/// `DashboardStatDivider` ile ayrılır; sayı fontları fayans halindekiyle aynı.
struct DashboardStatGroup: View {
    let label: String
    let value: String
    var sub: String? = nil
    var dot: Color? = nil
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let dot {
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            if let sub {
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// KPI grupları arasındaki dikey hairline — Buzz: 1pt, border/50, ~28pt boy.
struct DashboardStatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border.opacity(0.5))
            .frame(width: 1, height: 28)
    }
}

// BoardStatCard KALDIRILDI: KPI şeridiyle birlikte tek kullanıcısı gitti —
// aynı stat, aşağıdaki zengin kartlarda (halka, Vücut, Kalori Dengesi) yaşıyor.

extension View {
    func dashboardReveal(_ visible: Bool, delay: Double) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .animation(.spring(response: 0.58, dampingFraction: 0.86).delay(delay), value: visible)
    }
}
