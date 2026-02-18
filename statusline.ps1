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

$model = "$paperclip $($jsonInput.model.display_name)"

# Get git branch
$branch = ''
try {
    $b = git -C $jsonInput.workspace.current_dir --no-optional-locks rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $b) {
        $branch = " | $hammer $b"
    }
} catch {}

# Output just model and branch
Write-Output "$model$branch"
