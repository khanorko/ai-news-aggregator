import SwiftUI
import SwiftDate

struct ArticleRow: View {
    let article: Article
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(article.title)
                .font(.custom("Georgia", size: 15))
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundColor(article.readAt != nil ? .secondary : .primary)
            
            // Summary preview
            if let summary = article.llmSummary ?? article.summary {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Metadata row
            HStack(spacing: 8) {
                // Keywords
                if !article.keywords.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(article.keywords.prefix(3), id: \.self) { keyword in
                            Text(keyword)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                // Time ago
                if let publishedAt = article.publishedAt {
                    Text(timeAgo(from: publishedAt))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                // Relevance indicator
                RelevanceIndicator(score: article.relevanceScore)
            }
            
            // Action buttons (show on hover)
            if isHovered {
                HStack(spacing: 12) {
                    // Thumbs up
                    Button(action: {
                        Task { await appState.thumbsUp(article: article) }
                    }) {
                        Image(systemName: article.rating == .positive ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .foregroundColor(article.rating == .positive ? .green : .secondary)
                    }
                    .buttonStyle(.borderless)
                    
                    // Thumbs down
                    Button(action: {
                        Task { await appState.thumbsDown(article: article) }
                    }) {
                        Image(systemName: article.rating == .negative ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .foregroundColor(article.rating == .negative ? .red : .secondary)
                    }
                    .buttonStyle(.borderless)
                    
                    Divider()
                        .frame(height: 16)
                    
                    // Bookmark
                    Button(action: {
                        Task { await DatabaseManager.shared.toggleBookmark(article.id) }
                    }) {
                        Image(systemName: article.isBookmarked ? "bookmark.fill" : "bookmark")
                            .foregroundColor(article.isBookmarked ? .orange : .secondary)
                    }
                    .buttonStyle(.borderless)
                    
                    // Open in browser
                    Button(action: {
                        if let url = URL(string: article.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Image(systemName: "safari")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 1 : 0))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Relevance Indicator

struct RelevanceIndicator: View {
    let score: Double
    
    private var color: Color {
        if score > 0.7 { return .green }
        if score > 0.4 { return .orange }
        return .secondary.opacity(0.5)
    }
    
    private var width: CGFloat {
        return CGFloat(score) * 30 + 10
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: width, height: 4)
            .help("Relevance: \(Int(score * 100))%")
    }
}

// MARK: - Article Card (Alternative Grid Layout)

struct ArticleCard: View {
    let article: Article
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image placeholder or actual image
            if let imageUrl = article.imageUrl {
                AsyncImage(url: URL(string: imageUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                }
                .frame(height: 140)
                .clipped()
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(article.title)
                    .font(.custom("Georgia", size: 16))
                    .fontWeight(.semibold)
                    .lineLimit(3)
                
                if let summary = article.llmSummary ?? article.summary {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                
                // Keywords
                FlowLayout(spacing: 4) {
                    ForEach(article.keywords.prefix(4), id: \.self) { keyword in
                        Text(keyword)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Flow Layout for Keywords

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func flowLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            maxY = max(maxY, currentY + size.height)
            currentX += size.width + spacing
        }
        
        return (CGSize(width: maxWidth, height: maxY), positions)
    }
}

#Preview {
    VStack {
        ArticleRow(article: Article(
            sourceId: 1,
            title: "GPT-5 Achieves Human-Level Performance on Complex Reasoning Tasks",
            summary: "OpenAI's latest model demonstrates unprecedented capabilities in multi-step reasoning and shows emergent abilities in scientific discovery.",
            llmSummary: nil,
            url: "https://example.com",
            imageUrl: nil,
            author: "John Doe",
            publishedAt: Date().addingTimeInterval(-3600),
            fetchedAt: Date(),
            rating: nil,
            isBookmarked: false,
            readAt: nil,
            keywords: ["GPT-5", "OpenAI", "reasoning"],
            categories: ["research"],
            sentiment: 0.7,
            relevanceScore: 0.85
        ))
        .environmentObject(AppState())
    }
    .frame(width: 350)
}
