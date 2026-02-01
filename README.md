# AI News Aggregator 🦞

A native macOS news aggregator for AI/ML news with intelligent recommendations and filter-bubble breaking.

## Credits

- **Kristoffer Åström** – Original idea & architecture. Directed [Moltbot](https://github.com/moltbot/moltbot) via Signal to build the initial version.
- **Johan Salo** – Refinements, LLM integrations (Ollama/Anthropic/OpenAI), and ongoing development in Claude Code.
- **Claude** – AI pair programmer

## Features

- **Smart Feed Curation**: Content-based filtering with exploration/exploitation balance
- **Learning Agent**: Learns from your thumbs up/down feedback (Russell & Norvig architecture)
- **Filter Bubble Breaking**: Problem generator suggests diverse sources outside your comfort zone
- **AI Summarization**: LLM-powered article summaries
- **Benchmark Tracking**: Monitor AI benchmark trends and extrapolations
- **Minimalist UI**: BBC/Guardian-inspired typography, dark mode support
- **Chat Interface**: Talk to an AI agent about your feed preferences

## Architecture

Based on Russell & Norvig's Learning Agent model:

- **Performance Element**: Scores and ranks articles
- **Learning Element**: Updates preferences from feedback
- **Critic**: Evaluates recommendation quality
- **Problem Generator**: Breaks filter bubbles with exploration suggestions

## Tech Stack

- **SwiftUI**: Native macOS interface
- **GRDB**: SQLite database with Swift ORM (easily swappable)
- **FeedKit**: RSS/Atom/JSON feed parsing
- **SwiftSoup**: HTML scraping for websites
- **Alamofire**: Networking
- **Anthropic Claude**: Article summarization and keyword extraction

## Requirements

- macOS 14.0+
- Swift 5.9+
- Anthropic API key (optional, for LLM features)

## Building

```bash
cd ai-news-aggregator
swift build
swift run AINewsAggregator
```

Or open in Xcode:
```bash
open Package.swift
```

## Configuration

Set your Anthropic API key:
```bash
export ANTHROPIC_API_KEY="your-key-here"
```

## Default Sources

The app comes pre-configured with these AI news sources:

- **Research**: arXiv CS.AI, Papers with Code
- **Industry**: The Verge AI, Ars Technica AI
- **Analysis**: AI Snake Oil, The Gradient
- **Benchmarks**: HuggingFace Leaderboard, Papers with Code SOTA

## Usage

1. Launch the app
2. Add sources (RSS feeds, websites, or people to follow)
3. Browse the curated feed
4. 👍/👎 articles to train the recommendation engine
5. Use the Agent chat to refine your preferences
6. Check the Benchmarks tab for AI progress tracking

## License

MIT

---

Built by Weaver 🕸️ for Johan & kstoff
