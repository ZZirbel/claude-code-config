#Requires -Version 5.1
# Check if claude-code-config is up to date with upstream
# Handles four install scenarios: direct clone, fork, renamed clone, plugin
#
# Network calls (git fetch, gh api) are rate-limited to once per hour.
# Writes state to cache file.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$upstreamRepo = "aaronsb/claude-code-config"
$upstreamUrl = "https://github.com/$upstreamRepo"
$upstreamMarker = Join-Path $claudeDir ".claude-upstream"
$cacheFile = Join-Path $env:TEMP ".claude-config-update-state"
$oneHour = 3600
$currentTime = [int][double]::Parse((Get-Date -UFormat %s))

function Test-NeedsRefresh {
    if (-not (Test-Path $cacheFile)) { return $true }
    $content = Get-Content $cacheFile -ErrorAction SilentlyContinue
    $lastFetch = ($content | Where-Object { $_ -match '^fetched=' }) -replace '^fetched=', ''
    if ([string]::IsNullOrEmpty($lastFetch)) { return $true }
    return (($currentTime - [int]$lastFetch) -ge $oneHour)
}

function Write-Cache {
    param([string]$Type, [string]$Behind, [string]$Extra)
    $lines = @("fetched=$currentTime", "type=$Type", "behind=$Behind")
    if ($Extra) { $lines += $Extra }
    $lines | Set-Content $cacheFile -Force -ErrorAction SilentlyContinue
}

function Test-MarkerFile {
    if (-not (Test-Path $upstreamMarker)) { return $false }
    $declared = (Get-Content $upstreamMarker -TotalCount 1 -ErrorAction SilentlyContinue).Trim()
    return ($declared -eq $upstreamRepo)
}

function Test-GhAvailable {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        $script:ghIssue = "gh CLI not installed (needed for fork detection)"
        return $false
    }
    $authOutput = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($authOutput -match 'not logged in') {
            $script:ghIssue = "gh CLI not logged in - run: gh auth login"
        } elseif ($authOutput -match 'token.*expired') {
            $script:ghIssue = "gh auth token expired - run: gh auth refresh"
        } else {
            $script:ghIssue = "gh auth failed: $($authOutput | Select-Object -First 1)"
        }
        return $false
    }
    $script:ghIssue = ""
    return $true
}

# --- Check if it's a git repo ---
$isGitRepo = $false
try {
    git -C $claudeDir rev-parse --git-dir 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $isGitRepo = $true }
} catch {}

if ($isGitRepo) {
    $remoteUrl = git -C $claudeDir remote get-url origin 2>$null

    # Skip non-GitHub remotes
    if ($remoteUrl -notmatch 'github\.com') { exit 0 }

    # Extract owner/repo
    $ownerRepo = $remoteUrl -replace '.*github\.com[:/]', '' -replace '\.git$', ''

    # Validate format
    if ($ownerRepo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { exit 0 }

    if ($ownerRepo -eq $upstreamRepo) {
        # Direct clone
        if (Test-NeedsRefresh) {
            git -C $claudeDir fetch origin --quiet 2>$null
            $behind = git -C $claudeDir rev-list HEAD..origin/main --count 2>$null
            if (-not $behind) { $behind = "0" }
            Write-Cache "clone" $behind
        }
        exit 0
    } else {
        # Possible fork
        if (Test-NeedsRefresh) {
            if (Test-GhAvailable) {
                $ghOutput = gh api "repos/$ownerRepo" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    if ($ghOutput -match '404|not found') {
                        Write-Cache "gh_error" "0" "reason=repo not found on GitHub"
                    } elseif ($ghOutput -match '403|rate limit') {
                        Write-Cache "gh_error" "0" "reason=GitHub API rate limited"
                    } else {
                        Write-Cache "gh_error" "0" "reason=$($ghOutput | Select-Object -First 1)"
                    }
                } else {
                    $parent = ($ghOutput | ConvertFrom-Json).parent.full_name

                    if ($parent -eq $upstreamRepo) {
                        $hasUpstream = $false
                        try {
                            git -C $claudeDir remote get-url upstream 2>$null | Out-Null
                            if ($LASTEXITCODE -eq 0) { $hasUpstream = $true }
                        } catch {}

                        $upstreamHead = (git ls-remote $upstreamUrl refs/heads/main 2>$null) -replace '\t.*', ''
                        $localHead = git -C $claudeDir rev-parse HEAD 2>$null
                        $forkOwner = ($ownerRepo -split '/')[0]

                        if ($upstreamHead -and $upstreamHead -ne $localHead) {
                            Write-Cache "fork" "1" "has_upstream=$hasUpstream`nfork_owner=$forkOwner"
                        } else {
                            Write-Cache "fork" "0" "has_upstream=$hasUpstream`nfork_owner=$forkOwner"
                        }
                    } else {
                        if (Test-MarkerFile) {
                            $hasUpstream = $false
                            try {
                                git -C $claudeDir remote get-url upstream 2>$null | Out-Null
                                if ($LASTEXITCODE -eq 0) { $hasUpstream = $true }
                            } catch {}

                            $upstreamHead = (git ls-remote $upstreamUrl refs/heads/main 2>$null) -replace '\t.*', ''
                            $localHead = git -C $claudeDir rev-parse HEAD 2>$null

                            if ($upstreamHead -and $upstreamHead -ne $localHead) {
                                Write-Cache "renamed_clone" "1" "has_upstream=$hasUpstream"
                            } else {
                                Write-Cache "renamed_clone" "0" "has_upstream=$hasUpstream"
                            }
                        } else {
                            Write-Cache "unrelated" "0"
                        }
                    }
                }
            } else {
                if (Test-MarkerFile) {
                    $hasUpstream = $false
                    try {
                        git -C $claudeDir remote get-url upstream 2>$null | Out-Null
                        if ($LASTEXITCODE -eq 0) { $hasUpstream = $true }
                    } catch {}

                    $upstreamHead = (git ls-remote $upstreamUrl refs/heads/main 2>$null) -replace '\t.*', ''
                    $localHead = git -C $claudeDir rev-parse HEAD 2>$null

                    if ($upstreamHead -and $upstreamHead -ne $localHead) {
                        Write-Cache "renamed_clone" "1" "has_upstream=$hasUpstream"
                    } else {
                        Write-Cache "renamed_clone" "0" "has_upstream=$hasUpstream"
                    }
                } else {
                    Write-Cache "gh_unavailable" "0" "reason=$script:ghIssue"
                }
            }
        }
        exit 0
    }
}

# --- Plugin install (no git repo) ---
if ($env:CLAUDE_PLUGIN_ROOT) {
    $pluginJson = Join-Path $env:CLAUDE_PLUGIN_ROOT ".claude-plugin\plugin.json"
    if (Test-Path $pluginJson) {
        $installedVersion = (Get-Content $pluginJson -Raw | ConvertFrom-Json).version

        if (Test-NeedsRefresh) {
            if (Test-GhAvailable) {
                $latestVersion = (gh api "repos/$upstreamRepo/releases/latest" --jq '.tag_name' 2>$null) -replace '^v', ''
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($latestVersion)) {
                    Write-Cache "plugin" "0" "reason=failed to fetch latest release"
                } elseif ($installedVersion -ne $latestVersion) {
                    Write-Cache "plugin" "1" "installed=$installedVersion`nlatest=$latestVersion"
                } else {
                    Write-Cache "plugin" "0"
                }
            } else {
                Write-Cache "gh_unavailable" "0" "reason=$script:ghIssue"
            }
        }
    }
}
