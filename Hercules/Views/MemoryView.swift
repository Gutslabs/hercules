import SwiftUI
import LucideKit
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

// MARK: - Profil ▸ Hafıza sekmesi

/// Hafıza — Profil'in üçüncü sekmesi (V1 dili). Sol: AI'ın senin hakkında
/// öğrendikleri (tek tip satırlar, eylemler satır içinde). Sağ: PubMed araştırma
/// kütüphanesi. Eski ayrı "Hafıza" sayfasının yerine geçer; mantık aynı.
struct ProfileMemoryPane: View {
    var compact: Bool

    @State private var memories: [AgentMemory] = []
    @State private var filteredMemories: [AgentMemory] = []
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
    @State private var memoryStorageIssue: String?
    @State private var memoryStorageAllowsMutation = true
    @State private var memoryCanExportArchive = true
    @State private var memoryPage = 0
    @State private var memoryArchiveSheet: MemoryArchiveSheet?
    @State private var memoryArchiveBusy = false
    @State private var memoryArchiveError: String?
    @State private var memoryArchiveBanner: MemoryArchiveBanner?
    @State private var pendingMemoryRestore: HerculesMemoryArchive.DecodedArchive?
    @State private var confirmingMemoryRestore = false
    @State private var confirmingVaultReset = false

    private static let memoriesPerPage = 10

    /// Filtre gövde başına EN AZ 6 kez okunuyordu (sayfa sayısı, clamp, sayfa dilimi,
    /// sayaç metni…) ve her okuma tüm kayıtları yeniden Unicode-fold ediyordu — yani
    /// her tuş vuruşunda corpus × 6 ICU geçişi. Sonuç artık arama metni/kayıtlar
    /// değişince bir kez hesaplanıp saklanıyor.
    private struct MemoryFilterKey: Equatable {
        var query: String
        var count: Int
        var newestStamp: Date?
    }

    private var memoryFilterKey: MemoryFilterKey {
        MemoryFilterKey(
            query: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            count: memories.count,
            newestStamp: memories.map(\.updatedAt).max()
        )
    }

    private func recomputeFilteredMemories() {
        let query = memoryFilterKey.query
        guard !query.isEmpty else { filteredMemories = memories; return }
        let folded = fold(query)
        filteredMemories = memories.filter { memory in
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
                // Düz zemin: kart kabukları kalktı, bölümler ince çizgiyle ayrışır.
                VStack(alignment: .leading, spacing: 26) {
                    memoriesCard
                    Hairline()
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
        // Filtre yalnız sorgu/kayıtlar değişince — gövde başına 6 kez değil.
        .task(id: memoryFilterKey) { recomputeFilteredMemories() }
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
        }
        #if os(macOS)
        .sheet(item: $memoryArchiveSheet) { mode in
            MemoryArchivePassphraseSheet(
                isExport: mode.requiresConfirmation,
                fileName: mode.fileName,
                busy: memoryArchiveBusy,
                error: memoryArchiveError,
                onSubmit: { passphrase in
                    switch mode {
                    case .export(let url):
                        exportMemoryArchive(to: url, passphrase: passphrase)
                    case .import(let url):
                        openMemoryArchive(at: url, passphrase: passphrase)
                    }
                },
                onCancel: {
                    guard !memoryArchiveBusy else { return }
                    memoryArchiveSheet = nil
                    memoryArchiveError = nil
                }
            )
        }
        .confirmationDialog(
            "Hafıza yedeğini geri yükle",
            isPresented: $confirmingMemoryRestore,
            titleVisibility: .visible
        ) {
            Button("Tüm hafızayı değiştir", role: .destructive) {
                applyPendingMemoryRestore()
            }
            Button("Vazgeç", role: .cancel) {
                pendingMemoryRestore = nil
            }
        } message: {
            if let archive = pendingMemoryRestore {
                Text(
                    "\(Self.archiveDateText(archive.exportedAt)) tarihli yedek "
                    + "(\(archive.records.count) kayıt, geçersiz kılınmış geçmiş dahil) "
                    + "mevcut HERCULES hafızasının tamamının yerini alacak. "
                    + "Bu işlem geri alınamaz."
                )
            }
        }
        .confirmationDialog(
            "Kasayı sıfırla",
            isPresented: $confirmingVaultReset,
            titleVisibility: .visible
        ) {
            Button("Sıfırla ve yeni kasa aç", role: .destructive) {
                resetLockedMemoryVault()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(
                "Cihaz anahtarı olmadan mevcut kasa şifresi çözülemez; içerik "
                + "okunamaz durumda kalır. Dosya SİLİNMEZ — zaman damgalı bir "
                + "kopyaya taşınır ve hafıza boş bir kasayla yeniden çalışmaya başlar."
            )
        }
        #endif
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
                .disabled(!memoryStorageAllowsMutation)
                .help("Elle yeni hafıza kaydı ekle")
            }

            searchRow
                .padding(.top, 12)
            if let memoryStorageIssue {
                Text(memoryStorageIssue)
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        memoryStorageAllowsMutation ? Palette.warning : Palette.negative
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            #if os(macOS)
            memoryArchiveControls
                .padding(.top, 9)
            #endif

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
                Lucide(sf: "chevron.left", size: 9)
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
                Lucide(sf: "chevron.right", size: 9)
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
            Lucide(sf: "magnifyingglass", size: 11)
                .foregroundStyle(Palette.textTertiary)
            TextField("Ara", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textPrimary)
            Text(memoryStorageStatusText)
                .font(.system(size: 10.5))
                .foregroundStyle(embeddingStatusTint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    #if os(macOS)
    private var memoryArchiveControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Lucide(sf: "lock.shield", size: 11)
                    .foregroundStyle(Palette.textTertiary)
                Text("Cihaz kaybına karşı parola korumalı, taşınabilir hafıza yedeği.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                archiveButton("Yedekle", systemImage: "square.and.arrow.up") {
                    chooseMemoryArchiveDestination()
                }
                .disabled(!memoryCanExportArchive || memoryArchiveBusy)
                archiveButton("Geri yükle", systemImage: "square.and.arrow.down") {
                    chooseMemoryArchiveSource()
                }
                .disabled(memoryArchiveBusy)
                // Kilitli kasa kalıcı bir çıkmaz: anahtar yoksa zarf açılamaz.
                // Tek çıkış ya yedekten geri yükleme ya da kasayı sıfırlama.
                if !memoryStorageAllowsMutation {
                    archiveButton("Kasayı sıfırla", systemImage: "arrow.counterclockwise") {
                        confirmingVaultReset = true
                    }
                    .disabled(memoryArchiveBusy)
                    .help("Açılamayan kasa dosyasını kenarda saklar ve çalışan yeni bir kasa açar. Dosya silinmez.")
                }
            }

            if let banner = memoryArchiveBanner {
                HStack(spacing: 6) {
                    Lucide(
                        sf: banner.succeeded ? "checkmark.seal" : "exclamationmark.triangle",
                        size: 10
                    )
                    Text(banner.message)
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(banner.succeeded ? Palette.positive : Palette.negative)
            }
        }
    }

    private func archiveButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Lucide(sf: systemImage, size: 9)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    #endif

    private var embeddingStatusText: String {
        switch embeddingPhase {
        case .idle:
            return ""
        case .downloading(let fraction):
            return "Embedding modeli indiriliyor · %\(Int((fraction * 100).rounded()))"
        case .backfilling(let done, let total):
            return "Semantik indeksleniyor · \(done)/\(total)"
        case .ready:
            return "Semantic arama aktif · Multilingual E5 Small (on-device)"
        case .unavailable:
            return "Embedding yüklenemedi · lexical arama"
        }
    }

    private var memoryStorageStatusText: String {
        guard memoryStorageIssue != nil else { return embeddingStatusText }
        return memoryStorageAllowsMutation ? "Hafıza depolama uyarısı" : "Hafıza kasası kilitli"
    }

    private var embeddingStatusTint: Color {
        if memoryStorageIssue != nil {
            return memoryStorageAllowsMutation ? Palette.warning : Palette.negative
        }
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
                        Lucide(sf: "pin.fill", size: 8)
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
                    Lucide(sf: memory.pinned ? "pin.fill" : "pin", size: 10)
                        .foregroundStyle(memory.pinned ? Palette.accent : Palette.textQuaternary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(memory.pinned ? "Pin kaldır" : "Pinle")

                Button {
                    openEdit(memory)
                } label: {
                    Lucide(sf: "pencil", size: 10)
                        .foregroundStyle(Palette.textQuaternary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Düzenle")

                Button {
                    LocalMemoryProvider.shared.deleteMemory(id: memory.id)
                    reload()
                } label: {
                    Lucide(sf: "xmark", size: 10)
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
                    .fill(researchUpdating ? Palette.fieldFill : Palette.btnBg)
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
                    Lucide(sf: paper.pinned ? "pin.fill" : "pin", size: 10)
                        .foregroundStyle(paper.pinned ? Palette.accent : Palette.textQuaternary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(paper.pinned ? "Pin kaldır" : "Pinle")

                if let url = URL(string: paper.sourceURL) {
                    Link(destination: url) {
                        Lucide(sf: "arrow.up.right", size: 10)
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
        MemoryEditorSheet(
            isNew: editingMemory == nil,
            content: $draftContent,
            tags: $draftTags,
            pinned: $draftPinned,
            canSave: memoryStorageAllowsMutation
                && !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onSave: saveDraft,
            onCancel: { showingEditor = false }
        )
    }

    // MARK: Actions

    #if os(macOS)
    private func chooseMemoryArchiveDestination() {
        memoryArchiveBanner = nil
        memoryArchiveError = nil
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: HerculesMemoryArchive.fileExtension) ?? .data
        ]
        panel.nameFieldStringValue = Self.defaultMemoryArchiveFilename()
        panel.prompt = "Yedekle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        memoryArchiveSheet = .export(url)
    }

    private func chooseMemoryArchiveSource() {
        memoryArchiveBanner = nil
        memoryArchiveError = nil
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: HerculesMemoryArchive.fileExtension) ?? .data
        ]
        panel.prompt = "Aç"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        memoryArchiveSheet = .import(url)
    }

    private func exportMemoryArchive(to url: URL, passphrase: String) {
        let completeHistory = LocalMemoryProvider.shared.allMemories(includeInvalidated: true)
        memoryArchiveBusy = true
        memoryArchiveError = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try HerculesMemoryArchive.write(
                        records: completeHistory,
                        passphrase: passphrase,
                        to: url
                    )
                }.value
                await MainActor.run {
                    memoryArchiveBusy = false
                    memoryArchiveSheet = nil
                    memoryArchiveBanner = MemoryArchiveBanner(
                        succeeded: true,
                        message: "Şifreli hafıza yedeği kaydedildi · \(completeHistory.count) kayıt."
                    )
                }
            } catch {
                await MainActor.run {
                    memoryArchiveBusy = false
                    memoryArchiveError = Self.archiveErrorText(error)
                }
            }
        }
    }

    private func openMemoryArchive(at url: URL, passphrase: String) {
        memoryArchiveBusy = true
        memoryArchiveError = nil
        Task {
            do {
                let decoded = try await Task.detached(priority: .userInitiated) {
                    try HerculesMemoryArchive.read(from: url, passphrase: passphrase)
                }.value
                await MainActor.run {
                    memoryArchiveBusy = false
                    memoryArchiveSheet = nil
                    pendingMemoryRestore = decoded
                    confirmingMemoryRestore = true
                }
            } catch {
                await MainActor.run {
                    memoryArchiveBusy = false
                    memoryArchiveError = Self.archiveErrorText(error)
                }
            }
        }
    }

    /// Provider'ın durable replace API'sine bağlanır; doğrulanmış archive kayıtları
    /// bu noktaya gelene kadar mevcut hafızada hiçbir mutation yapılmaz.
    private func applyPendingMemoryRestore() {
        guard let archive = pendingMemoryRestore else { return }
        pendingMemoryRestore = nil
        memoryArchiveBusy = true
        memoryArchiveBanner = nil
        Task {
            do {
                let count = try await LocalMemoryProvider.shared
                    .replaceAllMemoriesDurably(with: archive.records)
                memoryArchiveBusy = false
                reload()
                memoryArchiveBanner = MemoryArchiveBanner(
                    succeeded: true,
                    message: "Hafıza geri yüklendi · \(count) kayıt mevcut hafızanın yerini aldı."
                )
            } catch {
                memoryArchiveBusy = false
                reload()
                memoryArchiveBanner = MemoryArchiveBanner(
                    succeeded: false,
                    message: "Geri yükleme tamamlanamadı: \(Self.archiveErrorText(error))"
                )
            }
        }
    }

    /// Kilitli kasadan çıkış: dosya kenara alınır, hafıza tekrar yazılabilir olur.
    private func resetLockedMemoryVault() {
        memoryArchiveBusy = true
        memoryArchiveBanner = nil
        Task {
            do {
                let archived = try await LocalMemoryProvider.shared.resetLockedVault()
                memoryArchiveBusy = false
                reload()
                memoryArchiveBanner = MemoryArchiveBanner(
                    succeeded: true,
                    message: archived.map {
                        "Kasa sıfırlandı · açılamayan dosya \($0.lastPathComponent) olarak saklandı."
                    } ?? "Kasa sıfırlandı."
                )
            } catch {
                memoryArchiveBusy = false
                reload()
                memoryArchiveBanner = MemoryArchiveBanner(
                    succeeded: false,
                    message: "Kasa sıfırlanamadı: \(Self.archiveErrorText(error))"
                )
            }
        }
    }

    private static func defaultMemoryArchiveFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "HERCULES-Hafiza-\(formatter.string(from: .now)).herculesmemory"
    }

    private static func archiveDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM yyyy · HH:mm"
        return formatter.string(from: date)
    }

    private static func archiveErrorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    #endif

    private func reload() {
        let provider = LocalMemoryProvider.shared
        memories = provider.allMemories()
        memoryStorageIssue = provider.storageIssue
        memoryStorageAllowsMutation = provider.storageAllowsMutation
        memoryCanExportArchive = provider.canExportPortableArchive
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

#if os(macOS)
private enum MemoryArchiveSheet: Identifiable {
    case export(URL)
    case `import`(URL)

    var id: String {
        switch self {
        case .export(let url): return "export:\(url.path)"
        case .import(let url): return "import:\(url.path)"
        }
    }

    var requiresConfirmation: Bool {
        if case .export = self { return true }
        return false
    }

    /// Uzantısız dosya adı (pencerenin alt satırı).
    var fileName: String {
        switch self {
        case .export(let url), .import(let url): return url.deletingPathExtension().lastPathComponent
        }
    }
}

private struct MemoryArchiveBanner {
    var succeeded: Bool
    var message: String
}

/// Hafıza yedeği parolası — tasarım: tuval ▸ Pencereler · İlerleme · Profil (az yazı). Yedeklerken
/// parola + güç çubuğu + tekrar (eşleşince ✓); açarken tek parola.
struct MemoryArchivePassphraseSheet: View {
    var isExport: Bool
    var fileName: String
    var busy: Bool
    var error: String?
    var onSubmit: (String) -> Void
    var onCancel: () -> Void

    @State private var passphrase = ""
    @State private var confirmation = ""

    private var mismatch: Bool {
        isExport && !confirmation.isEmpty && passphrase != confirmation
    }

    private var valid: Bool {
        passphrase.count >= 8 && (!isExport || passphrase == confirmation)
    }

    /// 0…4: uzunluk ve çeşitlilik (küçük/büyük harf, rakam, sembol).
    private var strength: Int {
        guard passphrase.count >= 8 else { return passphrase.isEmpty ? 0 : 1 }
        let kinds = [passphrase.contains(where: \.isLowercase), passphrase.contains(where: \.isUppercase),
                     passphrase.contains(where: \.isNumber),
                     passphrase.contains { !$0.isLetter && !$0.isNumber }].filter { $0 }.count
        var score = 2
        if passphrase.count >= 12 { score += 1 }
        if kinds >= 3 { score += 1 }
        return min(4, score)
    }

    var body: some View {
        SadeSheet(title: isExport ? "Yedeği şifrele" : "Yedeği aç", subtitle: fileName, onClose: onCancel) {
            VStack(alignment: .leading, spacing: 0) {
                SadeField(label: "Parola") {
                    SecureField("", text: $passphrase, prompt: Text("en az 8 karakter").foregroundStyle(Palette.textTertiary))
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                }
                if isExport {
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { i in
                            Capsule()
                                .fill(i < strength ? (strength >= 3 ? Palette.positive : Palette.warning) : Palette.textPrimary.opacity(0.08))
                                .frame(height: 4)
                        }
                    }
                    .padding(.top, 8)
                    .help("Parola gücü")
                    SadeField(label: "Tekrar") {
                        SecureField("", text: $confirmation)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                        if !confirmation.isEmpty && confirmation == passphrase {
                            Lucide(sf: "checkmark", size: 13)
                                .foregroundStyle(Palette.positive)
                        }
                    }
                    .padding(.top, 14)
                }
                Group {
                    if mismatch {
                        SadeNote(text: "Parolalar eşleşmiyor", color: Palette.negative)
                    } else if let error {
                        SadeNote(text: error, color: Palette.negative)
                    } else if isExport {
                        SadeNote(text: "Parola kaybolursa yedek açılamaz")
                    }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 24)
        } footerLeading: {
            EmptyView()
        } footerTrailing: {
            SadeButton(title: "Vazgeç", enabled: !busy, action: onCancel)
            if busy {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 90)
            } else {
                SadeButton(title: isExport ? "Şifrele" : "Yedeği aç", icon: isExport ? "lock" : nil, role: .primary, enabled: valid) {
                    let submitted = passphrase
                    // SwiftUI state keeps no passphrase after submission. The task
                    // receives only the short-lived value needed for this operation.
                    passphrase.removeAll(keepingCapacity: false)
                    confirmation.removeAll(keepingCapacity: false)
                    onSubmit(submitted)
                }
            }
        }
        .frame(width: 500)
        .onDisappear {
            passphrase.removeAll(keepingCapacity: false)
            confirmation.removeAll(keepingCapacity: false)
        }
    }
}
#endif

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
                VStack(alignment: .leading, spacing: 26) {
                    listCard
                    Hairline()
                    editorCard
                        .frame(maxHeight: .infinity)
                }
            } else {
                // Düz zeminde iki kolon: kart kabuğu yerine dikey ince çizgi.
                HStack(alignment: .top, spacing: 26) {
                    listCard
                        .frame(width: 320)
                        .frame(maxHeight: .infinity)
                    Rectangle()
                        .fill(Palette.border.opacity(0.6))
                        .frame(width: 1)
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            .selectionRing(active, cornerRadius: 8)
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
                if let note = selected.dynamicNote {
                    Lucide(sf: "info.circle", size: 11)
                        .foregroundStyle(Palette.textTertiary)
                        .help(note)
                }
                Spacer(minLength: Spacing.md)
                Text("\(Fmt.int(Double(draft.count))) karakter")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
            }

            // Uyarı kutusu yok: nötr gri ünlem, metin üzerine gelince tooltip'te.

            // Sabit kutu: metin uzadıkça sayfa değil editörün kendisi kayar.
            // "Hakkımda" alanıyla aynı dil: kutu yok, metin doğrudan yüzeyde.
            TextEditor(text: $draft)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12.5, design: .monospaced))
                .lineSpacing(5)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
                .padding(.top, 10)

            HStack(spacing: 10) {
                Button { save() } label: {
                    Text(savedFlash ? "Kaydedildi" : "Kaydet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isDirty || savedFlash ? Palette.btnFg : Palette.textTertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isDirty ? Palette.btnBg : (savedFlash ? Palette.positive.opacity(0.5) : Palette.fieldFill))
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
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
    }

    private func promptGhostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 5.5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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

// MARK: - Hafıza notu penceresi

/// Hafıza notu — tasarım: tuval ▸ Pencereler · İlerleme · Profil (az yazı): içerik, virgülle ayrılmış
/// etiketler ve sabitle anahtarı.
struct MemoryEditorSheet: View {
    let isNew: Bool
    @Binding var content: String
    @Binding var tags: String
    @Binding var pinned: Bool
    let canSave: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        SadeSheet(title: isNew ? "Yeni hafıza" : "Hafızayı düzenle", onClose: onCancel) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("İçerik")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                    TextEditor(text: $content)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 8)
                        .frame(height: 120)
                        .sadeBox(radius: 10)
                }
                SadeField(label: "Etiketler") {
                    TextField("", text: $tags, prompt: Text("beslenme, antrenman").foregroundStyle(Palette.textTertiary))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                }
                SadeToggleRow(title: "Sabitle", isOn: $pinned)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        } footerLeading: {
            EmptyView()
        } footerTrailing: {
            SadeButton(title: "İptal", action: onCancel)
            SadeButton(title: "Kaydet", role: .primary, enabled: canSave, action: onSave)
        }
        .frame(width: 560)
    }
}
