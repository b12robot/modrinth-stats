# Config
[CmdletBinding()]
param (
    [string[]]$Versions = @(
        "1.20", "1.20.1", "1.20.2", "1.20.3", "1.20.4", "1.20.5", "1.20.6",
        "1.21", "1.21.1", "1.21.2", "1.21.3", "1.21.4", "1.21.5", "1.21.6","1.21.7", "1.21.8", "1.21.9", "1.21.10", "1.21.11",
        "26.1", "26.1.1", "26.1.2", "26.2"
    ),

    [string[]]$Loaders = @(
        "forge", "fabric", "neoforge", "quilt"
    ),

    [int]$ValidHours = 48
)

# Initialization
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Modrinth Stats"
$ProgressPreference = 'SilentlyContinue'
$CachePath = Join-Path -Path $env:USERPROFILE -ChildPath "modrinth-stats-cache.json"
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

$RequestCount = 0
$TotalRequests = $Versions.Count * $Loaders.Count
$CurrentTime = (Get-Date).ToUniversalTime()
$TimeDifference = ($CurrentTime - $LastWriteTime).TotalHours

# Fetch data from API.
if ($TimeDifference -gt $ValidHours -or
	-not $Data -or
	$Data.Count -ne $Versions.Count -or
	@($Data[0].Loaders.PSObject.Properties).Count -ne $Loaders.Count) {
	$Data = [System.Collections.Generic.List[object]]::new()
	foreach ($Version in $Versions) {
		$Stats = @{}
		foreach ($Loader in $Loaders) {
			$Delay = 500
			$RequestCount++
			$Percentage = [math]::Round(($RequestCount / $TotalRequests) * 100)
			try {
				$Facets = "[[`"versions:$Version`"],[`"categories:$Loader`"]]"
				$Url = "https://api.modrinth.com/v2/search?project_type=mod&facets=$Facets&limit=1"
				$Response = Invoke-WebRequest -Uri $Url -Headers @{"User-Agent" = "b12robot/modrinth-stats/1.0 (https://github.com/b12robot/modrinth-stats)"} -UseBasicParsing -ErrorAction Stop
				$Hits = [int]($Response.Content | ConvertFrom-Json).total_hits
				$Stats[$Loader] = $Hits
				$Limit = [int]$Response.Headers["X-Ratelimit-Limit"]
				$Remaining = [int]$Response.Headers["X-Ratelimit-Remaining"]
				$Reset = [int]$Response.Headers["X-Ratelimit-Reset"]
				Write-Host ("[INFO] [{0,3}/{1}] {2,3}% │ {3,-$MaxVersionLength} │ {4,-$MaxLoaderLength} -> {5,-6} │ Limit: {6,-4} │ Remaining: {7,-4} │ Reset: {8,-4}" -f $RequestCount, $TotalRequests, $Percentage, $Version, $Loader, $Hits, $Limit, $Remaining, $Reset) -ForegroundColor Cyan
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
            $Value = [int]$Item.Loaders.$Loader
            if ($Value -ge 0) { $Value }
        }
    }
) | Sort-Object

if ($AllHits.Count -gt 0) {
	$P20 = $AllHits[[int]($AllHits.Count * 0.20)]
	$P40 = $AllHits[[int]($AllHits.Count * 0.40)]
	$P60 = $AllHits[[int]($AllHits.Count * 0.60)]
	$P80 = $AllHits[[int]($AllHits.Count * 0.80)]
}

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
$ColorError   = "$Esc[38;2;180;50;210m"  # Galactic Purple

# Heatmap
$ColorHitP20  = "$Esc[38;2;20;100;250m"  # Deep Blue
$ColorHitP40  = "$Esc[38;2;70;190;255m"  # Bright Cyan Blue
$ColorHitP60  = "$Esc[38;2;240;210;90m"  # Warm Sun Yellow
$ColorHitP80  = "$Esc[38;2;250;130;50m"  # Vibrant Tangerine
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
		if ($Hit -lt 0) {
			$ColorHit = $ColorError
			$DisplayHit = "NA"
		}
		else {
			$ColorHit = if ($Hit -lt $P20) { $ColorHitP20 }
				elseif ($Hit -lt $P40) { $ColorHitP40 }
				elseif ($Hit -lt $P60) { $ColorHitP60 }
				elseif ($Hit -lt $P80) { $ColorHitP80 }
				else { $ColorHitP100 }
			$DisplayHit = $Hit
		}
		$VersionText = "{0,-$MaxVersionLength}" -f $CellData.Version
		$HitsText = "{0,$MaxHitsLength}" -f $DisplayHit
        " $ColorVersion$VersionText $ColorArrow-> $ColorHit$HitsText$ColorDefault "
    }
	$RowText = $RowOutput -join "$ColorBorder║"
	Write-Host "$ColorZebra$ColorBorder║$RowText$ColorBorder║$AllDefault"
}

Write-Host "$ColorBorder$BotBorder$ColorDefault"
Read-Host "Press Enter to exit..."
Exit
