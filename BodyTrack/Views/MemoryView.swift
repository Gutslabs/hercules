import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Profil ▸ Hafıza sekmesi

/// Hafıza — Profil'in üçüncü sekmesi (V1 dili). Sol: AI'ın senin hakkında
/// öğrendikleri (tek tip satırlar, eylemler satır içinde). Sağ: PubMed araştırma
/// kütüphanesi. Eski ayrı "Hafıza" sayfasının yerine geçer; mantık aynı.
struct ProfileMemoryPane: View {
    var compact: Bool

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
    @State private var embeddingPhase: EmbeddingStatus.Phase = .idle
    @State private var memoryPage = 0

    private static let memoriesPerPage = 10

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

    // MARK: Sayfalama (10'arlı)

    private var memoryPageCount: Int {
        max(1, (filteredMemories.count + Self.memoriesPerPage - 1) / Self.memoriesPerPage)
    }

    /// Aktif sayfa — filtre daralınca taşmasın diye clamp'li.
    private var clampedMemoryPage: Int {
        min(memoryPage, memoryPageCount - 1)
    }

    private var pagedMemories: [AgentMemory] {
        let start = clampedMemoryPage * Self.memoriesPerPage
        guard start < filteredMemories.count else { return [] }
        return Array(filteredMemories[start..<min(start + Self.memoriesPerPage, filteredMemories.count)])
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
        guard let researchLastUpdatedAt else { return "henüz güncellenmedi" }
        return Fmt.dateLong.string(from: researchLastUpdatedAt)
    }

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    memoriesCard
                    researchCard
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.lg) {
                    memoriesCard
                        .frame(maxWidth: .infinity)
                    researchCard
                        .frame(width: 560)
                }
            }
        }
        .onAppear {
            reload()
            embeddingPhase = EmbeddingStatus.shared.phase
        }
        .task { await updateResearchIfNeeded() }
        // Embedding modelini (gerekiyorsa) indir/yükle ve eksik kayıtları backfill et.
        // .task → ekrandan çıkınca otomatik iptal (warmUpEmbeddingsAndBackfill in-flight guard'a sahip).
        .task { await MemoryManager.shared.warmUpEmbeddingsAndBackfill() }
        .onReceive(NotificationCenter.default.publisher(for: .localMemoryChanged)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .embeddingStatusChanged)) { _ in
            embeddingPhase = EmbeddingStatus.shared.phase
        }
        .sheet(isPresented: $showingEditor) {
            memoryEditor
                .frame(width: 520)
        }
    }

    // MARK: Hakkında öğrendiklerim

    private var memoriesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Hakkında Öğrendiklerim").eyebrow()
                Text("\(memories.count) kayıt · \(pinnedCount) pinli · \(autoCount) otomatik")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.md)
                Button {
                    openNewMemory()
                } label: {
                    Text("+ Yeni")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Elle yeni hafıza kaydı ekle")
            }

            searchRow
                .padding(.top, 12)

            if filteredMemories.isEmpty {
                Text(searchText.isEmpty ? "Henüz hafıza kaydı yok — sohbet ettikçe otomatik birikir." : "Eşleşme yok.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(pagedMemories.enumerated()), id: \.element.id) { idx, memory in
                        if idx > 0 { Hairline() }
                        memoryRow(memory)
                    }
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 12)

            Hairline()
            HStack(alignment: .center, spacing: 12) {
                Text("Otomatik kayıtlar sohbetten çıkarılır; pinlediklerin konsolidasyonda asla silinmez.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: Spacing.md)
                if memoryPageCount > 1 {
                    memoryPager
                }
            }
            .padding(.top, 11)
        }
        .padding(.init(top: 20, leading: 26, bottom: 16, trailing: 26))
        .dashboardCard()
        .onChange(of: searchText) { _, _ in memoryPage = 0 }
    }

    /// 10'arlı sayfa gezgini — ‹ 1 / 3 › + aralık.
    private var memoryPager: some View {
        HStack(spacing: 8) {
            Text(pageRangeText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.textQuaternary)
            Button {
                memoryPage = max(0, clampedMemoryPage - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(clampedMemoryPage == 0 ? Palette.textQuaternary : Palette.textSecondary)
                    .frame(width: 22, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(clampedMemoryPage == 0)

            Text("\(clampedMemoryPage + 1) / \(memoryPageCount)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)

            Button {
                memoryPage = min(memoryPageCount - 1, clampedMemoryPage + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(clampedMemoryPage >= memoryPageCount - 1 ? Palette.textQuaternary : Palette.textSecondary)
                    .frame(width: 22, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(clampedMemoryPage >= memoryPageCount - 1)
        }
    }

    private var pageRangeText: String {
        let start = clampedMemoryPage * Self.memoriesPerPage + 1
        let end = min((clampedMemoryPage + 1) * Self.memoriesPerPage, filteredMemories.count)
        return "\(start)–\(end) · \(filteredMemories.count)"
    }

    private var searchRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
            TextField("Ara", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textPrimary)
            Text(embeddingStatusText)
                .font(.system(size: 10.5))
                .foregroundStyle(embeddingStatusTint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    private var embeddingStatusText: String {
        switch embeddingPhase {
        case .idle:
            return ""
        case .downloading(let fraction):
            return "Embedding modeli indiriliyor · %\(Int((fraction * 100).rounded()))"
        case .backfilling(let done, let total):
            return "Semantik indeksleniyor · \(done)/\(total)"
        case .ready:
            return "Semantic arama aktif · Qwen3-Embedding (on-device)"
        case .unavailable:
            return "Embedding yüklenemedi · lexical arama"
        }
    }

    private var embeddingStatusTint: Color {
        switch embeddingPhase {
        case .unavailable: return Palette.negative
        default: return Palette.textTertiary
        }
    }

    /// V1 hafıza satırı: kaynak chip'i · içerik + etiket/conf · tarih + sakin eylemler.
    private func memoryRow(_ memory: AgentMemory) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(memory.source)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(memory.source.hasPrefix("llm-add") ? Palette.macroCarbs : Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .frame(width: 78)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.track))

            VStack(alignment: .leading, spacing: 4) {
                Text(memory.content)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if memory.type != .other {
                        Text(memory.type.label.lowercased(with: Locale(identifier: "tr_TR")))
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.accent.opacity(0.85))
                    }
                    ForEach(memory.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.accent.opacity(0.85))
                    }
                    Text("conf \(Fmt.num(memory.confidence, digits: 2))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.textQuaternary)
                    if memory.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Palette.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 12) {
                Text(Fmt.date.string(from: memory.updatedAt))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                Button {
                    LocalMemoryProvider.shared.setPinned(id: memory.id, pinned: !memory.pinned)
                    reload()
                } label: {
                    Image(systemName: memory.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(memory.pinned ? Palette.accent : Palette.textQuaternary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(memory.pinned ? "Pin kaldır" : "Pinle")

                Button {
                    openEdit(memory)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textQuaternary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Düzenle")

                Button {
                    LocalMemoryProvider.shared.deleteMemory(id: memory.id)
                    reload()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textQuaternary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Sil")
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 11)
    }

    // MARK: Research kütüphanesi

    private var researchCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    researchTitleBlock
                    Spacer(minLength: Spacing.md)
                    researchWindowSwitch
                    researchUpdateButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    researchTitleBlock
                    HStack(spacing: 10) {
                        researchWindowSwitch
                        researchUpdateButton
                    }
                }
            }

            Text(researchMessage ?? researchWindow.summary)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if filteredResearchPapers.isEmpty {
                Text(searchText.isEmpty ? "Henüz research cache yok — Güncelle ile PubMed'den çek." : "Research eşleşmesi yok.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filteredResearchPapers.prefix(8).enumerated()), id: \.element.id) { idx, paper in
                        if idx > 0 { Hairline() }
                        researchRow(paper)
                    }
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 12)

            Hairline()
            Text("AI cevap verirken bu kütüphaneden PMID'leriyle alıntı yapar.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, 11)
        }
        .padding(.init(top: 20, leading: 26, bottom: 16, trailing: 26))
        .dashboardCard()
    }

    private var researchTitleBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Bodybuilding Research").eyebrow()
            Text("\(researchPapers.count) PubMed kaydı · \(researchLastUpdatedText)")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var researchWindowSwitch: some View {
        HStack(spacing: 2) {
            ForEach(ResearchWindow.allCases) { window in
                Button {
                    researchWindow = window
                } label: {
                    Text(window.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(researchWindow == window ? Palette.btnFg : Palette.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(researchWindow == window ? Palette.btnBg : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(researchUpdating)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .help("Research tarih aralığı")
    }

    private var researchUpdateButton: some View {
        Button {
            Task { await updateResearch() }
        } label: {
            HStack(spacing: 6) {
                if researchUpdating {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 10, height: 10)
                }
                Text(researchUpdating ? "Çekiliyor" : "Güncelle")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(researchUpdating ? Palette.textTertiary : Palette.btnFg)
            .padding(.horizontal, 13)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(researchUpdating ? Palette.fieldFill : Palette.accent)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(researchUpdating)
        .help("PubMed'den güncel makaleleri çek")
    }

    private func researchRow(_ paper: ResearchPaper) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(paper.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(paper.journal) · \(paper.pubDate) · PMID \(paper.pmid)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let topic = paper.topicLabels.first {
                Text(paper.topicLabels.count > 1 ? "\(topic) +\(paper.topicLabels.count - 1)" : topic)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.macroCarbs)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Palette.macroCarbs.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Palette.macroCarbs.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.top, 1)
            }

            HStack(spacing: 10) {
                Button {
                    ResearchLibrary.shared.setPinned(id: paper.id, pinned: !paper.pinned)
                    reload()
                } label: {
                    Image(systemName: paper.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(paper.pinned ? Palette.accent : Palette.textQuaternary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(paper.pinned ? "Pin kaldır" : "Pinle")

                if let url = URL(string: paper.sourceURL) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.textQuaternary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("PubMed")
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 10.5)
    }

    // MARK: Editör sheet'i

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

    // MARK: Actions

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
        researchUpdating = true
        defer { researchUpdating = false }
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

// MARK: - Profil ▸ Promptlar sekmesi

/// Promptlar — Profil'in ikinci sekmesi (V1 dili). Sol: 4 prompt tek listede
/// (2 grup). Sağ: seçili promptun editörü. Override'lar `PromptStore`'da
/// (UserDefaults); "Varsayılana dön" fabrika metnini geri yükler.
struct ProfilePromptsPane: View {
    var compact: Bool

    private let store = PromptStore.shared
    @State private var selected: PromptKey = .chatSystem
    @State private var draft: String = ""
    @State private var showResetConfirm = false
    @State private var savedFlash = false

    private var groups: [(String, [PromptKey])] {
        var order: [String] = []
        var map: [String: [PromptKey]] = [:]
        for key in PromptKey.allCases {
            if map[key.group] == nil { order.append(key.group); map[key.group] = [] }
            map[key.group]?.append(key)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private var isDirty: Bool { draft != store.text(selected) }
    private var differsFromDefault: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
            != selected.defaultText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var editStateText: String {
        if isDirty { return "kaydedilmemiş değişiklik" }
        return store.isOverridden(selected) ? "düzenlenmiş · varsayılandan farklı" : "varsayılan metin"
    }

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    listCard
                    editorCard
                        .frame(maxHeight: .infinity)
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.lg) {
                    listCard
                        .frame(width: 320)
                        .frame(maxHeight: .infinity)
                    editorCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { draft = store.text(selected) }
        .onChange(of: selected) { _, newKey in draft = store.text(newKey) }
    }

    // MARK: Prompt listesi

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Promptlar").eyebrow()
                Spacer(minLength: Spacing.md)
                Text("\(PromptKey.allCases.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
            }
            Text("Düzenle, kaydet; istediğinde varsayılana dön.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, 4)

            ForEach(groups, id: \.0) { group, keys in
                Text(group.uppercased(with: Locale(identifier: "tr_TR")))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Palette.textQuaternary)
                    .padding(.top, 16)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(keys) { key in listRow(key) }
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 16)

            Hairline()
            Text("Promptlar yedeklemeye dahildir; \"Varsayılana dön\" orijinal metni geri yükler.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .padding(.init(top: 20, leading: 22, bottom: 16, trailing: 22))
        .frame(maxHeight: .infinity, alignment: .top)   // geniş yerleşimde editörle aynı boy
        .dashboardCard()
    }

    private func listRow(_ key: PromptKey) -> some View {
        let active = key == selected
        return Button { selected = key } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(active ? Palette.accent : Palette.textQuaternary)
                    .frame(width: 5, height: 5)
                Text(key.title)
                    .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Fmt.int(Double(store.text(key).count)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? Palette.accent.opacity(0.07) : Palette.fieldFill.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(active ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Editör

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(selected.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text(selected.locationNote)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Spacing.md)
                Text("\(Fmt.int(Double(draft.count))) karakter")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
            }

            if let note = selected.dynamicNote {
                HStack(spacing: 9) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.warning)
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.warning.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.warning.opacity(0.3), lineWidth: 1))
                .padding(.top, 12)
            }

            // Sabit kutu: metin uzadıkça sayfa değil editörün kendisi kayar.
            TextEditor(text: $draft)
                .scrollContentBackground(.hidden)
                .font(.system(size: 11.5, design: .monospaced))
                .lineSpacing(5)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                .padding(.top, 14)

            HStack(spacing: 10) {
                Button { save() } label: {
                    Text(savedFlash ? "Kaydedildi" : "Kaydet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isDirty || savedFlash ? Palette.btnFg : Palette.textTertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isDirty ? Palette.accent : (savedFlash ? Palette.positive.opacity(0.5) : Palette.fieldFill))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isDirty)

                promptGhostButton("Kopyala") { copyDraft() }

                Button { showResetConfirm = true } label: {
                    Text("Varsayılana dön")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(differsFromDefault ? Palette.textSecondary : Palette.textQuaternary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5.5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!store.isOverridden(selected) && !differsFromDefault)
                .confirmationDialog("Varsayılana dönülsün mü?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                    Button("Varsayılana dön", role: .destructive) { resetToDefault() }
                    Button("İptal", role: .cancel) {}
                } message: {
                    Text("Bu prompttaki değişikliklerin silinir, fabrika metni geri gelir.")
                }

                Spacer(minLength: 0)

                Text(editStateText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isDirty ? Palette.warning : Palette.textQuaternary)
            }
            .padding(.top, 14)
        }
        .padding(.init(top: 22, leading: 28, bottom: 18, trailing: 28))
        .dashboardCard()
    }

    private func promptGhostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 5.5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func save() {
        store.setOverride(selected, draft)
        draft = store.text(selected)
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { savedFlash = false }
    }

    private func resetToDefault() {
        store.resetToDefault(selected)
        draft = selected.defaultText
    }

    private func copyDraft() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft, forType: .string)
        #endif
    }
}
