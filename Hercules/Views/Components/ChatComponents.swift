import SwiftUI
import LucideKit
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AssistantMark: View {
    var size: CGFloat
    var cornerRadius: CGFloat

    /// Her örneğe sabit-ama-farklı bir desen: aynı ekrandaki avatarlar birbirinin kopyası
    /// görünmesin, ama yeniden çizimde zıplamasın.
    var seed: Double = 0
    var state: CoachOrbState = .idle

    /// Koç fotoğrafı dosyası değişince yüzü tazeleyen sayaç.
    @State private var avatarEpoch = 0

    var body: some View {
        Group {
            // Ayarlardan koç fotoğrafı seçilmişse yüz odur; seçilmemişse orb kalır.
            if avatarEpoch >= 0, let img = CoachAvatarStore.image() {
                Image(platform: img).resizable().scaledToFill()
            } else {
                CoachOrb(state: state, seed: seed)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
        .onReceive(NotificationCenter.default.publisher(for: CoachAvatarStore.changed)) { _ in
            avatarEpoch += 1
        }
    }
}

/// V1 preset popover'ı — kompakt satırlar: eyebrow başlık + arama, hairline ayraçlı
/// satır listesi (marka/ad/makro solda · kcal + ölçek pill'leri sağda), mikro dipnot.
struct FoodPresetWidget: View {
    let presets: [FoodPreset]
    @Binding var query: String
    let feedback: String?
    var onAdd: (FoodPreset, Double) -> Void

    private var filteredPresets: [FoodPreset] {
        let q = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return presets }
        return presets.filter { preset in
            normalized([preset.brand, preset.name, preset.category, preset.note, preset.searchText].joined(separator: " "))
                .contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("PRESETLER")
                        .font(Typography.label)
                        .tracking(0.9)
                        .foregroundStyle(ChatChrome.quaternary)
                    Text("sık kullandıklarını bugüne ekle")
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.tertiary)
                    Spacer(minLength: 0)
                    Text("\(filteredPresets.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(ChatChrome.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(ChatChrome.panelRaised))
                        .overlay(Capsule().strokeBorder(ChatChrome.border, lineWidth: 0.5))
                }

                HStack(spacing: 8) {
                    Lucide(sf: "magnifyingglass", size: 11)
                        .foregroundStyle(ChatChrome.tertiary)
                    TextField("Protein, marka, ürün ara", text: $query)
                        .textFieldStyle(.plain)
                        .font(Typography.body)
                        .foregroundStyle(ChatChrome.primary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ChatChrome.panelRaised.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(ChatChrome.border, lineWidth: 0.55)
                )

                if let feedback {
                    Label { Text(feedback) } icon: { Lucide(sf: "checkmark.circle.fill") }
                        .font(Typography.captionBold)
                        .foregroundStyle(ChatChrome.positive)
                        .lineLimit(2)
                }
            }
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 11, trailing: 14))

            Hairline()

            if filteredPresets.isEmpty {
                VStack(spacing: 6) {
                    Text("Preset bulunamadı")
                        .font(Typography.bodyBold)
                        .foregroundStyle(ChatChrome.secondary)
                    Text("Aramayı biraz kısaltmayı dene.")
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredPresets.enumerated()), id: \.element.id) { i, preset in
                            if i > 0 { Hairline().padding(.horizontal, 14) }
                            FoodPresetRow(preset: preset, onAdd: onAdd)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Hairline()

            Text("Eklenen kayıt bugünün günlüğüne düşer · sağdaki buton varsayılan ölçeği ekler")
                .font(.system(size: 9.5))
                .foregroundStyle(ChatChrome.quaternary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Balon zemini call-site'taki .presentationBackground'dan gelir — çifte border/chrome yok.
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased(with: Locale(identifier: "tr_TR"))
    }
}

/// V1 kompakt preset satırı. Not (varsa) hover'da görünür.
struct FoodPresetRow: View {
    let preset: FoodPreset
    var onAdd: (FoodPreset, Double) -> Void

    private var defaultServings: Double {
        max(1, preset.defaultServings)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if !preset.brand.isEmpty {
                    Text(preset.brand.uppercased(with: Locale(identifier: "tr_TR")))
                        .font(Typography.label)
                        .tracking(0.8)
                        .foregroundStyle(ChatChrome.quaternary)
                }
                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ChatChrome.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                macroLine
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(Fmt.int(preset.calories(for: defaultServings)))
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundStyle(ChatChrome.primary)
                    Text("kalori")
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(ChatChrome.quaternary)
                }
                HStack(spacing: 6) {
                    servingButton(preset.servingCountText(1), prominent: false) {
                        onAdd(preset, 1)
                    }
                    servingButton("+ " + preset.servingCountText(defaultServings), prominent: true) {
                        onAdd(preset, defaultServings)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .help(preset.note)
    }

    private var macroLine: some View {
        HStack(spacing: 4) {
            macroPair("P", preset.protein(for: defaultServings))
            Text("·").font(.system(size: 10.5)).foregroundStyle(ChatChrome.quaternary)
            macroPair("K", preset.carbs(for: defaultServings))
            Text("·").font(.system(size: 10.5)).foregroundStyle(ChatChrome.quaternary)
            macroPair("Y", preset.fat(for: defaultServings))
            Text("· \(Fmt.int(preset.servingGrams)) g / \(preset.servingLabel)")
                .font(.system(size: 10.5))
                .foregroundStyle(ChatChrome.quaternary)
        }
        .lineLimit(1)
        .padding(.top, 2)
    }

    private func macroPair(_ letter: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Text(letter)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ChatChrome.tertiary)
            Text(value.map { Fmt.num($0, digits: 1) } ?? "—")
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(ChatChrome.secondary)
        }
    }

    private func servingButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(prominent ? ChatChrome.ink : ChatChrome.secondary)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(prominent ? ChatChrome.white : ChatChrome.panelRaised.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(prominent ? Color.clear : ChatChrome.border, lineWidth: 0.6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Composer'daki "+" butonunun açtığı hızlı-ekle paneli (fotodaki launcher fikri).
/// Üstte veriden türetilen "Sık Girdiklerin" (son 60g · 3+ kez), altta elle presetler.
/// Satıra tıkla → metni composer'a yazar (kullanıcı gönderir) · ok → anında gönderir.
struct QuickAddPanel: View {
    let frequent: [FrequentFood]
    let presets: [FoodPreset]
    @Binding var query: String
    var onInsert: (String) -> Void
    var onSend: (String) -> Void

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased(with: Locale(identifier: "tr_TR"))
    }

    private var q: String { normalized(query.trimmingCharacters(in: .whitespacesAndNewlines)) }

    private var filteredFrequent: [FrequentFood] {
        guard !q.isEmpty else { return frequent }
        return frequent.filter { normalized($0.displayName).contains(q) }
    }

    private var filteredPresets: [FoodPreset] {
        guard !q.isEmpty else { return presets }
        return presets.filter {
            normalized([$0.brand, $0.name, $0.category, $0.note, $0.searchText].joined(separator: " ")).contains(q)
        }
    }

    private var totalCount: Int { filteredFrequent.count + filteredPresets.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            if filteredFrequent.isEmpty && filteredPresets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !filteredFrequent.isEmpty {
                            sectionHeader("SIK GİRDİKLERİN", detail: "son 60 gün · 3+ kez")
                            ForEach(Array(filteredFrequent.enumerated()), id: \.element.id) { i, food in
                                if i > 0 { Hairline().padding(.horizontal, 14) }
                                frequentRow(food)
                            }
                        }
                        if !filteredPresets.isEmpty {
                            sectionHeader("PRESETLER", detail: "elle tanımlı")
                            ForEach(Array(filteredPresets.enumerated()), id: \.element.id) { i, preset in
                                if i > 0 { Hairline().padding(.horizontal, 14) }
                                presetRow(preset)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Hairline()
            Text("Satıra dokun → mesaja yazılır (miktarı değiştirip ↵) · ok → hemen gönderir")
                .font(.system(size: 9.5))
                .foregroundStyle(ChatChrome.quaternary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Balon zemini call-site'taki .presentationBackground'dan gelir — çifte border/chrome yok.
    }

    // MARK: bölümler

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("HIZLI EKLE")
                    .font(Typography.label)
                    .tracking(0.9)
                    .foregroundStyle(ChatChrome.quaternary)
                Text("sık girdiklerini çat çut yaz")
                    .font(Typography.caption)
                    .foregroundStyle(ChatChrome.tertiary)
                Spacer(minLength: 0)
                Text("\(totalCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(ChatChrome.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(ChatChrome.panelRaised))
                    .overlay(Capsule().strokeBorder(ChatChrome.border, lineWidth: 0.5))
            }

            HStack(spacing: 8) {
                Lucide(sf: "magnifyingglass", size: 11)
                    .foregroundStyle(ChatChrome.tertiary)
                TextField("Yemek, marka ara", text: $query)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundStyle(ChatChrome.primary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                // Buzz input dolgusu: el yapımı yüzey tonu yerine kromun field-fill tülü.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ChatChrome.whiteSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ChatChrome.borderStrong.opacity(0.7), lineWidth: 1)
            )
        }
        .padding(EdgeInsets(top: 13, leading: 14, bottom: 11, trailing: 14))
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(Typography.label)
                .tracking(0.8)
                .foregroundStyle(ChatChrome.tertiary)
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(ChatChrome.quaternary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(query.isEmpty ? "Henüz yeterli tekrar yok" : "Eşleşme yok")
                .font(Typography.bodyBold)
                .foregroundStyle(ChatChrome.secondary)
            Text(query.isEmpty
                 ? "Aynı yemeği 3+ kez girince burada belirir."
                 : "Aramayı kısaltmayı dene.")
                .font(Typography.caption)
                .foregroundStyle(ChatChrome.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding(20)
    }

    // MARK: satırlar

    private func frequentRow(_ food: FrequentFood) -> some View {
        // Sol (isim+makro+rozet) = "yaz" butonu · ok = ayrı "gönder" butonu (iç içe değil).
        HStack(alignment: .center, spacing: 10) {
            Button { onInsert(food.displayName) } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ChatChrome.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        macroLine(kcal: food.calories, p: food.protein, c: food.carbs, f: food.fat, grams: food.grams)
                    }
                    Spacer(minLength: 6)
                    frequencyBadge(food.count)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mesaja yaz (miktarı değiştirip ↵)")

            sendArrow { onSend(food.displayName) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func presetRow(_ preset: FoodPreset) -> some View {
        let servings = max(1, preset.defaultServings)
        let text = preset.entryName(for: servings)
        return HStack(alignment: .center, spacing: 10) {
            Button { onInsert(text) } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        if !preset.brand.isEmpty {
                            Text(preset.brand.uppercased(with: Locale(identifier: "tr_TR")))
                                .font(Typography.label)
                                .tracking(0.8)
                                .foregroundStyle(ChatChrome.quaternary)
                        }
                        Text(preset.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ChatChrome.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        macroLine(
                            kcal: preset.calories(for: servings),
                            p: preset.protein(for: servings),
                            c: preset.carbs(for: servings),
                            f: preset.fat(for: servings),
                            grams: preset.grams(for: servings)
                        )
                    }
                    Spacer(minLength: 6)
                    Text(preset.servingCountText(servings))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ChatChrome.tertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(ChatChrome.panelRaised))
                        .overlay(Capsule().strokeBorder(ChatChrome.border, lineWidth: 0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(preset.note.isEmpty ? "Mesaja yaz" : preset.note)

            sendArrow { onSend(text) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func frequencyBadge(_ count: Int) -> some View {
        Text("\(count)×")
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(ChatChrome.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(ChatChrome.panelRaised))
            .overlay(Capsule().strokeBorder(ChatChrome.border, lineWidth: 0.5))
    }

    private func sendArrow(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Lucide(sf: "arrow.up", size: 11)
                .foregroundStyle(ChatChrome.ink)
                .frame(width: 26, height: 26)
                .background(Circle().fill(ChatChrome.accent))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Hemen gönder")
    }

    private func macroLine(kcal: Double, p: Double?, c: Double?, f: Double?, grams: Double?) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                Text(Fmt.int(kcal))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(ChatChrome.secondary)
                Text("kalori")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(ChatChrome.quaternary)
            }
            Text("·").font(.system(size: 10.5)).foregroundStyle(ChatChrome.quaternary)
            macroPair("P", p)
            macroPair("K", c)
            macroPair("Y", f)
            if let grams, grams > 0 {
                Text("· \(Fmt.int(grams)) g")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ChatChrome.quaternary)
            }
        }
        .lineLimit(1)
        .padding(.top, 1)
    }

    private func macroPair(_ letter: String, _ value: Double?) -> some View {
        HStack(spacing: 2) {
            Text(letter)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(ChatChrome.tertiary)
            Text(value.map { Fmt.int($0) } ?? "—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ChatChrome.secondary)
        }
    }
}

struct ChatNearBottomKey: PreferenceKey {
    static var defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

struct ChatHintFlow<Content: View>: View {
    var spacing: CGFloat = 5
    @ViewBuilder var content: Content

    var body: some View {
        ChatHintWrappingHStack(spacing: spacing) {
            content
        }
    }
}

struct ChatHintWrappingHStack: Layout {
    var spacing: CGFloat = 5

    /// Ölçülen alt-görünüm boyutları. `sizeThatFits` ve `placeSubviews` aynı geçişte
    /// ikisi de her token'ı ölçüyordu (SwiftUI `sizeThatFits`i birden çok kez de
    /// çağırabilir) — akan cevapta saniyede on binlerce metin ölçümü demekti.
    struct Cache {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        // Token sayısı değiştiyse (akış yeni kelime açtı) yeniden ölç.
        if cache.sizes.count != subviews.count {
            cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let sizes = cache.sizes
        let maxWidth = proposal.width ?? 0
        guard maxWidth > 0 else {
            return CGSize(
                width: sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1)),
                height: sizes.map(\.height).max() ?? 0
            )
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for size in sizes {
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            measuredWidth = max(measuredWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: measuredWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = index < cache.sizes.count
                ? cache.sizes[index]
                : subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Buzz kullanıcı avatarı: ada göre deterministik renk (hash*31+codePoint mod 7)
/// üstünde yarı-kalın baş harf — UserAvatar.tsx fallback paleti.
struct ChatUserAvatar: View {
    let name: String
    var size: CGFloat = 32

    private static let palette: [(bg: UInt32, fg: Color)] = [
        (0x3B82F6, .white), (0x10B981, .white), (0xFBBF24, Color(hex: 0x451A03)),
        (0xF43F5E, .white), (0x22D3EE, Color(hex: 0x083344)), (0x8B5CF6, .white),
        (0xF97316, .white),
    ]

    private var colors: (bg: UInt32, fg: Color) {
        var hash = 0
        for scalar in name.lowercased().unicodeScalars { hash = hash &* 31 &+ Int(scalar.value) }
        let n = Self.palette.count
        return Self.palette[((hash % n) + n) % n]
    }

    var body: some View {
        Group {
            if avatarEpoch >= 0, let img = ProfileAvatarStore.image() {
                Image(platform: img).resizable().scaledToFill()
            } else {
                initialFace
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onReceive(NotificationCenter.default.publisher(for: ProfileAvatarStore.changed)) { _ in
            avatarEpoch += 1
        }
    }

    @State private var avatarEpoch = 0

    private var initialFace: some View {
        ZStack {
            Circle().fill(Color(hex: colors.bg))
            Text(name.first.map(String.init)?.uppercased(with: Locale(identifier: "tr_TR")) ?? "S")
                .font(.system(size: size * 0.41, weight: .semibold))
                .foregroundStyle(colors.fg)
        }
    }
}

struct MessageBubble: View {
    let turn: ChatTurn
    let isStreaming: Bool
    var userName: String = "Sen"
    /// Kartın açılış günü, bugüne göre fark: geçmiş bir günün thread'inde o gün
    /// (bkz. `ChatDailyThread.logDayOffset`), aksi halde 0 = bugün.
    var defaultDayOffset: Int = 0
    /// Öğünü günlüğe yaz — parametre kartta seçilen gün.
    var onSave: (Date) -> Void
    var onConfirmAction: (AIAppAction) -> Void
    var onRejectAction: (AIAppAction) -> Void

    /// Kullanıcının kartta elle seçtiği gün; dokunulmadıysa thread'in günü geçerli.
    @State private var pickedDayOffset: Int? = nil
    @State private var pickingDate = false

    /// Kartta seçili günün bugüne göre farkı (0 = bugün, -1 = dün).
    private var dayOffset: Int {
        get { pickedDayOffset ?? defaultDayOffset }
        nonmutating set { pickedDayOffset = newValue }
    }
    @State private var zoomingAvatar = false

    /// Buzz kanal satırı: iki rol de aynı anatomide — avatar solda, yazar +
    /// saat başlığı, altında gövde. Balon yok; sahiplik avatar ve isimle okunur
    /// (MessageRow.tsx / MessageHeader.tsx dili).
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Yüze tıklayınca fotoğraf büyür (sidebar kimlik satırlarıyla aynı davranış).
            Button { zoomingAvatar = true } label: {
                Group {
                    if turn.role == .user {
                        ChatUserAvatar(name: userName)
                    } else {
                        ChatAssistantAvatar(state: isStreaming ? .talking : .idle, seed: orbSeed)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.top, 1)
            .popover(isPresented: $zoomingAvatar, arrowEdge: .trailing) {
                AvatarZoomCard(
                    name: turn.role == .user ? userName : CoachIdentity.name,
                    subtitle: turn.role == .user ? "Profil" : "AI koç",
                    // Fotoğraf seçimi Mac'te panelden, telefonda Profil sekmesinden.
                    onPickPhoto: pickAvatarAction
                ) {
                    if turn.role == .user {
                        ChatUserAvatar(name: userName, size: 168)
                    } else {
                        AssistantMark(size: 168, cornerRadius: 84)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(turn.role == .user ? userName : CoachIdentity.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(ChatChrome.primary)
                        .lineLimit(1)
                    Text(Fmt.timeShort.string(from: turn.createdAt))
                        .font(.system(size: 11, weight: .regular).monospacedDigit())
                        .foregroundStyle(ChatChrome.quaternary)
                }

                if turn.role == .user {
                    Text(turn.text)
                        .font(ChatChrome.messageBody)
                        .foregroundStyle(ChatChrome.primary)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else {
                    assistantBody
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var assistantBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let q = turn.searchedFor {
                HStack(spacing: 5) {
                    Lucide(sf: "globe", size: 9)
                    Text("Web'de arandı: \"\(q)\"")
                        .font(Typography.caption)
                }
                .foregroundStyle(ChatChrome.tertiary)
                .padding(.bottom, 2)
            }
            // Stream plain text; parse Markdown once the reply is complete.
            if isStreaming && !turn.text.isEmpty {
                StreamingRevealText(text: turn.text)
            } else if !turn.text.isEmpty {
                MarkdownText(text: turn.text)
                    .textSelection(.enabled)
            }

            if let food = turn.food {
                foodCard(food)
            }
            if !turn.actions.isEmpty {
                ForEach(turn.actions) { action in
                    actionCard(action)
                }
            }
        }
        .lineSpacing(4)
    }

    #if os(macOS)
    private var pickAvatarAction: (() -> Void)? {
        { turn.role == .user ? ProfileAvatarStore.pickImage() : CoachAvatarStore.pickImage() }
    }
    #else
    private var pickAvatarAction: (() -> Void)? { nil }
    #endif

    /// Eski orb API'siyle uyum için mesajdan türetilen sabit tohum.
    private var orbSeed: Double { Double(abs(turn.id.hashValue) % 628) / 100.0 }

    // MARK: Öğün kartı

    /// Seçili gün — bugüne göre `dayOffset` gün geride. Saat korunur ki dünkü
    /// öğün dünün akışında makul bir saatte dursun.
    private var targetDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
    }

    /// Öğün kartı: başlık + mono kalori · makro stat şeridi (sayfa geneliyle aynı
    /// hücre dili) · altta gün seçici + eylem.
    private func foodCard(_ food: AIFoodResult) -> some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    foodTitle(food).frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
                    foodCalories(food)
                }
                VStack(alignment: .leading, spacing: 10) {
                    foodTitle(food)
                    foodCalories(food)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)

            if food.protein_g != nil || food.carbs_g != nil || food.fat_g != nil {
                chatRule
                // Nokta+harf satırı yerine sayfa genelindeki stat hücreleri:
                // etiket üstte soluk, değer altta mono — dikey çizgiyle ayrık.
                HStack(spacing: 8) {
                    macroCell("Protein", food.protein_g, Palette.macroProtein)
                    macroRule
                    macroCell("Karb", food.carbs_g, Palette.macroCarbs)
                    macroRule
                    macroCell("Yağ", food.fat_g, Palette.macroFat)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }

            chatRule
            foodCardFooter
        }
        // Site geneliyle aynı düz dil: kart zemini + kenarlık yerine tek peçe
        // yüzey; bölmeler ince çizgiyle ayrışır.
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ChatChrome.whiteSoft))
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.top, 6)
    }

    private func foodTitle(_ food: AIFoodResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(food.name ?? "Yemek")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(ChatChrome.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let grams = food.grams {
                Text("\(Fmt.int(grams)) g")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ChatChrome.quaternary)
            }
        }
    }

    private func foodCalories(_ food: AIFoodResult) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(Fmt.int(food.calories ?? 0))
                .font(.system(size: 22, weight: .regular, design: .monospaced))
                .foregroundStyle(ChatChrome.primary)
            Text("kalori")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(ChatChrome.quaternary)
        }
        .fixedSize()
    }

    /// Koç yüzeyi temadan bağımsız kömür — ayraç da kendi kromundan gelir.
    private var chatRule: some View {
        Rectangle().fill(ChatChrome.border).frame(height: 0.5)
    }

    private var macroRule: some View {
        Rectangle().fill(ChatChrome.border).frame(width: 1, height: 24)
    }

    private func macroCell(_ label: String, _ value: Double?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(ChatChrome.quaternary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map(Fmt.int) ?? "—")
                    .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ChatChrome.primary)
                Text("g")
                    .font(.system(size: 10))
                    .foregroundStyle(ChatChrome.quaternary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Alt şerit: kaydedilmemişse gün seçici + ekle butonu, kaydedilmişse
    /// hangi güne yazıldığının onayı.
    @ViewBuilder
    private var foodCardFooter: some View {
        if turn.saved {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    foodSavedLabel
                    Spacer(minLength: 0)
                    foodSavedDate
                }
                VStack(alignment: .leading, spacing: 6) {
                    foodSavedLabel
                    foodSavedDate
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    dayStepper.fixedSize()
                    Spacer(minLength: 0)
                    saveFoodButton.fixedSize(horizontal: true, vertical: false)
                }
                VStack(spacing: 10) {
                    dayStepper
                    saveFoodButton
                }
            }
            .padding(12)
        }
    }

    private var foodSavedLabel: some View {
        Label {
            Text("Günlüğe eklendi")
                .font(Typography.captionBold)
                .foregroundStyle(ChatChrome.secondary)
        } icon: {
            Lucide(sf: "checkmark", size: 11)
                .foregroundStyle(ChatChrome.positive)
        }
        .fixedSize()
    }

    private var foodSavedDate: some View {
        Text("\(Fmt.dayMonth.string(from: turn.savedFoodDate ?? turn.createdAt)) · Takvim'de")
            .font(.system(size: 10.5))
            .foregroundStyle(ChatChrome.quaternary)
            .fixedSize()
    }

    private var saveFoodButton: some View {
        Button { onSave(targetDate) } label: {
            HStack(spacing: 7) {
                Lucide(sf: "plus", size: 12)
                Text("Günlüğe ekle")
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize()
            }
            .foregroundStyle(ChatChrome.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(ChatChrome.white))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat-save-food-\(turn.id.uuidString)")
    }

    /// ‹ Bugün › — bir tık bir gün. Etikete tıklayınca takvimden gün seçilir.
    /// İleri yön bugünde durur: geçmişe yemek yazılır, geleceğe değil.
    private var dayStepper: some View {
        HStack(spacing: 2) {
            stepButton("chevron.left", enabled: dayOffset > -180) { dayOffset -= 1 }

            Button { pickingDate = true } label: {
                Text(dayLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(dayOffset == 0 ? ChatChrome.secondary : ChatChrome.primary)
                    .lineLimit(1)
                    .frame(minWidth: 112, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Takvimden gün seç")
            .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { targetDate },
                        set: { picked in
                            let cal = Calendar.current
                            dayOffset = min(0, cal.dateComponents(
                                [.day],
                                from: cal.startOfDay(for: .now),
                                to: cal.startOfDay(for: picked)
                            ).day ?? 0)
                        }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(12)
            }

            stepButton("chevron.right", enabled: dayOffset < 0) { dayOffset += 1 }
        }
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Lucide(sf: icon, size: 9)
                .foregroundStyle(enabled ? ChatChrome.secondary : ChatChrome.quaternary)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var dayLabel: String {
        let date = Fmt.dayMonth.string(from: targetDate)
        switch dayOffset {
        case 0:  return "Bugün · \(date)"
        case -1: return "Dün · \(date)"
        default: return date
        }
    }

    /// Uygulama aksiyonu — öğün kartıyla aynı düz kabuk.
    private func actionCard(_ action: AIAppAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Lucide(sf: actionIcon(action), size: 11)
                    .foregroundStyle(actionTint(action))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(actionTint(action).opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(action.displayTitle)
                            .font(Typography.bodyBold)
                            .foregroundStyle(ChatChrome.primary)
                        statusPill(action)
                    }
                    Text(action.displaySummary)
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let result = action.resultMessage, !result.isEmpty {
                        Text(result)
                            .font(Typography.caption)
                            .foregroundStyle(action.status == .failed ? Palette.negative : ChatChrome.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if action.status == .pending && action.requiresConfirmation {
                HStack(spacing: 8) {
                    Button {
                        onConfirmAction(action)
                    } label: {
                        Label { Text("Onayla") } icon: { Lucide(sf: "checkmark") }
                            .font(Typography.captionBold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChatChrome.ink)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(ChatChrome.white))

                    Button {
                        onRejectAction(action)
                    } label: {
                        Text("Vazgeç")
                            .font(Typography.captionBold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChatChrome.secondary)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(ChatChrome.whiteSoft))
                }
            }
        }
        .padding(.init(top: 12, leading: 18, bottom: 12, trailing: 18))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ChatChrome.whiteSoft))
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.top, 6)
    }

    private func statusPill(_ action: AIAppAction) -> some View {
        Text(statusText(action.status, requiresConfirmation: action.requiresConfirmation))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(actionTint(action))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(actionTint(action).opacity(0.13)))
    }

    private func statusText(_ status: AIAppActionStatus, requiresConfirmation: Bool) -> String {
        switch status {
        case .pending: return requiresConfirmation ? "ONAY BEKLİYOR" : "BEKLİYOR"
        case .applied: return "UYGULANDI"
        case .rejected: return "VAZGEÇİLDİ"
        case .failed: return "HATA"
        }
    }

    private func actionIcon(_ action: AIAppAction) -> String {
        switch action.status {
        case .applied: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .pending:
            switch action.tool {
            case .logFood: return "plus.circle"
            case .addRecipe: return "book.closed"
            case .updateWorkoutPlan: return "dumbbell"
            }
        }
    }

    private func actionTint(_ action: AIAppAction) -> Color {
        switch action.status {
        case .applied: return Palette.positive
        case .rejected: return ChatChrome.tertiary
        case .failed: return Palette.negative
        case .pending: return action.requiresConfirmation ? ChatChrome.white : ChatChrome.secondary
        }
    }

    /// V1 makro noktası: renkli 5px nokta + harf + mono değer.
}

// MARK: - Orb (ElevenLabs "Orb" native SwiftUI karşılığı)

/// Ajanın canlı hâli. WebGL/Three.js yerine sesli mod olmadığı için canlı ses kaynağımız yok;
/// idle/thinking chat durumundan sürülür (listening/talking API paritesi için durur).
enum OrbState { case idle, listening, thinking, talking }

/// Akışkan iki-renk gradyan küre — Canvas + TimelineView (avatar boyutunda shader'dan farkı
/// okunmaz; macOS14/iOS17 güvenli, .metal/pbxproj yok). Perf: `idle` DONUK tek karedir (uzun
/// sohbette geçmiş avatarlar bedava), yalnız thinking/talking/listening akar.
struct Orb: View {
    /// ElevenLabs varsayılanı (#CADCFC → #A0B9D1).
    var colors: [Color] = [
        Color(red: 0.792, green: 0.863, blue: 0.988),
        Color(red: 0.627, green: 0.725, blue: 0.820)
    ]
    var state: OrbState = .idle
    var inputVolume: Double = 0
    var outputVolume: Double = 0
    var seed: Double = 0

    private var animated: Bool { if case .idle = state { return false } else { return true } }

    var body: some View {
        if animated {
            TimelineView(.animation) { tl in
                canvas(t: tl.date.timeIntervalSinceReferenceDate + seed)
            }
        } else {
            canvas(t: 8.37 + seed)   // sabit kare; seed her mesajda hafif farklı desen verir
        }
    }

    private func canvas(t: Double) -> some View {
        Canvas { ctx, size in Orb.render(&ctx, size, t: t, colors: colors, state: state,
                                         inputVolume: inputVolume, outputVolume: outputVolume, seed: seed) }
    }

    private static func render(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double,
                               colors: [Color], state: OrbState,
                               inputVolume: Double, outputVolume: Double, seed: Double) {
        let rect = CGRect(origin: .zero, size: size)
        let r = min(size.width, size.height) / 2
        let cx = size.width / 2, cy = size.height / 2
        let c0 = colors.first ?? .blue
        let c1 = colors.last ?? c0

        ctx.clip(to: Path(ellipseIn: rect))

        let energy: Double, speed: Double
        switch state {
        case .idle:      energy = 0.32; speed = 0.0
        case .listening: energy = 0.45 + inputVolume * 0.5;  speed = 0.9
        case .thinking:  energy = 0.95;                       speed = 1.7
        case .talking:   energy = 0.60 + outputVolume * 0.5; speed = 1.2
        }
        let tt = t * speed

        // taban gradyan
        ctx.fill(Path(ellipseIn: rect), with: .linearGradient(
            Gradient(colors: [c0, c1]),
            startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))

        // akan bloblar → parıltı
        ctx.blendMode = .plusLighter
        for i in 0..<3 {
            let ph = tt + Double(i) * 2.1 + seed
            let orbit = r * (0.30 + 0.18 * energy)
            let bx = cx + CGFloat(cos(ph * 0.9 + Double(i))) * orbit
            let by = cy + CGFloat(sin(ph * 1.1 + Double(i) * 1.7)) * orbit
            let br = r * (0.65 + 0.30 * (0.5 + 0.5 * sin(ph * 0.7)))
            let c = colors[i % max(colors.count, 1)]
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [c.opacity(0.30 + 0.40 * energy), .clear]),
                center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: br))
        }

        // sol-üst sheen (fresnel hissi)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.40), .clear]),
            center: CGPoint(x: cx - r * 0.35, y: cy - r * 0.45), startRadius: 0, endRadius: r * 0.95))

        // iç kenar gölgesi → küresellik
        ctx.blendMode = .multiply
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.06, dy: r * 0.06)),
                   with: .color(c1.opacity(0.35)), lineWidth: max(r * 0.14, 0.5))
    }
}

/// ElevenLabs "Shimmering Text" native karşılığı: metin boyunca kayan ışık bandı
/// (Motion yerine TimelineView + maskeli gradyan). Boş-ekran başlığı + "düşünüyor"da kullanılır.
struct ShimmeringText: View {
    let text: String
    var font: Font = ChatChrome.messageBody
    var base: Color = ChatChrome.tertiary
    var shimmer: Color = ChatChrome.primary
    var tracking: CGFloat = 0
    var duration: Double = 2.4

    var body: some View {
        TimelineView(.animation) { tl in
            let p = (tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)) / duration
            Text(text).font(font).tracking(tracking)
                .foregroundStyle(base)
                .overlay {
                    GeometryReader { geo in
                        let w = geo.size.width
                        LinearGradient(colors: [.clear, shimmer, .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: w * 0.55)
                            .offset(x: -w * 0.55 + (w + w * 0.55) * p)
                    }
                    .mask(Text(text).font(font).tracking(tracking))
                }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - TextEffect (streaming reveal) + GlowEffect

/// Kelime insertion transition'ı: blur+fade+yukarı kayarak belirir (ElevenLabs TextEffect
/// "fade-in-blur"/"slide" preset'i). iOS17/macOS14 Transition protokolü.
struct RevealTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 3)
            .offset(y: phase.isIdentity ? 0 : 5)
    }
}

/// One text layout for the live reply. Per-word views and blur transitions made
/// every typewriter tick remeasure hundreds of subviews in long answers.
struct StreamingRevealText: View {
    let text: String
    var font: Font = ChatChrome.messageBody
    var color: Color = ChatChrome.primary

    var body: some View {
        Text(verbatim: text)
            .font(font)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// ElevenLabs/motion-primitives "GlowEffect" — composer submit ederken renkli akan glow.
/// colorShift: dönen angular gradient + blur (Motion yerine TimelineView; kapalıyken duraklar).
struct GlowEffect: View {
    var colors: [Color] = [
        Color(red: 0.031, green: 0.580, blue: 1.000),   // #0894FF
        Color(red: 0.788, green: 0.349, blue: 0.867),   // #C959DD
        Color(red: 1.000, green: 0.180, blue: 0.329),   // #FF2E54
        Color(red: 1.000, green: 0.565, blue: 0.016)    // #FF9004
    ]
    var active: Bool
    var cornerRadius: CGFloat = 14
    var blur: CGFloat = 11
    var lineWidth: CGFloat = 4

    var body: some View {
        TimelineView(.animation(paused: !active)) { tl in
            let deg = (tl.date.timeIntervalSinceReferenceDate * 55).truncatingRemainder(dividingBy: 360)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(gradient: Gradient(colors: colors + [colors.first ?? .blue]),
                                    center: .center, angle: .degrees(deg)),
                    lineWidth: lineWidth)
                .blur(radius: blur)
        }
        .opacity(active ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: active)
        .allowsHitTesting(false)
    }
}

/// Mesaj ve düşünme durumunda aynı monokrom işareti kullanır; aktifken sağ alttaki
/// beyaz nokta iş akışının sürdüğünü gösterir.
struct ChatAssistantAvatar: View {
    var state: OrbState = .idle
    var seed: Double = 0

    private var isActive: Bool {
        switch state {
        case .idle: return false
        case .listening, .thinking, .talking: return true
        }
    }

    var body: some View {
        // Orb, avatarın kendi durumunu taşısın: yanıt akarken canlansın, boştayken donuk
        // tek kare kalsın (sohbette onlarca avatar var, hepsini sürekli çizmek kasar).
        AssistantMark(size: 32, cornerRadius: 8,
                      seed: seed,
                      state: isActive ? .talking : .idle)
            .overlay(alignment: .bottomTrailing) {
                if isActive {
                    Circle()
                        .fill(ChatChrome.primary)
                        .frame(width: 5, height: 5)
                        .overlay(Circle().strokeBorder(ChatChrome.background, lineWidth: 1))
                        .offset(x: 1, y: 1)
                }
            }
    }
}

/// İlk-token öncesi "ajan düşünüyor" hâli: thinking orb + kayan shimmer metin (ElevenLabs
/// Response/agent-thinking dili). 3 nokta/Timer yerine ShimmeringText kendi animasyonunu sürer.
struct TypingIndicator: View {
    var searchQuery: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentThinkingGlyph(tint: ChatChrome.primary, dim: ChatChrome.quaternary)
            Group {
                if let q = searchQuery {
                    HStack(spacing: 5) {
                        Lucide(sf: "globe", size: 10)
                            .foregroundStyle(ChatChrome.tertiary)
                        ShimmeringText(text: "Web'de aranıyor: \"\(q)\"", font: Typography.caption)
                    }
                } else {
                    ShimmeringText(text: "Düşünüyor…")
                }
            }
            .frame(minHeight: 28, alignment: .center)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Markdown rendering (AI cevapları için)

/// Hafif blok-seviyesi markdown render'ı: başlık / madde listesi / numaralı liste /
/// kod bloğu / alıntı / paragraf. Satır-içi (kalın, italik, `kod`, [link](url))
/// AttributedString ile çözülür. Streaming bitince çağrılır (token başına değil).
struct MarkdownText: View {
    let text: String
    var baseFont: Font = ChatChrome.messageBody

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet([String])
        case numbered([String])
        case code(String)
        case quote(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .foregroundStyle(ChatChrome.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 2 : 0)
        case .paragraph(let text):
            Text(inline(text))
                .font(baseFont)
                .foregroundStyle(ChatChrome.primary)
                .tint(ChatChrome.accent)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(baseFont).foregroundStyle(ChatChrome.tertiary)
                        Text(inline(item)).font(baseFont).foregroundStyle(ChatChrome.primary)
                            .tint(ChatChrome.accent)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(baseFont).fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(ChatChrome.tertiary)
                        Text(inline(item)).font(baseFont).foregroundStyle(ChatChrome.primary)
                            .tint(ChatChrome.accent)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ChatChrome.secondary)
                    .textSelection(.enabled)
                    .padding(10)
            }
            // Buzz kod bloğu: bg muted/60 + border/70 — zeminden kartla ayrılır.
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ChatChrome.panelRaised.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ChatChrome.borderStrong.opacity(0.7), lineWidth: 1))
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(ChatChrome.accent.opacity(0.55)).frame(width: 2.5)
                Text(inline(text)).font(baseFont).italic()
                    .foregroundStyle(ChatChrome.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return .system(size: 19, weight: .bold)
        case 2:  return .system(size: 16.5, weight: .bold)
        default: return .system(size: 15, weight: .semibold)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attr = try? AttributedString(markdown: s, options: options) {
            return attr
        }
        return AttributedString(s)
    }

    // MARK: Parser

    private func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1 // kapanış fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }
            if line.isEmpty {
                flushParagraph(); i += 1; continue
            }
            if let level = headingLevel(line) {
                flushParagraph()
                let txt = String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, text: txt))
                i += 1; continue
            }
            if isBullet(line) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if isBullet(l) { items.append(stripBullet(l)); i += 1 } else { break }
                }
                blocks.append(.bullet(items)); continue
            }
            if isNumbered(line) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if isNumbered(l) { items.append(stripNumber(l)); i += 1 } else { break }
                }
                blocks.append(.numbered(items)); continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix(">") {
                        quote.append(String(l.dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                    } else { break }
                }
                blocks.append(.quote(quote.joined(separator: " "))); continue
            }
            paragraph.append(line); i += 1
        }
        flushParagraph()
        return blocks
    }

    private func headingLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return min(hashes, 3)
    }
    private func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") || line.hasPrefix("+ ")
    }
    private func stripBullet(_ line: String) -> String {
        for p in ["- ", "* ", "• ", "+ "] where line.hasPrefix(p) {
            return String(line.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }
    private func isNumbered(_ line: String) -> Bool {
        var idx = line.startIndex
        var digits = 0
        while idx < line.endIndex, line[idx].isNumber { idx = line.index(after: idx); digits += 1 }
        guard digits > 0, idx < line.endIndex, line[idx] == "." || line[idx] == ")" else { return false }
        let next = line.index(after: idx)
        return next < line.endIndex && line[next] == " "
    }
    private func stripNumber(_ line: String) -> String {
        guard let sep = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return line }
        return String(line[line.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - V1 model satırı yardımcıları

// MARK: - V1 chat ayarları paneli (sidebar + dock "···" popover'ı)
