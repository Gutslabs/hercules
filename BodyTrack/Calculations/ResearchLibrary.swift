import Foundation

struct ResearchTopic: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let query: String
    let tags: [String]
}

struct ResearchPaper: Codable, Identifiable, Equatable {
    let id: UUID
    var pmid: String
    var title: String
    var journal: String
    var pubDate: String
    var topicIDs: [String]
    var topicLabels: [String]
    var query: String
    var sourceURL: String
    var addedAt: Date
    var updatedAt: Date
    var pinned: Bool

    init(
        id: UUID = UUID(),
        pmid: String,
        title: String,
        journal: String,
        pubDate: String,
        topicIDs: [String],
        topicLabels: [String],
        query: String,
        sourceURL: String,
        addedAt: Date = .now,
        updatedAt: Date = .now,
        pinned: Bool = false
    ) {
        self.id = id
        self.pmid = pmid
        self.title = title
        self.journal = journal
        self.pubDate = pubDate
        self.topicIDs = topicIDs
        self.topicLabels = topicLabels
        self.query = query
        self.sourceURL = sourceURL
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.pinned = pinned
    }
}

struct ResearchUpdateSummary {
    let addedCount: Int
    let updatedCount: Int
    let totalCount: Int
    let failedTopics: [String]
    let updatedAt: Date

    var statusText: String {
        var parts = ["\(addedCount) yeni", "\(updatedCount) güncellendi", "toplam \(totalCount)"]
        if !failedTopics.isEmpty {
            parts.append("hata: \(failedTopics.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }
}

enum ResearchWindow: Int, CaseIterable, Identifiable {
    case latest = 2024
    case current = 2020
    case foundation = 2015

    var id: Int { rawValue }
    var startYear: Int { rawValue }

    var title: String {
        switch self {
        case .latest: return "2024+"
        case .current: return "2020+"
        case .foundation: return "2015+"
        }
    }

    var summary: String {
        switch self {
        case .latest:
            return "En yeni dalgayı izler; hızlı ama dar olabilir."
        case .current:
            return "Güncel evidence için iyi default; yeni paperları ve yakın dönem review/RCT'leri dengeler."
        case .foundation:
            return "Daha geniş foundational tarama; klasik review ve meta analizleri de yakalar."
        }
    }
}

@MainActor
final class ResearchLibrary {
    static let shared = ResearchLibrary()

    static let defaultTopics: [ResearchTopic] = [
        ResearchTopic(
            id: "hypertrophy",
            title: "Hipertrofi",
            query: """
            ("resistance training"[Title/Abstract] OR "strength training"[Title/Abstract] OR bodybuilding[Title/Abstract]) AND ("muscle hypertrophy"[Title/Abstract] OR "lean body mass"[Title/Abstract]) AND (review[Publication Type] OR meta-analysis[Publication Type] OR randomized controlled trial[Publication Type] OR systematic review[Title/Abstract])
            """,
            tags: ["training", "hypertrophy"]
        ),
        ResearchTopic(
            id: "protein",
            title: "Protein",
            query: """
            ("dietary protein"[Title/Abstract] OR whey[Title/Abstract] OR leucine[Title/Abstract] OR "muscle protein synthesis"[Title/Abstract]) AND ("resistance training"[Title/Abstract] OR exercise[Title/Abstract] OR athlete[Title/Abstract]) AND (review[Publication Type] OR meta-analysis[Publication Type] OR randomized controlled trial[Publication Type] OR systematic review[Title/Abstract])
            """,
            tags: ["nutrition", "protein"]
        ),
        ResearchTopic(
            id: "creatine",
            title: "Kreatin",
            query: """
            ("creatine supplementation"[Title/Abstract] OR creatine[Title/Abstract]) AND ("resistance training"[Title/Abstract] OR strength[Title/Abstract] OR exercise[Title/Abstract]) AND (review[Publication Type] OR meta-analysis[Publication Type] OR randomized controlled trial[Publication Type] OR systematic review[Title/Abstract])
            """,
            tags: ["supplement", "creatine"]
        ),
        ResearchTopic(
            id: "volume",
            title: "Volume/Frekans",
            query: """
            ("training volume"[Title/Abstract] OR "training frequency"[Title/Abstract] OR "resistance training volume"[Title/Abstract] OR "sets"[Title/Abstract]) AND ("muscle hypertrophy"[Title/Abstract] OR strength[Title/Abstract]) AND (review[Publication Type] OR meta-analysis[Publication Type] OR randomized controlled trial[Publication Type] OR systematic review[Title/Abstract])
            """,
            tags: ["training", "volume"]
        ),
        ResearchTopic(
            id: "fat-loss",
            title: "Yağ Kaybı",
            query: """
            ("energy restriction"[Title/Abstract] OR "fat loss"[Title/Abstract] OR "weight loss"[Title/Abstract] OR "caloric deficit"[Title/Abstract]) AND ("resistance training"[Title/Abstract] OR "lean mass"[Title/Abstract] OR athlete[Title/Abstract]) AND (review[Publication Type] OR meta-analysis[Publication Type] OR randomized controlled trial[Publication Type] OR systematic review[Title/Abstract])
            """,
            tags: ["nutrition", "fat-loss"]
        ),
        ResearchTopic(
            id: "recovery",
            title: "Uyku/Recovery",
            query: """
            (sleep[Title/Abstract] OR recovery[Title/Abstract] OR "exercise recovery"[Title/Abstract]) AND ("resistance training"[Title/Abstract] OR athlete[Title/Abstract] OR "muscle strength"[Title/Abstract]) AND (review[Publication Type] OR meta-analysis[Publication Type] OR randomized controlled trial[Publication Type] OR systematic review[Title/Abstract])
            """,
            tags: ["recovery", "sleep"]
        )
    ]

    private struct ResearchPayload: Codable {
        var version: Int
        var savedAt: Date
        var lastUpdatedAt: Date?
        var papers: [ResearchPaper]
    }

    private struct PaperSummary {
        let pmid: String
        let title: String
        let journal: String
        let pubDate: String
    }

    private let researchURL: URL
    private let session: URLSession
    private var papers: [ResearchPaper] = []
    private(set) var lastUpdatedAt: Date?

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 16
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private init(session: URLSession? = nil) {
        researchURL = Self.makeResearchURL()
        self.session = session ?? Self.defaultSession
        reloadFromDisk()
    }

    func reloadFromDisk() {
        load()
    }

    func allPapers() -> [ResearchPaper] {
        reloadFromDisk()
        return papers.sorted(by: sortPapers)
    }

    func recentPapers(limit: Int) -> [ResearchPaper] {
        Array(allPapers().prefix(limit))
    }

    func needsRefresh(maxAgeDays: Double = 7) -> Bool {
        reloadFromDisk()
        guard let lastUpdatedAt else { return true }
        return Date().timeIntervalSince(lastUpdatedAt) > maxAgeDays * 86_400
    }

    func search(query: String, topK: Int) -> [ResearchPaper] {
        reloadFromDisk()
        let queryTerms = Set(Self.tokens(query))
        guard !queryTerms.isEmpty else { return recentPapers(limit: topK) }

        let scored = papers.map { paper -> (paper: ResearchPaper, score: Double) in
            let searchable = [
                paper.title,
                paper.journal,
                paper.pubDate,
                paper.topicLabels.joined(separator: " "),
                paper.topicIDs.joined(separator: " "),
                paper.query
            ].joined(separator: " ")
            let paperTerms = Set(Self.tokens(searchable))
            let overlap = queryTerms.intersection(paperTerms)
            let topicOverlap = queryTerms.intersection(Set(paper.topicLabels.flatMap(Self.tokens)))
            let recencyDays = max(0, Date().timeIntervalSince(paper.updatedAt) / 86_400)
            let recency = 1.0 / (1.0 + min(recencyDays, 90))
            let score = Double(overlap.count) * 2.0
                + Double(topicOverlap.count) * 3.0
                + recency
                + (paper.pinned ? 2.0 : 0.0)
            return (paper, score)
        }
        .filter { $0.score > 0.5 }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return sortPapers(lhs.paper, rhs.paper)
            }
            return lhs.score > rhs.score
        }

        return Array(scored.prefix(topK).map(\.paper))
    }

    func deletePaper(id: UUID) {
        papers.removeAll { $0.id == id }
        persist()
    }

    func setPinned(id: UUID, pinned: Bool) {
        guard let idx = papers.firstIndex(where: { $0.id == id }) else { return }
        papers[idx].pinned = pinned
        papers[idx].updatedAt = .now
        persist()
    }

    @discardableResult
    func updateNow(
        topics: [ResearchTopic] = ResearchLibrary.defaultTopics,
        fromYear: Int = ResearchWindow.current.startYear
    ) async -> ResearchUpdateSummary {
        reloadFromDisk()
        var addedCount = 0
        var updatedCount = 0
        var failedTopics: [String] = []

        for topic in topics {
            do {
                let ids = try await collectIDs(term: topic.query, fromYear: fromYear)
                let summaries = try await summaries(for: ids)
                let merge = merge(summaries: summaries, topic: topic)
                addedCount += merge.added
                updatedCount += merge.updated
            } catch {
                failedTopics.append(topic.title)
            }
        }

        lastUpdatedAt = .now
        persist()
        return ResearchUpdateSummary(
            addedCount: addedCount,
            updatedCount: updatedCount,
            totalCount: papers.count,
            failedTopics: failedTopics,
            updatedAt: lastUpdatedAt ?? .now
        )
    }

    private func collectIDs(term: String, fromYear: Int) async throws -> [String] {
        let recent = try await searchIDs(term: term, fromYear: fromYear, sort: "pub date", retmax: 6)
        let evidence = try await searchIDs(term: term, fromYear: fromYear, sort: "relevance", retmax: 6)
        var seen: Set<String> = []
        return (recent + evidence).filter { seen.insert($0).inserted }
    }

    private func merge(summaries: [PaperSummary], topic: ResearchTopic) -> (added: Int, updated: Int) {
        var added = 0
        var updated = 0

        for summary in summaries {
            if let idx = papers.firstIndex(where: { $0.pmid == summary.pmid }) {
                papers[idx].title = summary.title
                papers[idx].journal = summary.journal
                papers[idx].pubDate = summary.pubDate
                papers[idx].query = topic.query
                papers[idx].topicIDs = Array(Set(papers[idx].topicIDs + [topic.id])).sorted()
                papers[idx].topicLabels = Array(Set(papers[idx].topicLabels + [topic.title])).sorted()
                papers[idx].updatedAt = .now
                updated += 1
            } else {
                papers.append(
                    ResearchPaper(
                        pmid: summary.pmid,
                        title: summary.title,
                        journal: summary.journal,
                        pubDate: summary.pubDate,
                        topicIDs: [topic.id],
                        topicLabels: [topic.title],
                        query: topic.query,
                        sourceURL: "https://pubmed.ncbi.nlm.nih.gov/\(summary.pmid)/"
                    )
                )
                added += 1
            }
        }

        return (added, updated)
    }

    private func searchIDs(term: String, fromYear: Int, sort: String, retmax: Int) async throws -> [String] {
        var components = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi")!
        let maxYear = Calendar.current.component(.year, from: Date())
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "retmode", value: "json"),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "retmax", value: "\(retmax)"),
            URLQueryItem(name: "datetype", value: "pdat"),
            URLQueryItem(name: "mindate", value: "\(fromYear)"),
            URLQueryItem(name: "maxdate", value: "\(maxYear)"),
            URLQueryItem(name: "tool", value: "HerculesResearch"),
            URLQueryItem(name: "term", value: term)
        ]
        let url = components.url!
        await pauseForNCBI()
        let (data, response) = try await session.data(from: url)
        try Self.validate(response: response)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = root?["esearchresult"] as? [String: Any]
        return result?["idlist"] as? [String] ?? []
    }

    private func summaries(for ids: [String]) async throws -> [PaperSummary] {
        guard !ids.isEmpty else { return [] }
        var components = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi")!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "retmode", value: "json"),
            URLQueryItem(name: "tool", value: "HerculesResearch"),
            URLQueryItem(name: "id", value: ids.joined(separator: ","))
        ]
        let url = components.url!
        await pauseForNCBI()
        let (data, response) = try await session.data(from: url)
        try Self.validate(response: response)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = root?["result"] as? [String: Any] else { return [] }

        let orderedIDs = (result["uids"] as? [String]) ?? ids
        return orderedIDs.compactMap { id in
            guard let item = result[id] as? [String: Any] else { return nil }
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let journal = (item["fulljournalname"] as? String) ?? (item["source"] as? String) ?? "PubMed"
            let pubDate = (item["pubdate"] as? String) ?? "tarih yok"
            guard let title, !title.isEmpty else { return nil }
            return PaperSummary(pmid: id, title: title, journal: journal, pubDate: pubDate)
        }
    }

    private func pauseForNCBI() async {
        try? await Task.sleep(nanoseconds: 420_000_000)
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
    }

    private func sortPapers(_ lhs: ResearchPaper, _ rhs: ResearchPaper) -> Bool {
        if lhs.pinned != rhs.pinned {
            return lhs.pinned && !rhs.pinned
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func makeResearchURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("research-library.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: researchURL) else {
            papers = []
            lastUpdatedAt = nil
            return
        }

        do {
            let payload = try Self.decoder.decode(ResearchPayload.self, from: data)
            papers = Self.deduplicated(payload.papers)
            lastUpdatedAt = payload.lastUpdatedAt
        } catch {
            Self.backupUnreadableFile(at: researchURL)
            papers = []
            lastUpdatedAt = nil
        }
    }

    private func persist() {
        if papers.isEmpty, lastUpdatedAt == nil {
            try? FileManager.default.removeItem(at: researchURL)
            return
        }

        let payload = ResearchPayload(
            version: 1,
            savedAt: .now,
            lastUpdatedAt: lastUpdatedAt,
            papers: papers
        )
        guard let data = try? Self.encoder.encode(payload) else { return }
        try? data.write(to: researchURL, options: [.atomic])
    }

    private static func tokens(_ text: String) -> [String] {
        fold(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
    }

    private static func deduplicated(_ loaded: [ResearchPaper]) -> [ResearchPaper] {
        var output: [ResearchPaper] = []
        for paper in loaded {
            if let idx = output.firstIndex(where: { $0.pmid == paper.pmid }) {
                output[idx].topicIDs = Array(Set(output[idx].topicIDs + paper.topicIDs)).sorted()
                output[idx].topicLabels = Array(Set(output[idx].topicLabels + paper.topicLabels)).sorted()
                output[idx].updatedAt = max(output[idx].updatedAt, paper.updatedAt)
                output[idx].pinned = output[idx].pinned || paper.pinned
            } else {
                output.append(paper)
            }
        }
        return output
    }

    private static func backupUnreadableFile(at url: URL) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-unreadable-\(formatter.string(from: Date())).json")
        try? FileManager.default.copyItem(at: url, to: backupURL)
    }
}

struct ResearchLibrarySkill: AgentSkill {
    let id = "research.library"
    let name = "Bodybuilding Research Library"
    let description = "Local PubMed research cache içinden bodybuilding/nutrition/training makalelerini getirir."

    func canHandle(_ query: String) -> Bool {
        AgentQueryClassifier.shouldUseResearchCache(query)
    }

    func run(query: String, context: AgentContext) async throws -> SkillResult? {
        // ResearchLibrary artık @MainActor — erişimi main'e taşı (papers yarışını önler).
        let result: (lines: [String], sources: [String])? = await MainActor.run {
            let papers = ResearchLibrary.shared.search(query: query, topK: 6)
            guard !papers.isEmpty else { return nil }
            let lines = papers.map { paper -> String in
                let topics = paper.topicLabels.isEmpty ? "" : " · \(paper.topicLabels.joined(separator: ", "))"
                return "- \(paper.title) (\(paper.journal), \(paper.pubDate); PMID \(paper.pmid)\(topics))"
            }
            return (lines, papers.map(\.sourceURL))
        }
        guard let result else { return nil }

        return SkillResult(
            skillID: id,
            title: "Bodybuilding Research Cache",
            content: result.lines.joined(separator: "\n"),
            sources: result.sources
        )
    }
}
