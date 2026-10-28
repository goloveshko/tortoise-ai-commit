<#
.SYNOPSIS
    Dual-mode AI commit message generator for TortoiseGit and CLI.
.DESCRIPTION
    Extracts Git changes, filters out drafts, and queries any OpenAI-compatible
    endpoint (Ollama, LM Studio, OpenAI, OpenRouter) to generate commit messages.
    Supports both TortoiseGit Start-Commit hook integration and standalone terminal usage.
#>

param(
    [string]$PathListFile,
    [string]$MessageFile,
    [string]$CWD,
    [Alias("w", "context")]
    [switch]$FunctionContext,
    [Alias("a", "all")]
    [switch]$IncludeAll,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliFiles
)

# Ensure proper UTF-8 handling for non-ASCII characters and TortoiseGit integration
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Load environment configuration if present
$envFile = Join-Path $PSScriptRoot "environment.ps1"
if (Test-Path $envFile) {
    . $envFile
}

# Resolve active profile if defined
if ($AI_PROFILES -and $AI_ACTIVE_PROFILE -and $AI_PROFILES.ContainsKey($AI_ACTIVE_PROFILE)) {
    $selectedProfile = $AI_PROFILES[$AI_ACTIVE_PROFILE]
    if ($selectedProfile.BaseUrl) { $AI_BASE_URL = $selectedProfile.BaseUrl }
    if ($selectedProfile.Model) { $AI_MODEL = $selectedProfile.Model }
    if ($selectedProfile.ApiKey) { $AI_API_KEY = $selectedProfile.ApiKey }
}

# Apply default fallbacks
if (-not $AI_BASE_URL) { $AI_BASE_URL = "http://localhost:11434/v1" }
if (-not $AI_MODEL) { $AI_MODEL = "qwen2.5-coder:7b" }
if (-not $AI_API_KEY) { $AI_API_KEY = "ollama" }
if (-not $AI_LANGUAGE) { $AI_LANGUAGE = "en" }
if (-not $AI_FORMAT) { $AI_FORMAT = "conventional-body" }
if (-not $AI_EXCLUDE) { $AI_EXCLUDE = @() }
if ($null -eq $AI_EXPAND_CONTEXT) { $AI_EXPAND_CONTEXT = $false }
if ($null -eq $AI_INCLUDE_UNSTAGED) { $AI_INCLUDE_UNSTAGED = $false }
if (-not $AI_TIMEOUT) { $AI_TIMEOUT = 60 }
if (-not $AI_MAX_DIFF_CHARS) { $AI_MAX_DIFF_CHARS = 6000 }
if ($null -eq $AI_TEMPERATURE) { $AI_TEMPERATURE = 0.1 }

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
# 1. Determine which changes to describe
# ------------------------------------------------------------------------------

# Detect if launched by TortoiseGit (TortoiseGit supplies a temporary MessageFile and a valid CWD directory)
$isTortoiseGit = $MessageFile -and $CWD -and (Test-Path $CWD -PathType Container) -and ($PathListFile -and (Test-Path $PathListFile -PathType Leaf))
# In CLI mode, remaining arguments represent user-specified target files
$specifiedFiles = @()
if (-not $isTortoiseGit) {
    $allArgs = @($PathListFile, $MessageFile, $CWD) + $CliFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    # PowerShell binds only single-dash switches, so translate GNU-style flags by hand
    foreach ($arg in $allArgs) {
        switch ($arg) {
            '--context' { $FunctionContext = $true }
            '--all'     { $IncludeAll = $true }
            default     { $specifiedFiles += $arg }
        }
    }

    $MessageFile = $null
    $PathListFile = $null
}

# Determine if context expansion is active (via CLI switch -w or environment config)
$expandContext = $FunctionContext.IsPresent -or ($true -eq $AI_EXPAND_CONTEXT)

# Analyze the whole working tree (unstaged + untracked files) only when explicitly requested
$includeAll = $IncludeAll.IsPresent -or ($true -eq $AI_INCLUDE_UNSTAGED)

# Build arguments array for git diff
$diffArgs = @()
if ($expandContext) {
    $diffArgs += "-W"
}

# Keep non-ASCII paths readable (no octal escaping) for filters and the LLM prompt
$gitCfg = @("-c", "core.quotepath=false")

$targetPaths = @()
if ($PathListFile -and (Test-Path $PathListFile)) {
    $rawPaths = Get-Content $PathListFile | Where-Object { $_.Trim() -ne "" }
    $targetPaths = $rawPaths | Where-Object {
        (Test-Path $_ -PathType Leaf) -or ($_ -ne $CWD -and $_ -ne (Get-Location).Path)
    }
}

# Scope: files named on the command line or selected in Windows Explorer (TortoiseGit)
$scope = @()
if ($specifiedFiles.Count -gt 0) { $scope = $specifiedFiles }
elseif ($targetPaths.Count -gt 0) { $scope = $targetPaths }

# ------------------------------------------------------------------------------
# The Git index is the single source of truth.
# Only staged changes end up in the commit, so only staged changes may be
# described. Files that merely exist in the working directory (untracked) or
# carry unstaged edits are never part of the message unless --all is passed.
# ------------------------------------------------------------------------------
if ($scope.Count -gt 0) {
    $diff = git @gitCfg diff @diffArgs --cached -- $scope
} else {
    $diff = git @gitCfg diff @diffArgs --cached
}

# Opt-in: extend the analysis with unstaged modifications and untracked files
if ($includeAll) {
    $extraSections = @()

    # Unstaged modifications of tracked files (working tree vs index)
    if ($scope.Count -gt 0) {
        $unstagedDiff = git @gitCfg diff @diffArgs -- $scope
    } else {
        $unstagedDiff = git @gitCfg diff @diffArgs
    }
    if ($unstagedDiff) { $extraSections += $unstagedDiff }

    # Untracked files never appear in git diff, so render them against /dev/null
    $repoRoot = (git rev-parse --show-toplevel 2>$null) -replace '/', '\'
    if ($repoRoot) {
        $scopeAbs = @($scope | ForEach-Object {
            $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $_))
            if ($full -like "$repoRoot*") { $full }
        })
        Push-Location $repoRoot
        try {
            $untracked = @(git @gitCfg ls-files --others --exclude-standard -- $scopeAbs)
            $newFileDiffs = foreach ($f in $untracked) {
                git @gitCfg diff --no-index -- "/dev/null" $f
            }
        } finally {
            Pop-Location
        }
        if ($newFileDiffs) { $extraSections += ($newFileDiffs -join "`n") }
    }

    if ($extraSections.Count -gt 0) {
        $extraDiff = ($extraSections -join "`n")
        if ($diff) { $diff = $diff + "`n" + $extraDiff } else { $diff = $extraDiff }
    }
}

if (-not $diff) {
    if (-not $isTortoiseGit) {
        if ($specifiedFiles.Count -gt 0) {
            Write-Host "No staged changes detected in specified files: $($specifiedFiles -join ', ')" -ForegroundColor Yellow
            Write-Host "Stage them first (git add) or add --all to analyze the working tree as well." -ForegroundColor DarkGray
        } else {
            Write-Host "No staged changes detected in repository." -ForegroundColor Yellow
            Write-Host "Stage your changes (git add) or run 'ai-commit --all' to analyze the whole working tree." -ForegroundColor DarkGray
        }
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
        # Check both sides so renames are excluded by their new name too
        $skipCurrentFile = $false
        foreach ($pattern in $AI_EXCLUDE) {
            if ($matches[1] -like $pattern -or $matches[2] -like $pattern) {
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

if ($diffText.Length -gt $AI_MAX_DIFF_CHARS) {
    $diffText = $diffText.Substring(0, $AI_MAX_DIFF_CHARS) + "`n[Diff truncated...]"
}

# ------------------------------------------------------------------------------
# 3. CLI Banner (displayed only when running directly in terminal)
# ------------------------------------------------------------------------------

$isCliMode = [string]::IsNullOrEmpty($MessageFile)

if ($isCliMode) {
    Write-Host "`n  🐢 Tortoise AI Commit" -ForegroundColor Green
    Write-Host "  ────────────────────────────────────────────────────" -ForegroundColor DarkGray
    if ($AI_ACTIVE_PROFILE) {
        Write-Host "  Profile   : " -ForegroundColor DarkGray -NoNewline
        Write-Host $AI_ACTIVE_PROFILE -ForegroundColor Yellow
    }
    Write-Host "  Model     : " -ForegroundColor DarkGray -NoNewline
    Write-Host $AI_MODEL -ForegroundColor Cyan
    Write-Host "  Format    : " -ForegroundColor DarkGray -NoNewline
    Write-Host $AI_FORMAT -ForegroundColor Magenta
    if ($expandContext) {
        Write-Host "  Context   : " -ForegroundColor DarkGray -NoNewline
        Write-Host "Full functions (-W)" -ForegroundColor DarkGreen
    }
    if ($includeAll) {
        Write-Host "  Scope     : " -ForegroundColor DarkGray -NoNewline
        Write-Host "Index + working tree (--all)" -ForegroundColor DarkGreen
    } else {
        Write-Host "  Scope     : " -ForegroundColor DarkGray -NoNewline
        Write-Host "Git index (staged only)" -ForegroundColor DarkGreen
    }
    if ($specifiedFiles.Count -gt 0) {
        Write-Host "  Files     : " -ForegroundColor DarkGray -NoNewline
        Write-Host ($specifiedFiles -join ", ") -ForegroundColor White
    }
    Write-Host "  Endpoint  : " -ForegroundColor DarkGray -NoNewline
    Write-Host $AI_BASE_URL -ForegroundColor DarkGray
    Write-Host "  Language  : " -ForegroundColor DarkGray -NoNewline
    Write-Host $targetLanguage -ForegroundColor Yellow
    Write-Host "  ────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  ⏳ Querying LLM and analyzing diff...`n" -ForegroundColor DarkCyan
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
    $systemPrompt = @"
You are an expert Git commit generator. Follow Conventional Commits (conventional+body).
Output raw text only: subject line max 72 chars, blank line, then bullet points starting with '- '.
$langInstruction
"@
}

# Tell the model which slice of the repository it is looking at, so it never
# describes changes that are not part of the commit
if ($includeAll) {
    $diffLabel = "the full working-tree diff (staged, unstaged and untracked files)"
} else {
    $diffLabel = "the staged diff from the Git index (exactly the changes that will be committed)"
}
$diffLabel += ". Describe only the changes that are visible in this diff; never mention a file or a change that is absent from it."

$payload = @{
    model = $AI_MODEL
    messages = @(
        @{ role = "system"; content = $systemPrompt },
        @{ role = "user"; content = "Here is ${diffLabel}:`n$diffText" }
    )
    temperature = $AI_TEMPERATURE
} | ConvertTo-Json -Depth 5

$headers = @{
    "Authorization" = "Bearer $AI_API_KEY"
    "Content-Type" = "application/json; charset=utf-8"
}

# Start execution timer for CLI output metrics
$timer = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $endpoint = "$($AI_BASE_URL.TrimEnd('/'))/chat/completions"
    $raw = Invoke-WebRequest -Uri $endpoint -Method Post -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec $AI_TIMEOUT -UseBasicParsing

    $timer.Stop()
    $elapsed = [math]::Round($timer.Elapsed.TotalSeconds, 1)

    # Decode the response bytes explicitly: Windows PowerShell 5.1 would
    # otherwise guess ISO-8859-1 and mangle non-ASCII (e.g. Cyrillic) text
    $jsonText = [System.Text.Encoding]::UTF8.GetString($raw.RawContentStream.ToArray())
    $response = $jsonText | ConvertFrom-Json
    $commitMsg = $response.choices[0].message.content.Trim()

    # LLMs love invisible lookalikes (‑ no-break hyphen, nbsp, zero-width spaces)
    # that TortoiseGit renders as empty boxes
    $commitMsg = $commitMsg -replace '[\u2010\u2011\u2012\u2212]', '-'
    $commitMsg = $commitMsg -replace '\u00A0', ' '
    $commitMsg = $commitMsg -replace '[\u200B-\u200D\uFEFF]', ''

    # Strip accidental markdown code blocks
    $commitMsg = $commitMsg -replace '^```[a-zA-Z]*\r?\n', '' -replace '\r?\n```$', ''

    if (-not $isCliMode) {
        # TortoiseGit mode: write to temporary message file (UTF-8 without BOM)
        [System.IO.File]::WriteAllText($MessageFile, $commitMsg, $utf8NoBom)
    } else {
        # Copy to system clipboard automatically
        $copied = $false
        try {
            Set-Clipboard -Value $commitMsg
            $copied = $true
        } catch {}

        # Standalone CLI mode: render clean boxed card
        Write-Host "  ✨ Generated in ${elapsed}s:`n" -ForegroundColor Green
        Write-Host "  ╭── Commit Message ─────────────────────────────────" -ForegroundColor Cyan
        $commitMsg -split "`r?`n" | ForEach-Object {
            Write-Host "  │ " -ForegroundColor Cyan -NoNewline
            Write-Host $_
        }
        Write-Host "  ╰───────────────────────────────────────────────────`n" -ForegroundColor Cyan

        # Bottom hint / clipboard status
        if ($copied) {
            Write-Host "  📋 Copied to clipboard! " -ForegroundColor DarkGreen -NoNewline
            Write-Host "(Tip: Hold Alt to select text without borders)`n" -ForegroundColor DarkGray
        }
    }
} catch {
    $timer.Stop()
    $errMsg = "# [AI Error]: Unable to generate message ($($_.Exception.Message))`n# Check the endpoint ($AI_BASE_URL), the model name and your network or API key.`n"
    if (-not $isCliMode) {
        [System.IO.File]::WriteAllText($MessageFile, $errMsg, $utf8NoBom)
    } else {
        Write-Host "  ❌ Error ($($timer.Elapsed.TotalSeconds.ToString('0.0'))s): $($_.Exception.Message)`n" -ForegroundColor Red
    }
}
