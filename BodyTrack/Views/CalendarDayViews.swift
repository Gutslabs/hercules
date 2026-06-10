import SwiftUI
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

    /// Yalnız seçili/bugün durumunda görünen mercan halka — diğer durumda çizgi yok.
    private var stateRing: Color {
        if isSelected { return Palette.accent.opacity(0.5) }
        if isToday { return Palette.accent.opacity(0.3) }
        return .clear
    }

    private var fillColor: Color {
        if isSelected { return Palette.accent.opacity(0.07) }
        if hovering { return Palette.surfaceElevated }
        return Palette.surface
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 6) {
                    Text(dayNumber)
                        .font(.system(size: 12.5, weight: isSelected || isToday ? .bold : .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? Palette.accent : Palette.textPrimary)

                    if isToday {
                        Text("BUGÜN")
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(Palette.accent)
                    }

                    Spacer(minLength: 0)

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

                    if let g = monthlyGoal {
                        Button { onGoalTap(g) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "scope")
                                    .font(.system(size: 8, weight: .semibold))
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

                Spacer(minLength: 6)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(hasFood ? Fmt.int(consumed) : "—")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(hasFood ? Palette.textPrimary : Palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("kcal")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barColor)
                    .opacity(hasFood ? 0.9 : 1)
                    .frame(height: 3)
                    .padding(.top, 5)
            }
            .padding(.top, 9)
            .padding(.horizontal, 11)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            // Çizgisiz: hücre opak yüzey + hafif gölgeyle "kalkık fayans" okunur.
            // Yalnız seçili/bugün durumu mercan halkayla işaretlenir (anlamlı state).
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.background)
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillColor)
                    .shadow(color: Palette.cardShadowTight, radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(stateRing, lineWidth: 1)
            )
            .opacity(inMonth ? 1.0 : 0.32)
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
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
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
