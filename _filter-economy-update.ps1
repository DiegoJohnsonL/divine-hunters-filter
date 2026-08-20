<#
.SYNOPSIS
    Rebuilds the custom PoE2 loot filter with live market data from poe2scout.

.DESCRIPTION
    Three-stage pipeline:

      1. Pick a base filter - the FilterBlade-generated copy the game caches in
         OnlineFilters\, which carries fresher economy tiering than the GitHub release.
      2. Run _filter-build-script.awk over it, applying the 11 personal customisations.
      3. Insert an [ECONOMY] block above the unique tierlist that promotes bases the
         market now values above their NeverSink tier, and quiets apex bases that died.

    The economy block is regenerated from scratch every run, so it never accumulates.
    Nothing is ever hidden by this script - it only promotes and softens.

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

    # Ignore any unique with fewer live listings than this. Guards against the
    # 5-listing troll prices (The Gnashing Sash at 4290 div, etc).
    [int]    $MinListings = 20,

    # Promotion thresholds, in divine, on the best world-droppable unique for a base.
    [double] $DivS = 10.0,
    [double] $DivA = 2.0,
    [double] $DivB = 0.5,

    # Apex (t1) bases whose best unique is worth less than this get the quieter
    # t3 treatment instead of PlayAlertSound 6. Still shown, just not a siren.
    [double] $QuietFloor = 0.25,
    [switch] $NoQuiet,

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

if ($Output -eq '')     { $Output     = Join-Path $Root 'FinancialAdvisor Filter.filter' }
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
$noDrop     = @{}
$aspectBase = @{}
$aspects = ([System.IO.File]::ReadAllText($aspectFile, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json).Aspects
foreach ($baseProp in $aspects.PSObject.Properties) {
    foreach ($u in $baseProp.Value) {
        if ($u.Aspects -contains 'NonWorldDrop' -or $u.Aspects -contains 'NonDrop') { $noDrop[$u.Name] = $true }
        if (-not [string]::IsNullOrWhiteSpace($u.BaseType)) { $aspectBase[$u.Name] = $u.BaseType }
    }
}
Say "aspects     : $($aspectBase.Count) uniques mapped, $($noDrop.Count) flagged as non-world-drop"

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

# ------------------------------------------------------------- 4. unique prices
# Median of the trailing price log beats CurrentPrice - a single day's spike
# should not promote a base into the apex tier.
function Get-StablePrice($item) {
    $logs = @($item.PriceLogs | Where-Object { $null -ne $_ -and $null -ne $_.Price })
    if ($logs.Count -ge 3) {
        $sorted = @($logs | ForEach-Object { [double] $_.Price } | Sort-Object)
        return $sorted[[int]($sorted.Count / 2)]
    }
    return [double] $item.CurrentPrice
}

$categories = (Get-Json "$ApiRoot/poe2/Leagues/$([uri]::EscapeDataString($League))/Items/Categories").UniqueCategories
$best = @{}   # base type -> @{ Div; Name; Qty }
$seen = 0; $skipNoDrop = 0; $skipThin = 0

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
            if ($qty -lt $MinListings)               { $skipThin++;   continue }
            $d = (Get-StablePrice $i) / $divine
            if (-not $best.ContainsKey($base) -or $d -gt $best[$base].Div) {
                $best[$base] = @{ Div = $d; Name = $name; Qty = $qty }
            }
        }
        $page++
    } while ($page -le $r.Pages)
}
Say "prices      : $seen uniques seen, $skipNoDrop non-droppable, $skipThin under $MinListings listings, $($best.Count) bases priced"

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

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
$block = @(
    '#===============================================================================================================',
    '# [CUSTOM][ECONOMY] Live market overrides - regenerated in full on every run, do not hand-edit',
    '#===============================================================================================================',
    "# Generated $stamp from api.poe2scout.com | league: $League | 1 divine = $([math]::Round($divine)) ex",
    "# Thresholds: S >= $DivS div, A >= $DivA div, B >= $DivB div. Minimum $MinListings live listings.",
    '# Prices are the median of the trailing price log, taken on the best unique each base can actually drop.',
    "# Uniques NeverSink flags NonWorldDrop are excluded ($($noDrop.Count) of them) - they never drop from monsters,",
    '# so their price says nothing about whether the base is worth showing.',
    '# Nothing here hides an item: promotions raise visibility, the quiet rule only removes the apex siren.',
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
$block += ''

# --------------------------------------------------------- 8. build and splice
$staged = Join-Path $CacheDir 'staged.filter'
# Redirect via cmd.exe, NOT a PowerShell pipe. A PS pipe decodes the child's
# stdout with [Console]::OutputEncoding - under Task Scheduler that is the OEM
# codepage, which mangles every non-ASCII base name (Mórrigan's Insight -> M├│rrigan's).
# cmd's '>' is byte-for-byte, so UTF-8 survives regardless of codepage.
& $env:ComSpec /c "`"$awk`" -f `"$BuildAwk`" `"$BaseFilter`" > `"$staged`""
if ($LASTEXITCODE -ne 0) { throw "awk failed with exit code $LASTEXITCODE" }

$body = [System.IO.File]::ReadAllLines($staged, (New-Object System.Text.UTF8Encoding($false)))
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

$final = @()
if ($anchor -gt 0) { $final += $body[0..($anchor - 1)] }
$final += $block
$final += $body[$anchor..($body.Count - 1)]

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
$mojibake = $final | Select-String -Pattern '[─-╿�]|Ã.|â€' | Select-Object -First 3
if ($mojibake) {
    foreach ($m in $mojibake) { Say "  ERROR mojibake on line $($m.LineNumber): $($m.Line.Trim())" }
    $bad++
}
if ($bad -gt 0) { throw "$bad structural problem(s) - refusing to install." }
Say "structure   : OK  ($($final.Count) lines)"

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
