import Foundation

struct PubMedResearchSkill: AgentSkill {
    let id = "research.pubmed"
    let name = "PubMed Research"
    let description = "Bodybuilding, nutrition and training questions için güncel PubMed makale adayları getirir."

    private let session: URLSession

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init(session: URLSession? = nil) {
        self.session = session ?? Self.defaultSession
    }

    func canHandle(_ query: String) -> Bool {
        let lower = query.foldedForAgent
        let researchTriggers = [
            "pubmed", "makale", "calisma", "çalışma", "arastirma", "araştırma",
            "paper", "evidence", "kanit", "kanıt", "meta", "systematic",
            "literatur", "literatür", "guncel", "güncel", "son"
        ]
        let bodySignals = [
            "bodybuilding", "vucut", "vücut", "kas", "hipertrofi", "hypertrophy",
            "protein", "kreatin", "creatine", "supplement", "antrenman",
            "idman", "training", "resistance", "volume", "bulk", "cut",
            "definasyon", "yag", "yağ", "sleep", "uyku", "recovery"
        ]
        return lower.agentContainsAny(researchTriggers) && lower.agentContainsAny(bodySignals)
    }

    func run(query: String, context: AgentContext) async throws -> SkillResult? {
        let term = pubMedTerm(for: query)
        let ids = try await searchIDs(term: term)
        guard !ids.isEmpty else { return nil }

        let papers = try await summaries(for: ids)
        guard !papers.isEmpty else { return nil }

        let lines = papers.prefix(5).map { paper in
            "- \(paper.title) (\(paper.journal), \(paper.pubDate); PMID \(paper.pmid))"
        }
        let sources = papers.prefix(5).map { "https://pubmed.ncbi.nlm.nih.gov/\($0.pmid)/" }

        return SkillResult(
            skillID: id,
            title: "PubMed Güncel Araştırma Adayları",
            content: """
            Sorgu: \(term)
            \(lines.joined(separator: "\n"))
            """,
            sources: sources
        )
    }

    private func searchIDs(term: String) async throws -> [String] {
        var components = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi")!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "retmode", value: "json"),
            URLQueryItem(name: "sort", value: "pub date"),
            URLQueryItem(name: "retmax", value: "5"),
            URLQueryItem(name: "term", value: term)
        ]
        let url = components.url!
        let (data, _) = try await session.data(from: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = root?["esearchresult"] as? [String: Any]
        return result?["idlist"] as? [String] ?? []
    }

    private func summaries(for ids: [String]) async throws -> [PaperSummary] {
        var components = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi")!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "retmode", value: "json"),
            URLQueryItem(name: "id", value: ids.joined(separator: ","))
        ]
        let url = components.url!
        let (data, _) = try await session.data(from: url)
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

    private func pubMedTerm(for query: String) -> String {
        let lower = query.foldedForAgent
        var concepts: [String] = ["resistance training", "muscle hypertrophy", "bodybuilding"]

        if lower.agentContainsAny(["protein", "whey", "amino", "leucine"]) {
            concepts.append(contentsOf: ["dietary protein", "muscle protein synthesis"])
        }
        if lower.agentContainsAny(["kreatin", "creatine"]) {
            concepts.append("creatine supplementation")
        }
        if lower.agentContainsAny(["volume", "set", "frekans", "frequency"]) {
            concepts.append(contentsOf: ["training volume", "training frequency"])
        }
        if lower.agentContainsAny(["sleep", "uyku", "recovery", "toparlanma"]) {
            concepts.append(contentsOf: ["sleep", "exercise recovery"])
        }
        if lower.agentContainsAny(["fat", "yag", "yağ", "cut", "definasyon"]) {
            concepts.append(contentsOf: ["fat loss", "energy restriction"])
        }

        let conceptQuery = concepts
            .map { "\"\($0)\"" }
            .joined(separator: " OR ")

        return """
        (\(conceptQuery)) AND (review[Publication Type] OR meta-analysis[Publication Type] OR randomized controlled trial[Publication Type] OR systematic review[Title/Abstract] OR trial[Title/Abstract])
        """
    }
}

private struct PaperSummary {
    let pmid: String
    let title: String
    let journal: String
    let pubDate: String
}

private extension String {
    var foldedForAgent: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
    }

    func agentContainsAny(_ needles: [String]) -> Bool {
        needles.map(\.foldedForAgent).contains { contains($0) }
    }
}
