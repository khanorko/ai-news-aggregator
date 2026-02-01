import Foundation
import GRDB

/// Represents a news article from any source
struct Article: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var sourceId: Int64
    var title: String
    var summary: String?
    var llmSummary: String?  // AI-generated summary
    var url: String
    var imageUrl: String?
    var author: String?
    var publishedAt: Date?
    var fetchedAt: Date
    var rating: Rating?
    var isBookmarked: Bool
    var readAt: Date?
    
    // Content-based filtering features
    var keywords: [String]
    var categories: [String]
    var sentiment: Double?  // -1.0 to 1.0
    var relevanceScore: Double  // Calculated by recommendation engine
    
    enum Rating: Int, Codable {
        case negative = -1
        case neutral = 0
        case positive = 1
    }
    
    static let databaseTableName = "articles"
    
    enum Columns: String, ColumnExpression {
        case id, sourceId, title, summary, llmSummary, url, imageUrl
        case author, publishedAt, fetchedAt, rating, isBookmarked, readAt
        case keywords, categories, sentiment, relevanceScore
    }
}

/// Represents a news source (RSS feed, website, person to follow)
struct Source: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String
    var type: SourceType
    var url: String
    var feedUrl: String?  // For RSS sources
    var isActive: Bool
    var ranking: Double  // Learned source quality ranking
    var addedAt: Date
    var lastFetchedAt: Date?
    var fetchIntervalMinutes: Int
    
    enum SourceType: String, Codable {
        case rss = "rss"
        case website = "website"
        case person = "person"  // Individual to follow (Twitter/X, blog, etc.)
        case benchmark = "benchmark"  // AI benchmark tracker
    }
    
    static let databaseTableName = "sources"
    
    enum Columns: String, ColumnExpression {
        case id, name, type, url, feedUrl, isActive
        case ranking, addedAt, lastFetchedAt, fetchIntervalMinutes
    }
}

/// Keyword/tag for categorization
struct Keyword: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String
    var category: String?  // Optional grouping
    var usageCount: Int
    var positiveCount: Int  // Times associated with thumbs up
    var negativeCount: Int  // Times associated with thumbs down
    
    static let databaseTableName = "keywords"
    
    var score: Double {
        guard usageCount > 0 else { return 0.5 }
        return Double(positiveCount) / Double(usageCount)
    }
}

/// User preference learned from interactions
struct UserPreference: Codable, FetchableRecord, PersistableRecord {
    var keyword: String
    var weight: Double  // -1.0 to 1.0, learned over time
    var confidence: Double  // 0.0 to 1.0, increases with more data
    var lastUpdated: Date
    
    static let databaseTableName = "user_preferences"
}

/// AI Benchmark tracking
struct BenchmarkEntry: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var benchmarkName: String  // e.g., "MMLU", "HumanEval", "MATH"
    var modelName: String
    var score: Double
    var date: Date
    var sourceUrl: String?
    var notes: String?
    
    static let databaseTableName = "benchmark_entries"
}

/// Chat message for agent interaction
struct ChatMessage: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var role: Role
    var content: String
    var timestamp: Date
    var relatedArticleId: Int64?
    
    enum Role: String, Codable {
        case user
        case assistant
        case system
    }
    
    static let databaseTableName = "chat_messages"
}
