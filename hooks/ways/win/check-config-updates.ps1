# Check if claude-code-config is up to date with upstream
# Handles four install scenarios: direct clone, fork, renamed clone, plugin
#
# Detection order:
#   1. Is ~/.claude a git repo? If not, exit.
#   2. Is origin aaronsb/claude-code-config? -> direct clone
#   3. Is origin a fork of aaronsb/claude-code-config? -> fork
#   4. Does .claude-upstream marker exist? -> renamed clone
#   5. Is CLAUDE_PLUGIN_ROOT set? -> plugin install
#
# Network calls (git fetch, gh api) are rate-limited to once per hour.

param()

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$upstreamRepo = "aaronsb/claude-code-config"
$upstreamUrl = "https://github.com/$upstreamRepo"
$upstreamMarker = Join-Path $claudeDir ".claude-upstream"
$cacheFile = Join-Path $env:TEMP ".claude-config-update-state-$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name -replace '\\','_')"
$oneHour = 3600
$oneDay = 86400
$currentTime = [int][double]::Parse((Get-Date -UFormat %s))

function Test-NeedsRefresh {
    if (-not (Test-Path $cacheFile)) { return $true }
    $content = Get-Content $cacheFile -Raw -ErrorAction SilentlyContinue
    if ($content -match 'fetched=(\d+)') {
        $lastFetch = [int]$Matches[1]
        return ($currentTime - $lastFetch) -ge $oneHour
    }
    return $true
}

function Write-Cache {
    param([string]$Type, [string]$Behind, [string]$Extra = "")
    $content = @"
fetched=$currentTime
type=$Type
behind=$Behind
$Extra
"@
    Set-Content -Path $cacheFile -Value $content.Trim() -Encoding UTF8
}

function Read-Cache {
    if (-not (Test-Path $cacheFile)) { return $null }
    $content = Get-Content $cacheFile -Raw
    $result = @{}
    if ($content -match 'type=(\w+)') { $result.Type = $Matches[1] }
    if ($content -match 'behind=(\d+)') { $result.Behind = [int]$Matches[1] }
    if ($content -match 'has_upstream=(\w+)') { $result.HasUpstream = $Matches[1] }
    if ($content -match 'fork_owner=(\S+)') { $result.ForkOwner = $Matches[1] }
    return $result
}

function Show-CloneNotice {
    param([int]$Behind)
    Write-Output ""
    Write-Output ([char]0x2501 * 56)
    Write-Output "  Update Available - $Behind commit(s) behind origin/main"
    Write-Output ([char]0x2501 * 56)
    Write-Output ""
    Write-Output "  cd ~/.claude && git pull"
    Write-Output ""
    Write-Output ([char]0x2501 * 56)
    Write-Output ""
}

function Show-ForkNotice {
    param([string]$HasUpstream)
    Write-Output ""
    Write-Output ([char]0x2501 * 56)
    Write-Output "  Update Available - your fork is behind $upstreamRepo"
    Write-Output ([char]0x2501 * 56)
    Write-Output ""
    if ($HasUpstream -ne "true") {
        Write-Output "  git -C ~/.claude remote add upstream $upstreamUrl"
    }
    Write-Output "  cd ~/.claude && git fetch upstream && git merge upstream/main"
    Write-Output ""
    Write-Output ([char]0x2501 * 56)
    Write-Output ""
}

function Test-GhAvailable {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) { return $false }
    try {
        $authStatus = gh auth status 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

# Check if this is a git repo
Push-Location $claudeDir
try {
    $isGitRepo = git rev-parse --git-dir 2>$null
    if (-not $isGitRepo) {
        Pop-Location
        exit 0
    }

    $remoteUrl = git remote get-url origin 2>$null
    if (-not $remoteUrl -or $remoteUrl -notmatch "github\.com") {
        Pop-Location
        exit 0
    }

    # Extract owner/repo
    $ownerRepo = $remoteUrl -replace '.*github\.com[:/]', '' -replace '\.git$', ''

    if ($ownerRepo -eq $upstreamRepo) {
        # Direct clone
        if (Test-NeedsRefresh) {
            git fetch origin --quiet 2>$null
            $behind = git rev-list HEAD..origin/main --count 2>$null
            if (-not $behind) { $behind = "0" }
            Write-Cache -Type "clone" -Behind $behind
        } else {
            $cache = Read-Cache
            $behind = $cache.Behind
        }

        if ([int]$behind -gt 0) {
            Show-CloneNotice -Behind $behind
        }
    } else {
        # Possible fork
        if (Test-NeedsRefresh) {
            if (Test-GhAvailable) {
                try {
                    $ghOutput = gh api "repos/$ownerRepo" 2>$null | ConvertFrom-Json
                    $parent = $ghOutput.parent.full_name

                    if ($parent -eq $upstreamRepo) {
                        $hasUpstream = (git remote get-url upstream 2>$null) -ne $null

                        $upstreamHead = git ls-remote $upstreamUrl refs/heads/main 2>$null
                        $upstreamHead = ($upstreamHead -split '\s')[0]
                        $localHead = git rev-parse HEAD 2>$null

                        if ($upstreamHead -and $upstreamHead -ne $localHead) {
                            Write-Cache -Type "fork" -Behind "1" -Extra "has_upstream=$hasUpstream"
                        } else {
                            Write-Cache -Type "fork" -Behind "0" -Extra "has_upstream=$hasUpstream"
                        }
                    } else {
                        Write-Cache -Type "unrelated" -Behind "0"
                    }
                } catch {
                    Write-Cache -Type "gh_error" -Behind "0"
                }
            } else {
                Write-Cache -Type "gh_unavailable" -Behind "0"
            }
        }

        $cache = Read-Cache
        if ($cache.Type -eq "fork" -and [int]$cache.Behind -gt 0) {
            Show-ForkNotice -HasUpstream $cache.HasUpstream
        }
    }
} finally {
    Pop-Location
}
