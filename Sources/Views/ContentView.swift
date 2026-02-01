import SwiftUI
import GRDB

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var articles: [Article] = []
    @State private var selectedFilter: ArticleFilter = .all
    @State private var searchText = ""
    @State private var showChat = false
    @State private var showSourceManager = false
    @State private var showSettings = false
    
    enum ArticleFilter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case bookmarked = "Bookmarked"
        case topRated = "Top Rated"
    }
    
    var filteredArticles: [Article] {
        var result = articles
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .unread:
            result = result.filter { $0.readAt == nil }
        case .bookmarked:
            result = result.filter { $0.isBookmarked }
        case .topRated:
            result = result.filter { $0.rating == .positive }
        }
        
        // Apply search
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.summary?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.keywords.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("AI News")
                        .font(.custom("Georgia", size: 28))
                        .fontWeight(.bold)
                    Spacer()

                    Button(action: { Task { await refreshFeeds() } }) {
                        if appState.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.isRefreshing)
                    .help("Refresh feeds (⌘R)")

                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help("Settings (⌘,)")
                }
                .padding()
                
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search articles...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
                
                // Filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ArticleFilter.allCases, id: \.self) { filter in
                            FilterChip(
                                title: filter.rawValue,
                                isSelected: selectedFilter == filter
                            ) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                
                Divider()
                
                // Article List
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredArticles) { article in
                            ArticleRow(article: article)
                                .background(
                                    appState.selectedArticle?.id == article.id ?
                                    Color.accentColor.opacity(0.1) : Color.clear
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    appState.selectedArticle = article
                                }
                        }
                    }
                }
                
                Divider()
                
                // Bottom toolbar
                HStack {
                    Button(action: { showSourceManager = true }) {
                        Label("Sources", systemImage: "list.bullet")
                    }
                    .buttonStyle(.borderless)
                    
                    Spacer()
                    
                    Text("\(filteredArticles.count) articles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { showChat.toggle() }) {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)
            }
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 450)
            
        } detail: {
            // Detail View
            if let article = appState.selectedArticle {
                ArticleDetailView(article: article)
            } else {
                EmptyStateView()
            }
        }
        .sheet(isPresented: $showChat) {
            ChatView()
                .frame(minWidth: 400, minHeight: 500)
        }
        .sheet(isPresented: $showSourceManager) {
            SourceManagerView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showAddSourceSheet) {
            AddSourceSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .task {
            await loadArticles()
        }
        .preferredColorScheme(appState.forceDarkMode ? .dark : nil)
    }
    
    private func loadArticles() async {
        do {
            articles = try await DatabaseManager.shared.fetchArticles(limit: 100)
        } catch {
            print("Error loading articles: \(error)")
        }
    }
    
    private func refreshFeeds() async {
        await appState.refreshAllFeeds()
        await loadArticles()
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Select an article")
                .font(.custom("Georgia", size: 20))
                .foregroundColor(.secondary)
            
            Text("Choose an article from the sidebar to read")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Add Source Sheet

struct AddSourceSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var sourceName = ""
    @State private var sourceUrl = ""
    @State private var sourceType: Source.SourceType = .rss
    @State private var feedUrl = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add News Source")
                .font(.custom("Georgia", size: 24))
                .fontWeight(.bold)
            
            Form {
                TextField("Source Name", text: $sourceName)
                
                Picker("Type", selection: $sourceType) {
                    Text("RSS Feed").tag(Source.SourceType.rss)
                    Text("Website").tag(Source.SourceType.website)
                    Text("Benchmark").tag(Source.SourceType.benchmark)
                }
                
                TextField("URL", text: $sourceUrl)
                    .textContentType(.URL)
                
                if sourceType == .rss {
                    TextField("Feed URL (optional)", text: $feedUrl)
                        .textContentType(.URL)
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Add Source") {
                    Task {
                        await addSource()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sourceName.isEmpty || sourceUrl.isEmpty)
            }
            .padding()
        }
        .frame(width: 400)
        .padding()
    }
    
    private func addSource() async {
        var source = Source(
            name: sourceName,
            type: sourceType,
            url: sourceUrl,
            feedUrl: feedUrl.isEmpty ? nil : feedUrl,
            isActive: true,
            ranking: 0.5,
            addedAt: Date(),
            lastFetchedAt: nil,
            fetchIntervalMinutes: 60
        )
        
        do {
            try await DatabaseManager.shared.saveSource(&source)
        } catch {
            print("Error saving source: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
