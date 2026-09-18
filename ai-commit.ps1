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
if (-not $AI_MODEL)    { $AI_MODEL    = "qwen2.5-coder:7b" }
if (-not $AI_API_KEY)  { $AI_API_KEY  = "ollama" }
if (-not $AI_LANGUAGE) { $AI_LANGUAGE = "ru" }
if (-not $AI_EXCLUDE)  { $AI_EXCLUDE  = @() }

# Switch context to the target repository working tree
if ($CWD) { Set-Location $CWD }

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

if (-not $diff) { exit 0 }

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
# 3. Generate commit message via AI
# ------------------------------------------------------------------------------

$langInstruction = if ($AI_LANGUAGE -eq "ru") { 
    "Write the commit message strictly in Russian." 
} else { 
    "Write the commit message strictly in English." 
}

# Strict few-shot prompt forcing dashes (-) for bullet points
$systemPrompt = @"
You are an expert Git commit generator.
Strict rules:
1. Format: conventional+body
   - Line 1: <type>(<optional-scope>): <imperative short summary max 72 chars>
   - Line 2: MUST BE COMPLETELY EMPTY
   - Line 3+: Bullet list explaining key changes. EVERY bullet point MUST begin with a dash and a space: "- ".
2. DO NOT use asterisks (*), numbers, or introductory paragraphs.
3. $langInstruction
4. Output raw text ONLY. No markdown fences (no ```), no conversational intros.

Example output format:
feat(auth): implement refresh token rotation

- Add refreshToken endpoint to authentication router
- Store hash in Redis with a 7-day expiration
- Revoke existing tokens upon password reset
"@

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
    "Content-Type"  = "application/json; charset=utf-8"
}

try {
    $endpoint = "$($AI_BASE_URL.TrimEnd('/'))/chat/completions"
    $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 20
    
    $commitMsg = $response.choices[0].message.content.Trim()

    # Fix PowerShell 5.1 mojibake bug (decoding UTF-8 as Latin-1 when charset header is missing)
    if ($commitMsg -match '[\u0080-\u009F]|Ð|Ñ') {
        try {
            $rawBytes = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetBytes($commitMsg)
            $commitMsg = [System.Text.Encoding]::UTF8.GetString($rawBytes)
        } catch {}
    }
    
    # Strip accidental markdown code blocks
    $commitMsg = $commitMsg -replace '^```[a-zA-Z]*\r?\n', '' -replace '\r?\n```$', ''
    
    # Write to TortoiseGit message file
    [System.IO.File]::WriteAllText($MessageFile, $commitMsg, [System.Text.Encoding]::UTF8)
} catch {
    # On failure, inform user directly inside the commit message area
    $errMsg = "# [AI Error]: Unable to generate message ($($_.Exception.Message))`n# Please check your Ollama service or network connection.`n"
    [System.IO.File]::WriteAllText($MessageFile, $errMsg, [System.Text.Encoding]::UTF8)
} finally {
    exit 0
}