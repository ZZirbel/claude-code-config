# Claude Code Status Line Script
# Displays model, git branch, token usage, and context percentage

# Configure UTF-8 output encoding for proper emoji display
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try {
    $jsonInput = @($input) -join "`n" | ConvertFrom-Json
} catch {
    Write-Output "Error parsing input: $_"
    exit
}

# Define emojis using character conversion (most compatible)
$paperclip = [System.Char]::ConvertFromUtf32(0x1F4CE)
$hammer = [System.Char]::ConvertFromUtf32(0x1F528)

$fileEmoji = [System.Char]::ConvertFromUtf32(0x1F4C2)

$model = "$paperclip $($jsonInput.model.display_name)"

# Get current directory name
$dirPart = ''
$dir = $jsonInput.workspace.current_dir
if ($dir) {
    $dirName = Split-Path $dir -Leaf
    $dirPart = " | $fileEmoji $dirName"
}

# Get git branch
$branch = ''
try {
    $b = git -C $jsonInput.workspace.current_dir --no-optional-locks rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $b) {
        $branch = " | $hammer $b"
    }
} catch {}

# Get context window usage
$contextPart = ''
$usedPct = $jsonInput.context_window.used_percentage
if ($null -ne $usedPct) {
    $pct = [Math]::Round($usedPct)
    $used = $jsonInput.context_window.current_usage.input_tokens
    $total = $jsonInput.context_window.context_window_size
    if ($used -and $total) {
        $usedK = [Math]::Round($used / 1000)
        $totalK = [Math]::Round($total / 1000)
        $contextPart = " | ctx: ${usedK}k/${totalK}k ($pct%)"
    } else {
        $contextPart = " | ctx: $pct%"
    }
}

# Output model, branch, and context usage
Write-Output "$model$dirPart$branch$contextPart"
