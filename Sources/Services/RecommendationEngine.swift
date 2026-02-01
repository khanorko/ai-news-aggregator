import Foundation
import GRDB

/// Recommendation engine using Thompson Sampling for exploration/exploitation
actor RecommendationEngine {
    private let database: DatabaseManager
    
    // Exploration parameters
    private var explorationRate: Double = 0.15  // 15% exploration
    private var decayFactor: Double = 0.95  // How quickly old interactions matter less
    
    init(database: DatabaseManager) {
        self.database = database
    }
    
    /// Process positive feedback (thumbs up)
    func processPositiveFeedback(for article: Article) async {
        // Update keyword statistics
        for keyword in article.keywords {
            await database.updateKeywordStats(keyword: keyword, isPositive: true)
        }
        
        // Boost source ranking
        await database.updateSourceRanking(article.sourceId, delta: 0.02)
        
        // Update user preferences
        await updatePreferences(keywords: article.keywords, positive: true)
    }
    
    /// Process negative feedback (thumbs down)
    func processNegativeFeedback(for article: Article) async {
        // Update keyword statistics
        for keyword in article.keywords {
            await database.updateKeywordStats(keyword: keyword, isPositive: false)
        }
        
        // Slightly reduce source ranking
        await database.updateSourceRanking(article.sourceId, delta: -0.01)
        
        // Update user preferences
        await updatePreferences(keywords: article.keywords, positive: false)
    }
    
    /// Calculate relevance score for an article using Thompson Sampling
    func calculateRelevanceScore(for article: Article) async -> Double {
        var score: Double = 0.5  // Base score
        
        do {
            let preferences = try await database.fetchUserPreferences()
            let prefDict = Dictionary(uniqueKeysWithValues: preferences.map { 
                ($0.keyword.lowercased(), (weight: $0.weight, confidence: $0.confidence)) 
            })
            
            // Thompson Sampling: Sample from beta distribution for each keyword
            for keyword in article.keywords {
                let key = keyword.lowercased()
                if let pref = prefDict[key] {
                    // More confident preferences have less variance
                    let variance = (1 - pref.confidence) * 0.2
                    let sampledWeight = sampleNormal(mean: pref.weight, stdDev: variance)
                    score += sampledWeight * 0.15
                } else {
                    // Unknown keyword: high uncertainty encourages exploration
                    score += sampleNormal(mean: 0.0, stdDev: 0.3) * 0.1
                }
            }
            
            // Add exploration bonus for less-seen content
            if shouldExplore() {
                score += Double.random(in: 0.1...0.3)
            }
            
        } catch {
            // Fallback to simple calculation
            score = 0.5
        }
        
        return max(0, min(1, score))
    }
    
    /// Rank a list of articles
    func rankArticles(_ articles: [Article]) async -> [Article] {
        var scoredArticles: [(article: Article, score: Double)] = []
        
        for article in articles {
            let score = await calculateRelevanceScore(for: article)
            var updatedArticle = article
            updatedArticle.relevanceScore = score
            scoredArticles.append((updatedArticle, score))
        }
        
        // Sort by score descending, with some randomness for diversity
        return scoredArticles
            .sorted { a, b in
                // Add small random factor to prevent exact same ordering
                let noise = Double.random(in: -0.05...0.05)
                return a.score + noise > b.score
            }
            .map { $0.article }
    }
    
    /// Get exploration suggestions to break filter bubble
    func getExplorationSuggestions() async -> [String] {
        var suggestions: [String] = []
        
        do {
            let preferences = try await database.fetchUserPreferences()
            
            // Find topics user hasn't engaged with much
            let lowConfidenceTopics = preferences
                .filter { $0.confidence < 0.3 }
                .map { $0.keyword }
            
            suggestions.append(contentsOf: lowConfidenceTopics.prefix(3))
            
            // Suggest exploring opposite of strong preferences
            let strongNegatives = preferences
                .filter { $0.weight < -0.5 && $0.confidence > 0.5 }
                .map { "Revisit: \($0.keyword)" }
            
            suggestions.append(contentsOf: strongNegatives.prefix(2))
            
        } catch {
            // Return general suggestions
            suggestions = ["AI Safety", "Open Source Models", "AI Policy", "Benchmarks"]
        }
        
        return suggestions
    }
    
    // MARK: - Private Helpers
    
    private func updatePreferences(keywords: [String], positive: Bool) async {
        let delta = positive ? 0.1 : -0.1
        let confidenceBoost = 0.05
        
        // In a real implementation, this would update the database
        // For now, keyword stats handle this indirectly
    }
    
    private func shouldExplore() -> Bool {
        return Double.random(in: 0...1) < explorationRate
    }
    
    /// Sample from normal distribution using Box-Muller transform
    private func sampleNormal(mean: Double, stdDev: Double) -> Double {
        let u1 = Double.random(in: 0.0001...1)
        let u2 = Double.random(in: 0...1)
        let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        return mean + z * stdDev
    }
    
    /// Adjust exploration rate based on user engagement
    func adjustExplorationRate(engagementRate: Double) {
        // If user engages a lot, we can explore more
        // If user rarely engages, stick more to known preferences
        if engagementRate > 0.3 {
            explorationRate = min(0.25, explorationRate + 0.02)
        } else if engagementRate < 0.1 {
            explorationRate = max(0.05, explorationRate - 0.02)
        }
    }
}

// MARK: - Diversity Metrics

extension RecommendationEngine {
    /// Calculate how diverse the current feed is
    func calculateDiversityScore(articles: [Article]) -> Double {
        guard !articles.isEmpty else { return 0 }
        
        // Count unique categories and keywords
        let allKeywords = Set(articles.flatMap { $0.keywords })
        let allCategories = Set(articles.flatMap { $0.categories })
        let uniqueSources = Set(articles.map { $0.sourceId })
        
        // Diversity increases with more unique elements
        let keywordDiversity = min(1.0, Double(allKeywords.count) / 50.0)
        let categoryDiversity = min(1.0, Double(allCategories.count) / 7.0)
        let sourceDiversity = min(1.0, Double(uniqueSources.count) / 10.0)
        
        return (keywordDiversity + categoryDiversity + sourceDiversity) / 3.0
    }
    
    /// Get feedback on filter bubble status
    func getFilterBubbleStatus(articles: [Article]) -> FilterBubbleStatus {
        let diversity = calculateDiversityScore(articles: articles)
        
        if diversity > 0.7 {
            return .healthy
        } else if diversity > 0.4 {
            return .moderate
        } else {
            return .narrow
        }
    }
}

enum FilterBubbleStatus {
    case healthy
    case moderate  
    case narrow
    
    var description: String {
        switch self {
        case .healthy: return "Your feed is diverse and well-balanced"
        case .moderate: return "Consider exploring some new topics"
        case .narrow: return "Warning: You might be in a filter bubble"
        }
    }
    
    var emoji: String {
        switch self {
        case .healthy: return "🌈"
        case .moderate: return "⚠️"
        case .narrow: return "🔴"
        }
    }
}
