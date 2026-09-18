# ==============================================================================
# AI Commit Configuration (Template)
# Rename this file to 'environment.ps1' and adjust settings to your setup.
# ==============================================================================

# --- API Endpoint Configuration ---
# Set your Ollama cloud or local endpoint:
$AI_BASE_URL = "http://localhost:11434/v1"

# --- Model Selection ---
# Recommended cloud models:
#   - "nemotron-3-nano:30b" : Fastest inference (3B active params), best for git hooks.
#   - "gpt-oss:20b"         : OpenAI open-weight, excellent code & diff reasoning.
#   - "gemma4:31b"          : Strong multilingual support (recommended for non-English).
#   - "gpt-oss:120b"        : Heavy reasoning model (slower, high quality).
$AI_MODEL = "nemotron-3-nano:30b"

# API key (use "ollama" for local/cloud instances without auth, or paste your bearer token)
$AI_API_KEY = "ollama"

# Target language for commit messages: "ru" (Russian) or "en" (English)
$AI_LANGUAGE = "en"

# File patterns to exclude from commit diff analysis (drafts, scratchpads, temp logs)
$AI_EXCLUDE = @(
    "*.draft.*",
    "*temp*",
    "notes.txt",
    "todo.md",
    "scratchpad.*"
)