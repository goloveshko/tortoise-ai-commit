<#
.SYNOPSIS
    TortoiseGit Start-Commit Hook script for AI-powered commit messages.
.DESCRIPTION
    Headless hook script that extracts Git changes, filters out drafts,
    and queries an OpenAI-compatible endpoint to generate commit messages.
#>

param(
    [string]$PathListFile,
    [string]$MessageFile,
    [string]$CWD,
    [Parameter(ValueFromRemainingArguments = $true)]
    $ExtraArgs
)

# Ensure proper UTF-8 handling for non-ASCII characters and TortoiseGit integration
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Load environment configuration if present
$envFile = Join-Path $PSScriptRoot "environment.ps1"
if (Test-Path $envFile) {
    . $envFile
}

# Apply default fallbacks
if (-not $AI_BASE_URL) { $AI_BASE_URL = "http://localhost:11434/v1" }
if (-not $AI_MODEL) { $AI_MODEL = "qwen2.5-coder:7b" }
if (-not $AI_API_KEY) { $AI_API_KEY = "ollama" }
if (-not $AI_LANGUAGE) { $AI_LANGUAGE = "ru" }
if (-not $AI_FORMAT) { $AI_FORMAT = "conventional-body" }
if (-not $AI_EXCLUDE) { $AI_EXCLUDE = @() }

# Switch context to the target repository working tree
if ($CWD) { Set-Location $CWD }

# Automatically resolve 2-letter codes (ru -> Russian, de -> German, sv -> Swedish)
try {
    $targetLanguage = [System.Globalization.CultureInfo]::GetCultureInfo($AI_LANGUAGE).EnglishName
} catch {
    # If not an ISO code, use raw value as provided (e.g., "Spanish", "Русский")
    $targetLanguage = $AI_LANGUAGE
}

# ------------------------------------------------------------------------------
# 1. Determine files to include in diff
# ------------------------------------------------------------------------------

$targetPaths = @()
if ($PathListFile -and (Test-Path $PathListFile)) {
    $rawPaths = Get-Content $PathListFile | Where-Object { $_.Trim() -ne "" }
    $targetPaths = $rawPaths | Where-Object {
        (Test-Path $_ -PathType Leaf) -or ($_ -ne $CWD -and $_ -ne (Get-Location).Path)
    }
}

$stagedDiff = git diff --cached
$diff = ""

if ($stagedDiff) {
    $diff = $stagedDiff
} elseif ($targetPaths.Count -gt 0) {
    $diff = git diff HEAD -- $targetPaths
} else {
    $diff = git diff HEAD
}

if (-not $diff) {
    if (-not $MessageFile) {
        Write-Host "No staged or unstaged changes detected." -ForegroundColor Yellow
    }
    exit 0
}

# ------------------------------------------------------------------------------
# 2. Filter out excluded drafts and temp files
# ------------------------------------------------------------------------------

$diffLines = $diff -split "`r?`n"
$filteredDiff = New-Object System.Collections.Generic.List[string]
$skipCurrentFile = $false

foreach ($line in $diffLines) {
    if ($line -match '^diff --git a/(.*) b/(.*)$') {
        $filePath = $matches[1]
        $skipCurrentFile = $false
        foreach ($pattern in $AI_EXCLUDE) {
            if ($filePath -like $pattern) {
                $skipCurrentFile = $true
                break
            }
        }
    }
    if (-not $skipCurrentFile) {
        $filteredDiff.Add($line)
    }
}

$diffText = ($filteredDiff -join "`n").Trim()
if (-not $diffText) { exit 0 }

if ($diffText.Length -gt 6000) {
    $diffText = $diffText.Substring(0, 6000) + "`n[Diff truncated...]"
}


# ------------------------------------------------------------------------------
# 3. CLI Banner (displayed only when running directly in terminal)
# ------------------------------------------------------------------------------

$isCliMode = [string]::IsNullOrEmpty($MessageFile)

if ($isCliMode) {
    Write-Host "`n🐢 Tortoise AI Commit" -ForegroundColor Green
    Write-Host "   Model:    " -NoNewline; Write-Host $AI_MODEL -ForegroundColor Cyan
    Write-Host "   Format:   " -NoNewline; Write-Host $AI_FORMAT -ForegroundColor Magenta
    Write-Host "   Endpoint: " -NoNewline; Write-Host $AI_BASE_URL -ForegroundColor DarkGray
    Write-Host "   Language: " -NoNewline; Write-Host $targetLanguage -ForegroundColor Yellow
    Write-Host "--------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "⏳ Analyzing diff and generating message... Please wait.`n" -ForegroundColor DarkCyan
}

# ------------------------------------------------------------------------------
# 4. Load prompt template
# ------------------------------------------------------------------------------

$langInstruction = "Write the commit message strictly in $targetLanguage."

$promptPath = Join-Path $PSScriptRoot "prompts\$AI_FORMAT.txt"

if (Test-Path $promptPath) {
    $templateContent = Get-Content $promptPath -Raw -Encoding UTF8
    $systemPrompt = $templateContent.Replace("{{LANG_INSTRUCTION}}", $langInstruction)
} else {
    # Fallback prompt in case the selected format file is missing
    $systemPrompt = @"
You are an expert Git commit generator. Follow Conventional Commits (conventional+body).
Output raw text only: subject line max 72 chars, blank line, then bullet points starting with '- '.
$langInstruction
"@
}

$payload = @{
    model = $AI_MODEL
    messages = @(
        @{ role = "system"; content = $systemPrompt },
        @{ role = "user"; content = "Here is the git diff:`n$diffText" }
    )
    temperature = 0.1
} | ConvertTo-Json -Depth 5

$headers = @{
    "Authorization" = "Bearer $AI_API_KEY"
    "Content-Type" = "application/json; charset=utf-8"
}

try {
    $endpoint = "$($AI_BASE_URL.TrimEnd('/'))/chat/completions"
    $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 20

    $commitMsg = $response.choices[0].message.content.Trim()

    # Fix PowerShell 5.1 mojibake bug
    if ($commitMsg -match '[\u0080-\u009F]|Ð|Ñ') {
        try {
            $rawBytes = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetBytes($commitMsg)
            $commitMsg = [System.Text.Encoding]::UTF8.GetString($rawBytes)
        } catch {}
    }

    # Strip accidental markdown code blocks
    $commitMsg = $commitMsg -replace '^```[a-zA-Z]*\r?\n', '' -replace '\r?\n```$', ''

    if (-not $isCliMode) {
        # TortoiseGit mode: write to temporary message file
        [System.IO.File]::WriteAllText($MessageFile, $commitMsg, [System.Text.Encoding]::UTF8)
    } else {
        # Standalone CLI mode: print beautiful output
        Write-Host "✅ Commit message generated successfully:`n" -ForegroundColor Green
        Write-Host "==================================================" -ForegroundColor DarkGray
        Write-Output $commitMsg
        Write-Host "==================================================`n" -ForegroundColor DarkGray
    }
} catch {
    $errMsg = "# [AI Error]: Unable to generate message ($($_.Exception.Message))`n# Please check your Ollama service or network connection.`n"
    if (-not $isCliMode) {
        [System.IO.File]::WriteAllText($MessageFile, $errMsg, [System.Text.Encoding]::UTF8)
    } else {
        Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}
