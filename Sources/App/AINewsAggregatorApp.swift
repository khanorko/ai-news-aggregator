import SwiftUI

@main
struct AINewsAggregatorApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Sources") {
                Button("Add RSS Feed...") {
                    appState.showAddSourceSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Manage Sources...") {
                    appState.showSourceManager = true
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                Button("Refresh Feed") {
                    Task { await appState.refreshAllFeeds() }
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Toggle("Dark Mode", isOn: $appState.forceDarkMode)
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var showAddSourceSheet = false
    @Published var showSourceManager = false
    @Published var forceDarkMode = false
    @Published var selectedArticle: Article?
    @Published var isRefreshing = false
    @Published var articles: [Article] = []
    
    private let database: DatabaseManager
    private let feedService: FeedService
    private let llmService: LLMService
    private let recommendationEngine: RecommendationEngine
    private let benchmarkService: BenchmarkService
    
    init() {
        self.database = DatabaseManager.shared
        self.feedService = FeedService(database: database)
        self.llmService = LLMService()
        self.recommendationEngine = RecommendationEngine(database: database)
        self.benchmarkService = BenchmarkService(database: database)
        
        // Add default sources on first launch
        Task {
            await addDefaultSourcesIfNeeded()
        }
    }
    
    func refreshAllFeeds() async {
        isRefreshing = true
        await feedService.refreshAllFeeds()
        await benchmarkService.fetchAllBenchmarks()
        isRefreshing = false
    }
    
    func thumbsUp(article: Article) async {
        await database.setArticleRating(article.id, rating: .positive)
        await recommendationEngine.processPositiveFeedback(for: article)
    }
    
    func thumbsDown(article: Article) async {
        await database.setArticleRating(article.id, rating: .negative)
        await recommendationEngine.processNegativeFeedback(for: article)
    }

    func toggleBookmark(article: Article) async {
        await database.toggleBookmark(article.id)
        await refreshSelectedArticle()
    }

    func refreshSelectedArticle() async {
        guard let current = selectedArticle, let id = current.id else { return }
        do {
            let articles = try await database.fetchArticles(limit: 1000)
            if let updated = articles.first(where: { $0.id == id }) {
                selectedArticle = updated
            }
        } catch {
            print("Error refreshing article: \(error)")
        }
    }

    func saveLLMSummary(articleId: Int64?, summary: String) async {
        guard let id = articleId else { return }
        await database.saveLLMSummary(id, summary: summary)
    }
    
    private func addDefaultSourcesIfNeeded() async {
        do {
            let sources = try await database.fetchSources()
            if sources.isEmpty {
                // Add default AI news sources
                let defaultSources: [(String, String, String?, Source.SourceType)] = [
                    ("Hacker News", "https://news.ycombinator.com", "https://news.ycombinator.com/rss", .rss),
                    ("The Verge AI", "https://www.theverge.com/ai-artificial-intelligence", "https://www.theverge.com/ai-artificial-intelligence/rss/index.xml", .rss),
                    ("Ars Technica AI", "https://arstechnica.com/ai/", "https://feeds.arstechnica.com/arstechnica/technology-lab", .rss),
                    ("MIT Tech Review AI", "https://www.technologyreview.com/topic/artificial-intelligence/", "https://www.technologyreview.com/topic/artificial-intelligence/feed", .rss),
                    ("Papers with Code", "https://paperswithcode.com", nil, .benchmark),
                ]
                
                for (name, url, feedUrl, type) in defaultSources {
                    var source = Source(
                        name: name,
                        type: type,
                        url: url,
                        feedUrl: feedUrl,
                        isActive: true,
                        ranking: 0.5,
                        addedAt: Date(),
                        lastFetchedAt: nil,
                        fetchIntervalMinutes: 60
                    )
                    try await database.saveSource(&source)
                }
                print("Added default sources")
            }
        } catch {
            print("Error checking/adding default sources: \(error)")
        }
    }
}
