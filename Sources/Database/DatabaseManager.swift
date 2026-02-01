import Foundation
import GRDB

actor DatabaseManager {
    static let shared = DatabaseManager()
    
    private var dbQueue: DatabaseQueue!
    
    private init() {
        do {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbFolder = appSupport.appendingPathComponent("AINewsAggregator", isDirectory: true)
            try fileManager.createDirectory(at: dbFolder, withIntermediateDirectories: true)
            
            let dbPath = dbFolder.appendingPathComponent("data.sqlite").path
            dbQueue = try DatabaseQueue(path: dbPath)
            
            try migrator.migrate(dbQueue)
            print("Database initialized at: \(dbPath)")
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            // Sources table
            try db.create(table: "sources") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("url", .text).notNull().unique()
                t.column("feedUrl", .text)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("ranking", .double).notNull().defaults(to: 0.5)
                t.column("addedAt", .datetime).notNull()
                t.column("lastFetchedAt", .datetime)
                t.column("fetchIntervalMinutes", .integer).notNull().defaults(to: 60)
            }
            
            // Articles table
            try db.create(table: "articles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sourceId", .integer).notNull().references("sources", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("summary", .text)
                t.column("llmSummary", .text)
                t.column("url", .text).notNull().unique()
                t.column("imageUrl", .text)
                t.column("author", .text)
                t.column("publishedAt", .datetime)
                t.column("fetchedAt", .datetime).notNull()
                t.column("rating", .integer)
                t.column("isBookmarked", .boolean).notNull().defaults(to: false)
                t.column("readAt", .datetime)
                t.column("keywords", .text).notNull().defaults(to: "[]")  // JSON array
                t.column("categories", .text).notNull().defaults(to: "[]")  // JSON array
                t.column("sentiment", .double)
                t.column("relevanceScore", .double).notNull().defaults(to: 0.5)
            }
            try db.create(index: "articles_publishedAt", on: "articles", columns: ["publishedAt"])
            try db.create(index: "articles_relevanceScore", on: "articles", columns: ["relevanceScore"])
            
            // Keywords table
            try db.create(table: "keywords") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("category", .text)
                t.column("usageCount", .integer).notNull().defaults(to: 0)
                t.column("positiveCount", .integer).notNull().defaults(to: 0)
                t.column("negativeCount", .integer).notNull().defaults(to: 0)
            }
            
            // User preferences table
            try db.create(table: "user_preferences") { t in
                t.column("keyword", .text).primaryKey()
                t.column("weight", .double).notNull().defaults(to: 0.0)
                t.column("confidence", .double).notNull().defaults(to: 0.0)
                t.column("lastUpdated", .datetime).notNull()
            }
            
            // Benchmark entries table
            try db.create(table: "benchmark_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("benchmarkName", .text).notNull()
                t.column("modelName", .text).notNull()
                t.column("score", .double).notNull()
                t.column("date", .datetime).notNull()
                t.column("sourceUrl", .text)
                t.column("notes", .text)
            }
            try db.create(index: "benchmarks_name_model", on: "benchmark_entries", columns: ["benchmarkName", "modelName"])
            
            // Chat messages table
            try db.create(table: "chat_messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("relatedArticleId", .integer).references("articles", onDelete: .setNull)
            }
        }
        
        return migrator
    }
    
    // MARK: - Articles
    
    func fetchArticles(limit: Int = 50, offset: Int = 0) throws -> [Article] {
        try dbQueue.read { db in
            try Article
                .order(Article.Columns.relevanceScore.desc, Article.Columns.publishedAt.desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }
    
    func fetchBookmarkedArticles() throws -> [Article] {
        try dbQueue.read { db in
            try Article
                .filter(Article.Columns.isBookmarked == true)
                .order(Article.Columns.publishedAt.desc)
                .fetchAll(db)
        }
    }
    
    func saveArticle(_ article: inout Article) throws {
        try dbQueue.write { db in
            try article.save(db)
        }
    }
    
    func setArticleRating(_ articleId: Int64?, rating: Article.Rating) async {
        guard let id = articleId else { return }
        try? await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE articles SET rating = ? WHERE id = ?",
                arguments: [rating.rawValue, id]
            )
        }
    }
    
    func toggleBookmark(_ articleId: Int64?) async {
        guard let id = articleId else { return }
        try? await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE articles SET isBookmarked = NOT isBookmarked WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func saveLLMSummary(_ articleId: Int64, summary: String) async {
        try? await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE articles SET llmSummary = ? WHERE id = ?",
                arguments: [summary, articleId]
            )
        }
    }
    
    // MARK: - Sources
    
    func fetchSources() throws -> [Source] {
        try dbQueue.read { db in
            try Source.order(Source.Columns.ranking.desc).fetchAll(db)
        }
    }
    
    func fetchActiveSources() throws -> [Source] {
        try dbQueue.read { db in
            try Source.filter(Source.Columns.isActive == true).fetchAll(db)
        }
    }
    
    func saveSource(_ source: inout Source) throws {
        try dbQueue.write { db in
            try source.save(db)
        }
    }
    
    func updateSourceRanking(_ sourceId: Int64?, delta: Double) async {
        guard let id = sourceId else { return }
        try? await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sources SET ranking = MAX(0, MIN(1, ranking + ?)) WHERE id = ?",
                arguments: [delta, id]
            )
        }
    }
    
    // MARK: - Keywords & Preferences
    
    func updateKeywordStats(keyword: String, isPositive: Bool) async {
        try? await dbQueue.write { db in
            let existing = try Keyword.filter(Column("name") == keyword).fetchOne(db)
            if var kw = existing {
                kw.usageCount += 1
                if isPositive {
                    kw.positiveCount += 1
                } else {
                    kw.negativeCount += 1
                }
                try kw.update(db)
            } else {
                var kw = Keyword(
                    name: keyword,
                    category: nil,
                    usageCount: 1,
                    positiveCount: isPositive ? 1 : 0,
                    negativeCount: isPositive ? 0 : 1
                )
                try kw.insert(db)
            }
        }
    }
    
    func fetchUserPreferences() throws -> [UserPreference] {
        try dbQueue.read { db in
            try UserPreference.fetchAll(db)
        }
    }
    
    // MARK: - Chat
    
    func saveChatMessage(_ message: inout ChatMessage) throws {
        try dbQueue.write { db in
            try message.save(db)
        }
    }
    
    func fetchChatHistory(limit: Int = 100) throws -> [ChatMessage] {
        try dbQueue.read { db in
            try ChatMessage
                .order(Column("timestamp").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
