import SwiftUI
import SwiftData

struct RecipeSpotlightCard: View {
    let recipe: Recipe
    var onOpen: () -> Void
    var onEdit: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                recipeBadge(prominent: true)
                Spacer()
                cardActions
            }

            HStack(alignment: .top, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(recipe.title)
                        .font(Typography.hero(28))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                    Text(subtitleText)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let calories = recipe.calories {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.int(calories))
                            .font(Typography.display(34))
                            .foregroundStyle(Palette.textPrimary)
                        Text("kcal")
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .frame(minWidth: 92, alignment: .trailing)
                }
            }

            Divider().overlay(Palette.border)

            HStack(alignment: .top, spacing: Spacing.md) {
                macroSummary
                Divider().overlay(Palette.border).frame(height: 48)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: Spacing.sm) {
                        infoChip(icon: "person.2", text: recipe.servings.map { "\($0) porsiyon" } ?? "Porsiyon yok")
                        infoChip(icon: "clock", text: recipe.prepMinutes.map { "\($0) dk" } ?? "Süre yok")
                        infoChip(icon: recipe.hasDetail ? "checkmark.seal" : "doc.text", text: recipe.hasDetail ? "Detaylı" : "Link formatı")
                    }
                    HStack(spacing: Spacing.sm) {
                        infoChip(icon: "list.bullet", text: "\(ingredientCount) malzeme")
                        infoChip(icon: "flame", text: "\(instructionCount) adım")
                        infoChip(icon: "calendar", text: Fmt.date.string(from: recipe.createdAt))
                        if let host = sourceHost {
                            infoChip(icon: "link", text: host)
                        }
                    }
                }
            }

            HStack(spacing: 7) {
                Text("Tarifi aç")
                    .font(Typography.captionBold)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.top, 2)
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(hovering ? Palette.surfaceElevated : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(hovering ? Palette.borderStrong : Palette.border, lineWidth: 0.7)
        )
        .shadow(color: Palette.background.opacity(hovering ? 0.42 : 0.25), radius: hovering ? 28 : 18, x: 0, y: hovering ? 18 : 10)
        .scaleEffect(hovering ? 1.004 : 1)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
    }

    private var cardActions: some View {
        HStack(spacing: 7) {
            RecipeFavoriteButton(recipe: recipe, size: 28, iconSize: 11)

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .background(Circle().fill(Palette.surfaceElevated))

            if let url = recipe.url {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
                .background(Circle().fill(Palette.surfaceElevated))
            }
        }
    }

    @ViewBuilder
    private var macroSummary: some View {
        if macroMetrics.isEmpty {
            Text("Makro eklenmemiş")
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textTertiary)
                .frame(minWidth: 260, maxWidth: 320, alignment: .leading)
                .padding(.vertical, 12)
        } else {
            HStack(spacing: Spacing.sm) {
                ForEach(macroMetrics, id: \.label) { metric in
                    metricTile(metric, minWidth: 62)
                }
            }
            .frame(minWidth: 260, maxWidth: 320, alignment: .leading)
        }
    }

    private func recipeBadge(prominent: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: recipe.category.icon)
                .font(.system(size: prominent ? 13 : 11, weight: .semibold))
            Text(recipe.category.label)
                .font(Typography.captionBold)
            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: prominent ? 11 : 9, weight: .semibold))
            }
        }
        .foregroundStyle(categoryTint)
        .padding(.horizontal, prominent ? 11 : 9)
        .padding(.vertical, prominent ? 7 : 6)
        .background(
            Capsule(style: .continuous)
                .fill(categoryTint.opacity(0.14))
        )
    }

    private func metricTile(_ metric: RecipeMetric, minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.textQuaternary)
            Text(metric.value)
                .font(Typography.mono)
                .foregroundStyle(metric.tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(minWidth: minWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
    }

    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(Typography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var macroMetrics: [RecipeMetric] {
        recipe.recipeMetrics
    }

    private var subtitleText: String {
        recipe.displaySummary
    }

    private var ingredientCount: Int { recipe.ingredientLines.count }
    private var instructionCount: Int { recipe.instructionLines.count }
    private var sourceHost: String? { recipe.sourceHost }
    private var categoryTint: Color { recipe.category.displayTint }
}

struct RecipeInsightPanel: View {
    let total: Int
    let favorites: Int
    let detailed: Int
    let sourced: Int
    let quick: Int
    let highProtein: Int
    let missingDetail: Int
    let filteredCount: Int
    let selectedCategory: RecipeCategory?

    private var activeLabel: String {
        selectedCategory?.label ?? "Tüm tarifler"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AKTİF RAF")
                        .font(Typography.label)
                        .tracking(0.8)
                        .foregroundStyle(Palette.textQuaternary)
                    Text(activeLabel)
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text("\(filteredCount)")
                    .font(Typography.display(34))
                    .foregroundStyle(Palette.textPrimary)
            }

            Divider().overlay(Palette.border)

            VStack(spacing: 0) {
                insightRow(label: "Favori", value: favorites, total: total, icon: "heart.fill")
                Divider().overlay(Palette.border)
                insightRow(label: "Detaylı", value: detailed, total: total, icon: "checkmark.seal")
                Divider().overlay(Palette.border)
                insightRow(label: "Kaynaklı", value: sourced, total: total, icon: "link")
                Divider().overlay(Palette.border)
                insightRow(label: "20 dk altı", value: quick, total: total, icon: "timer")
                Divider().overlay(Palette.border)
                insightRow(label: "Protein yüksek", value: highProtein, total: total, icon: "bolt")
                Divider().overlay(Palette.border)
                insightRow(label: "Detay bekliyor", value: missingDetail, total: total, icon: "doc.badge.plus")
            }

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("AI tarif eklerken özet, malzeme, yapılış ve makrolar dolu gelirse burası gerçek kütüphane gibi çalışır.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.surfaceElevated.opacity(0.78))
            )
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.borderStrong.opacity(0.75), lineWidth: 0.6)
        )
        .shadow(color: Palette.background.opacity(0.32), radius: 24, x: 0, y: 18)
    }

    private func insightRow(label: String, value: Int, total: Int, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.055)))
            Text(label)
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(value)")
                    .font(Typography.monoLarge)
                    .foregroundStyle(Palette.textPrimary)
                Text(total > 0 ? "\(Int((Double(value) / Double(total)) * 100))%" : "-")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
        .padding(.vertical, 12)
    }
}

struct RecipeLibraryCard: View {
    let recipe: Recipe
    var onOpen: () -> Void
    var onEdit: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(recipe.category.displayTint.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: recipe.category.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(recipe.category.displayTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(recipe.category.label)
                            .font(Typography.micro)
                            .foregroundStyle(recipe.category.displayTint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule(style: .continuous).fill(recipe.category.displayTint.opacity(0.13)))
                        if recipe.hasDetail {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.positive)
                        }
                        if recipe.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.warning)
                        }
                        Spacer(minLength: 6)
                        Text(Fmt.date.string(from: recipe.createdAt))
                            .font(Typography.micro)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Text(recipe.title)
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                cardActions
            }

            Text(recipe.displaySummary)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if recipe.recipeMetrics.isEmpty {
                Text("Makro eklenmemiş")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.vertical, 7)
            } else {
                HStack(spacing: Spacing.sm) {
                    ForEach(recipe.recipeMetrics, id: \.label) { metric in
                        compactMetric(metric)
                    }
                }
            }

            HStack(spacing: Spacing.sm) {
                footerChip(icon: "clock", text: recipe.prepMinutes.map { "\($0) dk" } ?? "Süre yok")
                footerChip(icon: "person.2", text: recipe.servings.map { "\($0) porsiyon" } ?? "Porsiyon yok")
                if let host = recipe.sourceHost {
                    footerChip(icon: "link", text: host)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text("Aç")
                    .font(Typography.captionBold)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(hovering ? Palette.textPrimary : Palette.textSecondary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(hovering ? Palette.surfaceElevated : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(hovering ? Palette.borderStrong : Palette.border, lineWidth: 0.6)
        )
        .overlay(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(recipe.category.displayTint.opacity(0.72))
                .frame(width: hovering ? 96 : 56, height: 2)
                .padding(.leading, Spacing.lg)
                .padding(.top, 1)
                .animation(.easeOut(duration: 0.18), value: hovering)
        }
        .shadow(color: Palette.background.opacity(hovering ? 0.34 : 0.18), radius: hovering ? 18 : 10, x: 0, y: hovering ? 10 : 6)
        .scaleEffect(hovering ? 1.006 : 1)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
    }

    private var cardActions: some View {
        HStack(spacing: 5) {
            RecipeFavoriteButton(recipe: recipe, size: 25, iconSize: 10.5)
            iconButton("pencil", action: onEdit)
            if let url = recipe.url {
                iconButton("arrow.up.right") {
                    openURL(url)
                }
            }
        }
        .opacity(hovering ? 1 : 0.72)
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 25, height: 25)
                .background(Circle().fill(Color.white.opacity(0.045)))
        }
        .buttonStyle(.plain)
    }

    private func compactMetric(_ metric: RecipeMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label.uppercased())
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(Palette.textQuaternary)
            Text(metric.value)
                .font(Typography.mono)
                .foregroundStyle(metric.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
    }

    private func footerChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .font(Typography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(Palette.textTertiary)
    }
}
