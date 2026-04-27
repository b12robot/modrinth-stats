[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Modrinth Stats"
$ProgressPreference = 'SilentlyContinue'

$Versions = @(
	"1.16", "1.16.1", "1.16.2", "1.16.3", "1.16.4", "1.16.5",
	"1.17", "1.17.1",
	"1.18", "1.18.1", "1.18.2",
	"1.19", "1.19.1", "1.19.2", "1.19.3", "1.19.4",
    "1.20", "1.20.1", "1.20.2", "1.20.3", "1.20.4", "1.20.5", "1.20.6",
    "1.21", "1.21.1", "1.21.2", "1.21.3", "1.21.4", "1.21.5", "1.21.6","1.21.7", "1.21.8", "1.21.9", "1.21.10", "1.21.11",
	"26.1", "26.1.1", "26.1.2"
)

$Loaders = @(
	"forge", "fabric", "neoforge", "quilt"
)

$ValidHours = 48
$CachePath = Join-Path -Path $env:USERPROFILE -ChildPath "mod_stats_cache.json"
$LastWriteTime = [datetime]::MinValue
$Data = $null

# Read local cache.
if (Test-Path -Path $CachePath) {
	try {
		$Data = Get-Content -Path $CachePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
		$LastWriteTime = (Get-Item $CachePath).LastWriteTime.ToUniversalTime()
	}
	catch {
		Write-Host "[WARNING] Cache file is unreadable or corrupted. Fetching new data." -ForegroundColor Yellow
        Write-Host "$($_.Exception.GetType().Name)`n$($_.Exception.Message)" -ForegroundColor DarkGray
	}
}

$MaxVersionLength = 0
foreach ($Version in $Versions) {
    if ($Version.Length -gt $MaxVersionLength) { 
        $MaxVersionLength = $Version.Length 
    }
}

$MaxLoaderLength = 0
foreach ($Loader in $Loaders) {
    if ($Loader.Length -gt $MaxLoaderLength) {
		$MaxLoaderLength = $Loader.Length
	}
}

# Fetch data from API.
$CurrentTime = (Get-Date).ToUniversalTime()
$TimeDifference = ($CurrentTime - $LastWriteTime).TotalHours

if (-not $Data -or $Data.Count -ne $Versions.Count -or $TimeDifference -gt $ValidHours) {
	$Data = [System.Collections.Generic.List[object]]::new()
	foreach ($Version in $Versions) {
		$Stats = @{}
		foreach ($Loader in $Loaders) {
			$Delay = 500
			try {
				$Facets = "[[`"versions:$Version`"],[`"categories:$Loader`"]]"
				$Url = "https://api.modrinth.com/v2/search?project_type=mod&facets=$Facets&limit=1"
				$Response = Invoke-WebRequest -Uri $Url -Headers @{"User-Agent" = "b12robot/modrinth-stats/1.0 (https://github.com/b12robot/modrinth-stats)"} -UseBasicParsing -ErrorAction Stop
				$Hits = [int]($Response.Content | ConvertFrom-Json).total_hits
				$Stats[$Loader] = $Hits
				$Limit = [int]$Response.Headers["X-Ratelimit-Limit"]
				$Remaining = [int]$Response.Headers["X-Ratelimit-Remaining"]
				$Reset = [int]$Response.Headers["X-Ratelimit-Reset"]
				Write-Host ("[INFO] {0,-$MaxVersionLength} │ {1,-$MaxLoaderLength} -> {2,-6} │ Limit: {3,-4} │ Remaining: {4,-4} │ Reset: {5,-4}" -f $Version, $Loader, $Hits, $Limit, $Remaining, $Reset) -ForegroundColor Cyan
				$Threshold = [math]::Max([int]($Limit * 0.1), 4)
				if ($Remaining -lt $Threshold -and $Remaining -gt 0) {
					$DynamicDelay = ($Reset / $Remaining) * 1000
					$Delay = [Math]::Min(5000, [Math]::Max(1000, $DynamicDelay))
					Write-Host "[WARNING] Rate limit exceeded! Dynamic delay: $Delay ms" -ForegroundColor Yellow
				}
			}
			catch {
				$Stats[$Loader] = -1
				Write-Host "[ERROR] Failed to fetch data -> Version: $Version | Loader: $Loader" -ForegroundColor Red
				Write-Host "$($_.Exception.GetType().Name)`n$($_.Exception.Message)" -ForegroundColor DarkGray
			}
			Start-Sleep -Milliseconds $Delay
		}
		$Data.Add(
			[PSCustomObject]@{
				Version = $Version
				Loaders = $Stats
			}
		)
	}
	try {
		$Data | ConvertTo-Json -Depth 3 | Set-Content -Path $CachePath -Encoding UTF8 -ErrorAction Stop
    }
	catch {
		Write-Host "[ERROR] Failed to save data to the cache file: $CachePath" -ForegroundColor Red
        Write-Host "$($_.Exception.GetType().Name)`n$($_.Exception.Message)" -ForegroundColor DarkGray
		Read-Host "Press Enter to continue..."
	}
}

# Group and sort data.
$GroupedData = @{}
$MaxHitsLength = 0
foreach ($Loader in $Loaders) {
    $GroupedData[$Loader] = $(
        foreach ($Item in $Data) {
            [PSCustomObject]@{
                Version = $Item.Version
                Hits = [int]$Item.Loaders.$Loader
            }
        }
    ) | Sort-Object -Property Hits -Descending

    $CurrentLength = ([string]$GroupedData[$Loader][0].Hits).Length
    if ($CurrentLength -gt $MaxHitsLength) {
        $MaxHitsLength = $CurrentLength
    }
}

# Calculate table layout.
$ColumnWidth = 6 + $MaxVersionLength + $MaxHitsLength
$Segments = foreach ($Loader in $Loaders) { "═" * $ColumnWidth }
$TopBorder = "╔" + ($Segments -join "╦") + "╗"
$MidBorder = "╠" + ($Segments -join "╬") + "╣"
$BotBorder = "╚" + ($Segments -join "╩") + "╝"

# Calculate percentage.
$AllHits = $(
	foreach ($Item in $Data) {
		foreach ($Loader in $Loaders) {
			[int]$Item.Loaders.$Loader
		}
	}
) | Sort-Object

$P25 = $AllHits[[int]($AllHits.Count * 0.25)]
$P50 = $AllHits[[int]($AllHits.Count * 0.50)]
$P75 = $AllHits[[int]($AllHits.Count * 0.75)]

# Set color palette.
$Esc = [char]27
$ColorDefault = "$Esc[39m"
$AllDefault   = "$Esc[0m"

# Base
$ColorTitle   = "$Esc[38;2;27;217;106m"  # Modrinth Green
$ColorHeader  = "$Esc[38;2;50;120;255m"  # Neon Azure
$ColorBorder  = "$Esc[38;2;118;118;118m" # Campbell Bright Black
$ColorVersion = "$Esc[38;2;225;230;235m" # Crisp White
$ColorArrow   = "$Esc[38;2;90;140;180m"  # Slate Blue
$ColorRow     = "$Esc[48;2;22;27;34m"    # Dark Blue Gray

# Heatmap
$ColorHitP25  = "$Esc[38;2;70;190;255m"  # Bright Cyan Blue
$ColorHitP50  = "$Esc[38;2;240;210;90m"  # Warm Sun Yellow
$ColorHitP75  = "$Esc[38;2;250;130;50m"  # Vibrant Tangerine
$ColorHitP100 = "$Esc[38;2;240;70;70m"   # Crimson Red

# Render the table.
Clear-Host
Write-Host "$ColorTitle MODRINTH MOD VERSION STATISTICS $ColorDefault"
Write-Host "$ColorBorder$TopBorder$ColorDefault"

$HeaderArray = foreach ($Loader in $Loaders) {
    $Title = " " + $Loader.Substring(0,1).ToUpper() + $Loader.Substring(1)
    $Title.PadRight($ColumnWidth)
}
$HeaderString = $HeaderArray -join "$ColorBorder║$ColorHeader"

Write-Host "$ColorBorder║$ColorHeader$HeaderString$ColorBorder║$ColorDefault"
Write-Host "$ColorBorder$MidBorder$ColorDefault"

for ($RowIndex = 0; $RowIndex -lt $Data.Count; $RowIndex++) {
    $ColorZebra = if ($RowIndex % 2) { $ColorRow } else { "" }
    $RowOutput = foreach ($Loader in $Loaders) {
        $CellData = $GroupedData[$Loader][$RowIndex]
		$Hit = [int]$CellData.Hits
		$ColorHit = if ($Hit -lt $P25) { $ColorHitP25 } elseif ($Hit -lt $P50) { $ColorHitP50 } elseif ($Hit -lt $P75) { $ColorHitP75 } else { $ColorHitP100 }
        $VersionText = ("{0,-$MaxVersionLength}" -f $CellData.Version)
        $HitsText = ("{0,$MaxHitsLength}" -f $Hit)
        " $ColorVersion$VersionText $ColorArrow-> $ColorHit$HitsText$ColorDefault "
    }
	$RowText = $RowOutput -join "$ColorBorder║"
	Write-Host "$ColorZebra$ColorBorder║$RowText$ColorBorder║$AllDefault"
}

Write-Host "$ColorBorder$BotBorder$ColorDefault"
Read-Host "Press Enter to exit..."
Exit
