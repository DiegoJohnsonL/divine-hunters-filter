<#
.SYNOPSIS
    Rebuilds the custom PoE2 loot filter with live market data from poe2scout.

.DESCRIPTION
    Three-stage pipeline:

      1. Pick a base filter - the FilterBlade-generated copy the game caches in
         OnlineFilters\, which carries fresher economy tiering than the GitHub release.
      2. Run _filter-build-script.awk over it, applying the 22 personal customisations.
    3. Insert [ECONOMY] blocks above the essence and unique tierlists. The essence
       policy hides known low-value essences; the unique policy promotes bases the
       market now values above their NeverSink tier and quiets apex bases that died.

    The economy block is regenerated from scratch every run, so it never accumulates.
    Unique rules are only promoted or softened; the separate essence policy also hides
    known lower-value essences so stale stock rules cannot re-show them.

    NeverSink's own aspect data is used to drop uniques that cannot drop from monsters
    (Temporalis, Bursting Decay, Duality...). Without that filter, chase items that only
    exist as boss/vendor drops would promote their bases into the apex tier forever.

.EXAMPLE
    .\_filter-economy-update.ps1 -DryRun
    Prints the report without touching the installed filter.

.EXAMPLE
    .\_filter-economy-update.ps1
    Rebuilds and installs.
#>

[CmdletBinding()]
param(
    # Empty = auto-detect the current league from the poe2scout league list.
    [string] $League = '',

    # Unique price confidence. A normally liquid unique can fall back to its live
    # snapshot, while a thin or zero-listing unique must have sustained history.
    # Alias keeps old scheduled/manual commands using -MinListings compatible.
    [Alias('MinListings')]
    [int]    $UniqueMinListings = 5,
    [int]    $UniqueHistoryMinPoints = 5,

    # Promotion thresholds, in divine, on the best world-droppable unique for a base.
    [double] $DivS = 10.0,
    [double] $DivA = 2.0,
    [double] $DivB = 0.5,

    # Apex (t1) bases whose best unique is worth less than this get the quieter
    # t3 treatment instead of PlayAlertSound 6. Still shown, just not a siren.
    [double] $QuietFloor = 0.25,
    [switch] $NoQuiet,

    # Essence pickup policy. The normal floor uses a minimum live market quantity;
    # the thin-market floor protects a genuinely expensive essence with fewer listings
    # without allowing one-listing price spikes to turn the filter noisy.
    [double] $EssenceFloor = 0.10,
    [int]    $EssenceMinListings = 10,
    [double] $EssenceThinFloor = 0.25,
    [int]    $EssenceThinMinListings = 5,

    # Lineage support gems are non-stackable and the public stock tiers intentionally
    # show even their low C-tier entries. Use a higher live-value floor, but retain
    # thin-market chase gems and keep names with no usable price history visible.
    [double] $LineageFloor = 0.50,
    [int]    $LineageMinListings = 5,
    [double] $LineageThinFloor = 1.00,
    [int]    $LineageThinMinListings = 3,
    [double] $LineageChaseFloor = 2.00,

    # Unique pickup floor. Known visible bases below this value are hidden after
    # the explicit scepter and special-state exceptions emitted below.
    [double] $UniqueFloor = 0.50,

    [string] $BaseFilter = '',
    [string] $Output     = '',
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildAwk  = Join-Path $Root '_filter-build-script.awk'
$CacheDir  = Join-Path $Root '_filter-cache'
$LogPath   = Join-Path $Root '_filter-economy-update.log'
$UserAgent = 'poe2-personal-filter/1.0 (+local script; contact via github.com/NeverSinkDev filter user)'
$ApiRoot   = 'https://api.poe2scout.com'
$AspectUrl = 'https://raw.githubusercontent.com/NeverSinkDev/Filter-ItemEconomyAspects/master/p2/uniques.generic.txt'

if ($Output -eq '')     { $Output     = Join-Path $Root 'Divine Hunters.filter' }
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir | Out-Null }

$script:Lines = @()
function Say([string] $m) {
    Write-Host $m
    $script:Lines += ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m)
}

function Get-Json([string] $Url) {
    Invoke-RestMethod -Uri $Url -Headers @{ 'User-Agent' = $UserAgent } -TimeoutSec 40
}

# ---------------------------------------------------------------- 0. locate awk
$awk = $null
$cmd = Get-Command awk -ErrorAction SilentlyContinue
if ($null -ne $cmd) { $awk = $cmd.Source }
if ($null -eq $awk) {
    foreach ($p in @("$env:ProgramFiles\Git\usr\bin\awk.exe",
                     "${env:ProgramFiles(x86)}\Git\usr\bin\awk.exe",
                     "$env:LOCALAPPDATA\Programs\Git\usr\bin\awk.exe")) {
        if (Test-Path $p) { $awk = $p; break }
    }
}
if ($null -eq $awk)            { throw "awk not found. Install Git for Windows, or add awk to PATH." }
if (-not (Test-Path $BuildAwk)) { throw "Build script missing: $BuildAwk" }

# ------------------------------------------------- 1. pick the freshest base filter
if ($BaseFilter -eq '') {
    $onlineDir = Join-Path $Root 'OnlineFilters'
    $best = $null
    if (Test-Path $onlineDir) {
        foreach ($f in Get-ChildItem -Path $onlineDir -File) {
            $head = Get-Content $f.FullName -TotalCount 12 -ErrorAction SilentlyContinue
            if (($head -join "`n") -notmatch '#name:NeverSink-6uberplu-poe2') { continue }
            $stampLine = $head | Where-Object { $_ -like '#lastUpdate:*' } | Select-Object -First 1
            $stamp = [datetime]::MinValue
            if ($stampLine) { [void][datetime]::TryParse(($stampLine -replace '^#lastUpdate:', ''), [ref] $stamp) }
            if ($null -eq $best -or $stamp -gt $best.Stamp) {
                $best = [pscustomobject]@{ Path = $f.FullName; Stamp = $stamp }
            }
        }
    }
    if ($null -eq $best) {
        throw "No cached 6-UBER-PLUS filter found in $onlineDir. Select the online filter once in-game to populate it, or pass -BaseFilter."
    }
    $BaseFilter = $best.Path
}

$verLine = (Get-Content $BaseFilter -TotalCount 20 | Where-Object { $_ -like '# VERSION:*' } | Select-Object -First 1)
$baseVer = ($verLine -replace '^# VERSION:\s*', '').Trim()
Say "base filter : $(Split-Path -Leaf $BaseFilter)  (VERSION $baseVer)"
if ($baseVer -notmatch '^\d+\.\d+\.\d+\.\d{4}\.\d+') {
    Say "  WARNING: no economy datestamp on that version - this looks like the GitHub release, which lags."
}

# ------------------------------------------------------------- 2. aspect data
$aspectFile = Join-Path $CacheDir 'uniques.aspects.json'
$needAspects = $true
if (Test-Path $aspectFile) {
    $age = (Get-Date) - (Get-Item $aspectFile).LastWriteTime
    if ($age.TotalDays -lt 7) { $needAspects = $false }
}
if ($needAspects) {
    Say "fetching NeverSink aspect data"
    Invoke-WebRequest -Uri $AspectUrl -Headers @{ 'User-Agent' = $UserAgent } -OutFile $aspectFile -TimeoutSec 40
}

# noDrop:     name -> $true when the unique cannot drop from monsters
# aspectBase: name -> the base type the FILTER uses. poe2scout reports trade-site base
#             names, which disagree for tablets - it calls Visions of Paradise a
#             "Precursor Tablet" where the game and the filter say "Irradiated Tablet".
#             NeverSink's data is authoritative here because the filter is built from it.
$noDrop          = @{}
$aspectBase       = @{}
$preventHideBases = @{}
$droppableNamesByBase = @{}
# These single-outcome Runeforging ingredients have been reviewed against the live
# market. Their recipe eligibility alone is not a reason to defeat the pickup floor;
# if demand ever makes them valuable, the normal price promotion restores them.
$preventHidePriceFloorOverrides = @{
    'Leaden Greathammer' = $true # Chober Chaber
    'Torn Gloves'        = $true # Painter's Servant
}
$aspects = ([System.IO.File]::ReadAllText($aspectFile, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json).Aspects
foreach ($baseProp in $aspects.PSObject.Properties) {
    foreach ($u in $baseProp.Value) {
        $isNonDrop = $u.Aspects -contains 'NonWorldDrop' -or $u.Aspects -contains 'NonDrop'
        if ($isNonDrop) { $noDrop[$u.Name] = $true }
        if (-not [string]::IsNullOrWhiteSpace($u.BaseType)) {
            $aspectBase[$u.Name] = $u.BaseType
            if ($u.Aspects -contains 'PreventHiding') { $preventHideBases[$u.BaseType] = $true }
            if (-not $isNonDrop) {
                if (-not $droppableNamesByBase.ContainsKey($u.BaseType)) { $droppableNamesByBase[$u.BaseType] = @() }
                $droppableNamesByBase[$u.BaseType] = @($droppableNamesByBase[$u.BaseType]) + @($u.Name)
            }
        }
    }
}
foreach ($base in $preventHidePriceFloorOverrides.Keys) {
    $outcomes = @($droppableNamesByBase[$base])
    if ($outcomes.Count -ne 1) {
        throw "Reviewed PreventHiding override '$base' now has $($outcomes.Count) world-droppable outcomes; review before allowing the live price floor to hide it."
    }
}
Say "aspects     : $($aspectBase.Count) uniques mapped, $($noDrop.Count) flagged as non-world-drop, $($preventHideBases.Count) protected bases"

# ----------------------------------------------------------------- 3. league
$leagues = Get-Json "$ApiRoot/poe2/Leagues"
if ($League -eq '') {
    $pick = $leagues | Where-Object { $_.IsCurrent -and $_.Value -notlike 'HC *' } | Select-Object -First 1
    if ($null -eq $pick) { throw "Could not auto-detect a current softcore league." }
    $League = $pick.Value
} else {
    $pick = $leagues | Where-Object { $_.Value -eq $League } | Select-Object -First 1
    if ($null -eq $pick) { throw "League '$League' not found." }
}
$divine = [double] $pick.DivinePrice
Say "league      : $League   1 divine = $([math]::Round($divine)) ex"

# ------------------------------------------------------- shared snapshot price helper
# Some stackable-category responses contain inline price logs. The unique response
# currently exposes null placeholders instead, so uniques use the bulk history API
# further below rather than silently falling back to a one-day asking price.
function Get-StablePrice($item) {
    $logs = @($item.PriceLogs | Where-Object { $null -ne $_ -and $null -ne $_.Price })
    if ($logs.Count -ge 3) {
        $sorted = @($logs | ForEach-Object { [double] $_.Price } | Sort-Object)
        return $sorted[[int]($sorted.Count / 2)]
    }
    return [double] $item.CurrentPrice
}

# ------------------------------------------------------------- 4. essence prices
# Essences are stackable, but a single pickup still costs a stop, inventory space and
# later bulk-selling time. Use the larger of the current and trailing stable price so
# a real rise is not hidden, while requiring liquidity before trusting a thin market.
$essenceItems = @()
$essencePage = 1
do {
    $essenceUrl = "$ApiRoot/poe2/Leagues/$([uri]::EscapeDataString($League))/Currencies/ByCategory?category=essences&perPage=200&page=$essencePage"
    $essenceResponse = Get-Json $essenceUrl
    $essenceItems += @($essenceResponse.Items)
    $essencePage++
} while ($essencePage -le $essenceResponse.Pages)

$essenceShow = @()
$essenceHide = @()
$essenceSeen = 0
foreach ($i in $essenceItems) {
    $essenceSeen++
    $stableEx = Get-StablePrice $i
    $currentEx = [double] $i.CurrentPrice
    $stableDiv = $stableEx / $divine
    $currentDiv = $currentEx / $divine
    $effectiveDiv = [math]::Max($stableDiv, $currentDiv)
    $qty = [int] $i.CurrentQuantity

    # A normal listing pool needs 10+ listings. A thinner pool is accepted only when
    # the item is already at least 0.25 divine and has 5+ listings. This deliberately
    # rejects one-listing spikes such as cheap essences with stale price history.
    $trusted = ($qty -ge $EssenceMinListings) -or
               ($qty -ge $EssenceThinMinListings -and $effectiveDiv -ge $EssenceThinFloor)
    $row = [pscustomobject]@{
        Base = $i.Text
        Div  = $effectiveDiv
        Ex   = $effectiveDiv * $divine
        Qty  = $qty
    }
    if ($trusted -and $effectiveDiv -ge $EssenceFloor) {
        $essenceShow += $row
    } else {
        # The API enumerates the complete essence family. Hiding every known item that
        # fails the pickup policy ensures the stock S/A/B/C rules cannot re-show it.
        $essenceHide += $row
    }
}
$essenceShow = @($essenceShow | Sort-Object Div -Descending)
$essenceHide = @($essenceHide | Sort-Object Base)
Say "essences    : $essenceSeen parsed; show $($essenceShow.Count) at >= $EssenceFloor div, hide $($essenceHide.Count) below policy"
foreach ($row in $essenceShow) {
    Say ('   +essence  {0,-34} {1,8:N2} div  (n={2})' -f $row.Base, $row.Div, $row.Qty)
}

# ------------------------------------------------------- 4b. lineage support gem prices
# Lineage supports cannot be engraved from uncut support gems, so their only useful
# exception is market/build demand. The item snapshot has current prices; the bulk
# history endpoint supplies recent prices and listing quantities for liquidity guards.
$lineageItems = @(
    (Get-Json "$ApiRoot/poe2/Leagues/$([uri]::EscapeDataString($League))/Items") |
        Where-Object { $_.CategoryApiId -eq 'lineagesupportgems' }
)
$priceHistoryResponse = Get-Json "$ApiRoot/poe2/Leagues/$([uri]::EscapeDataString($League))/Items/PriceHistory"
$priceHistory = @{}
foreach ($history in @($priceHistoryResponse.ItemHistories)) {
    $priceHistory[[int]$history.ItemId] = @($history.History)
}

# poe2scout can retain a historical name after the game renames a lineage support.
# Canonicalising this one alias prevents the zero-price old row from affecting the
# current Dominus' Grasp entry.
$lineageAliases = @{ "Piety's Mercy" = "Dominus' Grasp" }
# A stock lineage can exist in the game and NeverSink tierlist before poe2scout adds
# it to the item snapshot. Keep missing names visible by default, but hide narrowly
# reviewed low-value omissions until the live API begins publishing them. Once a name
# appears in poe2scout, the normal live-value policy automatically takes authority.
$lineageMissingLowValue = @("Helbrym's Hide")
$lineageByBase = @{}
$lineageShow = @()
$lineageHide = @()
$lineageKeep = @()
$lineageSeen = $lineageItems.Count

foreach ($i in $lineageItems) {
    $base = [string]$i.Text
    if ($lineageAliases.ContainsKey($base)) { $base = $lineageAliases[$base] }

    $logs = @()
    if ($priceHistory.ContainsKey([int]$i.ItemId)) {
        $logs = @($priceHistory[[int]$i.ItemId] | Select-Object -First 10)
    }
    $prices = @($logs | Where-Object { $null -ne $_ -and $null -ne $_.Price } |
        ForEach-Object { [double]$_.Price })
    if ($prices.Count -gt 0) {
        $sorted = @($prices | Sort-Object)
        $medianEx = [double]$sorted[[int][math]::Floor($sorted.Count / 2)]
    } else {
        $medianEx = [double]$i.CurrentPrice
    }
    $currentEx = [double]$i.CurrentPrice
    $effectiveEx = [math]::Max($currentEx, $medianEx)
    $qty = if ($logs.Count -gt 0) { [int]$logs[0].Quantity } else { 0 }
    $row = [pscustomobject]@{
        Base        = $base
        CurrentEx   = $currentEx
        StableEx    = $effectiveEx
        Div         = $effectiveEx / $divine
        Qty         = $qty
        History     = $prices.Count
        ItemId      = [int]$i.ItemId
    }

    # Prefer the canonical/highest-value row if an old alias and current name both
    # appear in the API snapshot.
    if (-not $lineageByBase.ContainsKey($base) -or
        $row.StableEx -gt $lineageByBase[$base].StableEx) {
        $lineageByBase[$base] = $row
    }
}

foreach ($row in $lineageByBase.Values) {
    # No price history is an information gap, not evidence of low value. Keep it
    # visible so a newly added or thinly traded lineage support cannot disappear.
    if ($row.History -eq 0 -or $row.StableEx -le 0) {
        $lineageKeep += $row
    }
    elseif ($row.Div -ge $LineageChaseFloor -or
            ($row.Div -ge $LineageThinFloor -and $row.Qty -ge $LineageThinMinListings) -or
            ($row.Div -ge $LineageFloor -and $row.Qty -ge $LineageMinListings)) {
        $lineageShow += $row
    }
    else {
        $lineageHide += $row
    }
}
foreach ($base in $lineageMissingLowValue) {
    if (-not $lineageByBase.ContainsKey($base)) {
        $lineageHide += [pscustomobject]@{
            Base = $base; CurrentEx = 0; StableEx = 0; Div = 0; Qty = 0; History = 0; ItemId = 0
        }
        Say ('   !lineage  {0,-30} reviewed low-value fallback (missing from poe2scout)' -f $base)
    }
}
$lineageShow = @($lineageShow | Sort-Object Div -Descending)
$lineageHide = @($lineageHide | Sort-Object Base)
$lineageKeep = @($lineageKeep | Sort-Object Base)
Say "lineage    : $lineageSeen parsed; show $($lineageShow.Count) at >= $LineageFloor div with liquidity, keep $($lineageKeep.Count) unknown/unpriced, hide $($lineageHide.Count)"
foreach ($row in $lineageShow) {
    Say ('   +lineage  {0,-30} {1,8:N2} div  (n={2})' -f $row.Base, $row.Div, $row.Qty)
}
foreach ($row in $lineageKeep) {
    Say ('   ?lineage  {0,-30} no trusted price data' -f $row.Base)
}

$categories = (Get-Json "$ApiRoot/poe2/Leagues/$([uri]::EscapeDataString($League))/Items/Categories").UniqueCategories
$best = @{}   # base type -> @{ Div; Name; Qty }
$uncertainBases = @{}
$thinHistoryRows = @()
$seen = 0; $skipNoDrop = 0; $historyBacked = 0; $thinHistoryBacked = 0; $liveOnly = 0; $skipUntrusted = 0

foreach ($cat in $categories) {
    $page = 1
    do {
        $url = "$ApiRoot/poe2/Leagues/$([uri]::EscapeDataString($League))/Uniques/ByCategory?category=$($cat.ApiId)&perPage=200&page=$page"
        try { $r = Get-Json $url } catch { Say "  WARN: $($cat.ApiId) page $page failed - $($_.Exception.Message)"; break }
        foreach ($i in $r.Items) {
            $seen++
            $name = $i.Name
            if ($aspectBase.ContainsKey($name)) { $base = $aspectBase[$name] }
            else                                { $base = $i.ItemMetadata.base_type }
            if ([string]::IsNullOrWhiteSpace($base)) { continue }
            if ($noDrop.ContainsKey($name))          { $skipNoDrop++; continue }

            $qty = [int] $i.CurrentQuantity
            $currentEx = [double] $i.CurrentPrice
            $historyRows = @()
            if ($priceHistory.ContainsKey([int]$i.ItemId)) {
                $historyRows = @($priceHistory[[int]$i.ItemId] | Select-Object -First 24)
            }
            $historyPrices = @($historyRows |
                Where-Object { $null -ne $_ -and $null -ne $_.Price -and [double]$_.Price -gt 0 } |
                ForEach-Object { [double]$_.Price })

            $trusted = $false
            $mode = ''
            $priceEx = 0.0
            if ($historyPrices.Count -ge $UniqueHistoryMinPoints) {
                # A median is robust for liquid items. For rare items use the lower
                # quartile: the value must have survived several historical snapshots,
                # and one or two optimistic listings cannot establish the price.
                $sortedHistory = @($historyPrices | Sort-Object)
                if ($qty -ge $UniqueMinListings) {
                    $priceEx = [double]$sortedHistory[[int][math]::Floor($sortedHistory.Count / 2)]
                    $mode = 'history-median'
                } else {
                    $quartileIndex = [int][math]::Floor(($sortedHistory.Count - 1) * 0.25)
                    $priceEx = [double]$sortedHistory[$quartileIndex]
                    $mode = 'history-floor'
                    $thinHistoryBacked++
                }
                $historyBacked++
                $trusted = $true
            } elseif ($qty -ge $UniqueMinListings -and $currentEx -gt 0) {
                $priceEx = $currentEx
                $mode = 'live-fallback'
                $liveOnly++
                $trusted = $true
            }

            if (-not $trusted) {
                # An information gap is not evidence that the item is cheap. If any
                # droppable unique on a base is untrusted, that base cannot enter the
                # generated hide floor even when another common variant is inexpensive.
                $uncertainBases[$base] = $true
                $skipUntrusted++
                continue
            }

            $d = $priceEx / $divine
            if ($mode -eq 'history-floor') {
                $thinHistoryRows += [pscustomobject]@{ Base = $base; Div = $d; Name = $name; Qty = $qty; Points = $historyPrices.Count }
            }
            if (-not $best.ContainsKey($base) -or $d -gt $best[$base].Div) {
                $best[$base] = @{ Div = $d; Name = $name; Qty = $qty; History = $historyPrices.Count; Mode = $mode }
            }
        }
        $page++
    } while ($page -le $r.Pages)
}
Say "prices      : $seen uniques seen, $skipNoDrop non-world-drop, $historyBacked history-backed ($thinHistoryBacked thin/zero-listing), $liveOnly live fallbacks, $skipUntrusted untrusted"
Say "             $($best.Count) bases priced; $($uncertainBases.Count) uncertain bases protected from hiding"
foreach ($row in @($thinHistoryRows | Sort-Object Div -Descending | Select-Object -First 8)) {
    Say ('   ~rare  {0,-28} {1,9:N2} div  (n={2}, history={3}, {4})' -f $row.Base, $row.Div, $row.Qty, $row.Points, $row.Name)
}

# --------------------------------------------- 5. current tiers from the base filter
# A rule owns every BaseType between its header and the next blank line. Rules with no
# BaseType at all (restex) must not inherit the next rule's list.
$rank = @{ t1 = 3; multispecialhigh = 3; sekhemaring = 3; t2 = 2; multispecial = 2
           t3 = 1; t3boss = 1; hideable = 0 }
$current = @{}
$inRule = $false; $ruleTier = ''
# Explicit UTF-8: the online filters carry no BOM, so PS 5.1's Get-Content would
# fall back to the ANSI codepage and corrupt accented base names.
foreach ($line in [System.IO.File]::ReadAllLines($BaseFilter, (New-Object System.Text.UTF8Encoding($false)))) {
    if ($line -match '^(Show|Hide)\b.*\$type->uniques \$tier->([A-Za-z0-9]+)') {
        $inRule = $true; $ruleTier = $Matches[2]; continue
    }
    if ($line -match '^\s*$' -or $line -match '^(Show|Hide|#)') { $inRule = $false; continue }
    if ($inRule -and $line -match '^\s+BaseType\s*=*\s*(.+)$') {
        foreach ($m in [regex]::Matches($Matches[1], '"([^"]+)"')) {
            $b = $m.Groups[1].Value
            $r = 0
            if ($rank.ContainsKey($ruleTier)) { $r = $rank[$ruleTier] }
            if (-not $current.ContainsKey($b) -or $r -gt $current[$b]) { $current[$b] = $r }
        }
        $inRule = $false
    }
}
Say "tierlist    : $($current.Count) unique bases parsed from the base filter"

# Only hide bases that the current filter would otherwise show. T4/hideable bases
# are already hidden by stock, while unpriced or untracked bases remain untouched.
$uniqueHide = @()
foreach ($entry in $best.GetEnumerator()) {
    $base = $entry.Key
    $row  = $entry.Value
    $protectedByAspect = $preventHideBases.ContainsKey($base) -and
        -not $preventHidePriceFloorOverrides.ContainsKey($base)
    if ($current.ContainsKey($base) -and $current[$base] -gt 0 -and
        -not $uncertainBases.ContainsKey($base) -and
        -not $protectedByAspect -and $row.Div -lt $UniqueFloor) {
        $uniqueHide += [pscustomobject]@{ Base = $base; Div = $row.Div; Name = $row.Name; Qty = $row.Qty; History = $row.History; Mode = $row.Mode }
    }
}
$uniqueHide = @($uniqueHide | Sort-Object -Property Div, Base)
$effectivePreventHideCount = @($preventHideBases.Keys | Where-Object { -not $preventHidePriceFloorOverrides.ContainsKey($_) }).Count
Say "unique floor : hide $($uniqueHide.Count) tracked visible bases below $UniqueFloor div; preserve $effectivePreventHideCount PreventHiding and $($uncertainBases.Count) uncertain bases plus scepters/special states"
Say "             reviewed price-floor overrides: $(@($preventHidePriceFloorOverrides.Keys | Sort-Object) -join ', ')"

# ------------------------------------------------------------- 6. decide changes
$promoS = @(); $promoA = @(); $promoB = @(); $quiet = @(); $unknown = @()
foreach ($b in $best.Keys) {
    $d = $best[$b].Div

    # Only touch bases NeverSink already tracks. A base name we cannot find in the
    # tierlist is a name we cannot trust - poe2scout carries placeholder entries
    # ("INCOMPLETE" on "Slender Flail") and trade-site aliases that match nothing
    # in game. Emitting those is at best dead weight, at worst a wrong BaseType.
    if (-not $current.ContainsKey($b)) {
        if ($d -ge $DivB) { $unknown += [pscustomobject]@{ Base = $b; Div = $d; Name = $best[$b].Name } }
        continue
    }
    $now = $current[$b]

    $want = 0
    if     ($d -ge $DivS) { $want = 3 }
    elseif ($d -ge $DivA) { $want = 2 }
    elseif ($d -ge $DivB) { $want = 1 }

    if ($want -gt $now) {
        $row = [pscustomobject]@{ Base = $b; Div = $d; Name = $best[$b].Name; Qty = $best[$b].Qty; From = $now }
        if     ($want -eq 3) { $promoS += $row }
        elseif ($want -eq 2) { $promoA += $row }
        else                 { $promoB += $row }
    }
    elseif (-not $NoQuiet -and $now -eq 3 -and $d -lt $QuietFloor) {
        $quiet += [pscustomobject]@{ Base = $b; Div = $d; Name = $best[$b].Name; Qty = $best[$b].Qty; From = $now }
    }
}
$promoS = @($promoS | Sort-Object -Property Div -Descending)
$promoA = @($promoA | Sort-Object -Property Div -Descending)
$promoB = @($promoB | Sort-Object -Property Div -Descending)
$quiet  = @($quiet  | Sort-Object -Property Div)

Say "promotions  : S=$($promoS.Count)  A=$($promoA.Count)  B=$($promoB.Count)   quieted apex bases: $($quiet.Count)"
foreach ($set in @(@{L='S';R=$promoS}, @{L='A';R=$promoA}, @{L='B';R=$promoB})) {
    foreach ($row in $set.R) {
        Say ('   +{0}  {1,-26} {2,8:N2} div  ({3}, n={4}, was rank {5})' -f $set.L, $row.Base, $row.Div, $row.Name, $row.Qty, $row.From)
    }
}
foreach ($row in $quiet) {
    Say ('   -q  {0,-26} {1,8:N2} div  ({2}, n={3})' -f $row.Base, $row.Div, $row.Name, $row.Qty)
}
if ($unknown.Count -gt 0) {
    Say "skipped     : $($unknown.Count) valuable base(s) the filter does not track - review if any look real"
    foreach ($row in ($unknown | Sort-Object -Property Div -Descending)) {
        Say ('   ??  {0,-26} {1,8:N2} div  ({2})' -f $row.Base, $row.Div, $row.Name)
    }
}

# --------------------------------------------------------------- 7. emit the block
function Rule([string] $header, $rows, [string[]] $style) {
    if ($rows.Count -eq 0) { return @() }
    $bases = ($rows | ForEach-Object { '"' + $_.Base + '"' }) -join ' '
    $out = @($header, "`tRarity Unique", "`tBaseType == $bases")
    foreach ($s in $style) { $out += "`t$s" }
    return $out + @('')
}

function EssenceRule([string] $header, $rows, [string[]] $style) {
    if ($rows.Count -eq 0) { return @() }
    $bases = ($rows | ForEach-Object { '"' + $_.Base + '"' }) -join ' '
    $out = @($header, "`tClass == `"Stackable Currency`"", "`tBaseType == $bases")
    foreach ($s in $style) { $out += "`t$s" }
    return $out + @('')
}

function LineageRule([string] $header, $rows, [string[]] $style) {
    if ($rows.Count -eq 0) { return @() }
    $bases = ($rows | ForEach-Object { '"' + $_.Base + '"' }) -join ' '
    $out = @($header, "`tClass == `"Skill Gems`" `"Support Gems`"", "`tBaseType == $bases")
    foreach ($s in $style) { $out += "`t$s" }
    return $out + @('')
}

function ConditionRule([string] $header, [string[]] $conditions, [string[]] $style) {
    $out = @($header)
    foreach ($c in $conditions) { $out += "`t$c" }
    foreach ($s in $style) { $out += "`t$s" }
    return $out + @('')
}

function UniqueConditionRule([string] $header, [string[]] $conditions, [string[]] $style) {
    return ConditionRule $header $conditions $style
}

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
$essenceBlock = @(
    '#===============================================================================================================',
    '# [CUSTOM][ECONOMY] Live essence pickup policy - regenerated in full on every run',
    '#===============================================================================================================',
    "# Generated $stamp from api.poe2scout.com | league: $League | 1 divine = $([math]::Round($divine)) ex",
    "# Show floor: $EssenceFloor div with $EssenceMinListings+ listings; thin-market exception: $EssenceThinFloor div with $EssenceThinMinListings+ listings.",
    '# Current and trailing prices are used, and every known lower-value essence is hidden above the stock tierlist.',
    ''
)
$essenceBlock += EssenceRule "Show # [CUSTOM][ECONOMY] essence value floor >= $EssenceFloor div" $essenceShow `
    @('SetFontSize 42','SetTextColor 255 255 255 255','SetBorderColor 255 255 255 255',
      'SetBackgroundColor 188 96 37 255','PlayAlertSound 2 300','PlayEffect Yellow','MinimapIcon 1 Yellow Circle')
$essenceBlock += EssenceRule 'Hide # [CUSTOM][ECONOMY] essences below the live pickup floor' $essenceHide `
    @('SetFontSize 18','SetBackgroundColor 20 20 0 0')
$essenceBlock += @(
    '# [CUSTOM][ECONOMY] END live essence pickup policy',
    '#===============================================================================================================',
    ''
)

$lineageValueStyle = @(
    'SetFontSize 42','SetTextColor 255 255 255 255','SetBorderColor 255 255 255 255',
    'SetBackgroundColor 188 96 37 255','PlayAlertSound 2 300','PlayEffect Yellow','MinimapIcon 1 Yellow Circle'
)
$lineageSafetyStyle = @(
    'SetFontSize 42','SetTextColor 20 240 240 255','SetBorderColor 20 240 240 255',
    'SetBackgroundColor 6 0 60 255','PlayAlertSound 3 300','PlayEffect Cyan','MinimapIcon 1 Cyan Triangle'
)
$lineageBlock = @(
    '#===============================================================================================================',
    '# [CUSTOM][ECONOMY] Live lineage support pickup policy - regenerated in full on every run',
    '#===============================================================================================================',
    "# Generated $stamp from api.poe2scout.com | league: $League | 1 divine = $([math]::Round($divine)) ex",
    "# Normal floor: $LineageFloor div with $LineageMinListings+ listings; thin floor: $LineageThinFloor div with $LineageThinMinListings+ listings; chase floor: $LineageChaseFloor div.",
    '# Unknown or unpriced API entries remain visible; reviewed low-value names missing from poe2scout use a narrow fallback.',
    ''
)
$lineageBlock += LineageRule "Show # [CUSTOM][ECONOMY] lineage support value floor >= $LineageFloor div" $lineageShow $lineageValueStyle
$lineageBlock += LineageRule 'Show # [CUSTOM][ECONOMY] unknown or unpriced lineage supports - safety net' $lineageKeep $lineageSafetyStyle
$lineageBlock += LineageRule 'Hide # [CUSTOM][ECONOMY] lineage supports below the live pickup floor' $lineageHide `
    @('SetFontSize 18','SetBackgroundColor 20 20 0 0')
$lineageBlock += @(
    '# [CUSTOM][ECONOMY] END live lineage support pickup policy',
    '#===============================================================================================================',
    ''
)

$tier5MagicWhitelist = @('Ancestral Tiara', 'Obliterator Bow')
$tier5MagicBases = ($tier5MagicWhitelist | ForEach-Object { '"' + $_ + '"' }) -join ' '
$tier5GearStyle = @(
    'SetFontSize 42','SetTextColor 0 240 190 255','SetBorderColor 0 240 190 255',
    'SetBackgroundColor 0 75 30 255','PlayAlertSound 3 300','PlayEffect Blue','MinimapIcon 0 Blue Diamond'
)
$tier5HideStyle = @('SetFontSize 18','SetBackgroundColor 20 20 0 0')
$tier5Block = @(
    '#===============================================================================================================',
    '# [CUSTOM][ECONOMY] Endgame Tier-5 gear pickup policy - regenerated in full on every run',
    '#===============================================================================================================',
    '# Endgame magic/rare belts are hidden; tier-5 rare gear is hidden; only two magic crafting bases remain.',
    '# This intentionally trades occasional ground-craft upside for a cleaner currency-farming screen.',
    ''
)
$tier5Block += ConditionRule 'Hide # [CUSTOM][ECONOMY] endgame magic/rare belts - no ground pickup' `
    @('Rarity Magic Rare','Class == "Belts"','AreaLevel >= 65') $tier5HideStyle
$tier5Block += ConditionRule 'Show # [CUSTOM][ECONOMY] retained Tier-5 magic crafting bases' `
    @('UnidentifiedItemTier >= 5','Rarity Magic',"BaseType == $tier5MagicBases",'AreaLevel >= 65') $tier5GearStyle
$tier5Block += ConditionRule 'Hide # [CUSTOM][ECONOMY] all other endgame Tier-5 rare items' `
    @('UnidentifiedItemTier >= 5','Rarity Rare','AreaLevel >= 65') $tier5HideStyle
$tier5Block += ConditionRule 'Hide # [CUSTOM][ECONOMY] all other endgame Tier-5 magic items' `
    @('UnidentifiedItemTier >= 5','Rarity Magic','AreaLevel >= 65') $tier5HideStyle
$tier5Block += @(
    '# [CUSTOM][ECONOMY] END endgame Tier-5 gear pickup policy',
    '#===============================================================================================================',
    ''
)
Say "tier5 gear : rare endgame tier-5 hidden; magic whitelist = $($tier5MagicWhitelist -join ', ')"

$uniqueSpecialStyle = @(
    'SetFontSize 42','SetTextColor 0 0 0 255','SetBorderColor 0 240 190 255',
    'SetBackgroundColor 188 96 37 255','PlayAlertSound 3 300','PlayEffect Purple','MinimapIcon 0 Purple Star'
)
$uniquePolicyBlock = @(
    '#===============================================================================================================',
    '# [CUSTOM][ECONOMY] Live unique pickup policy - regenerated in full on every run',
    '#===============================================================================================================',
    "# Generated $stamp from api.poe2scout.com | league: $League | 1 divine = $([math]::Round($divine)) ex",
    "# Plain visible unique bases below $UniqueFloor div are hidden after these exceptions.",
    '# NeverSink PreventHiding outcomes remain visible except reviewed single-outcome recipe ingredients.',
    '# Unique scepters stay visible because same-class Vaal rerolling can produce valuable scepter outcomes.',
    '# Special corruption, Vaal, quality and socket states stay visible for identification/crafting value.',
    ''
)
$uniquePolicyBlock += UniqueConditionRule 'Show # [CUSTOM][ECONOMY] all unique scepters - same-class reroll exception' `
    @('Class == "Sceptres"','Rarity Unique') $uniqueSpecialStyle
$uniquePolicyBlock += UniqueConditionRule 'Show # [CUSTOM][ECONOMY] AlwaysShow uniques' `
    @('AlwaysShow True','Rarity Unique') $uniqueSpecialStyle
$uniquePolicyBlock += UniqueConditionRule 'Show # [CUSTOM][ECONOMY] double-corrupted uniques' `
    @('TwiceCorrupted True','Rarity Unique') $uniqueSpecialStyle
$uniquePolicyBlock += UniqueConditionRule 'Show # [CUSTOM][ECONOMY] uniques with Vaal modifiers' `
    @('HasVaalUniqueMod True','Rarity Unique') $uniqueSpecialStyle
$uniquePolicyBlock += UniqueConditionRule 'Show # [CUSTOM][ECONOMY] Vaal uniques' `
    @('IsVaalUnique True','Rarity Unique') $uniqueSpecialStyle
$uniquePolicyBlock += UniqueConditionRule 'Show # [CUSTOM][ECONOMY] corrupted enchanted uniques' `
    @('AnyEnchantment True','Corrupted True','Rarity Unique') $uniqueSpecialStyle
$uniquePolicyBlock += UniqueConditionRule 'Show # [CUSTOM][ECONOMY] over-quality uniques' `
    @('Quality >= 21','Rarity Unique') $uniqueSpecialStyle
$uniquePolicyBlock += UniqueConditionRule 'Show # [CUSTOM][ECONOMY] exceptional-socket uniques - two-handed/body classes' `
    @('Sockets >= 3','Rarity Unique','Class == "Body Armours" "Bows" "Crossbows" "Quarterstaves" "Staves" "Talismans" "Two Hand Maces"') $uniqueSpecialStyle
$uniquePolicyBlock += UniqueConditionRule 'Show # [CUSTOM][ECONOMY] exceptional-socket uniques - one-handed/armour classes' `
    @('Sockets >= 2','Rarity Unique','Class == "Boots" "Bucklers" "Foci" "Gloves" "Helmets" "One Hand Maces" "Sceptres" "Shields" "Spears" "Wands"') $uniqueSpecialStyle
$uniquePolicyBlock += Rule "Hide # [CUSTOM][ECONOMY] visible unique bases below $UniqueFloor div" $uniqueHide `
    @('SetFontSize 18','SetBackgroundColor 20 20 0 0')
$uniquePolicyBlock += @(
    '# [CUSTOM][ECONOMY] END live unique pickup policy',
    '#===============================================================================================================',
    ''
)

$block = @(
    '#===============================================================================================================',
    '# [CUSTOM][ECONOMY] Live market overrides - regenerated in full on every run, do not hand-edit',
    '#===============================================================================================================',
    "# Generated $stamp from api.poe2scout.com | league: $League | 1 divine = $([math]::Round($divine)) ex",
    "# Thresholds: S >= $DivS div, A >= $DivA div, B >= $DivB div.",
    "# Confidence: $UniqueMinListings+ live listings, or $UniqueHistoryMinPoints+ historical snapshots; thin markets use the lower quartile.",
    '# Prices are taken on the best unique each base can actually drop; uncertain bases are never hidden.',
    "# Uniques NeverSink flags NonWorldDrop are excluded ($($noDrop.Count) of them) - they never drop from monsters,",
    '# so their price says nothing about whether the base is worth showing.',
    '# This market block only promotes/softens; the separate unique/essence policies handle value-floor hides.',
    ''
)
$block += Rule 'Show # [CUSTOM][ECONOMY] S - best droppable unique >= 10 div' $promoS `
    @('SetFontSize 45','SetTextColor 255 0 0 255','SetBorderColor 255 0 0 255',
      'SetBackgroundColor 255 255 255 255','PlayAlertSound 6 300','PlayEffect Red','MinimapIcon 0 Red Star')
$block += Rule 'Show # [CUSTOM][ECONOMY] A - best droppable unique >= 2 div' $promoA `
    @('SetFontSize 45','SetTextColor 255 255 255 255','SetBorderColor 255 255 255 255',
      'SetBackgroundColor 188 96 37 255','PlayAlertSound 1 300','PlayEffect Red','MinimapIcon 0 Yellow Star')
$block += Rule 'Show # [CUSTOM][ECONOMY] B - best droppable unique >= 0.5 div' $promoB `
    @('SetFontSize 42','SetTextColor 188 96 37 255','SetBorderColor 188 96 37 255',
      'SetBackgroundColor 53 13 13 255','PlayAlertSound 3 300','PlayEffect Brown','MinimapIcon 1 Brown Star')
$block += Rule 'Show # [CUSTOM][ECONOMY] apex base whose market value collapsed - shown, no siren' $quiet `
    @('SetFontSize 42','SetTextColor 188 96 37 255','SetBorderColor 188 96 37 255',
      'SetBackgroundColor 53 13 13 255','PlayAlertSound 3 300','PlayEffect Brown','MinimapIcon 1 Brown Star')
$block += '#==============================================================================================================='
$block += '# [CUSTOM][ECONOMY] END live market overrides'
$block += '#==============================================================================================================='
$block += ''

# --------------------------------------------------------- 8. build and splice
$staged = Join-Path $CacheDir 'staged.filter'
$baseHead = Get-Content $BaseFilter -TotalCount 80 -ErrorAction SilentlyContinue
$alreadyBuilt = (($baseHead -join "`n") -match '# CUSTOMIZED COPY - built on stock 6-UBER-PLUS-STRICT\.')
if ($alreadyBuilt) {
    # The repository's checked-in filter is already the result of the AWK pass. Running
    # AWK over it again would duplicate every [CUSTOM] block, so treat it as the current
    # generated base and replace only the generated economy sections below.
    Say "base mode   : existing generated filter - skipping AWK to avoid duplicate custom blocks"
    $body = [System.IO.File]::ReadAllLines($BaseFilter, (New-Object System.Text.UTF8Encoding($false)))
} else {
    # Redirect via cmd.exe, NOT a PowerShell pipe. A PS pipe decodes the child's
    # stdout with [Console]::OutputEncoding - under Task Scheduler that is the OEM
    # codepage, which mangles every non-ASCII base name (Mórrigan's Insight -> M├│rrigan's).
    # cmd's '>' is byte-for-byte, so UTF-8 survives regardless of codepage.
    & $env:ComSpec /c "`"$awk`" -f `"$BuildAwk`" `"$BaseFilter`" > `"$staged`""
    if ($LASTEXITCODE -ne 0) { throw "awk failed with exit code $LASTEXITCODE" }
    $body = [System.IO.File]::ReadAllLines($staged, (New-Object System.Text.UTF8Encoding($false)))
}

function Remove-GeneratedBlock($lines, [string] $startPattern, [string] $endPattern, [switch] $KeepEndLine) {
    $out = @()
    $inside = $false
    $cleanupAfterEnd = $false
    foreach ($line in $lines) {
        if ($cleanupAfterEnd) {
            if ($line -eq '' -or $line -match '^#=+$') { continue }
            $cleanupAfterEnd = $false
        }
        if (-not $inside -and $line -match $startPattern) {
            while ($out.Count -gt 0 -and ($out[-1] -eq '' -or $out[-1] -match '^#=+$')) {
                if ($out.Count -eq 1) { $out = @(); break }
                $out = @($out[0..($out.Count - 2)])
            }
            $inside = $true
            continue
        }
        if ($inside -and $line -match $endPattern) {
            $inside = $false
            if ($KeepEndLine) { $out += $line } else { $cleanupAfterEnd = $true }
            continue
        }
        if (-not $inside) { $out += $line }
    }
    return ,$out
}

# Make repeated rebuilds idempotent. The checked-in generated filter predates the
# generated-block end markers, so the market block is removed through the unique anchor.
$marketEndPattern = '^# \[CUSTOM\]\[ECONOMY\] END live market overrides$'
if ($body -match $marketEndPattern) {
    $body = Remove-GeneratedBlock $body '^# \[CUSTOM\]\[ECONOMY\] Live market overrides' $marketEndPattern
} else {
    # Legacy generated copies have no market end marker. Preserve the first tier-1
    # Show line as the anchor while removing the old market block before it.
    $body = Remove-GeneratedBlock $body '^# \[CUSTOM\]\[ECONOMY\] Live market overrides' '^Show # .*\$type->uniques \$tier->t1\b' -KeepEndLine
}
$body = Remove-GeneratedBlock $body '^# \[CUSTOM\]\[ECONOMY\] Live essence pickup policy -' '^# \[CUSTOM\]\[ECONOMY\] END live essence pickup policy'
$body = Remove-GeneratedBlock $body '^# \[CUSTOM\]\[ECONOMY\] Live lineage support pickup policy -' '^# \[CUSTOM\]\[ECONOMY\] END live lineage support pickup policy'
$body = Remove-GeneratedBlock $body '^# \[CUSTOM\]\[ECONOMY\] Live unique pickup policy -' '^# \[CUSTOM\]\[ECONOMY\] END live unique pickup policy'
$body = Remove-GeneratedBlock $body '^# \[CUSTOM\]\[ECONOMY\] Endgame Tier-5 gear pickup policy -' '^# \[CUSTOM\]\[ECONOMY\] END endgame Tier-5 gear pickup policy'
# Older generated copies contain a belt-only tier-5 override before the stock 0800 section.
# Remove it so the new endgame suppression block is the only authority for magic/rare belts.
$body = Remove-GeneratedBlock $body '^# \[CUSTOM\] Belts - (magic and rare only survive at UnidentifiedItemTier 5|endgame magic/rare pickup disabled)$' '^# \[\[0800\]\] High Unidentified Mod Tier$' -KeepEndLine

$anchor = -1
for ($i = 0; $i -lt $body.Count; $i++) {
    if ($body[$i] -match '^# !! Waypoint c11\.uniques\.t1\b') { $anchor = $i; break }
}
if ($anchor -lt 0) {
    for ($i = 0; $i -lt $body.Count; $i++) {
        if ($body[$i] -match '^Show # .*\$type->uniques \$tier->t1 ') { $anchor = $i; break }
    }
}
if ($anchor -lt 0) { throw "Could not find the unique tierlist anchor - the base filter layout changed." }

$essenceAnchor = -1
$essenceOccurrences = 0
for ($i = 0; $i -lt $body.Count; $i++) {
    if ($body[$i] -match '^# !! Waypoint c9\.currency\.essences\.all\b') {
        $essenceOccurrences++
        if ($essenceOccurrences -eq 2) { $essenceAnchor = $i; break }
    }
}
if ($essenceAnchor -lt 0) {
    for ($i = 0; $i -lt $body.Count; $i++) {
        if ($body[$i] -match '^Show # .*\$type->currency->essence \$tier->s ') { $essenceAnchor = $i; break }
    }
}
if ($essenceAnchor -lt 0) { throw "Could not find the essence tierlist anchor - the base filter layout changed." }

$lineageAnchor = -1
for ($i = 0; $i -lt $body.Count; $i++) {
    if ($body[$i] -match '^Show # .*\$type->gems->lineage \$tier->s ') { $lineageAnchor = $i; break }
}
if ($lineageAnchor -lt 0) { throw "Could not find the lineage support tierlist anchor - the base filter layout changed." }

$tier5Anchor = -1
$tier5Occurrences = 0
for ($i = 0; $i -lt $body.Count; $i++) {
    if ($body[$i] -match '^# \[\[0800\]\] High Unidentified Mod Tier$') {
        $tier5Occurrences++
        if ($tier5Occurrences -eq 2) { $tier5Anchor = $i; break }
    }
}
if ($tier5Anchor -lt 0) {
    for ($i = 0; $i -lt $body.Count; $i++) {
        if ($body[$i] -match '^# !! Waypoint c3\.exotic\.state\.hightier\b') { $tier5Anchor = $i; break }
    }
}
if ($tier5Anchor -lt 0) { throw "Could not find the endgame Tier-5 gear anchor - the base filter layout changed." }

$final = @()
for ($i = 0; $i -lt $body.Count; $i++) {
    if ($i -eq $essenceAnchor) { $final += $essenceBlock }
    if ($i -eq $lineageAnchor) {
        # The stock gem section has a blank line before its first lineage rule,
        # while generated copies do not. Trim it at insertion time so the first
        # rebuild and every later idempotent rebuild produce the same structure.
        while ($final.Count -gt 0 -and $final[$final.Count - 1] -eq '') {
            if ($final.Count -eq 1) { $final = @(); break }
            $final = @($final[0..($final.Count - 2)])
        }
        $final += $lineageBlock
    }
    if ($i -eq $tier5Anchor) { $final += $tier5Block }
    if ($i -eq $anchor) {
        $final += $uniquePolicyBlock
        $final += $block
    }
    $final += $body[$i]
}

# --------------------------------------------------------------- 9. sanity checks
$bad = 0
$inBlock = $false
for ($i = 0; $i -lt $final.Count; $i++) {
    $l = $final[$i]
    if ($l -match '^(Show|Hide)')  { $inBlock = $true;  continue }
    if ($l -match '^\s*$')         { $inBlock = $false; continue }
    if ($l -match '^#')            { continue }
    if ($l -match '^\s' -and -not $inBlock) { Say "  ERROR orphaned directive at line $($i+1): $l"; $bad++ }
    if ($inBlock -and $l -match '^\s*#')    { Say "  ERROR comment inside rule at line $($i+1): $l"; $bad++ }
}
if ($final -match 'BaseType\s*==\s*$') { Say "  ERROR empty BaseType list emitted"; $bad++ }

# Mojibake tripwire. A codepage mishap turns UTF-8 into box-drawing / replacement
# characters, and the game then rejects the whole filter with "Unable to parse
# parameter for BaseType rule". None of these ever appear in a healthy filter.
$mojibakePattern = '[\u2500-\u257F]|\uFFFD|\u00C3.|\u00E2\u20AC'
$mojibake = $final | Select-String -Pattern $mojibakePattern | Select-Object -First 3
if ($mojibake) {
    foreach ($m in $mojibake) { Say "  ERROR mojibake on line $($m.LineNumber): $($m.Line.Trim())" }
    $bad++
}
if ($bad -gt 0) { throw "$bad structural problem(s) - refusing to install." }
Say "structure   : OK  ($($final.Count) lines)"
[System.IO.File]::WriteAllLines($staged, $final, (New-Object System.Text.UTF8Encoding($false)))

# ------------------------------------------------------------------ 10. install
if ($DryRun) {
    Say "DRY RUN - nothing written. Staged build is at $staged"
} else {
    if (Test-Path $Output) { Copy-Item $Output "$Output.bak" -Force }
    [System.IO.File]::WriteAllLines($Output, $final, (New-Object System.Text.UTF8Encoding($false)))
    Say "installed   : $Output  (previous kept as .bak)"
    Say "Reload the filter in-game to pick it up."
}

Add-Content -Path $LogPath -Value ($script:Lines + '') -Encoding utf8
