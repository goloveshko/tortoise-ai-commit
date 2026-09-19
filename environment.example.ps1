# ==============================================================================
# AI Commit Configuration (Template)
# Rename this file to 'environment.ps1' and adjust settings to your setup.
# ==============================================================================

# --- Active Provider Profile ---
# Switch between defined profiles by changing this single variable:
# Available options: "ollama", "lm-studio", "openai", "openrouter"
$AI_ACTIVE_PROFILE = "ollama"

# --- Provider Profiles ---
$AI_PROFILES = @{
    "ollama" = @{
        BaseUrl = "http://localhost:11434/v1"
        Model = "qwen2.5-coder:7b"
        ApiKey = "ollama"
    }
    "lm-studio" = @{
        BaseUrl = "http://localhost:1234/v1"
        Model = "qwen2.5-coder-7b-instruct"
        ApiKey = "lm-studio"
    }
    "openai" = @{
        BaseUrl = "https://api.openai.com/v1"
        Model = "gpt-4o-mini"
        ApiKey = "sk-proj-YOUR_OPENAI_API_KEY_HERE"
    }
    "openrouter" = @{
        BaseUrl = "https://openrouter.ai/api/v1"
        Model = "deepseek/deepseek-chat"
        ApiKey = "sk-or-YOUR_OPENROUTER_API_KEY_HERE"
    }
}

# --- Commit Format Template ---
# Options from prompts/ directory: "conventional-body", "conventional", "gitmoji"
$AI_FORMAT = "conventional-body"

# --- Language Configuration ---
# Supports 2-letter codes (en, ru, de, es, ja, etc.) or full names ("Spanish", "German")
$AI_LANGUAGE = "en"

# --- Exclusion Filter ---
# Patterns to exclude from diff analysis (drafts, notes, temp files)
$AI_EXCLUDE = @(
    "*.draft.*",
    "*temp*",
    "notes.txt",
    "todo.md",
    "scratchpad.*"
)

# Expand diff context to include entire enclosing functions (git diff -W / --function-context).
# Helps the AI understand the scope and purpose of localized changes.
# Can also be toggled on-the-fly via the '-w' CLI flag (e.g. ai-commit -w).
$AI_EXPAND_CONTEXT = $false
