import SwiftUI
import SwiftData

struct RecipesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]

    @State private var selectedCategory: RecipeCategory? = nil
    @State private var showingNew = false
    @State private var editing: Recipe? = nil

    private var filtered: [Recipe] {
        guard let c = selectedCategory else { return recipes }
        return recipes.filter { $0.category == c }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                header
                categoryPicker
                content
                Spacer(minLength: 24)
            }
            .padding(Spacing.xxl)
        }
        .background(Palette.background.ignoresSafeArea())
        .sheet(isPresented: $showingNew) {
            RecipeEditor(mode: .create) { r in
                ctx.insert(r)
                try? ctx.save()
            }
        }
        .sheet(item: $editing) { r in
            RecipeEditor(mode: .edit(r)) { _ in
                try? ctx.save()
            } onDelete: {
                ctx.delete(r)
                try? ctx.save()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Yemekler").eyebrow()
                Text("Tarifler")
                    .font(Typography.display(40))
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            PrimaryButton(title: "Yeni Tarif", systemImage: "plus") {
                showingNew = true
            }
            .frame(width: 150)
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 4) {
            categoryTab("Tümü", isSelected: selectedCategory == nil) { selectedCategory = nil }
            ForEach(RecipeCategory.allCases) { c in
                categoryTab(c.label, isSelected: selectedCategory == c) { selectedCategory = c }
            }
            Spacer()
            Text("\(filtered.count) tarif")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func categoryTab(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.bodyBold)
                .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.07) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            EmptyRecipesState { showingNew = true }
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
                spacing: Spacing.md
            ) {
                ForEach(filtered) { r in
                    RecipeRow(recipe: r) { editing = r }
                }
            }
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe
    var onEdit: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surfaceElevated)
                    .frame(width: 38, height: 38)
                Image(systemName: recipe.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(hostText)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Palette.surfaceElevated))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Palette.accent : Palette.textTertiary)
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(hovering ? Palette.surfaceElevated : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let url = recipe.url { openURL(url) }
        }
    }

    private var hostText: String {
        recipe.url?.host ?? recipe.urlString
    }
}

struct EmptyRecipesState: View {
    var action: () -> Void
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "fork.knife")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("Henüz tarif yok")
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
            PrimaryButton(title: "İlk tarifi ekle", systemImage: "plus", action: action)
                .frame(width: 220)
        }
        .padding(Spacing.xxxl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

enum RecipeEditorMode {
    case create
    case edit(Recipe)
}

struct RecipeEditor: View {
    let mode: RecipeEditorMode
    var onSave: (Recipe) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var urlString: String
    @State private var category: RecipeCategory

    init(mode: RecipeEditorMode, onSave: @escaping (Recipe) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _urlString = State(initialValue: "")
            _category = State(initialValue: .dinner)
        case .edit(let r):
            _title = State(initialValue: r.title)
            _urlString = State(initialValue: r.urlString)
            _category = State(initialValue: r.category)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !urlString.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header
            Card(padding: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Başlık").eyebrow()
                        textField($title, placeholder: "ör: Popeyes tarzı az kalorili tavuk")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Link").eyebrow()
                        textField($urlString, placeholder: "https://...")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Kategori").eyebrow()
                        SegmentedChoice(
                            options: RecipeCategory.allCases,
                            selection: $category,
                            label: { $0.label }
                        )
                    }
                }
            }
            actions
        }
        .padding(Spacing.xxl)
        .frame(width: 520)
        .background(Palette.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isEditing ? "Düzenle" : "Yeni Tarif").eyebrow()
                Text(isEditing ? "Tarifi Güncelle" : "Yeni Tarif Ekle")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.surfaceElevated))
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.md) {
            if isEditing, let onDelete {
                Button {
                    onDelete()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                        Text("Sil").font(Typography.bodyBold)
                    }
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Palette.negative)
                    .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.negative.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.negative.opacity(0.20), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            GhostButton(title: "İptal", action: { dismiss() })
            PrimaryButton(title: isEditing ? "Kaydet" : "Ekle", systemImage: "checkmark") {
                save()
                dismiss()
            }
            .opacity(canSave ? 1 : 0.4)
            .disabled(!canSave)
        }
    }

    private func textField(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.lowercased().hasPrefix("http://") && !trimmedURL.lowercased().hasPrefix("https://") {
            trimmedURL = "https://" + trimmedURL
        }
        switch mode {
        case .create:
            let r = Recipe(title: trimmedTitle, urlString: trimmedURL, category: category)
            onSave(r)
        case .edit(let r):
            r.title = trimmedTitle
            r.urlString = trimmedURL
            r.category = category
            onSave(r)
        }
    }
}
