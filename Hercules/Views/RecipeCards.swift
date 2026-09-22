import SwiftUI
import LucideKit
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
                    Lucide(sf: recipe.isFavorite ? "heart.fill" : "heart", size: 11)
                        .foregroundStyle(recipe.isFavorite ? Palette.warning : Palette.textQuaternary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(recipe.isFavorite ? "Favoriden çıkar" : "Favoriye ekle")
                Button(action: onEdit) {
                    Lucide(sf: "pencil", size: 11)
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
                        Text("kalori")
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
                            Lucide(sf: "arrow.up.right", size: 8)
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

// MARK: - Tarif Videoları

/// "Tarif Videoları" rafı — sadece isim + video linki. Recipe kütüphanesinden ayrı;
/// izlemek/hatırlamak için adlandırılmış linkler. Üstte isim+link ekle satırı, altta
/// liste (tıkla → linki aç, çöp → sil). Recipe gibi SwiftData/CloudKit ile saklanır.
struct RecipeVideosSection: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @Query(sort: \RecipeVideo.createdAt, order: .reverse) private var videos: [RecipeVideo]

    @State private var newTitle = ""
    @State private var newURL = ""
    @FocusState private var focus: Field?
    private enum Field { case title, url }

    private var canAdd: Bool {
        !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Circle().fill(Palette.accent).frame(width: 5, height: 5)
                Text("Tarif Videoları").eyebrow()
                Spacer(minLength: 8)
                if !videos.isEmpty {
                    Text("\(videos.count)")
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.textQuaternary)
                }
            }

            Text("Sadece isim + video linki. İzlemek için sakladığın tarifli videolar.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Palette.textQuaternary)

            addRow

            if videos.isEmpty {
                Text("Henüz video yok — üstten isim ve link ekle.")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.element.persistentModelID) { idx, video in
                        if idx > 0 { Hairline() }
                        RecipeVideoRow(
                            video: video,
                            onOpen: { if let u = video.url { openURL(u) } },
                            onDelete: { delete(video) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("", text: $newTitle, prompt: Text("İsim (ör: Fırında tavuk)"))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focus, equals: .title)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(fieldBackground)
                .onSubmit { focus = .url }

            TextField("", text: $newURL, prompt: Text("Video linki"))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focus, equals: .url)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(fieldBackground)
                .onSubmit { add() }

            Button(action: add) {
                Text("Ekle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canAdd ? Palette.btnFg : Palette.textQuaternary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(canAdd ? Palette.btnBg : Palette.fieldFill)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .help("Videoyu ekle")
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.fieldFill)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.6)
            )
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !url.isEmpty else { return }
        let lower = url.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            url = "https://" + url
        }
        let video = RecipeVideo(title: title, urlString: url)
        ctx.insert(video)
        ctx.saveOrReport()
        newTitle = ""
        newURL = ""
        focus = .title
    }

    private func delete(_ video: RecipeVideo) {
        ctx.delete(video)
        ctx.saveOrReport()
    }
}

/// Tek video satırı — isim + kaynak host, tıkla linki aç, çöp ikonu sil.
struct RecipeVideoRow: View {
    let video: RecipeVideo
    var onOpen: () -> Void
    var onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Lucide(sf: "link", size: 12)
                .foregroundStyle(Palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(video.sourceHost ?? video.urlString)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onDelete) {
                Lucide(sf: "trash", size: 11)
                    .foregroundStyle(hovering ? Palette.negative : Palette.textQuaternary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Videoyu sil")
            Lucide(sf: "arrow.up.right", size: 10)
                .foregroundStyle(hovering ? Palette.textSecondary : Palette.textQuaternary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
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
