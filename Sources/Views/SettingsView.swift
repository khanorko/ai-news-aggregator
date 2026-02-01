import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""
    @AppStorage("openaiAPIKey") private var openaiAPIKey = ""
    @AppStorage("refreshInterval") private var refreshInterval = 60
    @AppStorage("maxArticles") private var maxArticles = 500
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("explorationRate") private var explorationRate = 15.0

    var body: some View {
        TabView {
            // General Settings
            GeneralSettingsTab(
                refreshInterval: $refreshInterval,
                maxArticles: $maxArticles,
                enableNotifications: $enableNotifications
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            // LLM Settings
            APISettingsTab(
                anthropicAPIKey: $anthropicAPIKey,
                openaiAPIKey: $openaiAPIKey
            )
            .tabItem {
                Label("LLM", systemImage: "cpu")
            }

            // Summary Settings
            SummarySettingsTab()
            .tabItem {
                Label("Summary", systemImage: "text.quote")
            }
            
            // Recommendations
            RecommendationSettingsTab(explorationRate: $explorationRate)
            .tabItem {
                Label("Recommendations", systemImage: "sparkles")
            }
            
            // Appearance
            AppearanceSettingsTab()
            .tabItem {
                Label("Appearance", systemImage: "paintbrush")
            }
            
            // About
            AboutTab()
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @Binding var refreshInterval: Int
    @Binding var maxArticles: Int
    @Binding var enableNotifications: Bool
    
    var body: some View {
        Form {
            Section {
                Picker("Refresh Interval", selection: $refreshInterval) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                    Text("4 hours").tag(240)
                }
                
                Picker("Max Articles to Keep", selection: $maxArticles) {
                    Text("100").tag(100)
                    Text("250").tag(250)
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                    Text("Unlimited").tag(0)
                }
                
                Toggle("Enable Notifications", isOn: $enableNotifications)
            } header: {
                Text("Feed Settings")
            }
            
            Section {
                HStack {
                    Text("Database Location")
                    Spacer()
                    Text("~/Library/Application Support/AINewsAggregator/")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Button("Clear Database") {
                    // Implement database clearing
                }
                .foregroundColor(.red)
            } header: {
                Text("Storage")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - LLM Settings

struct APISettingsTab: View {
    @Binding var anthropicAPIKey: String
    @Binding var openaiAPIKey: String
    @AppStorage("llmProvider") private var llmProvider = "ollama"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2:3b"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @State private var showAnthropicKey = false
    @State private var showOpenAIKey = false
    @State private var ollamaStatus = "Checking..."
    @State private var availableModels: [String] = []

    var body: some View {
        Form {
            // Active Provider Selection
            Section {
                Picker("LLM Provider", selection: $llmProvider) {
                    HStack {
                        Image(systemName: "desktopcomputer")
                        Text("Ollama (Local)")
                    }.tag("ollama")
                    HStack {
                        Image(systemName: "cloud")
                        Text("Anthropic (Claude)")
                    }.tag("anthropic")
                    HStack {
                        Image(systemName: "cloud")
                        Text("OpenAI (GPT)")
                    }.tag("openai")
                }
                .pickerStyle(.radioGroup)

                if llmProvider == "ollama" {
                    HStack {
                        Circle()
                            .fill(ollamaStatus == "Connected" ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(ollamaStatus)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Active Provider")
            }

            // Ollama Settings
            Section {
                HStack {
                    Text("Server URL")
                    Spacer()
                    TextField("http://localhost:11434", text: $ollamaURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }

                if !availableModels.isEmpty {
                    Picker("Model", selection: $ollamaModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                } else {
                    HStack {
                        Text("Model")
                        Spacer()
                        Text(ollamaModel)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Button("Refresh Models") {
                        Task { await checkOllama() }
                    }
                    Button("Pull New Model") {
                        NSWorkspace.shared.open(URL(string: "https://ollama.com/library")!)
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "desktopcomputer")
                    Text("Ollama (Local - Free)")
                }
            } footer: {
                Text("Run models locally. Install: brew install ollama && ollama pull llama3.2:3b")
            }

            // Anthropic Settings
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if showAnthropicKey {
                            TextField("sk-ant-...", text: $anthropicAPIKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-ant-...", text: $anthropicAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showAnthropicKey.toggle() }) {
                            Image(systemName: showAnthropicKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    Text("Claude Code token works here!")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            } header: {
                HStack {
                    Image(systemName: "cloud")
                    Text("Anthropic (Claude)")
                }
            } footer: {
                Text("Uses Claude 3 Haiku for fast summarization (~$0.25/1M tokens)")
            }

            // OpenAI Settings
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if showOpenAIKey {
                            TextField("sk-...", text: $openaiAPIKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-...", text: $openaiAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showOpenAIKey.toggle() }) {
                            Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "cloud")
                    Text("OpenAI (GPT)")
                }
            } footer: {
                Text("Uses GPT-4o-mini for summarization (~$0.15/1M tokens)")
            }
        }
        .formStyle(.grouped)
        .task {
            await checkOllama()
        }
    }

    private func checkOllama() async {
        do {
            let url = URL(string: "\(ollamaURL)/api/tags")!
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                await MainActor.run {
                    availableModels = models.compactMap { $0["name"] as? String }
                    ollamaStatus = "Connected"
                }
            }
        } catch {
            await MainActor.run {
                ollamaStatus = "Not running"
                availableModels = []
            }
        }
    }
}

// MARK: - Summary Settings

struct SummarySettingsTab: View {
    @AppStorage("summaryStyle") private var summaryStyle = "newsletter"
    @AppStorage("customSummaryPrompt") private var customSummaryPrompt = ""
    @State private var showPromptEditor = false

    static let defaultPrompts: [String: String] = [
        "newsletter": """
            You are an AI news analyst writing for busy tech professionals. Summarize this article in 3-4 sentences using this structure:
            1. WHAT: What happened or what is being discussed (1 sentence)
            2. WHY IT MATTERS: Why this is significant for AI/tech (1 sentence)
            3. KEY INSIGHT: The main takeaway or implication (1-2 sentences)
            Write in a direct, informative style. No fluff. No questions. Just the summary.
            """,
        "tldr": """
            Write a TL;DR summary in 1-2 sentences. Be extremely concise. Capture only the most important point.
            """,
        "sowhat": """
            Summarize this article by first explaining why the reader should care, then the key facts. Start with "This matters because..." Format: 2-3 sentences.
            """,
        "bullets": """
            Summarize this article as 3 bullet points:
            • Main point
            • Technical detail or context
            • Implication for the industry
            Output only the bullet points, nothing else.
            """,
        "executive": """
            Write an executive brief in 4 sentences: Context → News → Analysis → Conclusion. Be professional and insightful.
            """,
        "hottake": """
            Give a brief "hot take" opinion on this article (1 sentence), followed by the key facts (2 sentences). Be opinionated but fair.
            """,
        "custom": ""
    ]

    var body: some View {
        Form {
            Section {
                Picker("Summary Style", selection: $summaryStyle) {
                    HStack {
                        Image(systemName: "newspaper")
                        Text("Newsletter Style (Recommended)")
                    }.tag("newsletter")

                    HStack {
                        Image(systemName: "bolt")
                        Text("TL;DR (Ultra Short)")
                    }.tag("tldr")

                    HStack {
                        Image(systemName: "questionmark.circle")
                        Text("\"So What?\" Format")
                    }.tag("sowhat")

                    HStack {
                        Image(systemName: "list.bullet")
                        Text("Bullet Points")
                    }.tag("bullets")

                    HStack {
                        Image(systemName: "briefcase")
                        Text("Executive Brief")
                    }.tag("executive")

                    HStack {
                        Image(systemName: "flame")
                        Text("Hot Take + Facts")
                    }.tag("hottake")

                    HStack {
                        Image(systemName: "pencil")
                        Text("Custom Prompt")
                    }.tag("custom")
                }
                .pickerStyle(.radioGroup)

                // Preview of current style
                GroupBox {
                    Text(getPromptPreview())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
            } header: {
                Text("Summary Style")
            } footer: {
                Text("Choose how AI summarizes articles. Newsletter style gives structured, scannable summaries.")
            }

            Section {
                Button("Edit Prompt for \"\(styleName(summaryStyle))\"") {
                    if customSummaryPrompt.isEmpty && summaryStyle != "custom" {
                        customSummaryPrompt = Self.defaultPrompts[summaryStyle] ?? ""
                    }
                    showPromptEditor = true
                }

                if summaryStyle != "custom" {
                    Button("Reset to Default") {
                        customSummaryPrompt = ""
                    }
                    .foregroundColor(.orange)
                }
            } header: {
                Text("Customize")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showPromptEditor) {
            PromptEditorSheet(
                prompt: $customSummaryPrompt,
                styleName: styleName(summaryStyle),
                defaultPrompt: Self.defaultPrompts[summaryStyle] ?? ""
            )
        }
    }

    private func styleName(_ style: String) -> String {
        switch style {
        case "newsletter": return "Newsletter"
        case "tldr": return "TL;DR"
        case "sowhat": return "So What?"
        case "bullets": return "Bullets"
        case "executive": return "Executive"
        case "hottake": return "Hot Take"
        case "custom": return "Custom"
        default: return style
        }
    }

    private func getPromptPreview() -> String {
        if !customSummaryPrompt.isEmpty {
            return String(customSummaryPrompt.prefix(200)) + "..."
        }
        return String((Self.defaultPrompts[summaryStyle] ?? "").prefix(200)) + "..."
    }
}

// MARK: - Prompt Editor Sheet

struct PromptEditorSheet: View {
    @Binding var prompt: String
    let styleName: String
    let defaultPrompt: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit \(styleName) Prompt")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            Text("Customize the instruction sent to the LLM. Use {title} and {content} as placeholders.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $prompt)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button("Reset to Default") {
                    prompt = defaultPrompt
                }
                .foregroundColor(.orange)

                Spacer()

                Button("Clear") {
                    prompt = ""
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 500, height: 350)
        .onAppear {
            if prompt.isEmpty {
                prompt = defaultPrompt
            }
        }
    }
}

// MARK: - Recommendation Settings

struct RecommendationSettingsTab: View {
    @Binding var explorationRate: Double
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Exploration Rate")
                        Spacer()
                        Text("\(Int(explorationRate))%")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $explorationRate, in: 5...50, step: 5)
                    
                    Text("Higher values show more diverse content that might be outside your usual interests")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Filter Bubble Prevention")
            }
            
            Section {
                Button("Reset Preferences") {
                    // Implement preference reset
                }
                
                Button("Export Preferences") {
                    // Implement export
                }
            } header: {
                Text("Preference Data")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsTab: View {
    @AppStorage("forceDarkMode") private var forceDarkMode = false
    @AppStorage("fontScale") private var fontScale = 1.0
    @AppStorage("compactMode") private var compactMode = false
    
    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $forceDarkMode) {
                    Text("System").tag(false)
                    Text("Always Dark").tag(true)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Font Scale")
                        Spacer()
                        Text("\(Int(fontScale * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $fontScale, in: 0.8...1.4, step: 0.1)
                }
                
                Toggle("Compact Mode", isOn: $compactMode)
            } header: {
                Text("Display")
            }
            
            Section {
                HStack {
                    Text("Title Font")
                    Spacer()
                    Text("Georgia (Serif)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Body Font")
                    Spacer()
                    Text("SF Pro (Sans-serif)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Typography")
            } footer: {
                Text("Design inspired by BBC/Guardian for comfortable reading")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("AI News Aggregator")
                .font(.custom("Georgia", size: 24))
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Text("A smart news reader that learns your preferences")
                    .font(.system(size: 14))
                
                Text("Built with SwiftUI, GRDB, and Claude AI")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com")!)
                Link("Documentation", destination: URL(string: "https://github.com")!)
            }
            .font(.system(size: 12))
        }
        .padding(40)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
