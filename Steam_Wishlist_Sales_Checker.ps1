<#
.SYNOPSIS
    Steam Wishlist Sales - Displays discounted games from your Steam wishlist.

.DESCRIPTION
    Fetches your Steam wishlist, identifies games on sale,
    generates an HTML page with genre filters and dual theme
    (Modern / Classic Steam), then opens it in your browser.
    Uses intelligent caching to speed up subsequent scans.

.PARAMETER SteamID
    Your 64-bit Steam ID (17 digits). Find it at https://steamid.io/

.PARAMETER Country
    Country code for pricing (fr, us, uk, de, etc.)

.PARAMETER OutputPath
    Path for the generated HTML file (optional)

.PARAMETER ClearCache
    Deletes the cache before scanning (forces a full refresh)

.PARAMETER ScrapeEndDates
    Scrapes each game's store page to retrieve promotion end dates (slow, ~1 request per game)

.EXAMPLE
    .\Steam_Wishlist_Sales_Checker.ps1 -SteamID 12345678901234567
    .\Steam_Wishlist_Sales_Checker.ps1 -SteamID 12345678901234567 -Country us
    .\Steam_Wishlist_Sales_Checker.ps1 12345678901234567 -ClearCache
    .\Steam_Wishlist_Sales_Checker.ps1 12345678901234567 -ScrapeEndDates
#>

param(
    [Parameter(Position = 0)]
    [string]$SteamID,

    [Parameter()]
    [string]$Country = "fr",

    [Parameter()]
    [string]$OutputPath = "",

    [Parameter()]
    [switch]$ClearCache,

    [Parameter()]
    [switch]$ScrapeEndDates
)

# -- Configuration -------------------------------------------------
$BatchSize = 30
$DelayMs = 2000
$CurrencySymbols = @{
    "fr" = [char]0x20AC; "de" = [char]0x20AC; "it" = [char]0x20AC; "es" = [char]0x20AC
    "us" = "$"; "uk" = [char]0x00A3; "ca" = "CA$"; "au" = "A$"
    "jp" = [char]0x00A5; "br" = "R$"
}
$CurrSymbol = if ($CurrencySymbols.ContainsKey($Country)) { $CurrencySymbols[$Country] } else { [char]0x20AC }

# -- Utility functions ---------------------------------------------
function Write-Step { param($Msg) Write-Host '  [..] ' -NoNewline -ForegroundColor Cyan; Write-Host $Msg }
function Write-Ok   { param($Msg) Write-Host '  [OK] ' -NoNewline -ForegroundColor Green; Write-Host $Msg }
function Write-Warn { param($Msg) Write-Host '  [!!] ' -NoNewline -ForegroundColor Yellow; Write-Host $Msg }
function Write-Err  { param($Msg) Write-Host '  [ERR] ' -NoNewline -ForegroundColor Red; Write-Host $Msg }

# -- Banner --------------------------------------------------------
Write-Host ''
Write-Host '  +===============================================+' -ForegroundColor Cyan
Write-Host '  |    Steam Wishlist Sales Checker               |' -ForegroundColor Cyan
Write-Host '  +===============================================+' -ForegroundColor Cyan
Write-Host ''

# -- Ask for Steam ID if not provided -----------------------------
if (-not $SteamID) {
    Write-Host '  Enter your 64-bit Steam ID - 17 digits' -ForegroundColor White
    Write-Host '  Find it at: ' -NoNewline; Write-Host 'https://steamid.io/' -ForegroundColor Cyan
    Write-Host ''
    $SteamID = Read-Host '  Steam ID'
}

if ($SteamID -notmatch '^\d{17}$') {
    Write-Err "Steam ID invalide : '$SteamID' - doit contenir 17 chiffres"
    exit 1
}

# -- Output paths --------------------------------------------------
if (-not $OutputPath) {
    $OutputPath = Join-Path $env:TEMP 'steam-wishlist-sales.html'
} else {
    if ((Test-Path $OutputPath -PathType Container) -or $OutputPath.EndsWith('\') -or $OutputPath.EndsWith('/')) {
        $OutputPath = Join-Path $OutputPath 'steam-wishlist-sales.html'
    }
    elseif (-not [System.IO.Path]::HasExtension($OutputPath)) {
        $OutputPath = "$OutputPath.html"
    }
    $ParentDir = Split-Path -Parent $OutputPath
    if ($ParentDir -and -not (Test-Path $ParentDir)) {
        try { New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null }
        catch { Write-Err "Impossible de creer le dossier : $ParentDir"; exit 1 }
    }
}
$CacheDir = Join-Path $env:APPDATA 'SteamWishlistSales'
$CachePath = Join-Path $CacheDir "cache_$SteamID.json"
$PreviousSalesPath = Join-Path $CacheDir "previous_sales_$SteamID.json"

if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

if ($ClearCache -and (Test-Path $CachePath)) {
    Remove-Item $CachePath -Force
    if (Test-Path $PreviousSalesPath) { Remove-Item $PreviousSalesPath -Force }
    Write-Warn 'Cache supprime.'
}

# Load existing cache
$Cache = @{}
if (Test-Path $CachePath) {
    try {
        $CacheRaw = Get-Content $CachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $CacheRaw.PSObject.Properties) {
            $Cache[$prop.Name] = @{
                name   = $prop.Value.name
                img    = $prop.Value.img
                genres = $prop.Value.genres
            }
        }
    } catch {
        $Cache = @{}
    }
}

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# ==================================================================
# STEP 1: Fetch wishlist
# ==================================================================
Write-Step 'Recuperation de la wishlist...'

try {
    $WishlistUrl = "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=$SteamID"
    $WishlistData = Invoke-RestMethod -Uri $WishlistUrl -TimeoutSec 30
} catch {
    Write-Err 'Impossible de recuperer la wishlist. Verifiez que votre profil est public.'
    exit 1
}

$AppIDs = @($WishlistData.response.items | ForEach-Object { $_.appid })
$Total = $AppIDs.Count

if ($Total -eq 0) {
    Write-Err 'Wishlist vide ou inaccessible.'
    exit 1
}

Write-Ok "Wishlist recuperee : $Total jeux"

# ==================================================================
# STEP 2: Fetch prices in batches
# ==================================================================
Write-Step "Recuperation des prix par lots de $BatchSize..."

$AllPrices = @{}
$TotalBatches = [math]::Ceiling($Total / $BatchSize)

for ($i = 0; $i -lt $Total; $i += $BatchSize) {
    $BatchNum = [math]::Floor($i / $BatchSize) + 1
    $BatchIDs = ($AppIDs[$i..[math]::Min($i + $BatchSize - 1, $Total - 1)]) -join ','

    Write-Host "`r  [..] Lot $BatchNum/$TotalBatches..." -NoNewline

    try {
        $Url = "https://store.steampowered.com/api/appdetails?appids=$BatchIDs&cc=$Country&filters=price_overview"
        $Response = Invoke-RestMethod -Uri $Url -TimeoutSec 30

        foreach ($prop in $Response.PSObject.Properties) {
            $AppId = $prop.Name
            $Data = $prop.Value
            if ($Data.success -and $Data.data -and $Data.data.price_overview) {
                $Price = $Data.data.price_overview
                if ($Price.discount_percent -gt 0) {
                    $AllPrices[$AppId] = @{
                        normal_price = $Price.initial
                        sale_price   = $Price.final
                        discount_pct = $Price.discount_percent
                    }
                }
            }
        }
    } catch {
        # Batch failed, continue
    }

    if ($BatchNum -lt $TotalBatches) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

Write-Host ''
$SaleCount = $AllPrices.Count
Write-Ok "Jeux en promotion : $SaleCount"

if ($SaleCount -eq 0) {
    Write-Warn 'Aucun jeu en promo dans votre wishlist.'
    Write-Host ''
    exit 0
}

# ==================================================================
# STEP 3: Fetch names/images/genres with SMART CACHE
# ==================================================================
$Games = @()
$MissingIDs = @()
$CachedCount = 0

foreach ($AppId in $AllPrices.Keys) {
    if ($Cache.ContainsKey($AppId) -and $Cache[$AppId].name -and $Cache[$AppId].name.Length -gt 0) {
        $CachedCount++
    } else {
        $MissingIDs += $AppId
    }
}

$MissingCount = $MissingIDs.Count
Write-Ok "Cache : $CachedCount en cache, $MissingCount a recuperer"

if ($MissingCount -gt 0) {
    Write-Step "Recuperation des noms/genres de $MissingCount nouveaux jeux..."

    $Done = 0
    foreach ($AppId in $MissingIDs) {
        $Done++
        if ($Done % 20 -eq 0) {
            Write-Host "`r  [..] $Done/$MissingCount noms recuperes..." -NoNewline
        }

        try {
            $Url = "https://store.steampowered.com/api/appdetails?appids=$AppId&cc=$Country"
            $Detail = Invoke-RestMethod -Uri $Url -TimeoutSec 15
            $AppData = $Detail.$AppId

            if ($AppData.success -and $AppData.data) {
                $AppName = if ($AppData.data.name) { $AppData.data.name } else { '' }
                $AppImg = if ($AppData.data.header_image) { $AppData.data.header_image } else { '' }
                $AppGenres = ''
                if ($AppData.data.genres) {
                    $AppGenres = ($AppData.data.genres | ForEach-Object { $_.description }) -join ','
                }
                $AppMC = if ($AppData.data.metacritic -and $AppData.data.metacritic.score) { [int]$AppData.data.metacritic.score } else { $null }
                $AppDesc = if ($AppData.data.short_description) { $AppData.data.short_description } else { '' }
                $AppCats = ''
                if ($AppData.data.categories) {
                    $AppCats = ($AppData.data.categories | ForEach-Object { $_.description }) -join ','
                }

                $Cache[$AppId] = @{
                    name   = $AppName
                    img    = $AppImg
                    genres = $AppGenres
                    metacritic = $AppMC
                    desc   = $AppDesc
                    cats   = $AppCats
                }
            }
        } catch {
            # Continue
        }

        Start-Sleep -Milliseconds 1000
    }

    if ($MissingCount -ge 20) { Write-Host '' }
    Write-Ok "Nouveaux noms recuperes : $Done/$MissingCount"
} else {
    Write-Ok 'Tous les jeux sont en cache! Aucun appel API necessaire.'
}

# Save updated cache
$CacheExport = @{}
foreach ($key in $Cache.Keys) {
    $CacheExport[$key] = $Cache[$key]
}
$CacheExport | ConvertTo-Json -Depth 5 | Set-Content -Path $CachePath -Encoding UTF8
Write-Ok "Cache sauvegarde : $CachePath"

# Build enriched game list
foreach ($AppId in $AllPrices.Keys) {
    $PriceInfo = $AllPrices[$AppId]
    $CacheEntry = if ($Cache.ContainsKey($AppId)) { $Cache[$AppId] } else { $null }

    $Name = if ($CacheEntry -and $CacheEntry.name) { $CacheEntry.name } else { "App $AppId" }
    $Image = if ($CacheEntry -and $CacheEntry.img) { $CacheEntry.img } else {
        "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/$AppId/header.jpg"
    }
    $Genres = if ($CacheEntry -and $CacheEntry.genres) { $CacheEntry.genres } else { '' }
    $MC = if ($CacheEntry -and $CacheEntry.metacritic) { $CacheEntry.metacritic } else { $null }
    $Desc = if ($CacheEntry -and $CacheEntry.desc) { $CacheEntry.desc } else { '' }
    $Cats = if ($CacheEntry -and $CacheEntry.cats) { $CacheEntry.cats } else { '' }

    $Games += [PSCustomObject]@{
        AppId       = $AppId
        Name        = $Name
        Image       = $Image
        NormalPrice = $PriceInfo.normal_price
        SalePrice   = $PriceInfo.sale_price
        DiscountPct = $PriceInfo.discount_pct
        Genres      = $Genres
        Metacritic  = $MC
        Desc        = $Desc
        Cats        = $Cats
    }
}

$Games = $Games | Sort-Object { $_.Name.ToLower() }

# ==================================================================
# STEP 4: Compare with previous scan (badges New / Price changes)
# ==================================================================
$PreviousSales = @{}
if (Test-Path $PreviousSalesPath) {
    try {
        $PrevRaw = Get-Content $PreviousSalesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $PrevRaw.PSObject.Properties) {
            $PreviousSales[$prop.Name] = [int]$prop.Value
        }
        Write-Step "Comparaison avec le scan precedent..."
    } catch {
        $PreviousSales = @{}
    }
}

$NewCount = 0; $UpCount = 0; $DownCount = 0
foreach ($Game in $Games) {
    $aid = [string]$Game.AppId
    if ($PreviousSales.Count -eq 0) {
        $Game | Add-Member -NotePropertyName Badge -NotePropertyValue '' -Force
    } elseif (-not $PreviousSales.ContainsKey($aid)) {
        $Game | Add-Member -NotePropertyName Badge -NotePropertyValue 'new' -Force
        $NewCount++
    } elseif ($Game.SalePrice -gt $PreviousSales[$aid]) {
        $Game | Add-Member -NotePropertyName Badge -NotePropertyValue 'price_up' -Force
        $UpCount++
    } elseif ($Game.SalePrice -lt $PreviousSales[$aid]) {
        $Game | Add-Member -NotePropertyName Badge -NotePropertyValue 'price_down' -Force
        $DownCount++
    } else {
        $Game | Add-Member -NotePropertyName Badge -NotePropertyValue '' -Force
    }
}

if ($PreviousSales.Count -gt 0) {
    Write-Ok "Badges : $NewCount nouveau(x), $UpCount prix en hausse, $DownCount prix en baisse"
} else {
    Write-Step "Premier scan : pas de donnees precedentes pour comparaison."
}

# Save current prices for next scan comparison
$CurrentSales = @{}
foreach ($Game in $Games) {
    $CurrentSales[[string]$Game.AppId] = $Game.SalePrice
}
$CurrentSales | ConvertTo-Json -Depth 5 | Set-Content -Path $PreviousSalesPath -Encoding UTF8
Write-Ok "Prix sauvegardes pour comparaison future"

# ==================================================================
# STEP 5: Scrape end-of-sales dates (if enabled)
# ==================================================================
$SaleDates = @{}
if ($ScrapeEndDates -and $Games.Count -gt 0) {
    Write-Step "Recuperation des dates de fin de promotion ($($Games.Count) jeux)..."
    $DateCount = 0
    $FoundCount = 0
    foreach ($Game in $Games) {
        $DateCount++
        Write-Host -NoNewline "`r  [$DateCount/$($Games.Count)] App $($Game.AppId)..."
        try {
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $session.Cookies.Add((New-Object System.Net.Cookie("birthtime", "0", "/", "store.steampowered.com")))
            $session.Cookies.Add((New-Object System.Net.Cookie("wants_mature_content", "1", "/", "store.steampowered.com")))
            $PageHtml = (Invoke-WebRequest -Uri "https://store.steampowered.com/app/$($Game.AppId)/" -WebSession $session -TimeoutSec 15 -UseBasicParsing).Content
            $EndTs = $null
            # Pattern 1 : InitDailyDealTimer (timestamp precis)
            if ($PageHtml -match 'InitDailyDealTimer\s*\(\s*\$DiscountCountdown\s*,\s*(\d{10})') {
                $EndTs = [long]$Matches[1]
            }
            # Pattern 2 : texte "prend fin le DD mois" (FR) ou "Offer ends DD month" (EN)
            if (-not $EndTs -and $PageHtml -match '(?:prend fin le |Offer ends )([^<]+)') {
                $DateText = $Matches[1].Trim()
                $MonthMap = @{ 'janvier'=1;'january'=1;'février'=2;'february'=2;'mars'=3;'march'=3;'avril'=4;'april'=4;'mai'=5;'may'=5;'juin'=6;'june'=6;'juillet'=7;'july'=7;'août'=8;'august'=8;'septembre'=9;'september'=9;'octobre'=10;'october'=10;'novembre'=11;'november'=11;'décembre'=12;'december'=12 }
                foreach ($mName in $MonthMap.Keys) {
                    if ($DateText -match "(?:^|\s)(\d{1,2})\s+$mName" -or $DateText -match "$mName\s*$") {
                        if ($Matches[1]) { $day = [int]$Matches[1] }
                        else { $day = [int]($DateText -replace '[^0-9]','') }
                        $month = $MonthMap[$mName]
                        $year = (Get-Date).Year
                        $EndDate = Get-Date -Year $year -Month $month -Day $day -Hour 18 -Minute 0 -Second 0
                        $EndTs = [long]($EndDate - (Get-Date '1970-01-01')).TotalSeconds
                        break
                    }
                }
            }
            if ($EndTs -and $EndTs -gt 0) {
                $SaleDates[[string]$Game.AppId] = $EndTs
                $FoundCount++
            }
        } catch { }
        Start-Sleep -Seconds 1
    }
    Write-Host ""
    Write-Ok "Dates de fin recuperees : $FoundCount/$($Games.Count) jeux"
}

# ==================================================================
# STEP 6: Generate HTML page
# ==================================================================
Write-Step 'Generation de la page HTML...'

Add-Type -AssemblyName System.Web

$BestDiscount = ($Games | Measure-Object -Property DiscountPct -Maximum).Maximum
$CheapestPrice = ($Games | Measure-Object -Property SalePrice -Minimum).Minimum
$CheapestFmt = "{0:N2}" -f ($CheapestPrice / 100) -replace '\.', ','
$MaxPrice = ($Games | Measure-Object -Property SalePrice -Maximum).Maximum
$MaxPriceEur = [math]::Ceiling($MaxPrice / 100)
$Now = Get-Date -Format 'dd/MM/yyyy HH:mm'
$Elapsed = $Stopwatch.Elapsed

# Extract unique genres for filter buttons
$AllGenres = @()
foreach ($Game in $Games) {
    if ($Game.Genres -and $Game.Genres.Length -gt 0) {
        $AllGenres += $Game.Genres -split ','
    }
}
$AllGenres = $AllGenres | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Sort-Object -Unique

$GenreButtonsHtml = ''
foreach ($Genre in $AllGenres) {
    $SafeGenre = [System.Web.HttpUtility]::HtmlEncode($Genre.Trim())
    $GCount = ($Games | Where-Object { $_.Genres -split ',' -contains $SafeGenre }).Count
    $GenreButtonsHtml += "<button class=`"sidebar-btn`" data-genre=`"$SafeGenre`"><span>$SafeGenre</span><span class=`"count`">$GCount</span></button>"
}

# Extract unique categories for filter buttons (gameplay-relevant only)
$AllCats = @()
foreach ($Game in $Games) {
    if ($Game.Cats -and $Game.Cats.Length -gt 0) {
        $AllCats += $Game.Cats -split ','
    }
}
$AllCats = $AllCats | Where-Object { $_ -and $_.Trim() -match '(?i)single.player|multi.player|co.op|pvp|mmo|cross.platform|shared.split|lan|un joueur|multijoueur|coop|coop.ratif|joueur contre joueur|JcJ|.cran partag' } | ForEach-Object { $_.Trim() } | Sort-Object -Unique

$CatButtonsHtml = ''
foreach ($Cat in $AllCats) {
    $SafeCat = [System.Web.HttpUtility]::HtmlEncode($Cat)
    $CCount = ($Games | Where-Object { $_.Cats -split ',' -contains $SafeCat }).Count
    $CatButtonsHtml += "<button class=`"sidebar-btn`" data-cat=`"$SafeCat`"><span>$SafeCat</span><span class=`"count`">$CCount</span></button>"
}

# Generate card HTML
$CardsHtml = ''
foreach ($Game in $Games) {
    $NormalFmt = "{0:N2}" -f ($Game.NormalPrice / 100) -replace '\.', ','
    $SaleFmt = "{0:N2}" -f ($Game.SalePrice / 100) -replace '\.', ','
    $SafeName = [System.Web.HttpUtility]::HtmlEncode($Game.Name)
    $SafeNameAttr = $SafeName -replace '"', '&quot;'

    $GenreTagsHtml = ''
    $GenresData = ''
    if ($Game.Genres -and $Game.Genres.Length -gt 0) {
        $GenresData = $Game.Genres
        $GenreSplit = $Game.Genres -split ','
        foreach ($g in $GenreSplit) {
            $gt = $g.Trim()
            if ($gt.Length -gt 0) {
                $SafeG = [System.Web.HttpUtility]::HtmlEncode($gt)
                $GenreTagsHtml += "<span class=`"genre-tag`">$SafeG</span>"
            }
        }
    }

    $StatusBadgeHtml = ''
    switch ($Game.Badge) {
        'new'        { $StatusBadgeHtml = '<span class="status-badge new-badge">NEW</span>' }
        'price_up'   { $StatusBadgeHtml = '<span class="status-badge up-badge">Prix &#128316;</span>' }
        'price_down' { $StatusBadgeHtml = '<span class="status-badge down-badge">Prix &#128317;</span>' }
    }

    $BadgeClass = if ($Game.DiscountPct -ge 70) { 'badge-high' } elseif ($Game.DiscountPct -ge 30) { 'badge-mid' } else { 'badge-low' }

    $McHtml = ''
    if ($Game.Metacritic) {
        $McClass = if ($Game.Metacritic -ge 75) { 'mc-high' } elseif ($Game.Metacritic -ge 50) { 'mc-mid' } else { 'mc-low' }
        $McHtml = "<span class=`"metacritic $McClass`">$($Game.Metacritic)</span>"
    }

    $SafeDesc = [System.Web.HttpUtility]::HtmlAttributeEncode(($Game.Desc -replace '<[^>]*>', ''))
    $CatsData = if ($Game.Cats) { $Game.Cats } else { '' }
    $McVal = if ($Game.Metacritic) { $Game.Metacritic } else { 0 }

    $CardsHtml += @"
<a class="card" data-name="$SafeNameAttr" data-sale="$($Game.SalePrice)" data-disc="$($Game.DiscountPct)" data-genres="$GenresData" data-cats="$CatsData" data-badge="$($Game.Badge)" data-mc="$McVal" title="$SafeDesc" href="https://store.steampowered.com/app/$($Game.AppId)" target="_blank" rel="noopener">
<div class="img-wrap"><img src="$($Game.Image)" alt="$SafeNameAttr" loading="lazy" /><span class="badge $BadgeClass">-$($Game.DiscountPct)%</span>$StatusBadgeHtml</div>
<div class="info"><div class="name">$SafeName</div><div class="genres-row">$GenreTagsHtml</div><div class="prices"><span class="old">$NormalFmt$CurrSymbol</span><span class="new">$SaleFmt$CurrSymbol</span>$McHtml</div></div></a>
"@
}

$SaleCountPlural = if ($SaleCount -gt 1) { 'x' } else { '' }
$ElapsedSec = [math]::Round($Elapsed.TotalSeconds)
$Html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>&#x1F3AE;</text></svg>">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Steam Wishlist Sales Checker</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Exo+2:wght@400;600;700;800&family=Outfit:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
    :root {
        --bg-deep: #070a0f; --bg-card: #111822; --bg-sidebar: #0a0f17;
        --border: rgba(102,192,244,0.08); --border-hover: rgba(102,192,244,0.2);
        --accent: #66c0f4; --accent-glow: rgba(102,192,244,0.12);
        --green: #a4d007; --orange: #f39c12; --red: #e05a4f;
        --text: #c6d4df; --text-dim: #5a6a78; --text-muted: #3e4f5e;
        --font-h: 'Exo 2', sans-serif; --font-b: 'Outfit', sans-serif;
    }
    body { background: var(--bg-deep); color: var(--text); font-family: var(--font-b); min-height: 100vh; display: flex; overflow-x: hidden; }
    ::-webkit-scrollbar { width: 5px; } ::-webkit-scrollbar-track { background: transparent; }
    ::-webkit-scrollbar-thumb { background: rgba(102,192,244,0.12); border-radius: 3px; }
    .sidebar { position: fixed; top: 0; left: 0; bottom: 0; width: 260px; background: var(--bg-sidebar); border-right: 1px solid var(--border); display: flex; flex-direction: column; z-index: 10; overflow-y: auto; transition: background 0.3s, transform 0.3s ease; }
    .sidebar.open { transform: translateX(0); }
    .sidebar-logo { padding: 16px 14px; border-bottom: 1px solid var(--border); display: flex; align-items: center; gap: 8px; }
    .sidebar-logo .icon { font-size: 1.3rem; }
    .sidebar-logo h1 { font-family: var(--font-h); font-size: 0.88rem; font-weight: 700; color: #fff; letter-spacing: 0.02em; text-transform: uppercase; }
    .sidebar-logo .version { font-size: 0.58rem; color: var(--accent); background: var(--accent-glow); padding: 2px 6px; border-radius: 8px; font-weight: 600; }
    .sidebar-section { padding: 10px 8px 4px; }
    .sidebar-section-title { font-size: 0.62rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; color: var(--text-muted); margin-bottom: 5px; padding-left: 6px; }
    .sidebar-btn { display: flex; align-items: center; gap: 8px; width: 100%; padding: 5px 8px; border: none; background: transparent; color: var(--text-dim); font-size: 0.88rem; font-family: var(--font-b); cursor: pointer; border-radius: 6px; transition: all 0.2s; margin-bottom: 1px; text-align: left; }
    .sidebar-btn:hover { background: rgba(255,255,255,0.03); color: var(--text); }
    .sidebar-btn.active { background: linear-gradient(135deg, rgba(102,192,244,0.12), rgba(102,192,244,0.06)); color: var(--accent); font-weight: 600; }
    .sidebar-btn .count { margin-left: auto; font-size: 0.62rem; color: var(--text-muted); background: rgba(255,255,255,0.04); padding: 1px 5px; border-radius: 8px; }
    .sidebar-divider { height: 1px; background: var(--border); margin: 4px 8px; }
    .sidebar-meta { margin-top: auto; padding: 10px 12px; border-top: 1px solid var(--border); font-size: 0.68rem; color: var(--text-muted); line-height: 1.5; }
    .sidebar-meta strong { color: var(--accent); }
    .new-only-btn.active { background: linear-gradient(135deg, rgba(102,192,244,0.14), rgba(102,192,244,0.06)); color: var(--accent); font-weight: 600; }
    .expiring-btn.active { background: linear-gradient(135deg, rgba(224,90,79,0.14), rgba(224,90,79,0.06)); color: var(--red); font-weight: 600; }
    .cat-active { background: linear-gradient(135deg, rgba(164,208,7,0.12), rgba(164,208,7,0.06)); color: var(--green); font-weight: 600; }
    .main { margin-left: 260px; flex: 1; padding: 18px 22px; position: relative; z-index: 1; }
    .topbar { display: flex; align-items: center; gap: 12px; margin-bottom: 16px; }
    .search-box { flex: 1; max-width: 400px; position: relative; }
    .search-box input { width: 100%; padding: 8px 14px 8px 36px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; color: var(--text); font-family: var(--font-b); font-size: 0.9rem; outline: none; transition: border-color 0.2s; }
    .search-box input:focus { border-color: var(--accent); }
    .search-box input::placeholder { color: var(--text-muted); }
    .search-box::before { content: '\01F50D'; position: absolute; left: 11px; top: 50%; transform: translateY(-50%); font-size: 0.74rem; opacity: 0.3; }
    .topbar-right { display: flex; align-items: center; gap: 8px; margin-left: auto; }
    .count-topbar { font-size: 0.95rem; font-weight: 600; color: var(--green); font-family: var(--font-h); }
    .gear-wrap { position: relative; }
    .gear-btn { display: flex; align-items: center; justify-content: center; width: 36px; height: 36px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; color: var(--text-dim); font-size: 1.15rem; cursor: pointer; transition: all 0.25s; }
    .gear-btn:hover { border-color: var(--border-hover); color: var(--text); transform: rotate(45deg); }
    .gear-dropdown { display: none; position: absolute; top: 42px; right: 0; background: #0c1018; border: 1px solid var(--border-hover); border-radius: 8px; padding: 6px 0; min-width: 260px; box-shadow: 0 10px 35px rgba(0,0,0,0.5); z-index: 100; }
    .gear-wrap.open .gear-dropdown { display: block; }
    .gear-item { display: flex; align-items: center; gap: 10px; padding: 8px 14px; color: var(--text-dim); font-size: 0.84rem; cursor: pointer; transition: all 0.15s; border: none; background: none; width: 100%; font-family: var(--font-b); text-decoration: none; text-align: left; }
    .gear-item:hover { background: rgba(255,255,255,0.04); color: var(--text); }
    .gear-item .g-ico { width: 18px; text-align: center; }
    .gear-item.active-theme { color: var(--accent); font-weight: 600; }
    .gear-item.active-theme::after { content: '\2713'; margin-left: auto; font-size: 0.7rem; }
    .gear-sep { height: 1px; background: var(--border); margin: 4px 12px; }
    .gear-danger { color: var(--red); }
    .gear-danger:hover { background: rgba(224,90,79,0.06); }
    .stats-row { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 10px; margin-bottom: 16px; }
    .stat-card { background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; padding: 12px 16px; transition: border-color 0.2s; }
    .stat-card:hover { border-color: var(--border-hover); }
    .stat-label { font-size: 0.64rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: var(--text-muted); margin-bottom: 2px; }
    .stat-value { font-family: var(--font-h); font-size: 1.35rem; font-weight: 700; color: #fff; white-space: nowrap; }
    .stat-value.accent { color: var(--accent); }
    .stat-value.green { color: var(--green); }
    .toolbar-row { display: flex; align-items: center; gap: 6px; margin-bottom: 14px; flex-wrap: wrap; }
    .toolbar-row .label { font-size: 0.8rem; color: var(--text-muted); font-weight: 600; letter-spacing: 0.05em; text-transform: uppercase; margin-right: 2px; }
    .sort-btn { padding: 5px 12px; background: transparent; border: 1px solid var(--border); color: var(--text-dim); border-radius: 14px; font-size: 0.8rem; font-family: var(--font-b); cursor: pointer; transition: all 0.2s; }
    .sort-btn:hover { border-color: var(--border-hover); color: var(--text); }
    .sort-btn.active { background: var(--accent); color: #fff; border-color: transparent; font-weight: 600; }
    .price-slider { display: flex; align-items: center; gap: 8px; margin-left: 10px; padding-left: 10px; border-left: 1px solid var(--border); flex: 1; max-width: 320px; }
    .price-slider label { font-size: 0.74rem; color: var(--text-muted); white-space: nowrap; }
    .price-slider input[type=range] { -webkit-appearance: none; appearance: none; flex: 1; min-width: 120px; height: 4px; background: rgba(102,192,244,0.12); border-radius: 2px; outline: none; }
    .price-slider input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; width: 14px; height: 14px; border-radius: 50%; background: var(--accent); cursor: pointer; border: 2px solid var(--bg-deep); }
    .price-slider input[type=range]::-moz-range-thumb { width: 14px; height: 14px; border-radius: 50%; background: var(--accent); cursor: pointer; border: 2px solid var(--bg-deep); }
    .price-val { font-size: 0.88rem; color: var(--accent); font-weight: 600; font-family: var(--font-h); min-width: 40px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 12px; }
    .card { background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; overflow: hidden; text-decoration: none; color: inherit; display: flex; flex-direction: column; transition: all 0.3s; opacity: 0; animation: fadeUp 0.4s ease forwards; }
    .card:hover { border-color: var(--border-hover); transform: translateY(-3px); box-shadow: 0 8px 28px rgba(0,0,0,0.35); }
    @keyframes fadeUp { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: translateY(0); } }
    .img-wrap { position: relative; aspect-ratio: 460/215; overflow: hidden; background: #080c12; }
    .img-wrap img { width: 100%; height: 100%; object-fit: cover; transition: transform 0.4s; }
    .card:hover .img-wrap img { transform: scale(1.06); }
    .badge { position: absolute; top: 0; right: 0; color: #fff; font-family: var(--font-h); font-weight: 800; font-size: 0.95rem; padding: 5px 12px 5px 14px; border-radius: 0 0 0 8px; text-shadow: 0 1px 3px rgba(0,0,0,0.3); }
    .badge-high { background: linear-gradient(135deg, #a4d007, #7aa800); }
    .badge-mid { background: linear-gradient(135deg, #f39c12, #d68910); }
    .badge-low { background: linear-gradient(135deg, #e05a4f, #c0392b); }
    .status-badge { position: absolute; top: 0; left: 0; color: #fff; font-family: var(--font-h); font-weight: 700; font-size: 0.76rem; padding: 4px 10px 4px 8px; border-radius: 0 0 8px 0; text-shadow: 0 1px 2px rgba(0,0,0,0.4); z-index: 2; }
    .new-badge { background: linear-gradient(135deg, #66c0f4, #4a9fd4); }
    .up-badge { background: linear-gradient(135deg, #e05a4f, #c0392b); }
    .down-badge { background: linear-gradient(135deg, #27ae60, #1e8449); }
    .info { padding: 10px 12px 12px; display: flex; flex-direction: column; gap: 4px; flex: 1; }
    .name { font-size: 0.96rem; font-weight: 600; color: #fff; line-height: 1.25; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
    .genres-row { display: flex; gap: 4px; flex-wrap: wrap; }
    .genre-tag { font-size: 0.6rem; padding: 2px 6px; border-radius: 3px; background: rgba(255,255,255,0.04); color: var(--text-dim); font-weight: 600; text-transform: uppercase; letter-spacing: 0.03em; }
    .prices { display: flex; align-items: center; gap: 8px; margin-top: auto; }
    .old { font-size: 0.8rem; color: var(--text-muted); text-decoration: line-through; }
    .new { font-family: var(--font-h); font-size: 1.15rem; font-weight: 800; color: var(--green); }
    .metacritic { display: inline-flex; align-items: center; justify-content: center; min-width: 24px; height: 18px; font-family: var(--font-h); font-weight: 700; font-size: 0.72rem; border-radius: 4px; color: #fff; padding: 0 4px; margin-left: auto; }
    .mc-high { background: #66cc33; } .mc-mid { background: #ffcc33; color: #111; } .mc-low { background: #ff4444; }
    .end-date { display: block; font-size: 0.74rem; color: #8f98a0; margin-top: 2px; }
    .end-date-urgent { color: var(--red); font-weight: 600; }



    .mob-gear { position: relative; margin-left: auto; }
    .sidebar-close { display: none; position: absolute; top: 12px; right: 12px; background: none; border: none; color: var(--text-dim); font-size: 1.3rem; cursor: pointer; z-index: 2; padding: 4px 8px; }
    .sidebar-close:hover { color: var(--text); }
    .mobile-bar { display: none; }
    .empty { text-align: center; padding: 60px 20px; color: var(--text-muted); font-size: 1.1rem; }
    body.classic { --bg-deep: #1e2a16; --bg-card: #2a3a20; --bg-sidebar: #1a2612; --border: rgba(138,154,128,0.15); --border-hover: rgba(138,154,128,0.35); --accent: #8aaa74; --accent-glow: rgba(138,154,128,0.12); --green: #a4d007; --orange: #b8860b; --red: #b03a2e; --text: #d2e8b0; --text-dim: #8a9a80; --text-muted: #5a6a50; --font-h: Tahoma, sans-serif; --font-b: Tahoma, sans-serif; }
    body.classic .card { border-radius: 2px; } body.classic .card:hover { transform: none; box-shadow: 0 2px 8px rgba(0,0,0,0.4); }
    body.classic .card:hover .img-wrap img { transform: none; }
    body.classic .badge, body.classic .status-badge, body.classic .metacritic { border-radius: 2px; }
    body.classic .sort-btn { border-radius: 2px; background: linear-gradient(180deg, #3a4a30 0%, #2a3a20 100%); border-color: #4a5a40; }
    body.classic .sort-btn.active { background: linear-gradient(180deg, #7a9a64 0%, #5a7a47 100%); }
    body.classic .sidebar-btn { border-radius: 2px; font-size: 0.82rem; }
    body.classic .stat-card, body.classic .search-box input, body.classic .gear-btn, body.classic .gear-dropdown { border-radius: 2px; }
    body.classic .gear-btn { background: linear-gradient(180deg, #6b8a56 0%, #4a6637 100%); border: 1px solid #7a9a64; }
    body.classic .gear-dropdown { background: #1a2612; border-color: #4a5a40; }
    body.classic .gear-item { color: #8a9a80; } body.classic .gear-item.active-theme { color: #a4d007; }
    body.classic .gear-sep { background: rgba(138,154,128,0.15); } body.classic .gear-danger { color: #b03a2e; }
    body.classic .badge-high { background: #a4d007; } body.classic .badge-mid { background: #b8860b; } body.classic .badge-low { background: #b03a2e; }
    body.classic .new { text-shadow: none; } body.classic .name { color: #d2e8b0; font-size: 0.88rem; }
    body.classic .end-date { font-size: 0.7rem; color: #8a9a80; } body.classic .end-date-urgent { color: #c0392b; }
    body.classic .sidebar-logo .version { border-radius: 2px; }
    body.classic .price-slider input[type=range] { background: rgba(138,154,128,0.2); }
    body.classic .price-slider input[type=range]::-webkit-slider-thumb { background: #7a9a64; border-color: #1e2a16; }
    body.light { --bg-deep: #f0f2f5; --bg-card: #ffffff; --bg-sidebar: #f8f9fb; --border: rgba(0,0,0,0.07); --border-hover: rgba(0,0,0,0.16); --accent: #1a73e8; --accent-glow: rgba(26,115,232,0.08); --green: #2e7d32; --orange: #ef6c00; --red: #c62828; --text: #37474f; --text-dim: #78909c; --text-muted: #b0bec5; }
    body.light .stat-card, body.light .card { box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
    body.light .card:hover { box-shadow: 0 6px 20px rgba(0,0,0,0.08); }
    body.light .sidebar { box-shadow: 1px 0 4px rgba(0,0,0,0.03); }
    body.light .gear-dropdown { background: #fff; box-shadow: 0 8px 28px rgba(0,0,0,0.1); }
    body.light .gear-item { color: #78909c; } body.light .gear-item:hover { background: rgba(0,0,0,0.03); color: #37474f; }
    body.light .gear-item.active-theme { color: #1a73e8; } body.light .gear-sep { background: rgba(0,0,0,0.06); }
    body.light .gear-danger { color: #c62828; }
    body.light .name { color: #212121; } body.light .old { color: #b0bec5; } body.light .new { color: #2e7d32; text-shadow: none; }
    body.light .badge-high { background: #2e7d32; color: #fff; } body.light .badge-mid { background: #ef6c00; color: #fff; } body.light .badge-low { background: #c62828; }
    body.light .new-badge { background: #1a73e8; } body.light .status-badge { text-shadow: none; }
    body.light .metacritic.mc-high { background: #2e7d32; } body.light .metacritic.mc-mid { background: #f9a825; color: #333; }
    body.light .sort-btn.active { background: #1a73e8; color: #fff; }
    body.light .search-box input::placeholder { color: #b0bec5; } body.light .img-wrap { background: #e8eaed; }
    body.light .genre-tag { background: rgba(0,0,0,0.04); }
    body.light .end-date { color: #78909c; } body.light .end-date-urgent { color: #c62828; }
    body.light .stat-value { color: #212121; } body.light .stat-value.accent { color: #1a73e8; } body.light .stat-value.green { color: #2e7d32; }
    body.light .price-slider input[type=range] { background: rgba(26,115,232,0.1); }
    body.light .price-slider input[type=range]::-webkit-slider-thumb { background: #1a73e8; border-color: #f0f2f5; }
    body.light .price-val { color: #1a73e8; } body.light .empty { color: #b0bec5; }
    body.light .sidebar-logo h1 { color: #1a73e8; }
    body.light .sidebar-btn.active { background: linear-gradient(135deg, rgba(26,115,232,0.08), rgba(26,115,232,0.03)); color: #1a73e8; }
    body.light .new-only-btn.active { color: #1a73e8; } body.light .expiring-btn.active { color: #c62828; }
    body.light .cat-active { color: #2e7d32; }
    @media (max-width: 1100px) { .stats-row { grid-template-columns: repeat(3, 1fr); } }
    @media (max-width: 900px) {
        .sidebar { transform: translateX(-100%); }
    
    .mob-gear { position: relative; margin-left: auto; }
    .sidebar-close { display: block; }
        .sidebar.open .sidebar-close { display: block; }
        .main { margin-left: 0; padding: 14px 10px; }
        .mobile-bar { display: flex; align-items: center; gap: 10px; padding: 8px 0; margin-bottom: 10px; }
        .mobile-bar .mob-title { font-family: var(--font-h); font-size: 0.8rem; font-weight: 700; color: #fff; text-transform: uppercase; }
        .mobile-bar .mob-version { font-size: 0.5rem; color: var(--accent); background: var(--accent-glow); padding: 2px 5px; border-radius: 6px; font-weight: 600; }
        .mobile-bar .mob-burger { background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; width: 36px; height: 36px; display: flex; align-items: center; justify-content: center; font-size: 1.1rem; color: var(--text-dim); cursor: pointer; margin-left: auto; }
        .cart-bar { left: 0; }
    }
    @media (max-width: 640px) { .grid { grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 8px; } .stats-row { grid-template-columns: repeat(2, 1fr); } .price-slider { display: none; } }

    .card-select { position: absolute; top: 8px; left: 8px; width: 22px; height: 22px; border-radius: 4px; border: 2px solid rgba(255,255,255,0.3); background: rgba(0,0,0,0.4); cursor: pointer; z-index: 3; opacity: 0; transition: opacity 0.2s; display: flex; align-items: center; justify-content: center; color: #fff; font-size: 0.8rem; }
    .card:hover .card-select, .card-select.checked { opacity: 1; }
    .card-select.checked { background: var(--accent); border-color: var(--accent); }
    .card.selected { border-color: var(--accent); box-shadow: 0 0 0 2px var(--accent), 0 8px 28px rgba(0,0,0,0.35); }
    .cart-bar { position: fixed; bottom: 0; left: 260px; right: 0; background: var(--bg-card); border-top: 2px solid var(--accent); padding: 12px 24px; display: none; align-items: center; gap: 16px; z-index: 50; box-shadow: 0 -4px 20px rgba(0,0,0,0.4); }
    .cart-bar.visible { display: flex; }
    .cart-info { display: flex; gap: 20px; align-items: center; flex: 1; }
    .cart-stat { font-size: 0.82rem; color: var(--text-dim); }
    .cart-stat strong { color: #fff; font-family: var(--font-h); }
    .cart-stat .savings { color: var(--green); font-weight: 700; }
    .cart-actions { display: flex; gap: 8px; }
    .cart-btn { padding: 8px 18px; border-radius: 6px; border: none; font-family: var(--font-b); font-size: 0.82rem; font-weight: 600; cursor: pointer; transition: all 0.2s; }
    .cart-btn-steam { background: var(--green); color: #111; }
    .cart-btn-steam:hover { filter: brightness(1.15); }
    .cart-btn-clear { background: transparent; border: 1px solid var(--border); color: var(--text-dim); }
    .cart-btn-clear:hover { border-color: var(--border-hover); color: var(--text); }
    @media (max-width: 900px) { .cart-bar { left: 0; } }

    .help-overlay { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); z-index: 200; align-items: center; justify-content: center; }
    .help-overlay.visible { display: flex; }
    .help-box { background: var(--bg-card); border: 1px solid var(--border-hover); border-radius: 10px; padding: 24px 28px; max-width: 520px; width: 90%; max-height: 80vh; overflow-y: auto; box-shadow: 0 16px 50px rgba(0,0,0,0.5); }
    .help-box h2 { font-family: var(--font-h); font-size: 1.2rem; color: var(--accent); margin-bottom: 14px; }
    .help-box h3 { font-size: 0.88rem; color: var(--green); margin: 12px 0 6px; }
    .help-box p { font-size: 0.8rem; color: var(--text); line-height: 1.6; margin-bottom: 8px; }
    .help-box code { background: rgba(102,192,244,0.1); padding: 1px 6px; border-radius: 3px; font-family: Consolas, monospace; font-size: 0.76rem; color: var(--accent); }
    .help-close { float: right; background: none; border: none; color: var(--text-dim); font-size: 1.3rem; cursor: pointer; }
    .help-close:hover { color: var(--text); }

    .sidebar-overlay { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); z-index: 9; }
    .sidebar-overlay.visible { display: block; }
</style>
</head>
<body>

<div class="sidebar-overlay" id="sidebarOverlay" onclick="toggleSidebar()"></div>
<aside class="sidebar" id="sidebar">
    <button class="sidebar-close" onclick="toggleSidebar()">&#10005;</button>
    <div class="sidebar-logo"><span class="icon">&#127918;</span><h1>Steam Wishlist Sales Checker</h1><span class="version">v2.0.1</span></div>
    <div class="sidebar-section">
        <div class="sidebar-section-title">Filtres rapides</div>
        <button class="sidebar-btn active" data-genre="all"><span>&#128203; Tout</span></button>
        <button class="sidebar-btn new-only-btn" id="newOnlyBtn" onclick="toggleNewOnly()"><span>&#127381; Nouveaut&#233;s</span></button>
        <button class="sidebar-btn expiring-btn" id="expiringBtn" onclick="toggleExpiring()" style="display:none"><span>&#9203; Expire bient&#244;t</span></button>
    </div>
    <div class="sidebar-divider"></div>
    <div class="sidebar-section" id="genreSection">
        <div class="sidebar-section-title">Genres</div>
        $GenreButtonsHtml
    </div>
    <div class="sidebar-divider"></div>
    <div class="sidebar-section" id="catSection">
        <div class="sidebar-section-title">Mode de jeu</div>
        <button class="sidebar-btn active" data-cat="all"><span>&#128203; Tous</span></button>
        $CatButtonsHtml
    </div>
    <div class="sidebar-meta">G&#233;n&#233;r&#233; le $Now (${ElapsedSec}s)</div>
</aside>

<div class="main">
    <div class="mobile-bar"><span class="mob-title">&#127918; Steam Wishlist Sales Checker</span><span class="mob-version">v2.0.1</span><button class="mob-burger" onclick="toggleSidebar()">&#9776;</button></div>
    <div class="topbar">
        <div class="search-box"><input type="text" id="search" placeholder="Rechercher un jeu..." /></div>
        <div class="topbar-right">
            <span class="count-topbar" id="count">$SaleCount jeu$(if ($SaleCount -gt 1) {'x'}) en promo</span>
            <div class="gear-wrap" id="gearWrap">
                <button class="gear-btn" onclick="this.parentElement.classList.toggle('open')">&#9881;</button>
                <div class="gear-dropdown">
                    <button class="gear-item gear-danger" onclick="clearCache()"><span class="g-ico">&#128465;</span> Vider le cache</button>
                    <div class="gear-sep"></div>
                    <button class="gear-item" id="thModern" onclick="setTheme('modern')"><span class="g-ico">&#10024;</span> Th&#232;me Modern</button>
                    <button class="gear-item" id="thClassic" onclick="setTheme('classic')"><span class="g-ico">&#128421;</span> Th&#232;me Classic Steam</button>
                    <button class="gear-item" id="thLight" onclick="setTheme('light')"><span class="g-ico">&#9728;</span> Th&#232;me Light</button>
                    <div class="gear-sep"></div>
                    <a class="gear-item" href="https://steamdb.info/sales/history/" target="_blank" rel="noopener"><span class="g-ico">&#128197;</span> Calendrier des Soldes</a>
                <div class="gear-sep"></div>
                <button class="gear-item" onclick="showHelp()"><span class="g-ico">&#10067;</span> Aide</button>
                <a class="gear-item" href="https://github.com/W1p3out/steam-wishlist-sales-checker" target="_blank" rel="noopener"><span class="g-ico">&#128187;</span> GitHub</a>
                </div>
            </div>
        </div>
        </div>

    <div class="stats-row">
        <div class="stat-card"><div class="stat-label">Wishlist</div><div class="stat-value">$Total</div></div>
        <div class="stat-card"><div class="stat-label">En promo</div><div class="stat-value accent">$SaleCount</div></div>
        <div class="stat-card"><div class="stat-label">Meilleure remise</div><div class="stat-value green">-$BestDiscount%</div></div>
        <div class="stat-card"><div class="stat-label">Prix le plus bas</div><div class="stat-value green">$CheapestFmt&#8364;</div></div>
        <div class="stat-card"><div class="stat-label">Dur&#233;e du scan</div><div class="stat-value accent">${ElapsedSec}s</div></div>
    </div>

    <div class="toolbar-row">
        <span class="label">Trier :</span>
        <button class="sort-btn active" data-sort="alpha">A&#8594;Z</button>
        <button class="sort-btn" data-sort="alpha_desc">Z&#8594;A</button>
        <button class="sort-btn" data-sort="price_asc">Prix &#8593;</button>
        <button class="sort-btn" data-sort="price_desc">Prix &#8595;</button>
        <button class="sort-btn" data-sort="discount">% Promo</button>
        <button class="sort-btn" data-sort="metacritic">Metacritic</button>
        <div class="price-slider">
            <label>En dessous de</label>
            <input type="range" id="priceMax" min="0" max="$MaxPriceEur" value="$MaxPriceEur" step="1">
            <span class="price-val" id="priceLabel">${MaxPriceEur}&#8364;</span>
        </div>
    </div>

<div class="grid" id="grid">
$CardsHtml
</div>
<script>
var SALE_DATES = $(if ($SaleDates.Count -gt 0) { $SaleDates | ConvertTo-Json -Compress } else { '{}' });
document.querySelectorAll('.card').forEach((c,i) => { c.style.animationDelay = Math.min(i*30,800)+'ms'; });

// Panier
document.querySelectorAll('.card').forEach(c => {
    var cb = document.createElement('div');
    cb.className = 'card-select';
    cb.innerHTML = '&#10003;';
    c.querySelector('.img-wrap').appendChild(cb);
    cb.addEventListener('click', function(e) {
        e.preventDefault(); e.stopPropagation();
        c.classList.toggle('selected');
        cb.classList.toggle('checked');
        updateCart();
    });
});
function updateCart() {
    var sel = document.querySelectorAll('.card.selected');
    var bar = document.getElementById('cartBar');
    if (sel.length === 0) { bar.classList.remove('visible'); document.querySelector('.main').style.paddingBottom = ''; return; }
    bar.classList.add('visible');
    document.querySelector('.main').style.paddingBottom = '80px';
    var original = 0, total = 0;
    sel.forEach(function(c) {
        total += parseInt(c.dataset.sale) || 0;
        var oldEl = c.querySelector('.old');
        if (oldEl) { original += Math.round(parseFloat(oldEl.textContent.replace(/[^\d,]/g,'').replace(',','.')) * 100); }
    });
    var savings = original - total;
    document.getElementById('cartCount').textContent = sel.length;
    document.getElementById('cartTotal').textContent = (total / 100).toFixed(2).replace('.',',') + '\u20ac';
    document.getElementById('cartSavings').textContent = (savings / 100).toFixed(2).replace('.',',') + '\u20ac';
}

function openCartInSteam() {
    var sel = document.querySelectorAll('.card.selected');
    var ids = [];
    sel.forEach(function(c) {
        var m = c.href.match(/\/app\/(\d+)/);
        if (m) ids.push(m[1]);
    });
    if (ids.length === 0) return;
    for (var i = 0; i < ids.length; i++) {
        (function(id, delay) {
            setTimeout(function() {
                var a = document.createElement('a');
                a.href = 'https://store.steampowered.com/app/' + id + '/';
                a.target = '_blank';
                a.rel = 'noopener';
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
            }, delay);
        })(ids[i], i * 400);
    }
}
function toggleSidebar() {
    var sb = document.getElementById('sidebar');
    var ov = document.getElementById('sidebarOverlay');
    sb.classList.toggle('open');
    ov.classList.toggle('visible');
}
// Close sidebar when clicking a filter on mobile
document.querySelectorAll('.sidebar-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
        if (window.innerWidth <= 900) {
            document.getElementById('sidebar').classList.remove('open');
            document.getElementById('sidebarOverlay').classList.remove('visible');
        }
    });
});
function showHelp() {
    document.getElementById('helpOverlay').classList.add('visible');
    document.getElementById('gearWrap').classList.remove('open');
}
function clearCart() {
    document.querySelector('.main').style.paddingBottom = '';
    document.querySelectorAll('.card.selected').forEach(function(c) {
        c.classList.remove('selected');
        c.querySelector('.card-select').classList.remove('checked');
    });
    updateCart();
}

document.querySelectorAll('.sort-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.sort-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        const grid = document.getElementById('grid');
        const cards = [...grid.querySelectorAll('.card')];
        const type = btn.dataset.sort;
        cards.sort((a, b) => {
            if (type === 'alpha') return a.dataset.name.localeCompare(b.dataset.name, 'fr', {sensitivity:'base'});
            if (type === 'alpha_desc') return b.dataset.name.localeCompare(a.dataset.name, 'fr', {sensitivity:'base'});
            if (type === 'price_asc') return Number(a.dataset.sale) - Number(b.dataset.sale);
            if (type === 'price_desc') return Number(b.dataset.sale) - Number(a.dataset.sale);
            if (type === 'discount') return Number(b.dataset.disc) - Number(a.dataset.disc);
            if (type === 'metacritic') return Number(b.dataset.mc || 0) - Number(a.dataset.mc || 0);
        });
        cards.forEach(c => grid.appendChild(c));
    });
});

let activeGenre = 'all';
let activeCat = 'all';
document.querySelectorAll('.sidebar-btn[data-genre]').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.sidebar-btn[data-genre]').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        activeGenre = btn.dataset.genre;
        applyFilters();
    });
});

document.querySelectorAll('.sidebar-btn[data-cat]').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.sidebar-btn[data-cat]').forEach(b => { b.classList.remove('active'); b.classList.remove('cat-active'); });
        btn.classList.add('active');
        btn.classList.add('cat-active');
        activeCat = btn.dataset.cat;
        applyFilters();
    });
});

let showNewOnly = false;
let showExpiring = false;
function toggleNewOnly() {
    showNewOnly = !showNewOnly;
    const btn = document.getElementById('newOnlyBtn');
    if (showNewOnly) { btn.classList.add('active'); } else { btn.classList.remove('active'); }
    applyFilters();
}
function toggleExpiring() {
    showExpiring = !showExpiring;
    const btn = document.getElementById('expiringBtn');
    if (showExpiring) { btn.classList.add('active'); } else { btn.classList.remove('active'); }
    applyFilters();
}

function applyFilters() {
    const q = document.getElementById('search').value.toLowerCase();
    const pMax = parseInt(document.getElementById('priceMax').value) * 100;
    document.getElementById('priceLabel').textContent = document.getElementById('priceMax').value + '\u20ac';
    var now72 = Date.now() + 259200000;
    let visible = 0;
    document.querySelectorAll('.card').forEach(c => {
        const name = c.querySelector('.name').textContent.toLowerCase();
        const genres = (c.dataset.genres || '').toLowerCase();
        const cats = (c.dataset.cats || '').toLowerCase();
        const badge = c.dataset.badge || '';
        const price = parseInt(c.dataset.sale) || 0;
        const endTs = parseInt(c.dataset.endts || '0') * 1000;
        const matchSearch = name.includes(q);
        const matchGenre = activeGenre === 'all' || genres.split(',').some(g => g.trim().toLowerCase() === activeGenre.toLowerCase());
        const matchCat = activeCat === 'all' || cats.split(',').some(ct => ct.trim().toLowerCase() === activeCat.toLowerCase());
        const matchNew = !showNewOnly || badge === 'new';
        const matchExpiring = !showExpiring || (endTs > 0 && endTs <= now72 && endTs > Date.now());
        const matchPrice = price <= pMax;
        const show = matchSearch && matchGenre && matchCat && matchNew && matchExpiring && matchPrice;
        c.style.display = show ? '' : 'none';
        if (show) visible++;
    });
    document.getElementById('count').textContent = visible + ' jeu' + (visible > 1 ? 'x' : '') + ' en promo';
}

document.getElementById('priceMax').addEventListener('input', applyFilters);

document.getElementById('search').addEventListener('input', applyFilters);

function clearCache() {
    var cachePath = document.body.dataset.cachePath || '';
    alert('Pour vider le cache, relancez le script avec le parametre -ClearCache :\n\n.\\Steam_Wishlist_Sales_Checker.ps1 -SteamID VOTRE_ID -ClearCache\n\n' + (cachePath ? 'Fichier cache : ' + cachePath : 'Le prochain scan sera plus long car toutes les informations devront etre recuperees a nouveau.'));
}

var GENRE_ICONS = {'Action':'&#9876;&#65039;','Adventure':'&#128506;&#65039;','Casual':'&#129513;','Early Access':'&#129514;','Free To Play':'&#127873;','Free to Play':'&#127873;','Indie':'&#128377;&#65039;','Massively Multiplayer':'&#127760;','Racing':'&#127950;&#65039;','RPG':'&#127922;','Simulation':'&#127959;&#65039;','Sports':'&#9917;','Strategy':'&#9823;&#65039;','Animation &amp; Modeling':'&#127902;&#65039;','Audio Production':'&#128266;','Design &amp; Illustration':'&#127912;','Education':'&#128218;','Game Development':'&#127916;','Photo Editing':'&#128248;','Utilities':'&#128295;&#65039;','Video Production':'&#127909;','Web Publishing':'&#127760;'};
var CAT_ICONS = {'Single-player':'&#128100;','Single player':'&#128100;','Un joueur':'&#128100;','Multi-player':'&#128101;','Multi player':'&#128101;','Multijoueur':'&#128101;','Co-op':'&#129309;','Online Co-op':'&#129309;','Online Co-Op':'&#129309;','Coop':'&#129309;','LAN Co-op':'&#128268;','LAN Co-Op':'&#128268;','PvP':'&#9889;','Online PvP':'&#9889;','LAN PvP':'&#9876;&#65039;','MMO':'&#127760;','Cross-Platform Multiplayer':'&#128421;&#65039;','Multi cross-platform':'&#128421;&#65039;','Shared/Split Screen':'&#128250;','Shared/Split Screen Co-op':'&#128250;','Shared/Split Screen PvP':'&#128250;'};
document.querySelectorAll('.sidebar-btn[data-genre]').forEach(function(b) {
    var g = b.dataset.genre; if (g !== 'all' && GENRE_ICONS[g]) {
        var sp = b.querySelector('span'); if (sp) sp.innerHTML = GENRE_ICONS[g] + ' ' + sp.textContent;
    }
});
document.querySelectorAll('.sidebar-btn[data-cat]').forEach(function(b) {
    var ct = b.dataset.cat; if (ct !== 'all' && CAT_ICONS[ct]) {
        var sp = b.querySelector('span'); if (sp) sp.innerHTML = CAT_ICONS[ct] + ' ' + sp.textContent;
    }
});

function setTheme(theme) {
    document.body.className = (theme === 'classic') ? 'classic' : (theme === 'light') ? 'light' : '';
    document.cookie = 'theme=' + theme + ';path=/;max-age=31536000';
    document.querySelectorAll('.gear-item[id^="th"]').forEach(function(el) { el.classList.remove('active-theme'); });
    var id = theme === 'classic' ? 'thClassic' : theme === 'light' ? 'thLight' : 'thModern';
    document.getElementById(id).classList.add('active-theme');
}
(function() {
    const m = document.cookie.match(/theme=(\w+)/);
    if (m) {
        if (m[1] === 'classic') { document.body.classList.add('classic'); }
        else if (m[1] === 'light') { document.body.classList.add('light'); }
    }
    var active = (m && m[1] === 'classic') ? 'thClassic' : (m && m[1] === 'light') ? 'thLight' : 'thModern';
    document.querySelectorAll('.gear-item[id^="th"]').forEach(function(el) { el.classList.remove('active-theme'); });
    document.getElementById(active).classList.add('active-theme');
})();
document.addEventListener('click', function(e) {
    var gw = document.getElementById('gearWrap');
    if (gw && !gw.contains(e.target)) gw.classList.remove('open');
});

// ── Dates de fin de promo (countdown live) ──
if (SALE_DATES && Object.keys(SALE_DATES).length > 0) {
    var countdownEls = [];
    var hasAny = false;
    document.querySelectorAll('.card').forEach(function(card) {
        var m = card.href.match(/\/app\/(\d+)/);
        if (m && SALE_DATES[m[1]]) {
            card.dataset.endts = SALE_DATES[m[1]];
            var el = document.createElement('span');
            el.className = 'end-date';
            el.dataset.endTs = SALE_DATES[m[1]];
            card.querySelector('.info').appendChild(el);
            countdownEls.push(el);
            hasAny = true;
        }
    });
    if (hasAny) { document.getElementById('expiringBtn').style.display = ''; }
    function updateCountdowns() {
        var now = Date.now();
        countdownEls.forEach(function(el) {
            var endMs = parseInt(el.dataset.endTs) * 1000;
            var diff = endMs - now;
            if (diff <= 0) { el.textContent = '\u23f3 Termin\u00e9e !'; el.className = 'end-date end-date-urgent'; return; }
            var d = Math.floor(diff / 86400000);
            var h = Math.floor((diff % 86400000) / 3600000);
            var m = Math.floor((diff % 3600000) / 60000);
            var s = Math.floor((diff % 60000) / 1000);
            var txt = '\u23f3 ';
            if (d > 0) txt += d + 'j ' + h + 'h ' + m + 'min';
            else if (h > 0) txt += h + 'h ' + ('0'+m).slice(-2) + 'min ' + ('0'+s).slice(-2) + 's';
            else txt += m + 'min ' + ('0'+s).slice(-2) + 's';
            el.textContent = txt;
            el.className = (diff <= 259200000) ? 'end-date end-date-urgent' : 'end-date';
        });
    }
    updateCountdowns();
    setInterval(updateCountdowns, 1000);
}
</script>
</div>
<div class="help-overlay" id="helpOverlay" onclick="if(event.target===this)this.classList.remove('visible')">
    <div class="help-box">
        <button class="help-close" onclick="document.getElementById('helpOverlay').classList.remove('visible')">&times;</button>
        <h2>&#10067; Aide &#8212; Steam Wishlist Sales Checker</h2>
        <h3>&#128270; Recherche</h3>
        <p>Tapez un nom de jeu pour filtrer en temps r&#233;el.</p>
        <h3>&#9881; Roue crant&#233;e</h3>
        <p>Actualiser le scan, vider le cache, changer de th&#232;me (Modern / Classic Steam / Light), acc&#233;der au calendrier des soldes Steam.</p>
        <h3>&#128203; Filtres</h3>
        <p>Cliquez sur un genre ou mode de jeu dans la barre lat&#233;rale pour filtrer. Tous les filtres sont cumulatifs avec la recherche et le slider prix.</p>
        <h3>&#127381; Nouveaut&#233;s</h3>
        <p>Affiche uniquement les jeux apparus en promo depuis le dernier scan.</p>
        <h3>&#9203; Expire bient&#244;t</h3>
        <p>Visible si le scraping des dates est activ&#233;. Affiche les promos expirant sous 72h.</p>
        <h3>&#9203; Dates de fin de promo</h3>
        <p>Ajoutez <code>-ScrapeEndDates</code> en argument de l'ex&#233;cutable/PowerShell pour activer le scraping des dates de fin. Non activ&#233; par d&#233;faut car Steam peut casser cette possibilit&#233; &#224; tout moment. Le scraping ajoute ~1s par jeu.</p>
        <h3>&#128722; Panier</h3>
        <p>Cliquez sur le &#10003; en haut &#224; gauche d'une carte pour s&#233;lectionner un jeu. Une barre appara&#238;t en bas avec le total, l'&#233;conomie et un bouton pour ouvrir les pages Steam. D&#233;sactivez votre bloqueur de pubs pour ouvrir plusieurs onglets.</p>
        <h3>&#128187; Arguments Ex&#233;cutable/PowerShell</h3>
        <p><code>-SteamID 12345678901234567</code> &#8212; Votre Steam ID 64-bit</p>
        <p><code>-Country fr</code> &#8212; Code pays pour les prix (d&#233;faut : fr)</p>
        <p><code>-ClearCache</code> &#8212; Vider le cache avant le scan</p>
        <p><code>-ScrapeEndDates</code> &#8212; Scraper les dates de fin de promo</p>
        <p><code>-OutputPath C:\chemin\fichier.html</code> &#8212; Chemin du HTML g&#233;n&#233;r&#233;</p>
        <h3>&#128640; Cr&#233;er un raccourci (Windows)</h3>
        <p>Clic droit sur l'ex&#233;cutable &#8594; Cr&#233;er un raccourci.</p>
        <p>Clic droit sur le raccourci &#8594; Propri&#233;t&#233;s. Cible :</p>
        <p><code>"C:\chemin\Steam_Wishlist_Sales_Checker.exe" -SteamID 12345678901234567</code></p>
        <p>Vous pouvez ainsi lancer un scan en double-cliquant, sans configurer &#224; chaque lancement. Les autres arguments se placent &#224; la suite du SteamID.</p>
        <h3>&#127918; Version</h3>
        <p>SWSC v2.0.1 &#8212; Code g&#233;n&#233;r&#233; avec Claude (Anthropic)</p>
    </div>
</div>
<div class="cart-bar" id="cartBar">
    <div class="cart-info">
        <span class="cart-stat">&#128722; <strong id="cartCount">0</strong> jeu(x)</span>
        <span class="cart-stat">Total : <strong id="cartTotal">0,00&#8364;</strong></span>
        <span class="cart-stat">&#201;conomie : <span class="savings" id="cartSavings">0,00&#8364;</span></span>
    </div>
    <div class="cart-actions">
        <button class="cart-btn cart-btn-steam" onclick="openCartInSteam()" title="D&#233;sactivez votre bloqueur de pubs si les pages ne s'ouvrent pas">&#127918; Ouvrir sur Steam (Web)</button>
        <button class="cart-btn cart-btn-clear" onclick="clearCart()">&#10005; Vider</button>
    </div>
</div>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutputPath, $Html, [System.Text.Encoding]::UTF8)

$Stopwatch.Stop()
Write-Ok "Page generee : $OutputPath"
Write-Ok "Duree totale : $([math]::Round($Stopwatch.Elapsed.TotalSeconds))s"

# -- Open in browser -----------------------------------------------
Write-Host ''
Write-Host '  Ouverture dans le navigateur...' -ForegroundColor Cyan
Start-Process $OutputPath

Write-Host ''
Write-Host '  +===============================================+' -ForegroundColor Green
Write-Host '  |          [OK] Termine !                       |' -ForegroundColor Green
Write-Host '  +===============================================+' -ForegroundColor Green
Write-Host ''
