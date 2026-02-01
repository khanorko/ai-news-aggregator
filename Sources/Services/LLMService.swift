import Foundation
import Alamofire

actor LLMService {
    enum Provider: String {
        case ollama
        case anthropic
        case openai
    }

    private let provider: Provider
    private let anthropicKey: String
    private let openaiKey: String
    private let ollamaBaseURL: String
    private let ollamaModel: String
    private let anthropicURL = "https://api.anthropic.com/v1/messages"
    private let openaiURL = "https://api.openai.com/v1/chat/completions"

    init() {
        // Read settings from UserDefaults
        let defaults = UserDefaults.standard
        let providerString = defaults.string(forKey: "llmProvider") ?? "ollama"
        self.provider = Provider(rawValue: providerString) ?? .ollama
        self.ollamaBaseURL = defaults.string(forKey: "ollamaURL") ?? "http://localhost:11434"
        self.ollamaModel = defaults.string(forKey: "ollamaModel") ?? "llama3.2:3b"
        self.anthropicKey = defaults.string(forKey: "anthropicAPIKey")
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        self.openaiKey = defaults.string(forKey: "openaiAPIKey")
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }

    init(provider: Provider) {
        self.provider = provider
        let defaults = UserDefaults.standard
        self.ollamaBaseURL = defaults.string(forKey: "ollamaURL") ?? "http://localhost:11434"
        self.ollamaModel = defaults.string(forKey: "ollamaModel") ?? "llama3.2:3b"
        self.anthropicKey = defaults.string(forKey: "anthropicAPIKey")
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        self.openaiKey = defaults.string(forKey: "openaiAPIKey")
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }
    
    func summarize(title: String, content: String) async -> String? {
        let articleContent = content.isEmpty ? title : String(content.prefix(2000))
        let prompt = """
        You are a news summarizer. Write a 1-2 sentence summary of this article. Only output the summary, nothing else. Do not ask questions or request more information.

        Title: \(title)
        Content: \(articleContent)

        Summary:
        """

        guard let result = await chat(prompt: prompt, maxTokens: 150) else {
            return nil
        }

        // Clean up the response - remove any conversational prefixes
        let cleaned = result
            .replacingOccurrences(of: "Summary:", with: "")
            .replacingOccurrences(of: "Here is", with: "")
            .replacingOccurrences(of: "Here's", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // If the model still asks for more info, generate a basic summary from title
        if cleaned.contains("no article") || cleaned.contains("please share") || cleaned.contains("Can you") {
            return "Article discusses: \(title)"
        }

        return cleaned
    }
    
    func extractKeywords(title: String, content: String) async -> [String] {
        let articleContent = content.isEmpty ? title : String(content.prefix(1000))
        let prompt = """
        Extract 3-5 keywords from this text. Output ONLY a comma-separated list, nothing else.

        Text: \(title). \(articleContent)

        Keywords:
        """

        guard let response = await chat(prompt: prompt, maxTokens: 50) else {
            // Fallback: extract simple keywords from title
            return extractSimpleKeywords(from: title)
        }

        let keywords = response
            .replacingOccurrences(of: "Keywords:", with: "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count < 30 }

        return keywords.isEmpty ? extractSimpleKeywords(from: title) : Array(keywords.prefix(7))
    }

    private func extractSimpleKeywords(from title: String) -> [String] {
        let stopWords = Set(["the", "a", "an", "is", "are", "was", "were", "it", "its", "in", "on", "at", "to", "for", "of", "and", "or", "but", "with", "by", "from", "as", "be", "this", "that", "these", "those", "how", "what", "why", "when", "where", "who"])
        return Array(title
            .components(separatedBy: CharacterSet.whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters).lowercased() }
            .filter { $0.count > 2 && !stopWords.contains($0) }
            .prefix(5)
            .map { $0.capitalized })
    }
    
    func classifyArticle(title: String, content: String) async -> (categories: [String], sentiment: Double) {
        let prompt = """
        Analyze this AI news article.
        
        Title: \(title)
        Content: \(content.prefix(1000))
        
        Respond in this exact JSON format:
        {
            "categories": ["category1", "category2"],
            "sentiment": 0.5
        }
        
        Categories should be from: research, product, business, policy, tutorial, opinion, benchmark
        Sentiment should be -1.0 (negative) to 1.0 (positive), where 0 is neutral.
        """
        
        guard let response = await chat(prompt: prompt, maxTokens: 100) else {
            return ([], 0.0)
        }
        
        // Parse JSON response
        if let data = response.data(using: .utf8),
           let json = try? JSONDecoder().decode(ClassificationResponse.self, from: data) {
            return (json.categories, json.sentiment)
        }
        
        return ([], 0.0)
    }
    
    func chat(messages: [ChatMessage]) async -> String? {
        let messagePrompt: String = messages.map { msg in
            switch msg.role {
            case .user: return "Human: \(msg.content)"
            case .assistant: return "Assistant: \(msg.content)"
            case .system: return "System: \(msg.content)"
            }
        }.joined(separator: "\n\n")
        
        return await chat(prompt: messagePrompt, maxTokens: 500)
    }
    
    func suggestExplorationSources(currentSources: [Source], preferences: [UserPreference]) async -> [SourceSuggestion] {
        let sourceList = currentSources.map { "\($0.name) (\($0.type.rawValue))" }.joined(separator: ", ")
        let prefList = preferences.prefix(10).map { "\($0.keyword): \($0.weight > 0 ? "likes" : "dislikes")" }.joined(separator: ", ")
        
        let prompt = """
        You are helping break a user out of their AI news filter bubble.
        
        Current sources: \(sourceList)
        User preferences: \(prefList)
        
        Suggest 3 NEW sources that would:
        1. Cover perspectives the user might be missing
        2. Challenge their current viewpoint constructively
        3. Introduce adjacent topics they might find interesting
        
        Respond in JSON format:
        [
            {"name": "Source Name", "url": "https://...", "reason": "Why this would help diversify"},
            ...
        ]
        """
        
        guard let response = await chat(prompt: prompt, maxTokens: 300) else {
            return []
        }
        
        if let data = response.data(using: .utf8),
           let suggestions = try? JSONDecoder().decode([SourceSuggestion].self, from: data) {
            return suggestions
        }
        
        return []
    }
    
    private func chat(prompt: String, maxTokens: Int) async -> String? {
        switch provider {
        case .ollama:
            return await chatOllama(prompt: prompt)
        case .anthropic:
            return await chatAnthropic(prompt: prompt, maxTokens: maxTokens)
        case .openai:
            return await chatOpenAI(prompt: prompt, maxTokens: maxTokens)
        }
    }

    private func chatOllama(prompt: String) async -> String? {
        let url = "\(ollamaBaseURL)/api/generate"
        let body: [String: Any] = [
            "model": ollamaModel,
            "prompt": prompt,
            "stream": false
        ]

        do {
            let response = try await AF.request(
                url,
                method: .post,
                parameters: body,
                encoding: JSONEncoding.default
            ).serializingDecodable(OllamaResponse.self).value

            return response.response
        } catch {
            print("Ollama error: \(error)")
            return nil
        }
    }

    private func chatAnthropic(prompt: String, maxTokens: Int) async -> String? {
        guard !anthropicKey.isEmpty else {
            print("Warning: Anthropic API key not set")
            return nil
        }

        let headers: HTTPHeaders = [
            "x-api-key": anthropicKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        ]

        let body: [String: Any] = [
            "model": "claude-3-haiku-20240307",
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            let response = try await AF.request(
                anthropicURL,
                method: .post,
                parameters: body,
                encoding: JSONEncoding.default,
                headers: headers
            ).serializingDecodable(AnthropicResponse.self).value

            return response.content.first?.text
        } catch {
            print("Anthropic API error: \(error)")
            return nil
        }
    }

    private func chatOpenAI(prompt: String, maxTokens: Int) async -> String? {
        guard !openaiKey.isEmpty else {
            print("Warning: OpenAI API key not set")
            return nil
        }

        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(openaiKey)",
            "Content-Type": "application/json"
        ]

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            let response = try await AF.request(
                openaiURL,
                method: .post,
                parameters: body,
                encoding: JSONEncoding.default,
                headers: headers
            ).serializingDecodable(OpenAIResponse.self).value

            return response.choices.first?.message.content
        } catch {
            print("OpenAI API error: \(error)")
            return nil
        }
    }
}

// MARK: - OpenAI Response

private struct OpenAIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Ollama Response

private struct OllamaResponse: Codable {
    let response: String
}

// MARK: - Response Types

private struct ClassificationResponse: Codable {
    let categories: [String]
    let sentiment: Double
}

struct SourceSuggestion: Codable {
    let name: String
    let url: String
    let reason: String
}

private struct AnthropicResponse: Codable {
    struct Content: Codable {
        let type: String
        let text: String
    }
    let content: [Content]
}
