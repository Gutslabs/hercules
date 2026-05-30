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
