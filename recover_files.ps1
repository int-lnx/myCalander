$transcriptPath = "C:\Users\deneme\.gemini\antigravity-ide\brain\5d4606f9-fd46-4833-a99e-ac23811a54e1\.system_generated\logs\transcript_full.jsonl"
$projectRoot = "C:\Users\deneme\Desktop\Flutter-Deneme\1_deneme\my_plan"

$targetFiles = @(
    "lib/models/task_item.dart",
    "lib/main.dart",
    "lib/screens/plan_screen.dart",
    "lib/screens/plan_form_screen.dart",
    "lib/screens/project_details_screen.dart",
    "lib/screens/settings_screen.dart",
    "lib/screens/event_form_screen.dart",
    "lib/screens/task_form_screen.dart",
    "lib/services/firestore_service.dart",
    "lib/services/notification_service.dart"
)

# Normalize to lowercase with forward slashes
function Normalize-Path($p) {
    return $p.ToLower().Replace("\", "/").TrimEnd("/")
}

$targetNorm = @{}
foreach ($t in $targetFiles) {
    $key = Normalize-Path("$projectRoot/$t")
    $targetNorm[$key] = @{ RelPath = $t; Lines = @{} }
}

Write-Host "Reading transcript..."
$content = Get-Content $transcriptPath -Encoding UTF8
Write-Host "Total lines: $($content.Length)"

$lineRegex = [regex]'^(\d+): (.*)$'
$filePathRegex = [regex]'File Path: `file:///([^`]+)`'
$totalLinesRegex = [regex]'Total Lines: (\d+)'
$showingRegex = [regex]'Showing lines (\d+) to (\d+)'

foreach ($rawLine in $content) {
    if ($rawLine.Length -lt 20) { continue }
    
    # Try to parse as JSON to get tool results
    try {
        $obj = $rawLine | ConvertFrom-Json -ErrorAction SilentlyContinue
    } catch {
        continue
    }
    
    if ($null -eq $obj) { continue }
    
    # Look at content field for VIEW_FILE results
    $textContent = ""
    if ($obj.content) {
        if ($obj.content -is [string]) {
            $textContent = $obj.content
        } elseif ($obj.content.text) {
            $textContent = $obj.content.text
        }
    }
    
    if ([string]::IsNullOrEmpty($textContent)) { continue }
    if (-not ($textContent -match "File Path:")) { continue }
    
    # Find which file this view is for
    $fpMatch = $filePathRegex.Match($textContent)
    if (-not $fpMatch.Success) { continue }
    
    $rawPath = $fpMatch.Groups[1].Value
    $normPath = Normalize-Path($rawPath)
    
    if (-not $targetNorm.ContainsKey($normPath)) { continue }
    
    $entry = $targetNorm[$normPath]
    Write-Host "Found view of: $($entry.RelPath)"
    
    # Extract line-numbered content
    $lines = $textContent -split "`n"
    foreach ($line in $lines) {
        $lm = $lineRegex.Match($line)
        if ($lm.Success) {
            $lineNum = [int]$lm.Groups[1].Value
            $lineContent = $lm.Groups[2].Value
            # Only add if not already present (keep first occurrence = latest edit)
            if (-not $entry.Lines.ContainsKey($lineNum)) {
                $entry.Lines[$lineNum] = $lineContent
            }
        }
    }
}

# Write recovered files
$recovered = 0
foreach ($key in $targetNorm.Keys) {
    $entry = $targetNorm[$key]
    if ($entry.Lines.Count -eq 0) {
        Write-Host "WARNING: No content found for $($entry.RelPath)"
        continue
    }
    
    $outPath = Join-Path $projectRoot $entry.RelPath.Replace("/", "\")
    $dir = Split-Path $outPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    
    $maxLine = ($entry.Lines.Keys | Measure-Object -Maximum).Maximum
    $fileLines = @()
    for ($i = 1; $i -le $maxLine; $i++) {
        if ($entry.Lines.ContainsKey($i)) {
            $fileLines += $entry.Lines[$i]
        } else {
            $fileLines += ""
        }
    }
    
    $fileLines | Set-Content -Path $outPath -Encoding UTF8 -NoNewline:$false
    Write-Host "RECOVERED: $($entry.RelPath) ($($entry.Lines.Count) lines captured, max=$maxLine)"
    $recovered++
}

Write-Host ""
Write-Host "Done. Recovered $recovered / $($targetFiles.Length) files."
