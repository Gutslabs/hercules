import SwiftUI
import SwiftData

// MARK: - Main View

struct GuideView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UserGuideSection.sortIndex) private var sections: [UserGuideSection]
    @State private var selectedSection: UserGuideSection?
    @State private var showingAddSection = false
    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 12, alignment: .top)
    ]

    private var filtered: [UserGuideSection] {
        if searchText.isEmpty { return sections }
        return sections.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if let section = selectedSection {
                GuideDetailView(section: section) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedSection = nil
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                listView
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedSection?.id)
        .sheet(isPresented: $showingAddSection) {
            AddSectionSheet { newSection in
                newSection.sortIndex = sections.count
                context.insert(newSection)
                try? context.save()
            }
        }
    }

    // MARK: List

    private var listView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spor Beslenmesi Rehberi")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(sections.count) bölüm")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                addSectionButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                TextField("Ara…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                    )
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider().opacity(0.15)

            if sections.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(filtered) { section in
                            GuideSectionCard(section: section) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    selectedSection = section
                                }
                            } onDelete: {
                                context.delete(section)
                                try? context.save()
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Palette.background)
    }

    private var addSectionButton: some View {
        Button { showingAddSection = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Bölüm Ekle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.25))
            Text("Henüz bölüm yok")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Text("Sağ üstteki 'Bölüm Ekle' butonuyla başla.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
            Button { showingAddSection = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("İlk Bölümü Ekle")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }
}

// MARK: - Section Card

private struct GuideSectionCard: View {
    let section: UserGuideSection
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(section.swiftUIColor.opacity(0.18))
                        Image(systemName: section.iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(section.swiftUIColor)
                    }
                    .frame(width: 38, height: 38)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title.isEmpty ? "Başlıksız" : section.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !section.subtitle.isEmpty {
                        Text(section.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(section.cards.count) kart")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.065) : Color.white.opacity(0.042))
                    .animation(.easeInOut(duration: 0.15), value: hovering)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        hovering ? Color.white.opacity(0.18) : Color.white.opacity(0.09),
                        lineWidth: 0.75
                    )
                    .animation(.easeInOut(duration: 0.15), value: hovering)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }
}

// MARK: - Detail View

struct GuideDetailView: View {
    @Environment(\.modelContext) private var context
    let section: UserGuideSection
    let onBack: () -> Void

    @State private var showingAddCard = false
    @State private var showingAddTable = false
    @State private var editingCard: UserGuideCard?

    private var sortedCards: [UserGuideCard] {
        section.cards.sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Rehber")
                            .font(.system(size: 13.5, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                // Kart Ekle
                Button { showingAddCard = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Kart Ekle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                            )
                    )
                }
                .buttonStyle(.plain)

                // Tablo Ekle
                Button { showingAddTable = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tablecells.badge.ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Tablo Ekle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                            )
                    )
                }
                .buttonStyle(.plain)

                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(section.swiftUIColor.opacity(0.18))
                    Image(systemName: section.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(section.swiftUIColor)
                }
                .frame(width: 34, height: 34)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider().opacity(0.12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title.isEmpty ? "Başlıksız" : section.title)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        if !section.subtitle.isEmpty {
                            Text(section.subtitle)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 24)

                    if section.cards.isEmpty {
                        detailEmptyState
                    } else {
                        VStack(spacing: 14) {
                            ForEach(sortedCards) { card in
                                GuideCardView(card: card) {
                                    editingCard = card
                                } onDelete: {
                                    section.cards.removeAll { $0.id == card.id }
                                    context.delete(card)
                                    try? context.save()
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .background(Palette.background)
        .sheet(isPresented: $showingAddCard) {
            AddCardSheet { newCard in
                newCard.sortIndex = section.cards.count
                newCard.section = section
                context.insert(newCard)
                section.cards.append(newCard)
                try? context.save()
            }
        }
        .sheet(isPresented: $showingAddTable) {
            AddTableSheet { newCard in
                newCard.sortIndex = section.cards.count
                newCard.section = section
                context.insert(newCard)
                section.cards.append(newCard)
                try? context.save()
            }
        }
        .sheet(item: $editingCard) { card in
            if card.isTable {
                EditTableSheet(card: card)
            } else {
                EditCardSheet(card: card)
            }
        }
    }

    private var detailEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 40, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.2))
            Text("Henüz kart yok")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
            Text("Kart veya tablo eklemek için yukarıdaki butonları kullan.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Card View

private struct GuideCardView: View {
    let card: UserGuideCard
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack {
                HStack(spacing: 6) {
                    if card.isTable {
                        Image(systemName: "tablecells")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Text(card.cardTitle.isEmpty ? "Başlıksız" : card.cardTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Menu {
                    Button { onEdit() } label: {
                        Label("Düzenle", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Sil", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }

            // Content
            if card.isTable {
                tableView
            } else if !card.body.isEmpty {
                Text(card.body)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75)
                )
        )
    }

    @ViewBuilder
    private var tableView: some View {
        let headers = card.headers
        let rows = card.rows
        if headers.isEmpty {
            Text("Tablo boş")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
        } else {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(headers.indices, id: \.self) { i in
                        Text(headers[i])
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
                .background(Color.white.opacity(0.055))

                ForEach(rows.indices, id: \.self) { ri in
                    Divider().opacity(0.10)
                    HStack(spacing: 0) {
                        ForEach(rows[ri].indices, id: \.self) { ci in
                            Text(rows[ri][ci])
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.78))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                        }
                    }
                    .background(ri % 2 == 1 ? Color.white.opacity(0.022) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
            )
        }
    }

}

// MARK: - Add Section Sheet

struct AddSectionSheet: View {
    let onSave: (UserGuideSection) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var subtitle = ""
    @State private var selectedIcon = "book.closed"
    @State private var selectedColor = "blue"

    private let icons: [String] = [
        "square.3.layers.3d", "drop.fill", "sun.max.fill", "atom",
        "humidity.fill", "bolt.fill", "pills.fill", "cup.and.saucer.fill",
        "figure.strengthtraining.traditional", "waveform.path.ecg",
        "moon.stars.fill", "leaf.fill", "bolt.circle.fill", "arrow.left.arrow.right",
        "flame.fill", "dumbbell", "heart.fill", "brain",
        "fork.knife", "cross.vial.fill", "tablecells.fill", "list.clipboard.fill",
        "book.closed", "chart.bar",
    ]

    private let colors: [(String, Color)] = [
        ("blue", .blue), ("cyan", .cyan), ("teal", .teal), ("mint", .mint),
        ("green", .green), ("orange", .orange), ("red", .red), ("pink", .pink),
        ("purple", .purple), ("indigo", .indigo), ("yellow", .yellow), ("gray", .gray),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Yeni Bölüm")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button("İptal") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider().opacity(0.12)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Preview
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(colorValue(selectedColor).opacity(0.18))
                            Image(systemName: selectedIcon)
                                .font(.system(size: 22, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(colorValue(selectedColor))
                        }
                        .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(title.isEmpty ? "Bölüm başlığı" : title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(title.isEmpty ? .white.opacity(0.25) : .white)
                            Text(subtitle.isEmpty ? "Alt başlık" : subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(subtitle.isEmpty ? .white.opacity(0.2) : .white.opacity(0.5))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75)
                            )
                    )

                    // Text fields
                    VStack(alignment: .leading, spacing: 12) {
                        sheetLabel("Başlık")
                        styledField("Temel Kavramlar…", text: $title)
                        sheetLabel("Alt Başlık")
                        styledField("Kısa açıklama…", text: $subtitle)
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 10) {
                        sheetLabel("İkon")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                            ForEach(icons, id: \.self) { icon in
                                Button { selectedIcon = icon } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 18, weight: .medium))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(selectedIcon == icon ? colorValue(selectedColor) : .white.opacity(0.5))
                                        .frame(width: 44, height: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(selectedIcon == icon ? colorValue(selectedColor).opacity(0.16) : Color.white.opacity(0.05))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .strokeBorder(selectedIcon == icon ? colorValue(selectedColor).opacity(0.4) : Color.clear, lineWidth: 1.5)
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 10) {
                        sheetLabel("Renk")
                        HStack(spacing: 10) {
                            ForEach(colors, id: \.0) { name, color in
                                Button { selectedColor = name } label: {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(.white, lineWidth: selectedColor == name ? 2.5 : 0)
                                                .padding(2)
                                        )
                                        .scaleEffect(selectedColor == name ? 1.12 : 1)
                                        .animation(.spring(response: 0.2), value: selectedColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider().opacity(0.12)

            Button {
                let s = UserGuideSection(title: title, subtitle: subtitle, iconName: selectedIcon, colorName: selectedColor)
                onSave(s)
                dismiss()
            } label: {
                Text("Kaydet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(title.isEmpty ? Color.white.opacity(0.06) : Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .disabled(title.isEmpty)
            .padding(24)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .frame(minWidth: 460, minHeight: 600)
    }

    private func colorValue(_ name: String) -> Color {
        colors.first { $0.0 == name }?.1 ?? .blue
    }

    private func sheetLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func styledField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 14.5))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                    )
            )
    }
}

// MARK: - Add Card Sheet

struct AddCardSheet: View {
    let onSave: (UserGuideCard) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var cardTitle = ""
    @State private var cardBody = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Yeni Kart")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button("İptal") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider().opacity(0.12)

            VStack(alignment: .leading, spacing: 16) {
                cardSheetLabel("Kart Başlığı")
                TextField("Kolesterol, B12, mTOR…", text: $cardTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                            )
                    )

                cardSheetLabel("İçerik")
                TextEditor(text: $cardBody)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 200)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                            )
                    )
            }
            .padding(24)

            Spacer()

            Divider().opacity(0.12)

            Button {
                let card = UserGuideCard(cardTitle: cardTitle, body: cardBody)
                onSave(card)
                dismiss()
            } label: {
                Text("Kaydet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(cardTitle.isEmpty ? Color.white.opacity(0.06) : Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .disabled(cardTitle.isEmpty)
            .padding(24)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .frame(minWidth: 460, minHeight: 480)
    }

    private func cardSheetLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

// MARK: - Add Table Sheet

struct AddTableSheet: View {
    let onSave: (UserGuideCard) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var tableTitle = ""
    @State private var headers: [String] = ["", ""]
    @State private var rows: [[String]] = [["", ""]]

    var colCount: Int { headers.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Yeni Tablo")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button("İptal") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider().opacity(0.12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Title
                    tableSheetLabel("Tablo Başlığı")
                    styledTF("Vitamin Tablosu…", text: $tableTitle)

                    // Column headers
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            tableSheetLabel("Sütunlar")
                            Spacer()
                            HStack(spacing: 8) {
                                Button {
                                    if headers.count > 1 {
                                        headers.removeLast()
                                        rows = rows.map { row in
                                            var r = row
                                            if r.count > headers.count { r.removeLast() }
                                            return r
                                        }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.white.opacity(headers.count > 1 ? 0.5 : 0.2))
                                }
                                .buttonStyle(.plain)
                                .disabled(headers.count <= 1)

                                Button {
                                    headers.append("")
                                    rows = rows.map { $0 + [""] }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.system(size: 18))
                        }

                        HStack(spacing: 8) {
                            ForEach(headers.indices, id: \.self) { i in
                                TextField("Başlık \(i + 1)", text: $headers[i])
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                                            )
                                    )
                            }
                        }
                    }

                    // Rows
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            tableSheetLabel("Satırlar")
                            Spacer()
                            HStack(spacing: 8) {
                                Button {
                                    if rows.count > 1 { rows.removeLast() }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.white.opacity(rows.count > 1 ? 0.5 : 0.2))
                                }
                                .buttonStyle(.plain)
                                .disabled(rows.count <= 1)

                                Button {
                                    rows.append(Array(repeating: "", count: colCount))
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.system(size: 18))
                        }

                        VStack(spacing: 6) {
                            ForEach(rows.indices, id: \.self) { ri in
                                HStack(spacing: 8) {
                                    Text("\(ri + 1)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.25))
                                        .frame(width: 18)

                                    ForEach(rows[ri].indices, id: \.self) { ci in
                                        TextField(headers[ci].isEmpty ? "Hücre" : headers[ci], text: $rows[ri][ci])
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .frame(maxWidth: .infinity)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color.white.opacity(0.05))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                                                    )
                                            )
                                    }
                                }
                            }
                        }
                    }

                    // Preview
                    if !headers.filter({ !$0.isEmpty }).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            tableSheetLabel("Önizleme")
                            tablePreview
                        }
                    }
                }
                .padding(24)
            }

            Divider().opacity(0.12)

            Button {
                let card = UserGuideCard(cardTitle: tableTitle)
                card.isTable = true
                card.headers = headers
                card.rows = rows
                onSave(card)
                dismiss()
            } label: {
                Text("Kaydet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(tableTitle.isEmpty ? Color.white.opacity(0.06) : Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .disabled(tableTitle.isEmpty)
            .padding(24)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .frame(minWidth: 520, minHeight: 580)
    }

    private var tablePreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(headers.indices, id: \.self) { i in
                    Text(headers[i].isEmpty ? "—" : headers[i])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
            .background(Color.white.opacity(0.055))

            ForEach(rows.indices, id: \.self) { ri in
                Divider().opacity(0.08)
                HStack(spacing: 0) {
                    ForEach(rows[ri].indices, id: \.self) { ci in
                        Text(rows[ri][ci].isEmpty ? "—" : rows[ri][ci])
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                }
                .background(ri % 2 == 1 ? Color.white.opacity(0.02) : Color.clear)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
        )
    }

    private func tableSheetLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func styledTF(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 14.5))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                    )
            )
    }
}

// MARK: - Edit Table Sheet

struct EditTableSheet: View {
    @Bindable var card: UserGuideCard
    @Environment(\.dismiss) private var dismiss

    @State private var headers: [String] = []
    @State private var rows: [[String]] = []

    var colCount: Int { headers.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tabloyu Düzenle")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button("Tamam") {
                    card.headers = headers
                    card.rows = rows
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider().opacity(0.12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    editSheetLabel("Tablo Başlığı")
                    TextField("Başlık…", text: $card.cardTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                                )
                        )

                    // Columns
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            editSheetLabel("Sütunlar")
                            Spacer()
                            HStack(spacing: 8) {
                                Button {
                                    if headers.count > 1 {
                                        headers.removeLast()
                                        rows = rows.map { row in
                                            var r = row
                                            if r.count > headers.count { r.removeLast() }
                                            return r
                                        }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.white.opacity(headers.count > 1 ? 0.5 : 0.2))
                                }
                                .buttonStyle(.plain)
                                .disabled(headers.count <= 1)

                                Button {
                                    headers.append("")
                                    rows = rows.map { $0 + [""] }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.system(size: 18))
                        }

                        HStack(spacing: 8) {
                            ForEach(headers.indices, id: \.self) { i in
                                TextField("Başlık \(i + 1)", text: $headers[i])
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                                            )
                                    )
                            }
                        }
                    }

                    // Rows
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            editSheetLabel("Satırlar")
                            Spacer()
                            HStack(spacing: 8) {
                                Button {
                                    if rows.count > 1 { rows.removeLast() }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.white.opacity(rows.count > 1 ? 0.5 : 0.2))
                                }
                                .buttonStyle(.plain)
                                .disabled(rows.count <= 1)

                                Button {
                                    rows.append(Array(repeating: "", count: colCount))
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.system(size: 18))
                        }

                        VStack(spacing: 6) {
                            ForEach(rows.indices, id: \.self) { ri in
                                HStack(spacing: 8) {
                                    Text("\(ri + 1)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.25))
                                        .frame(width: 18)

                                    ForEach(rows[ri].indices, id: \.self) { ci in
                                        TextField(headers[safe: ci] ?? "Hücre", text: $rows[ri][ci])
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .frame(maxWidth: .infinity)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color.white.opacity(0.05))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                                                    )
                                            )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            Spacer()
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .frame(minWidth: 520, minHeight: 560)
        .onAppear {
            headers = card.headers
            rows = card.rows.isEmpty ? [Array(repeating: "", count: max(1, card.headers.count))] : card.rows
        }
    }

    private func editSheetLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

// MARK: - Edit Card Sheet

struct EditCardSheet: View {
    @Bindable var card: UserGuideCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kartı Düzenle")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button("Tamam") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider().opacity(0.12)

            VStack(alignment: .leading, spacing: 16) {
                editSheetLabel("Kart Başlığı")
                TextField("Başlık…", text: $card.cardTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                            )
                    )

                editSheetLabel("İçerik")
                TextEditor(text: $card.body)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 200)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                            )
                    )
            }
            .padding(24)

            Spacer()
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .frame(minWidth: 460, minHeight: 480)
    }

    private func editSheetLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

// MARK: - Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Color Helper

extension UserGuideSection {
    var swiftUIColor: Color {
        switch colorName {
        case "cyan":   return .cyan
        case "teal":   return .teal
        case "mint":   return .mint
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        case "pink":   return .pink
        case "purple": return .purple
        case "indigo": return .indigo
        case "yellow": return .yellow
        case "gray":   return .gray
        default:       return .blue
        }
    }
}
