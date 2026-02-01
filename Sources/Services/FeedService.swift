import Foundation
import FeedKit
import SwiftSoup
import Alamofire

actor FeedService {
    private let database: DatabaseManager
    private let llmService = LLMService()
    
    init(database: DatabaseManager) {
        self.database = database
    }
    
    func refreshAllFeeds() async {
        do {
            let sources = try await database.fetchActiveSources()
            await withTaskGroup(of: Void.self) { group in
                for source in sources {
                    group.addTask {
                        await self.refreshSource(source)
                    }
                }
            }
        } catch {
            print("Error fetching sources: \(error)")
        }
    }
    
    func refreshSource(_ source: Source) async {
        switch source.type {
        case .rss:
            await refreshRSSFeed(source)
        case .website:
            await scrapeWebsite(source)
        case .person:
            await fetchPersonUpdates(source)
        case .benchmark:
            await fetchBenchmarkUpdates(source)
        }
    }
    
    private func refreshRSSFeed(_ source: Source) async {
        let feedUrlString = source.feedUrl ?? source.url
        guard let url = URL(string: feedUrlString) else { return }
        
        let parser = FeedParser(URL: url)
        let result = await withCheckedContinuation { continuation in
            parser.parseAsync { result in
                continuation.resume(returning: result)
            }
        }
        
        switch result {
        case .success(let feed):
            await processFeed(feed, source: source)
        case .failure(let error):
            print("RSS fetch error for \(source.name): \(error)")
        }
    }
    
    private func processFeed(_ feed: Feed, source: Source) async {
        let items: [(title: String, link: String, description: String?, date: Date?, author: String?)]
        
        switch feed {
        case .atom(let atomFeed):
            items = atomFeed.entries?.compactMap { entry in
                guard let title = entry.title, let link = entry.links?.first?.attributes?.href else { return nil }
                return (title, link, entry.summary?.value, entry.published ?? entry.updated, entry.authors?.first?.name)
            } ?? []
        case .rss(let rssFeed):
            items = rssFeed.items?.compactMap { item in
                guard let title = item.title, let link = item.link else { return nil }
                return (title, link, item.description, item.pubDate, item.author)
            } ?? []
        case .json(let jsonFeed):
            items = jsonFeed.items?.compactMap { item in
                guard let title = item.title, let link = item.url else { return nil }
                return (title, link, item.summary, item.datePublished, item.author?.name)
            } ?? []
        }
        
        for item in items.prefix(20) {  // Limit to 20 most recent
            await processArticle(
                title: item.title,
                url: item.link,
                summary: item.description,
                publishedAt: item.date,
                author: item.author,
                source: source
            )
        }
    }
    
    private func scrapeWebsite(_ source: Source) async {
        guard let url = URL(string: source.url) else { return }
        
        do {
            let html = try await AF.request(url).serializingString().value
            let doc = try SwiftSoup.parse(html)
            
            // Try common article selectors
            let selectors = ["article", ".post", ".article", ".news-item", "[class*='article']"]
            
            for selector in selectors {
                let elements = try doc.select(selector)
                if !elements.isEmpty() {
                    for element in elements.prefix(10) {
                        if let title = try? element.select("h1, h2, h3, .title").first()?.text(),
                           let link = try? element.select("a").first()?.attr("href") {
                            let absoluteUrl = link.hasPrefix("http") ? link : source.url + link
                            let summary = try? element.select("p, .summary, .excerpt").first()?.text()
                            
                            await processArticle(
                                title: title,
                                url: absoluteUrl,
                                summary: summary,
                                publishedAt: nil,
                                author: nil,
                                source: source
                            )
                        }
                    }
                    break
                }
            }
        } catch {
            print("Scraping error for \(source.name): \(error)")
        }
    }
    
    private func fetchPersonUpdates(_ source: Source) async {
        // TODO: Implement social media / blog fetching
        // This would integrate with Twitter API, RSS for blogs, etc.
    }
    
    private func fetchBenchmarkUpdates(_ source: Source) async {
        // TODO: Implement benchmark scraping
        // Sources like Papers with Code, HuggingFace leaderboards, etc.
    }
    
    private func processArticle(
        title: String,
        url: String,
        summary: String?,
        publishedAt: Date?,
        author: String?,
        source: Source
    ) async {
        // Generate LLM summary if original is missing or too long
        let llmSummary: String?
        if summary == nil || (summary?.count ?? 0) > 300 {
            llmSummary = await llmService.summarize(title: title, content: summary ?? "")
        } else {
            llmSummary = nil
        }
        
        // Extract keywords using LLM
        let keywords = await llmService.extractKeywords(title: title, content: summary ?? "")
        
        // Calculate initial relevance score
        let relevanceScore = await calculateRelevance(keywords: keywords, sourceRanking: source.ranking)
        
        var article = Article(
            sourceId: source.id ?? 0,
            title: title,
            summary: summary,
            llmSummary: llmSummary,
            url: url,
            imageUrl: nil,
            author: author,
            publishedAt: publishedAt,
            fetchedAt: Date(),
            rating: nil,
            isBookmarked: false,
            readAt: nil,
            keywords: keywords,
            categories: [],
            sentiment: nil,
            relevanceScore: relevanceScore
        )
        
        do {
            try await database.saveArticle(&article)
        } catch {
            // URL probably already exists, which is fine
            print("Could not save article: \(error)")
        }
    }
    
    private func calculateRelevance(keywords: [String], sourceRanking: Double) async -> Double {
        // Base score from source ranking
        var score = sourceRanking * 0.3
        
        // Add keyword preference weights
        do {
            let preferences = try await database.fetchUserPreferences()
            let prefDict = Dictionary(uniqueKeysWithValues: preferences.map { ($0.keyword.lowercased(), $0.weight) })
            
            for keyword in keywords {
                if let weight = prefDict[keyword.lowercased()] {
                    score += weight * 0.1
                }
            }
        } catch {
            // Continue with base score
        }
        
        // Normalize to 0-1 range
        return max(0, min(1, score + 0.5))
    }
}
