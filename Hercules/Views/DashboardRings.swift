import SwiftUI
import LucideKit

// MARK: - Yeniden tasarlanan sayfaların ortak parçaları
//
// Genel Bakış (DashboardSade.swift), Ölçümler ve İlerleme panelleri aynı kabuğu ve aynı
// yerleşim dilini kullanır: her panel boyunu kendi GeometryReader'ından alır ve her şeyi
// panel koordinatında yerleştirir — tasarım ölçüsünde çizim artboard'la aynı noktaya düşer,
// başka ölçüde formüller orantılı esner. Tasarımdaki rgba(255,255,255,a) →
// `Palette.textPrimary.opacity(a)` (açık temada da okunsun diye).

// MARK: - Yerleşim yardımcıları

extension View {
    /// Panel koordinatına iğneler. (x, y) kutunun ÜST kenarıdır: `.topLeading` → sol üst
    /// köşe, `.top` → üst-orta, `.topTrailing` → sağ üst, `.center` → kutunun merkezi.
    /// Kutu doğal boyunu alır (fixedSize), çevresindeki yerleşimi itmez.
    func ringsPin(_ x: CGFloat, _ y: CGFloat, _ alignment: Alignment = .topLeading) -> some View {
        fixedSize()
            .frame(width: 0, height: 0, alignment: alignment)
            .position(x: x, y: y)
    }
}

/// Saat 12'den saat yönünde `deg` derecedeki çember noktası.
func ringsPoint(_ center: CGPoint, _ radius: CGFloat, _ deg: Double) -> CGPoint {
    let a = (deg - 90) * .pi / 180
    return CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a)))
}

/// Saat 12'den saat yönünde `from…to` derecelik yay; merkez ve yarıçap panel koordinatında.
/// (Tasarımdaki SVG çember yayının eşi — kalınlık ve uç stili stroke'ta verilir.)
struct RingsArc: Shape {
    let center: CGPoint
    let radius: CGFloat
    let from: Double
    let to: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard to > from, radius > 0 else { return path }
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
        return path
    }
}

/// Taşan halka turunun ucundaki bulanık koyu gölge (alttaki turun üstünden geçiyormuş gibi).
struct RingsTipShadow: View {
    let point: CGPoint
    let lineWidth: CGFloat

    var body: some View {
        Circle()
            .fill(Color.black.opacity(0.55))
            .frame(width: lineWidth + 2, height: lineWidth + 2)
            .blur(radius: 3)
            .position(point)
            .allowsHitTesting(false)
    }
}

// MARK: - Panel kabuğu

/// Bölüm kabuğu: 18pt köşe, yarı saydam yüzey, taşan çizim kırpılır. İçerik panelin
/// boyunu alır; başlık (24, 20)'de.
struct RingsPanel<Content: View>: View {
    let title: String
    var sub: String? = nil
    @ViewBuilder var content: (CGSize) -> Content

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                content(geo.size)
                RingsPanelTitle(title: title, sub: sub)
                    .ringsPin(24, 20)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(shape.fill(Palette.surface.opacity(0.55)))
        .clipShape(shape)
    }
}

/// Tek kelimelik bölüm başlığı + isteğe bağlı soluk ek ("Bugün  22 Eylül Salı").
struct RingsPanelTitle: View {
    let title: String
    var sub: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            if let sub {
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .lineLimit(1)
    }
}

/// Hedef planı hesaplanamadığında panelin yerine: ne eksik, kısaca.
struct RingsSetupMessage: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Lucide(sf: "scope", size: 22)
                .foregroundStyle(Palette.warning)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Palette.warning.opacity(0.12)))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Öğün gruplama

/// Öğünün tek kaydı — değerler kopyalanır; `model` yalnız silme için tutulur
/// (silinen kaydın alanına görünüm çizilirken dokunulmasın).
struct RingsMealEntry: Identifiable {
    let id: ObjectIdentifier
    let model: FoodEntry
    let date: Date
    let name: String
    let calories: Double
    let protein: Double?
    let carbs: Double?
    let fat: Double?
}

/// Bir öğün = birbirine 20 dakikadan yakın kayıtların grubu (ör. yemek + içecek).
struct RingsMeal: Identifiable {
    let id: ObjectIdentifier
    let date: Date
    /// Günün saati (09:20 → 9.33).
    let hour: Double
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let entries: [RingsMealEntry]

    /// Hover ipucu: her kayıt bir satır — "13:15 · 3 lahmacun + ayran · 973 kalori · P 39 · K 109 · Y 39".
    var helpText: String {
        entries.map { entry in
            var parts = [Fmt.timeShort.string(from: entry.date), entry.name, "\(Fmt.int(entry.calories)) kalori"]
            if let p = entry.protein { parts.append("P \(Fmt.int(p))") }
            if let c = entry.carbs { parts.append("K \(Fmt.int(c))") }
            if let f = entry.fat { parts.append("Y \(Fmt.int(f))") }
            return parts.joined(separator: " · ")
        }
        .joined(separator: "\n")
    }

    /// Saate göre sıralar; bir kayıt, önceki grubun SON kaydından en çok `gap` sonra
    /// geldiyse o gruba katılır. Ad = kayıt adları " + " ile, kalori/makro toplanır.
    static func group(_ foods: [FoodEntry], gap: TimeInterval = 20 * 60,
                      calendar: Calendar = .current) -> [RingsMeal] {
        var buckets: [[FoodEntry]] = []
        for food in foods.sorted(by: { $0.date < $1.date }) {
            if let last = buckets.last?.last, food.date.timeIntervalSince(last.date) <= gap {
                buckets[buckets.count - 1].append(food)
            } else {
                buckets.append([food])
            }
        }
        return buckets.compactMap { bucket -> RingsMeal? in
            guard let first = bucket.first else { return nil }
            let time = calendar.dateComponents([.hour, .minute], from: first.date)
            return RingsMeal(
                id: ObjectIdentifier(first),
                date: first.date,
                hour: Double(time.hour ?? 0) + Double(time.minute ?? 0) / 60,
                name: bucket.map(\.name).joined(separator: " + "),
                calories: bucket.reduce(0) { $0 + $1.calories },
                protein: bucket.reduce(0) { $0 + ($1.protein ?? 0) },
                carbs: bucket.reduce(0) { $0 + ($1.carbs ?? 0) },
                fat: bucket.reduce(0) { $0 + ($1.fat ?? 0) },
                entries: bucket.map { food in
                    RingsMealEntry(id: ObjectIdentifier(food), model: food, date: food.date, name: food.name,
                                   calories: food.calories, protein: food.protein, carbs: food.carbs, fat: food.fat)
                }
            )
        }
    }
}
