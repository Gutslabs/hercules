import SwiftUI

struct MemoryView: View {
    @State private var memories: [AgentMemory] = []
    @State private var searchText = ""
    @State private var editingMemory: AgentMemory?
    @State private var showingEditor = false
    @State private var draftContent = ""
    @State private var draftTags = ""
    @State private var draftPinned = true
    @State private var researchPapers: [ResearchPaper] = []
    @State private var researchLastUpdatedAt: Date?
    @State private var researchUpdating = false
    @State private var researchMessage: String?
    @State private var researchWindow: ResearchWindow = .current

    private var filteredMemories: [AgentMemory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return memories }
        let folded = fold(query)
        return memories.filter { memory in
            fold(memory.content).contains(folded)
                || memory.tags.contains { fold($0).contains(folded) }
                || fold(memory.source).contains(folded)
        }
    }

    private var pinnedCount: Int {
        memories.filter(\.pinned).count
    }

    private var autoCount: Int {
        memories.filter { !$0.source.hasPrefix("manual") && $0.source != "explicit" }.count
    }

    private var filteredResearchPapers: [ResearchPaper] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return researchPapers }
        let folded = fold(query)
        return researchPapers.filter { paper in
            fold(paper.title).contains(folded)
                || fold(paper.journal).contains(folded)
                || fold(paper.pubDate).contains(folded)
                || paper.topicLabels.contains { fold($0).contains(folded) }
                || paper.topicIDs.contains { fold($0).contains(folded) }
        }
    }

    private var researchLastUpdatedText: String {
        guard let researchLastUpdatedAt else { return "Henüz güncellenmedi" }
        return Fmt.dateLong.string(from: researchLastUpdatedAt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                controls
                researchPanel
                memoryGrid
            }
            .padding(Spacing.xxl)
        }
        .background(Palette.background.ignoresSafeArea())
        .onAppear {
            reload()
            Task { await updateResearchIfNeeded() }
        }
        .sheet(isPresented: $showingEditor) {
            memoryEditor
                .frame(width: 520)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Palette.accent.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "brain")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory")
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(memories.count) kayıt · \(pinnedCount) pinli · \(autoCount) otomatik")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Button {
                    openNewMemory()
                } label: {
                    Label("Yeni", systemImage: "plus")
                        .font(Typography.bodyBold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.accent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                TextField("Ara", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))
            Spacer(minLength: 0)
            Button {
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.surfaceElevated))
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Yenile")
        }
    }

    @ViewBuilder
    private var memoryGrid: some View {
        if filteredMemories.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(filteredMemories) { memory in
                    memoryCard(memory)
                }
            }
        }
    }

    private var researchPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Palette.macroCarbs.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.macroCarbs)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Bodybuilding Research")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(researchWindow.title) · \(researchPapers.count) PubMed kaydı · \(researchLastUpdatedText)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }

                Spacer()

                Picker("", selection: $researchWindow) {
                    ForEach(ResearchWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 188)
                .disabled(researchUpdating)
                .help("Research tarih aralığı")

                Button {
                    Task { await updateResearch() }
                } label: {
                    HStack(spacing: 7) {
                        if researchUpdating {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(researchUpdating ? "Çekiliyor" : "Güncelle")
                            .font(Typography.bodyBold)
                    }
                    .foregroundStyle(researchUpdating ? Palette.textTertiary : .black)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: Radius.sm).fill(researchUpdating ? Palette.surfaceElevated : Palette.accent))
                }
                .buttonStyle(.plain)
                .disabled(researchUpdating)
                .help("PubMed'den güncel makaleleri çek")
            }

            Text(researchMessage ?? researchWindow.summary)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)

            if filteredResearchPapers.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                    Text(searchText.isEmpty ? "Henüz research cache yok" : "Research eşleşmesi yok")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredResearchPapers.prefix(6).enumerated()), id: \.element.id) { idx, paper in
                        researchRow(paper)
                        if idx < min(filteredResearchPapers.count, 6) - 1 {
                            Divider()
                                .overlay(Palette.border)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))
            }
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func researchRow(_ paper: ResearchPaper) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 7) {
                Text(paper.title)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)

                Text("\(paper.journal) · \(paper.pubDate) · PMID \(paper.pmid)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)

                if !paper.topicLabels.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(paper.topicLabels, id: \.self) { topic in
                            Text(topic)
                                .font(Typography.captionBold)
                                .foregroundStyle(Palette.macroCarbs)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Palette.macroCarbs.opacity(0.12)))
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                ResearchLibrary.shared.setPinned(id: paper.id, pinned: !paper.pinned)
                reload()
            } label: {
                Image(systemName: paper.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(paper.pinned ? Palette.accent : Palette.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(paper.pinned ? "Pin kaldır" : "Pinle")

            if let url = URL(string: paper.sourceURL) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("PubMed")
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text(searchText.isEmpty ? "Henüz memory yok" : "Eşleşme yok")
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func memoryCard(_ memory: AgentMemory) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: 8) {
                sourceBadge(memory)
                Spacer()
                Button {
                    LocalMemoryProvider.shared.setPinned(id: memory.id, pinned: !memory.pinned)
                    reload()
                } label: {
                    Image(systemName: memory.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(memory.pinned ? Palette.accent : Palette.textTertiary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help(memory.pinned ? "Pin kaldır" : "Pinle")

                Button {
                    openEdit(memory)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Düzenle")

                Button {
                    LocalMemoryProvider.shared.deleteMemory(id: memory.id)
                    reload()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.negative)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Sil")
            }

            Text(memory.content)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !memory.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(memory.tags, id: \.self) { tag in
                        Text(tag)
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.accent.opacity(0.12)))
                    }
                }
            }

            HStack {
                Text("conf \(Fmt.num(memory.confidence, digits: 2))")
                Text("·")
                Text(Fmt.dateLong.string(from: memory.updatedAt))
                Spacer(minLength: 0)
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.textQuaternary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func sourceBadge(_ memory: AgentMemory) -> some View {
        let icon: String = {
            if memory.source == "explicit" { return "quote.bubble" }
            if memory.source.hasPrefix("manual") { return "hand.point.up.left" }
            return "sparkles"
        }()
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(memory.source)
                .font(Typography.captionBold)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Palette.surfaceElevated))
    }

    private var memoryEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text(editingMemory == nil ? "Yeni Memory" : "Memory Düzenle")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    showingEditor = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Palette.surfaceElevated))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("İçerik").eyebrow()
                TextEditor(text: $draftContent)
                    .scrollContentBackground(.hidden)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(minHeight: 130)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Etiketler").eyebrow()
                TextField("nutrition, training, preference", text: $draftTags)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surfaceElevated))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))
            }

            Toggle("Pinli", isOn: $draftPinned)
                .toggleStyle(.switch)
                .font(Typography.bodyBold)

            HStack {
                Spacer()
                Button {
                    saveDraft()
                } label: {
                    Label("Kaydet", systemImage: "checkmark")
                        .font(Typography.bodyBold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.accent))
                }
                .buttonStyle(.plain)
                .disabled(draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .background(Palette.background)
    }

    private func reload() {
        memories = LocalMemoryProvider.shared.allMemories()
        researchPapers = ResearchLibrary.shared.allPapers()
        researchLastUpdatedAt = ResearchLibrary.shared.lastUpdatedAt
    }

    @MainActor
    private func updateResearch() async {
        guard !researchUpdating else { return }
        researchUpdating = true
        researchMessage = "\(researchWindow.title) PubMed taranıyor..."
        let summary = await ResearchLibrary.shared.updateNow(fromYear: researchWindow.startYear)
        reload()
        researchMessage = summary.statusText
        researchUpdating = false
    }

    @MainActor
    private func updateResearchIfNeeded() async {
        guard ResearchLibrary.shared.needsRefresh(), !researchUpdating else { return }
        researchMessage = "Research cache eski, PubMed taranıyor..."
        let summary = await ResearchLibrary.shared.updateNow(fromYear: ResearchWindow.current.startYear)
        reload()
        researchMessage = summary.statusText
    }

    private func openNewMemory() {
        editingMemory = nil
        draftContent = ""
        draftTags = ""
        draftPinned = true
        showingEditor = true
    }

    private func openEdit(_ memory: AgentMemory) {
        editingMemory = memory
        draftContent = memory.content
        draftTags = memory.tags.joined(separator: ", ")
        draftPinned = memory.pinned
        showingEditor = true
    }

    private func saveDraft() {
        let tags = draftTags.split(separator: ",").map { String($0) }
        if let editingMemory {
            LocalMemoryProvider.shared.updateMemory(id: editingMemory.id, content: draftContent, tags: tags)
            LocalMemoryProvider.shared.setPinned(id: editingMemory.id, pinned: draftPinned)
        } else {
            _ = LocalMemoryProvider.shared.addManualMemory(content: draftContent, tags: tags, pinned: draftPinned)
        }
        reload()
        showingEditor = false
    }

    private func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
    }
}

private struct FlowLayout<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: Content

    var body: some View {
        WrappingHStack(spacing: spacing) {
            content
        }
    }
}

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        guard maxWidth > 0 else {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(
                width: sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1)),
                height: sizes.map(\.height).max() ?? 0
            )
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
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
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
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
