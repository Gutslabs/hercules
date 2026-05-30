import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum MobileTab: Hashable, CaseIterable {
    case dashboard
    case nutrition
    case workout
    case measurements
    case sync

    var title: String {
        switch self {
        case .dashboard: return "Hercules"
        case .nutrition: return "Yemek"
        case .workout: return "Antrenman"
        case .measurements: return "Ölçümler"
        case .sync: return "Senkron"
        }
    }

    var shortTitle: String {
        switch self {
        case .dashboard: return "Bugün"
        case .nutrition: return "Yemek"
        case .workout: return "Antrenman"
        case .measurements: return "Ölçüm"
        case .sync: return "Sync"
        }
    }

    var eyebrow: String {
        switch self {
        case .dashboard: return "Mobil"
        case .nutrition: return "Beslenme"
        case .workout: return "Program"
        case .measurements: return "Takip"
        case .sync: return "Vault"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "house.fill"
        case .nutrition: return "fork.knife"
        case .workout: return "dumbbell.fill"
        case .measurements: return "chart.line.uptrend.xyaxis"
        case .sync: return "externaldrive.connected.to.line.below"
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
