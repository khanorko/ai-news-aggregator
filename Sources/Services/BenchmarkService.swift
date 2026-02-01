import Foundation
import SwiftSoup
import Alamofire

/// Service for scraping AI benchmark leaderboards
actor BenchmarkService {
    private let database: DatabaseManager
    
    init(database: DatabaseManager) {
        self.database = database
    }
    
    /// Fetch all benchmark updates from configured sources
    func fetchAllBenchmarks() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchPapersWithCodeBenchmarks() }
            group.addTask { await self.fetchHuggingFaceLeaderboards() }
            group.addTask { await self.fetchOpenLLMLeaderboard() }
        }
    }
    
    // MARK: - Papers with Code
    
    /// Scrape benchmarks from Papers with Code
    func fetchPapersWithCodeBenchmarks() async {
        let benchmarks = [
            ("MMLU", "https://paperswithcode.com/sota/multi-task-language-understanding-on-mmlu"),
            ("HumanEval", "https://paperswithcode.com/sota/code-generation-on-humaneval"),
            ("GSM8K", "https://paperswithcode.com/sota/arithmetic-reasoning-on-gsm8k"),
            ("MATH", "https://paperswithcode.com/sota/math-word-problem-solving-on-math"),
            ("HellaSwag", "https://paperswithcode.com/sota/sentence-completion-on-hellaswag"),
            ("ARC-Challenge", "https://paperswithcode.com/sota/common-sense-reasoning-on-arc-challenge"),
            ("WinoGrande", "https://paperswithcode.com/sota/common-sense-reasoning-on-winogrande"),
            ("TruthfulQA", "https://paperswithcode.com/sota/question-answering-on-truthfulqa"),
        ]
        
        for (name, url) in benchmarks {
            await fetchPapersWithCodeSota(benchmarkName: name, url: url)
        }
    }
    
    private func fetchPapersWithCodeSota(benchmarkName: String, url: String) async {
        guard let requestUrl = URL(string: url) else { return }
        
        do {
            let html = try await AF.request(requestUrl).serializingString().value
            let doc = try SwiftSoup.parse(html)
            
            // Find the leaderboard table
            let rows = try doc.select("table tbody tr")
            
            for (index, row) in rows.prefix(10).enumerated() {
                let cells = try row.select("td")
                guard cells.count >= 3 else { continue }
                
                // Extract model name (usually in first column)
                let modelName = try cells[0].text().trimmingCharacters(in: .whitespaces)
                
                // Extract score (usually in second or third column)
                var scoreText = try cells[1].text()
                    .replacingOccurrences(of: "%", with: "")
                    .trimmingCharacters(in: .whitespaces)
                
                // Try to parse score
                if let score = Double(scoreText) {
                    // Create article for significant updates
                    if index == 0 {
                        await createBenchmarkArticle(
                            benchmarkName: benchmarkName,
                            modelName: modelName,
                            score: score,
                            url: url
                        )
                    }
                    
                    // Store benchmark entry
                    await storeBenchmarkEntry(
                        benchmarkName: benchmarkName,
                        modelName: modelName,
                        score: score,
                        url: url
                    )
                }
            }
        } catch {
            print("Error fetching Papers with Code \(benchmarkName): \(error)")
        }
    }
    
    // MARK: - Hugging Face Leaderboards
    
    /// Fetch from Hugging Face Open LLM Leaderboard
    func fetchHuggingFaceLeaderboards() async {
        // The HF leaderboard uses a Gradio app, so we need to handle it differently
        // For now, we'll use their API endpoint if available
        let url = "https://huggingface.co/spaces/HuggingFaceH4/open_llm_leaderboard"
        
        // Note: HF leaderboard requires special handling due to Gradio
        // In production, you'd use their API or scrape the rendered page
        print("HuggingFace leaderboard scraping requires Gradio handling")
    }
    
    /// Fetch Open LLM Leaderboard data via API
    func fetchOpenLLMLeaderboard() async {
        // Try to fetch from the HF datasets API
        let apiUrl = "https://datasets-server.huggingface.co/rows?dataset=open-llm-leaderboard%2Fresults&config=default&split=train&offset=0&length=20"
        
        do {
            let response = try await AF.request(apiUrl)
                .serializingDecodable(HFLeaderboardResponse.self).value
            
            for row in response.rows.prefix(10) {
                let modelName = row.row.model ?? "Unknown"
                
                // Average score across benchmarks
                if let average = row.row.average {
                    await storeBenchmarkEntry(
                        benchmarkName: "Open LLM Average",
                        modelName: modelName,
                        score: average,
                        url: "https://huggingface.co/spaces/HuggingFaceH4/open_llm_leaderboard"
                    )
                }
                
                // Individual benchmark scores
                if let mmlu = row.row.mmlu {
                    await storeBenchmarkEntry(benchmarkName: "MMLU (HF)", modelName: modelName, score: mmlu, url: nil)
                }
                if let hellaswag = row.row.hellaswag {
                    await storeBenchmarkEntry(benchmarkName: "HellaSwag (HF)", modelName: modelName, score: hellaswag, url: nil)
                }
                if let arc = row.row.arc {
                    await storeBenchmarkEntry(benchmarkName: "ARC (HF)", modelName: modelName, score: arc, url: nil)
                }
            }
        } catch {
            print("Error fetching HF leaderboard: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func storeBenchmarkEntry(
        benchmarkName: String,
        modelName: String,
        score: Double,
        url: String?
    ) async {
        // In a full implementation, this would save to the database
        // and check for significant changes to create alerts
        print("Benchmark: \(benchmarkName) - \(modelName): \(score)")
    }
    
    private func createBenchmarkArticle(
        benchmarkName: String,
        modelName: String,
        score: Double,
        url: String
    ) async {
        // Create a news article for the top benchmark result
        // This shows up in the main feed
        
        let title = "🏆 \(modelName) leads \(benchmarkName) benchmark with \(String(format: "%.1f", score))%"
        let summary = "According to Papers with Code, \(modelName) currently achieves state-of-the-art performance on the \(benchmarkName) benchmark with a score of \(String(format: "%.2f", score))%."
        
        // Find or create benchmark source
        do {
            let sources = try await database.fetchSources()
            let benchmarkSource = sources.first { $0.type == .benchmark }
            
            if let source = benchmarkSource {
                var article = Article(
                    sourceId: source.id ?? 0,
                    title: title,
                    summary: summary,
                    llmSummary: nil,
                    url: url,
                    imageUrl: nil,
                    author: "Papers with Code",
                    publishedAt: Date(),
                    fetchedAt: Date(),
                    rating: nil,
                    isBookmarked: false,
                    readAt: nil,
                    keywords: [benchmarkName, modelName, "benchmark", "SOTA", "leaderboard"],
                    categories: ["benchmark"],
                    sentiment: 0.5,
                    relevanceScore: 0.8
                )
                
                try await database.saveArticle(&article)
            }
        } catch {
            print("Error creating benchmark article: \(error)")
        }
    }
    
    // MARK: - Benchmark Tracking
    
    /// Get historical data for a specific benchmark
    func getBenchmarkHistory(name: String) async -> [(model: String, score: Double, date: Date)] {
        // Would query database for historical entries
        return []
    }
    
    /// Get current leaders across all benchmarks
    func getCurrentLeaders() async -> [String: (model: String, score: Double)] {
        // Would return top model for each benchmark
        return [:]
    }
    
    /// Check for significant benchmark changes
    func checkForSignificantChanges() async -> [BenchmarkAlert] {
        // Compare current state to previous and detect:
        // - New SOTA achievements
        // - Large improvements (>5%)
        // - New models entering top 10
        return []
    }
}

// MARK: - Response Types

struct HFLeaderboardResponse: Codable {
    let rows: [HFLeaderboardRow]
}

struct HFLeaderboardRow: Codable {
    let row: HFLeaderboardEntry
}

struct HFLeaderboardEntry: Codable {
    let model: String?
    let average: Double?
    let mmlu: Double?
    let hellaswag: Double?
    let arc: Double?
    let truthfulqa: Double?
    let winogrande: Double?
    let gsm8k: Double?
    
    enum CodingKeys: String, CodingKey {
        case model = "fullname"
        case average = "Average ⬆️"
        case mmlu = "MMLU"
        case hellaswag = "HellaSwag"
        case arc = "ARC"
        case truthfulqa = "TruthfulQA"
        case winogrande = "Winogrande"
        case gsm8k = "GSM8K"
    }
}

struct BenchmarkAlert {
    let benchmarkName: String
    let previousLeader: String
    let newLeader: String
    let previousScore: Double
    let newScore: Double
    let improvement: Double
    
    var message: String {
        "🏆 New SOTA on \(benchmarkName): \(newLeader) surpasses \(previousLeader) with \(String(format: "%.1f", newScore))% (+\(String(format: "%.1f", improvement))%)"
    }
}

// MARK: - Benchmark Analytics

extension BenchmarkService {
    /// Analyze benchmark trends over time
    func analyzeTrends() async -> BenchmarkTrends {
        // Would analyze historical data to find:
        // - Fastest improving models
        // - Benchmark saturation (approaching 100%)
        // - Emerging patterns
        
        return BenchmarkTrends(
            fastestImproving: [],
            saturatedBenchmarks: [],
            emergingModels: []
        )
    }
}

struct BenchmarkTrends {
    let fastestImproving: [(model: String, improvementRate: Double)]
    let saturatedBenchmarks: [String]  // Benchmarks where top scores are >95%
    let emergingModels: [String]  // New models showing rapid improvement
}
