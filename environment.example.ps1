# ==============================================================================
# AI Commit Configuration (Template)
# Rename this file to 'environment.ps1' and adjust settings to your setup.
# Supports any OpenAI-compatible API (Ollama, LM Studio, OpenAI, OpenRouter, etc.)
# ==============================================================================

# --- API Endpoint Configuration ---
# 1. Local Ollama (Default):
$AI_BASE_URL = "http://localhost:11434/v1"
$AI_MODEL    = "qwen2.5-coder:7b"
$AI_API_KEY  = "ollama"  # Dummy key, required by client specification

# 2. Local LM Studio (Alternative local runner):
# $AI_BASE_URL = "http://localhost:1234/v1"
# $AI_MODEL    = "qwen2.5-coder-7b-instruct"
# $AI_API_KEY  = "lm-studio"

# 3. Official OpenAI Cloud API:
# $AI_BASE_URL = "https://api.openai.com/v1"
# $AI_MODEL    = "gpt-4o-mini"
# $AI_API_KEY  = "sk-proj-YOUR_OPENAI_API_KEY_HERE"

# 4. OpenRouter / DeepSeek / Groq (or any OpenAI-compatible gateway):
# $AI_BASE_URL = "https://openrouter.ai/api/v1"
# $AI_MODEL    = "deepseek/deepseek-chat"
# $AI_API_KEY  = "sk-or-YOUR_API_KEY_HERE"

# Target language for commit messages: "en" for English, "ru" for Russian
$AI_LANGUAGE = "en"

# File patterns to exclude from commit diff analysis (drafts, scratchpads, temp logs)
$AI_EXCLUDE = @(
    "*.draft.*",
    "*temp*",
    "notes.txt",
    "todo.md",
    "scratchpad.*"
)