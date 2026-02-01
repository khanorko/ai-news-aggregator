import SwiftUI

struct SourceManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [Source] = []
    @State private var selectedSource: Source?
    @State private var showAddSheet = false
    @State private var showDeleteConfirmation = false
    @State private var sourceToDelete: Source?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
        }
        .frame(minWidth: 700, minHeight: 500)
        .task { await loadSources() }
        .sheet(isPresented: $showAddSheet) {
            AddSourceSheet().environmentObject(appState)
        }
        .confirmationDialog("Delete Source?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let source = sourceToDelete {
                    Task { await deleteSource(source) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the source. This cannot be undone.")
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Manage Sources")
                .font(.system(size: 22, weight: .bold, design: .serif))
            Spacer()
            Button(action: { showAddSheet = true }) {
                Label("Add Source", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }
    
    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            ProgressView("Loading sources...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sources.isEmpty {
            emptyView
        } else {
            sourceListView
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Sources Configured")
                .font(.system(size: 20, weight: .semibold, design: .serif))
            Button(action: { showAddSheet = true }) {
                Label("Add Your First Source", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var sourceListView: some View {
        HStack(spacing: 0) {
            List(sources, selection: $selectedSource) { source in
                SourceRowView(source: source)
                    .tag(source)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 280, maxWidth: 350)
            
            Divider()
            
            if let source = selectedSource {
                SourceDetailView(source: source, onDelete: {
                    sourceToDelete = source
                    showDeleteConfirmation = true
                })
            } else {
                Text("Select a source to view details")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func loadSources() async {
        isLoading = true
        do {
            sources = try await DatabaseManager.shared.fetchSources()
        } catch {
            print("Error loading sources: \(error)")
        }
        isLoading = false
    }
    
    private func deleteSource(_ source: Source) async {
        await loadSources()
    }
}

struct SourceRowView: View {
    let source: Source
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(source.isActive ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.system(size: 13, weight: .medium))
                Text(source.url)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(Int(source.ranking * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct SourceDetailView: View {
    let source: Source
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(source.name)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                Spacer()
                if source.isActive {
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }
            
            Divider()
            
            LabeledContent("URL", value: source.url)
            LabeledContent("Type", value: source.type.rawValue.capitalized)
            LabeledContent("Quality Ranking", value: "\(Int(source.ranking * 100))%")
            LabeledContent("Refresh Interval", value: "\(source.fetchIntervalMinutes) minutes")
            
            if let lastFetched = source.lastFetchedAt {
                LabeledContent("Last Fetched") {
                    Text(lastFetched, style: .relative)
                }
            }
            
            Spacer()
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete Source", systemImage: "trash")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    SourceManagerView()
        .environmentObject(AppState())
}
