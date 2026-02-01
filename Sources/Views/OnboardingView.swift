import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0
    @State private var ollamaStatus: OllamaStatus = .checking
    @State private var downloadProgress: Double = 0
    @State private var statusMessage = "Checking system..."
    @State private var isInstalling = false

    enum OllamaStatus {
        case checking
        case notInstalled
        case installed
        case modelMissing
        case ready
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<4) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            Spacer()

            // Content based on step
            Group {
                switch currentStep {
                case 0:
                    WelcomeStep()
                case 1:
                    LLMSetupStep(
                        status: ollamaStatus,
                        progress: downloadProgress,
                        message: statusMessage,
                        isInstalling: isInstalling,
                        onInstall: installOllama,
                        onSkip: { currentStep = 2 }
                    )
                case 2:
                    SourcesStep()
                case 3:
                    ReadyStep()
                default:
                    EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 && currentStep < 3 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if currentStep < 3 {
                    Button(currentStep == 0 ? "Get Started" : "Continue") {
                        withAnimation { currentStep += 1 }
                        if currentStep == 1 {
                            Task { await checkOllamaStatus() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == 1 && isInstalling)
                } else {
                    Button("Start Reading") {
                        hasCompletedOnboarding = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(30)
        }
        .frame(width: 600, height: 500)
    }

    private func checkOllamaStatus() async {
        statusMessage = "Checking for Ollama..."
        ollamaStatus = .checking

        // Check if ollama command exists
        let ollamaPath = "/opt/homebrew/bin/ollama"
        let ollamaExists = FileManager.default.fileExists(atPath: ollamaPath)

        if !ollamaExists {
            // Also check /usr/local/bin for Intel Macs
            let ollamaPathIntel = "/usr/local/bin/ollama"
            if !FileManager.default.fileExists(atPath: ollamaPathIntel) {
                await MainActor.run {
                    ollamaStatus = .notInstalled
                    statusMessage = "Ollama not found. Click Install to set it up."
                }
                return
            }
        }

        // Check if Ollama server is running
        do {
            let url = URL(string: "http://localhost:11434/api/tags")!
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let hasLlama = models.contains { ($0["name"] as? String)?.contains("llama") == true }
                await MainActor.run {
                    if hasLlama {
                        ollamaStatus = .ready
                        statusMessage = "Ollama is ready with Llama!"
                    } else {
                        ollamaStatus = .modelMissing
                        statusMessage = "Ollama installed but Llama model missing."
                    }
                }
            }
        } catch {
            await MainActor.run {
                ollamaStatus = .installed
                statusMessage = "Ollama installed but not running. Starting..."
            }
            // Try to start Ollama
            await startOllamaService()
        }
    }

    private func startOllamaService() async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", "brew services start ollama"]
        try? task.run()
        task.waitUntilExit()

        // Wait a moment for service to start
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await checkOllamaStatus()
    }

    private func installOllama() {
        isInstalling = true
        statusMessage = "Installing Ollama via Homebrew..."
        downloadProgress = 0.1

        Task {
            // Step 1: Install Ollama
            await runCommand("brew install ollama", progress: 0.3)

            // Step 2: Start Ollama service
            await MainActor.run {
                statusMessage = "Starting Ollama service..."
                downloadProgress = 0.5
            }
            await runCommand("brew services start ollama", progress: 0.6)

            // Wait for service
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            // Step 3: Pull Llama model
            await MainActor.run {
                statusMessage = "Downloading Llama 3.2 (2GB)... This may take a few minutes."
                downloadProgress = 0.7
            }
            await runCommand("ollama pull llama3.2:3b", progress: 0.95)

            // Done
            await MainActor.run {
                downloadProgress = 1.0
                statusMessage = "Installation complete!"
                isInstalling = false
                ollamaStatus = .ready
            }
        }
    }

    private func runCommand(_ command: String, progress: Double) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        task.environment = ProcessInfo.processInfo.environment
        task.environment?["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (task.environment?["PATH"] ?? "")

        do {
            try task.run()
            task.waitUntilExit()
            await MainActor.run {
                downloadProgress = progress
            }
        } catch {
            await MainActor.run {
                ollamaStatus = .error("Failed to run: \(command)")
                statusMessage = "Error: \(error.localizedDescription)"
                isInstalling = false
            }
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Welcome to AI News")
                .font(.custom("Georgia", size: 32))
                .fontWeight(.bold)

            Text("Your intelligent AI/ML news aggregator with\nlocal LLM-powered summaries")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "cpu", text: "Runs locally with Llama 3.2 - no API costs")
                FeatureRow(icon: "hand.thumbsup", text: "Learns your preferences over time")
                FeatureRow(icon: "sparkles", text: "AI-powered article summaries")
                FeatureRow(icon: "globe", text: "RSS feeds from top AI sources")
            }
            .padding(.top, 20)
        }
        .padding(40)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.system(size: 14))
        }
    }
}

// MARK: - LLM Setup Step

struct LLMSetupStep: View {
    let status: OnboardingView.OllamaStatus
    let progress: Double
    let message: String
    let isInstalling: Bool
    let onInstall: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: statusIcon)
                .font(.system(size: 60))
                .foregroundColor(statusColor)

            Text("Local AI Setup")
                .font(.custom("Georgia", size: 28))
                .fontWeight(.bold)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if isInstalling {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 300)

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 10)
            }

            // Action buttons based on status
            switch status {
            case .notInstalled, .modelMissing:
                VStack(spacing: 12) {
                    Button(action: onInstall) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Install Ollama + Llama 3.2")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isInstalling)

                    Button("Skip (use cloud API instead)") {
                        onSkip()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
            case .ready:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Ready to go!")
                        .foregroundColor(.green)
                }
                .font(.system(size: 16, weight: .medium))
            case .error(let msg):
                Text(msg)
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            default:
                ProgressView()
            }

            // Info box
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why local AI?")
                        .font(.system(size: 12, weight: .semibold))
                    Text("• Free - no API costs\n• Private - data stays on your Mac\n• Fast - no network latency\n• Works offline")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 300)
        }
        .padding(40)
    }

    private var statusIcon: String {
        switch status {
        case .checking: return "magnifyingglass"
        case .notInstalled: return "arrow.down.circle"
        case .installed: return "checkmark.circle"
        case .modelMissing: return "exclamationmark.triangle"
        case .ready: return "checkmark.seal.fill"
        case .error: return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .ready: return .green
        case .error: return .red
        case .notInstalled, .modelMissing: return .orange
        default: return .accentColor
        }
    }
}

// MARK: - Sources Step

struct SourcesStep: View {
    @AppStorage("includeHackerNews") private var includeHackerNews = true
    @AppStorage("includeVerge") private var includeVerge = true
    @AppStorage("includeArsTechnica") private var includeArsTechnica = true
    @AppStorage("includeMIT") private var includeMIT = true
    @AppStorage("includeLastWeekAI") private var includeLastWeekAI = true

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("Choose Your Sources")
                .font(.custom("Georgia", size: 28))
                .fontWeight(.bold)

            Text("Select which AI news sources to follow")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Hacker News", isOn: $includeHackerNews)
                Toggle("The Verge AI", isOn: $includeVerge)
                Toggle("Ars Technica", isOn: $includeArsTechnica)
                Toggle("MIT Tech Review AI", isOn: $includeMIT)
                Toggle("Last Week in AI", isOn: $includeLastWeekAI)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .frame(width: 300)

            Text("You can add more sources later in Settings")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}

// MARK: - Ready Step

struct ReadyStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.custom("Georgia", size: 32))
                .fontWeight(.bold)

            Text("AI News is ready to keep you informed")
                .font(.system(size: 16))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "keyboard")
                        .frame(width: 24)
                    Text("⌘R to refresh feeds")
                }
                HStack {
                    Image(systemName: "hand.thumbsup")
                        .frame(width: 24)
                    Text("👍/👎 to train recommendations")
                }
                HStack {
                    Image(systemName: "sparkles")
                        .frame(width: 24)
                    Text("Click 'Generate' for AI summaries")
                }
            }
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .padding(.top, 20)
        }
        .padding(40)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
