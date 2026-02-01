import SwiftUI

struct ArticleDetailView: View {
    let article: Article
    @EnvironmentObject var appState: AppState
    @State private var llmSummary: String?
    @State private var isLoadingSummary = false
    @State private var fullContent: String?
    @State private var isLoadingContent = false
    @State private var showRawHTML = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 16) {
                    // Categories/Tags
                    if !article.categories.isEmpty || !article.keywords.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(article.categories, id: \.self) { category in
                                    CategoryBadge(text: category.uppercased(), style: .primary)
                                }
                                ForEach(article.keywords.prefix(5), id: \.self) { keyword in
                                    CategoryBadge(text: keyword, style: .secondary)
                                }
                            }
                        }
                    }
                    
                    // Title
                    Text(article.title)
                        .font(.custom("Georgia", size: 32))
                        .fontWeight(.bold)
                        .lineSpacing(4)
                    
                    // Meta info
                    HStack(spacing: 16) {
                        if let author = article.author {
                            HStack(spacing: 4) {
                                Image(systemName: "person")
                                    .font(.system(size: 12))
                                Text(author)
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        if let publishedAt = article.publishedAt {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 12))
                                Text(formatDate(publishedAt))
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        // Relevance score
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 12))
                            Text("Relevance: \(Int(article.relevanceScore * 100))%")
                        }
                        .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .font(.system(size: 13))
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Action Bar
                HStack(spacing: 20) {
                    // Rating buttons
                    HStack(spacing: 12) {
                        RatingButton(
                            icon: "hand.thumbsup",
                            filledIcon: "hand.thumbsup.fill",
                            isSelected: article.rating == .positive,
                            color: .green
                        ) {
                            Task {
                                await appState.thumbsUp(article: article)
                                await appState.refreshSelectedArticle()
                            }
                        }

                        RatingButton(
                            icon: "hand.thumbsdown",
                            filledIcon: "hand.thumbsdown.fill",
                            isSelected: article.rating == .negative,
                            color: .red
                        ) {
                            Task {
                                await appState.thumbsDown(article: article)
                                await appState.refreshSelectedArticle()
                            }
                        }
                    }

                    Divider()
                        .frame(height: 24)

                    // Bookmark
                    RatingButton(
                        icon: "bookmark",
                        filledIcon: "bookmark.fill",
                        isSelected: article.isBookmarked,
                        color: .orange
                    ) {
                        Task {
                            await appState.toggleBookmark(article: article)
                        }
                    }
                    
                    Spacer()
                    
                    // Open in browser
                    Button(action: openInBrowser) {
                        HStack(spacing: 6) {
                            Image(systemName: "safari")
                            Text("Read Original")
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
                
                Divider()
                
                // AI Summary Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        Text("AI Summary")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.purple)
                        
                        Spacer()
                        
                        if isLoadingSummary {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if llmSummary == nil && article.llmSummary == nil {
                            Button("Generate") {
                                Task { await generateSummary() }
                            }
                            .font(.system(size: 12))
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    if let summary = llmSummary ?? article.llmSummary {
                        Text(summary)
                            .font(.system(size: 15))
                            .lineSpacing(6)
                            .padding()
                            .background(Color.purple.opacity(0.05))
                            .cornerRadius(8)
                    }
                }
                
                Divider()
                
                // Original Summary/Content
                VStack(alignment: .leading, spacing: 12) {
                    Text("Article Content")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    if let summary = article.summary {
                        Text(cleanHTML(summary))
                            .font(.custom("Georgia", size: 16))
                            .lineSpacing(8)
                    } else {
                        Text("No preview available. Click 'Read Original' to view the full article.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                
                // Sentiment Analysis
                if let sentiment = article.sentiment {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sentiment Analysis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        SentimentBar(sentiment: sentiment)
                    }
                }
                
                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func openInBrowser() {
        if let url = URL(string: article.url) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func generateSummary() async {
        isLoadingSummary = true
        let service = LLMService()
        if let summary = await service.summarize(
            title: article.title,
            content: article.summary ?? ""
        ) {
            llmSummary = summary
            // Save to database
            await appState.saveLLMSummary(articleId: article.id, summary: summary)
        } else {
            llmSummary = "API key missing. Set ANTHROPIC_API_KEY environment variable."
        }
        isLoadingSummary = false
    }
    
    private func cleanHTML(_ html: String) -> String {
        // Basic HTML tag removal
        var result = html
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Category Badge

struct CategoryBadge: View {
    enum Style {
        case primary
        case secondary
    }
    
    let text: String
    let style: Style
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(style == .primary ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundColor(style == .primary ? .white : .primary)
            .cornerRadius(4)
    }
}

// MARK: - Rating Button

struct RatingButton: View {
    let icon: String
    let filledIcon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? filledIcon : icon)
                .font(.system(size: 18))
                .foregroundColor(isSelected ? color : .secondary)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Sentiment Bar

struct SentimentBar: View {
    let sentiment: Double  // -1.0 to 1.0
    
    private var normalizedPosition: CGFloat {
        CGFloat((sentiment + 1) / 2)  // Convert to 0-1 range
    }
    
    private var sentimentLabel: String {
        if sentiment > 0.3 { return "Positive" }
        if sentiment < -0.3 { return "Negative" }
        return "Neutral"
    }
    
    private var sentimentColor: Color {
        if sentiment > 0.3 { return .green }
        if sentiment < -0.3 { return .red }
        return .gray
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background gradient
                    LinearGradient(
                        colors: [.red.opacity(0.6), .gray.opacity(0.3), .green.opacity(0.6)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 8)
                    .cornerRadius(4)
                    
                    // Position indicator
                    Circle()
                        .fill(sentimentColor)
                        .frame(width: 16, height: 16)
                        .shadow(radius: 2)
                        .offset(x: normalizedPosition * (geometry.size.width - 16))
                }
            }
            .frame(height: 16)
            
            // Labels
            HStack {
                Text("Negative")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.7))
                Spacer()
                Text(sentimentLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(sentimentColor)
                Spacer()
                Text("Positive")
                    .font(.system(size: 10))
                    .foregroundColor(.green.opacity(0.7))
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    ArticleDetailView(article: Article(
        sourceId: 1,
        title: "Claude 3 Opus Surpasses GPT-4 on Complex Reasoning Benchmarks",
        summary: "Anthropic's latest model demonstrates significant improvements in multi-step reasoning and mathematical problem-solving. The model achieves state-of-the-art results on GSM8K, MATH, and other challenging benchmarks while maintaining strong alignment properties.",
        llmSummary: "Claude 3 Opus achieves SOTA on reasoning benchmarks, surpassing GPT-4 on GSM8K and MATH while maintaining alignment.",
        url: "https://example.com/article",
        imageUrl: nil,
        author: "Jane Smith",
        publishedAt: Date(),
        fetchedAt: Date(),
        rating: .positive,
        isBookmarked: true,
        readAt: nil,
        keywords: ["Claude 3", "Anthropic", "benchmarks", "reasoning"],
        categories: ["research", "benchmark"],
        sentiment: 0.6,
        relevanceScore: 0.92
    ))
    .environmentObject(AppState())
    .frame(width: 700, height: 800)
}
