import SwiftUI

// MARK: - Body Half View

private struct BodyHalfView: View {
    let isFront: Bool
    let primaryMuscles: Set<MuscleRegion>
    let secondaryMuscles: Set<MuscleRegion>
    let onTap: (MuscleRegion) -> Void

    private var imageName: String { isFront ? "body_front" : "body_back" }

    /// All regions that appear on this side according to isFront flag
    private var relevantRegions: [MuscleRegion] {
        MuscleRegion.allCases.filter { $0.isFront == isFront }
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(isFront ? "Ön" : "Arka")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)

            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    // Base display image
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)

                    // Muscle color overlays (mask-based)
                    ForEach(relevantRegions, id: \.rawValue) { region in
                        if let color = overlayColor(for: region),
                           let mask = muscleMask(for: region, isFront: isFront) {
                            Image(decorative: mask, scale: 1, orientation: .up)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(color.opacity(0.65))
                                .frame(width: size.width, height: size.height)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let pt = value.location
                            let norm = CGPoint(
                                x: pt.x / size.width,
                                y: pt.y / size.height
                            )
                            if let region = muscleRegion(at: norm, isFront: isFront) {
                                onTap(region)
                            }
                        }
                )
            }
            // PNG aspect ratio: 300 / 508
            .aspectRatio(300.0 / 508.0, contentMode: .fit)
        }
    }

    private func overlayColor(for region: MuscleRegion) -> Color? {
        if primaryMuscles.contains(region)   { return .red }
        if secondaryMuscles.contains(region) { return .orange }
        return nil
    }
}

// MARK: - Interactive Diagram (form'da kullanılır)

struct MuscleBodyDiagram: View {
    @Binding var primaryMuscles: Set<MuscleRegion>
    @Binding var secondaryMuscles: Set<MuscleRegion>

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Legend + clear button
            HStack(spacing: Spacing.lg) {
                legendBadge(color: .red.opacity(0.75),    label: "Birincil")
                legendBadge(color: .orange.opacity(0.65), label: "İkincil")
                Spacer()
                if !primaryMuscles.isEmpty || !secondaryMuscles.isEmpty {
                    Button("Temizle") {
                        withAnimation { primaryMuscles.removeAll(); secondaryMuscles.removeAll() }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Body diagrams
            HStack(alignment: .top, spacing: Spacing.xl) {
                BodyHalfView(
                    isFront: true,
                    primaryMuscles: primaryMuscles,
                    secondaryMuscles: secondaryMuscles,
                    onTap: handleTap
                )
                BodyHalfView(
                    isFront: false,
                    primaryMuscles: primaryMuscles,
                    secondaryMuscles: secondaryMuscles,
                    onTap: handleTap
                )
            }

            // Selected muscles summary
            if !primaryMuscles.isEmpty || !secondaryMuscles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !primaryMuscles.isEmpty {
                        muscleRow(label: "Birincil", muscles: primaryMuscles, color: .red.opacity(0.85))
                    }
                    if !secondaryMuscles.isEmpty {
                        muscleRow(label: "İkincil", muscles: secondaryMuscles, color: .orange.opacity(0.85))
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func legendBadge(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func muscleRow(label: String, muscles: Set<MuscleRegion>, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 52, alignment: .trailing)
            Text(muscles.map(\.label).sorted().joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
        }
    }

    private func handleTap(_ region: MuscleRegion) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
            if primaryMuscles.contains(region) {
                primaryMuscles.remove(region)
                secondaryMuscles.insert(region)
            } else if secondaryMuscles.contains(region) {
                secondaryMuscles.remove(region)
            } else {
                primaryMuscles.insert(region)
            }
        }
    }
}

// MARK: - Heat Map (program odak yoğunluğu)

/// 0...1 yoğunluğu soğuk→sıcak renge çevirir (klasik heat ramp).
enum MuscleHeat {
    static func color(_ t: Double) -> Color {
        let clamped = max(0, min(1, t))
        // mavi (0.62) → kırmızı (0.0)
        return Color(hue: 0.62 - 0.62 * clamped, saturation: 0.85, brightness: 0.95)
    }
}

private struct HeatHalfView: View {
    let isFront: Bool
    let intensities: [MuscleRegion: Double]

    private var imageName: String { isFront ? "body_front" : "body_back" }
    private var relevantRegions: [MuscleRegion] {
        MuscleRegion.allCases.filter { $0.isFront == isFront }
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(isFront ? "Ön" : "Arka")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)

            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)

                    ForEach(relevantRegions, id: \.rawValue) { region in
                        let t = intensities[region] ?? 0
                        if t > 0.001, let mask = muscleMask(for: region, isFront: isFront) {
                            Image(decorative: mask, scale: 1, orientation: .up)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(MuscleHeat.color(t).opacity(0.4 + 0.5 * t))
                                .frame(width: size.width, height: size.height)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .aspectRatio(300.0 / 508.0, contentMode: .fit)
        }
    }
}

/// Bölge yoğunluklarına göre ön+arka gövdeyi ısı haritası olarak gösterir.
struct MuscleHeatBody: View {
    let intensities: [MuscleRegion: Double]

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            HeatHalfView(isFront: true, intensities: intensities)
            HeatHalfView(isFront: false, intensities: intensities)
        }
    }
}

// MARK: - Read-only Display (detay sayfasında kullanılır)

struct MuscleBodyDisplay: View {
    let primaryMuscles: Set<MuscleRegion>
    let secondaryMuscles: Set<MuscleRegion>

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            BodyHalfView(
                isFront: true,
                primaryMuscles: primaryMuscles,
                secondaryMuscles: secondaryMuscles
            ) { _ in }
            BodyHalfView(
                isFront: false,
                primaryMuscles: primaryMuscles,
                secondaryMuscles: secondaryMuscles
            ) { _ in }
        }
    }
}
