import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum MobileTab: Hashable, CaseIterable {
    case dashboard
    case feed
    case nutrition
    case recipes
    case workout
    case measurements
    case calendar
    case profile

    var title: String {
        switch self {
        case .dashboard: return "Hercules"
        case .feed: return "Akış"
        case .nutrition: return "Yemek"
        case .recipes: return "Tarifler"
        case .workout: return "Antrenman"
        case .measurements: return "Ölçümler"
        case .calendar: return "Takvim"
        case .profile: return "Profil"
        }
    }

    var shortTitle: String {
        switch self {
        case .dashboard: return "Bugün"
        case .feed: return "Akış"
        case .nutrition: return "Yemek"
        case .recipes: return "Tarif"
        case .workout: return "Spor"
        case .measurements: return "Ölçüm"
        case .calendar: return "Takvim"
        case .profile: return "Profil"
        }
    }

    var eyebrow: String {
        switch self {
        case .dashboard: return "Mobil"
        case .feed: return "Mac'ten"
        case .nutrition: return "Beslenme"
        case .recipes: return "Mutfak"
        case .workout: return "Program"
        case .measurements: return "Takip"
        case .calendar: return "Ay"
        case .profile: return "Hesap"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "house.fill"
        case .feed: return "tray.and.arrow.down.fill"
        case .nutrition: return "fork.knife"
        case .recipes: return "book.closed.fill"
        case .workout: return "dumbbell.fill"
        case .measurements: return "chart.line.uptrend.xyaxis"
        case .calendar: return "calendar"
        case .profile: return "person.crop.circle"
        }
    }
}

struct MobilePresetItem: Identifiable {
    let id: String
    let preset: FoodPreset
}

struct MobileCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 0.5)
            )
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Hafif çizgi grafik (Swift Charts gerektirmez) — ölçüm/kilo trendi için.
/// values: eskiden yeniye sıralı.
struct MobileSparkline: View {
    let values: [Double]
    var tint: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let lo = values.min(), let hi = values.max() {
                let range = max(hi - lo, 0.0001)
                let pts: [CGPoint] = values.enumerated().map { i, v in
                    CGPoint(
                        x: geo.size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: geo.size.height * (1 - CGFloat((v - lo) / range))
                    )
                }
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

/// Mac kalitesinde dairesel ilerleme halkası (kalori/makro hedefleri için).
/// progress > 1 olunca (hedefi aştın) renk uyarıya döner.
struct MobileProgressRing<Center: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 11
    var size: CGFloat = 132
    var tint: Color = Palette.accent
    @ViewBuilder var center: () -> Center

    var body: some View {
        let clamped = max(0, min(progress, 1))
        ZStack {
            Circle()
                .stroke(Palette.surfaceElevated, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    progress > 1.001 ? Palette.warning : tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: clamped)
            center()
        }
        .frame(width: size, height: size)
    }
}

/// Sola kaydırınca kırmızı "Sil" aksiyonu açan satır sarmalayıcı (List gerektirmez,
/// custom kart UI ile uyumlu). Butona basınca onDelete tetiklenir; "emin misin" onayını
/// üst katman (alert) gösterir. Satır arka planı kart rengiyle (surface) aynı olmalı.
struct MobileSwipeToDelete<Content: View>: View {
    var onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    private let revealWidth: CGFloat = 88

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.negative)
                .overlay(alignment: .trailing) {
                    Button {
                        close()
                        onDelete()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Sil")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(width: revealWidth)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, max(startOffset + value.translation.width, -revealWidth))
                        }
                        .onEnded { value in
                            let projected = startOffset + value.translation.width
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                offset = projected < -revealWidth / 2 ? -revealWidth : 0
                            }
                            startOffset = offset
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { offset = 0 }
        startOffset = 0
    }
}
