import SwiftUI
import SwiftData

/// V1 tarif kartı — kategori satırı, başlık + kcal, 2 satırlık özet,
/// makro noktalı footer. Karta tıkla → detay; ✎ → editör; ♡ → favori.
struct RecipeCard: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    let recipe: Recipe
    var onOpen: () -> Void
    var onEdit: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(recipe.category.displayTint).frame(width: 5, height: 5)
                Text(recipe.category.label).eyebrow()
                if recipe.hasDetail {
                    Text("✓ detaylı")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.positive)
                }
                Spacer(minLength: 8)
                Text(Fmt.date.string(from: recipe.createdAt))
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                Button {
                    recipe.isFavorite.toggle()
                    ctx.saveOrReport()
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(recipe.isFavorite ? Palette.warning : Palette.textQuaternary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(recipe.isFavorite ? "Favoriden çıkar" : "Favoriye ekle")
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hovering ? Palette.textSecondary : Palette.textQuaternary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Tarifi düzenle")
            }

            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text(recipe.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let kcal = recipe.calories {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.int(kcal))
                            .font(.system(size: 22, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                        Text("kcal")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.textQuaternary)
                    }
                    .fixedSize()
                }
            }

            Text(recipe.displaySummary)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2.5)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Hairline().padding(.top, 2)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                RecipeMacroDots(recipe: recipe)
                Spacer(minLength: 8)
                if !planMeta.isEmpty {
                    Text(planMeta)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(Palette.textQuaternary)
                        .lineLimit(1)
                }
                if let host = recipe.sourceHost, let url = recipe.url {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 3) {
                            Text(host)
                                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundStyle(Palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Kaynağı aç")
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dashboardCard()
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(hovering ? Palette.borderStrong : Color.clear, lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private var planMeta: String {
        var parts: [String] = []
        if let m = recipe.prepMinutes { parts.append("\(m) dk") }
        if let s = recipe.servings { parts.append("\(s) porsiyon") }
        return parts.joined(separator: " · ")
    }
}

/// P/K/Y renk noktalı makro özeti — makro yoksa sakin bir "Makro eklenmemiş".
struct RecipeMacroDots: View {
    let recipe: Recipe
    var fontSize: CGFloat = 11.5

    var body: some View {
        let items: [(value: Double, tint: Color)] = [
            recipe.protein.map { ($0, Palette.macroProtein) },
            recipe.carbs.map { ($0, Palette.macroCarbs) },
            recipe.fat.map { ($0, Palette.macroFat) }
        ].compactMap { $0 }

        if items.isEmpty {
            Text("Makro eklenmemiş")
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Palette.textQuaternary)
        } else {
            HStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 5) {
                        Circle().fill(item.tint).frame(width: 5, height: 5)
                        Text("\(Fmt.int(item.value))g")
                            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
            }
        }
    }
}
