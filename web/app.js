// AI News Aggregator - Web Version
// Credits: Kristoffer Åström (idea), Johan Salo (implementation)

const RSS_FEEDS = [
    { name: 'Hacker News', url: 'https://hnrss.org/frontpage', type: 'rss' },
    { name: 'The Verge AI', url: 'https://www.theverge.com/ai-artificial-intelligence/rss/index.xml', type: 'rss' },
    { name: 'Ars Technica', url: 'https://feeds.arstechnica.com/arstechnica/technology-lab', type: 'rss' },
    { name: 'Last Week in AI', url: 'https://lastweekin.ai/feed', type: 'rss' },
];

const CORS_PROXY = 'https://api.allorigins.win/raw?url=';

let articles = [];
let currentArticle = null;
let settings = {
    provider: localStorage.getItem('llmProvider') || 'groq',
    apiKey: localStorage.getItem('apiKey') || '',
    summaryStyle: localStorage.getItem('summaryStyle') || 'newsletter'
};

// DOM Elements
const articleList = document.getElementById('articleList');
const articleContent = document.getElementById('articleContent');
const articleCount = document.getElementById('articleCount');
const searchInput = document.getElementById('searchInput');
const refreshBtn = document.getElementById('refreshBtn');
const settingsBtn = document.getElementById('settingsBtn');
const settingsModal = document.getElementById('settingsModal');
const closeSettings = document.getElementById('closeSettings');
const saveSettingsBtn = document.getElementById('saveSettings');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    loadSettings();
    loadArticles();
    setupEventListeners();
});

function setupEventListeners() {
    refreshBtn.addEventListener('click', () => loadArticles(true));
    settingsBtn.addEventListener('click', () => settingsModal.classList.add('open'));
    closeSettings.addEventListener('click', () => settingsModal.classList.remove('open'));
    saveSettingsBtn.addEventListener('click', saveSettings);
    searchInput.addEventListener('input', filterArticles);

    document.querySelectorAll('.filter-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
            e.target.classList.add('active');
            filterArticles();
        });
    });

    settingsModal.addEventListener('click', (e) => {
        if (e.target === settingsModal) settingsModal.classList.remove('open');
    });
}

function loadSettings() {
    document.getElementById('llmProvider').value = settings.provider;
    document.getElementById('apiKey').value = settings.apiKey;
    document.getElementById('summaryStyle').value = settings.summaryStyle;
}

function saveSettings() {
    settings.provider = document.getElementById('llmProvider').value;
    settings.apiKey = document.getElementById('apiKey').value;
    settings.summaryStyle = document.getElementById('summaryStyle').value;

    localStorage.setItem('llmProvider', settings.provider);
    localStorage.setItem('apiKey', settings.apiKey);
    localStorage.setItem('summaryStyle', settings.summaryStyle);

    settingsModal.classList.remove('open');
}

async function loadArticles(forceRefresh = false) {
    refreshBtn.classList.add('loading');
    articleList.innerHTML = '<div class="loading">Loading articles...</div>';

    // Try to load from cache first
    const cached = localStorage.getItem('articles');
    const cacheTime = localStorage.getItem('articlesTime');
    const oneHour = 60 * 60 * 1000;

    if (!forceRefresh && cached && cacheTime && (Date.now() - parseInt(cacheTime)) < oneHour) {
        articles = JSON.parse(cached);
        renderArticles();
        refreshBtn.classList.remove('loading');
        return;
    }

    try {
        const allArticles = [];

        for (const feed of RSS_FEEDS) {
            try {
                const feedArticles = await fetchFeed(feed);
                allArticles.push(...feedArticles);
            } catch (e) {
                console.error(`Error fetching ${feed.name}:`, e);
            }
        }

        // Sort by date
        articles = allArticles.sort((a, b) => new Date(b.date) - new Date(a.date));

        // Cache
        localStorage.setItem('articles', JSON.stringify(articles));
        localStorage.setItem('articlesTime', Date.now().toString());

        renderArticles();
    } catch (error) {
        articleList.innerHTML = '<div class="loading">Error loading articles. Try again.</div>';
        console.error(error);
    }

    refreshBtn.classList.remove('loading');
}

async function fetchFeed(feed) {
    const response = await fetch(CORS_PROXY + encodeURIComponent(feed.url));
    const text = await response.text();
    const parser = new DOMParser();
    const xml = parser.parseFromString(text, 'text/xml');

    const items = xml.querySelectorAll('item');
    const articles = [];

    items.forEach((item, index) => {
        if (index >= 15) return; // Limit per feed

        const title = item.querySelector('title')?.textContent || '';
        const link = item.querySelector('link')?.textContent || '';
        const description = item.querySelector('description')?.textContent || '';
        const pubDate = item.querySelector('pubDate')?.textContent || new Date().toISOString();

        // Extract keywords from title
        const keywords = extractKeywords(title);

        articles.push({
            id: btoa(link).slice(0, 20),
            title: cleanHTML(title),
            description: cleanHTML(description).slice(0, 200),
            link,
            date: pubDate,
            source: feed.name,
            keywords,
            summary: null,
            liked: false,
            disliked: false,
            bookmarked: false,
            read: false
        });
    });

    return articles;
}

function extractKeywords(title) {
    const stopWords = new Set(['the', 'a', 'an', 'is', 'are', 'was', 'were', 'it', 'its', 'in', 'on', 'at', 'to', 'for', 'of', 'and', 'or', 'but', 'with', 'by', 'from', 'as', 'be', 'this', 'that', 'how', 'what', 'why', 'when', 'where', 'who']);
    return title
        .split(/\s+/)
        .map(w => w.replace(/[^\w]/g, '').toLowerCase())
        .filter(w => w.length > 2 && !stopWords.has(w))
        .slice(0, 4);
}

function cleanHTML(html) {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    return doc.body.textContent || '';
}

function renderArticles() {
    const filter = document.querySelector('.filter-btn.active')?.dataset.filter || 'all';
    const search = searchInput.value.toLowerCase();

    let filtered = articles;

    if (filter === 'unread') {
        filtered = filtered.filter(a => !a.read);
    } else if (filter === 'bookmarked') {
        filtered = filtered.filter(a => a.bookmarked);
    }

    if (search) {
        filtered = filtered.filter(a =>
            a.title.toLowerCase().includes(search) ||
            a.description.toLowerCase().includes(search)
        );
    }

    articleList.innerHTML = filtered.map(article => `
        <div class="article-item ${article.id === currentArticle?.id ? 'active' : ''}" data-id="${article.id}">
            <h3>${article.title}</h3>
            <p>${article.description}</p>
            <div class="article-tags">
                ${article.keywords.slice(0, 3).map(k => `<span class="tag">${k}</span>`).join('')}
            </div>
            <div class="article-meta">
                <span>${article.source}</span>
                <span>${formatDate(article.date)}</span>
            </div>
        </div>
    `).join('');

    articleCount.textContent = `${filtered.length} articles`;

    // Add click handlers
    document.querySelectorAll('.article-item').forEach(item => {
        item.addEventListener('click', () => {
            const article = articles.find(a => a.id === item.dataset.id);
            if (article) showArticle(article);
        });
    });
}

function filterArticles() {
    renderArticles();
}

function showArticle(article) {
    currentArticle = article;
    article.read = true;

    // Update sidebar
    document.querySelectorAll('.article-item').forEach(item => {
        item.classList.toggle('active', item.dataset.id === article.id);
    });

    articleContent.innerHTML = `
        <div class="article-detail">
            <div class="tags">
                ${article.keywords.map(k => `<span class="tag">${k}</span>`).join('')}
            </div>

            <h1>${article.title}</h1>

            <div class="meta">
                <span>${article.source}</span>
                <span>${formatDate(article.date)}</span>
            </div>

            <div class="article-actions">
                <button class="action-btn ${article.liked ? 'liked' : ''}" onclick="toggleLike('${article.id}')">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="${article.liked ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="2">
                        <path d="M14 9V5a3 3 0 00-3-3l-4 9v11h11.28a2 2 0 002-1.7l1.38-9a2 2 0 00-2-2.3zM7 22H4a2 2 0 01-2-2v-7a2 2 0 012-2h3"/>
                    </svg>
                </button>
                <button class="action-btn ${article.disliked ? 'disliked' : ''}" onclick="toggleDislike('${article.id}')">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="${article.disliked ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="2">
                        <path d="M10 15v4a3 3 0 003 3l4-9V2H5.72a2 2 0 00-2 1.7l-1.38 9a2 2 0 002 2.3zm7-13h2.67A2.31 2.31 0 0122 4v7a2.31 2.31 0 01-2.33 2H17"/>
                    </svg>
                </button>
                <button class="action-btn ${article.bookmarked ? 'bookmarked' : ''}" onclick="toggleBookmark('${article.id}')">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="${article.bookmarked ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="2">
                        <path d="M19 21l-7-5-7 5V5a2 2 0 012-2h10a2 2 0 012 2z"/>
                    </svg>
                </button>
                <div style="flex:1"></div>
                <a href="${article.link}" target="_blank" class="btn-primary">Read Original</a>
            </div>

            <div class="summary-section">
                <h3>
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/>
                    </svg>
                    AI Summary
                </h3>
                <div id="summaryContent">
                    ${article.summary ? `<p>${article.summary}</p>` : `
                        <p style="color: var(--text-secondary)">Click Generate to create an AI summary</p>
                        <button class="btn-primary generate-btn" onclick="generateSummary('${article.id}')">Generate Summary</button>
                    `}
                </div>
            </div>

            <div class="article-body">
                <h4>Article Preview</h4>
                <p>${article.description || 'No preview available. Click "Read Original" to view the full article.'}</p>
            </div>
        </div>
    `;
}

function toggleLike(id) {
    const article = articles.find(a => a.id === id);
    if (article) {
        article.liked = !article.liked;
        if (article.liked) article.disliked = false;
        showArticle(article);
    }
}

function toggleDislike(id) {
    const article = articles.find(a => a.id === id);
    if (article) {
        article.disliked = !article.disliked;
        if (article.disliked) article.liked = false;
        showArticle(article);
    }
}

function toggleBookmark(id) {
    const article = articles.find(a => a.id === id);
    if (article) {
        article.bookmarked = !article.bookmarked;
        showArticle(article);
    }
}

async function generateSummary(id) {
    const article = articles.find(a => a.id === id);
    if (!article) return;

    if (!settings.apiKey) {
        alert('Please set your API key in Settings first.\n\nGet a free Groq API key at console.groq.com');
        settingsModal.classList.add('open');
        return;
    }

    const summaryContent = document.getElementById('summaryContent');
    summaryContent.innerHTML = '<p style="color: var(--text-secondary)">Generating summary...</p>';

    try {
        const prompt = getSummaryPrompt(article);
        const summary = await callLLM(prompt);
        article.summary = summary;
        summaryContent.innerHTML = `<p>${summary}</p>`;
    } catch (error) {
        summaryContent.innerHTML = `<p style="color: #ef4444">Error: ${error.message}</p>
            <button class="btn-primary generate-btn" onclick="generateSummary('${article.id}')">Try Again</button>`;
    }
}

function getSummaryPrompt(article) {
    const prompts = {
        newsletter: `You are an AI news analyst. Summarize this article in 3-4 sentences:
1. What happened (1 sentence)
2. Why it matters (1 sentence)
3. Key takeaway (1-2 sentences)

Title: ${article.title}
Content: ${article.description}

Summary:`,
        tldr: `Write a TL;DR in 1-2 sentences. Be extremely concise.

Title: ${article.title}
Content: ${article.description}

TL;DR:`,
        bullets: `Summarize as 3 bullet points:
• Main point
• Technical detail
• Implication

Title: ${article.title}
Content: ${article.description}

Bullets:`,
        executive: `Write an executive brief in 4 sentences: Context → News → Analysis → Conclusion.

Title: ${article.title}
Content: ${article.description}

Brief:`
    };

    return prompts[settings.summaryStyle] || prompts.newsletter;
}

async function callLLM(prompt) {
    const configs = {
        groq: {
            url: 'https://api.groq.com/openai/v1/chat/completions',
            model: 'llama-3.3-70b-versatile',
            headers: { 'Authorization': `Bearer ${settings.apiKey}` }
        },
        openai: {
            url: 'https://api.openai.com/v1/chat/completions',
            model: 'gpt-4o-mini',
            headers: { 'Authorization': `Bearer ${settings.apiKey}` }
        },
        anthropic: {
            url: 'https://api.anthropic.com/v1/messages',
            model: 'claude-3-haiku-20240307',
            headers: {
                'x-api-key': settings.apiKey,
                'anthropic-version': '2023-06-01'
            }
        }
    };

    const config = configs[settings.provider];

    if (settings.provider === 'anthropic') {
        const response = await fetch(config.url, {
            method: 'POST',
            headers: { ...config.headers, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: config.model,
                max_tokens: 300,
                messages: [{ role: 'user', content: prompt }]
            })
        });
        const data = await response.json();
        if (data.error) throw new Error(data.error.message);
        return data.content[0].text;
    } else {
        const response = await fetch(config.url, {
            method: 'POST',
            headers: { ...config.headers, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: config.model,
                max_tokens: 300,
                messages: [{ role: 'user', content: prompt }]
            })
        });
        const data = await response.json();
        if (data.error) throw new Error(data.error.message || data.error);
        return data.choices[0].message.content;
    }
}

function formatDate(dateStr) {
    const date = new Date(dateStr);
    const now = new Date();
    const diff = now - date;
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));

    if (days === 0) return 'Today';
    if (days === 1) return 'Yesterday';
    if (days < 7) return `${days}d ago`;
    return date.toLocaleDateString();
}
