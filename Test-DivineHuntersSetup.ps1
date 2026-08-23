#requires -Version 5.1

[CmdletBinding()]
param(
    [switch] $KeepArtifacts
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$setup = Join-Path $root 'DivineHuntersSetup.exe'
$updater = Join-Path $root '_filter-cache\DivineHuntersUpdater.build.exe'
$assetNames = @(
    'hibdivine.mp3',
    'HibOmenLight.mp3',
    'Echoes.mp3',
    'OmenOfTheLiege.mp3',
    'OrbOfAnnulment.mp3',
    'DivineHunters.filter'
)

if (-not (Test-Path -LiteralPath $setup) -or -not (Test-Path -LiteralPath $updater)) {
    throw 'Build the installer before running its integration test.'
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('DivineHuntersSetupTest-' + [guid]::NewGuid().ToString('N'))
$channel = Join-Path $testRoot 'channel'
$target = Join-Path $testRoot 'game'
$state = Join-Path $testRoot 'state'
$releaseJson = Join-Path $channel 'release.json'
[IO.Directory]::CreateDirectory($channel) | Out-Null
[IO.Directory]::CreateDirectory($target) | Out-Null
[IO.Directory]::CreateDirectory($state) | Out-Null

function Get-FileUri([string] $Path) {
    return (New-Object System.Uri([IO.Path]::GetFullPath($Path))).AbsoluteUri
}

function Write-TestRelease([switch] $BadFilterDigest) {
    $assets = foreach ($name in $assetNames) {
        $path = Join-Path $channel $name
        $digest = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($BadFilterDigest -and $name -eq 'DivineHunters.filter') {
            $digest = '0' * 64
        }
        [ordered]@{
            name = $name
            browser_download_url = Get-FileUri $path
            digest = 'sha256:' + $digest
        }
    }
    $json = [ordered]@{
        tag_name = 'filter-latest'
        assets = @($assets)
    } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($releaseJson, $json, (New-Object Text.UTF8Encoding($false)))
}

function Assert([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-TestExecutable([string] $Path, [string[]] $ArgumentList) {
    $process = Start-Process -FilePath $Path -ArgumentList $ArgumentList -Wait -PassThru -WindowStyle Hidden
    return $process.ExitCode
}

$oldApi = $env:DIVINEHUNTERS_FILTER_CHANNEL_API
$oldState = $env:DIVINEHUNTERS_UPDATER_STATE
$oldSkip = $env:DIVINEHUNTERS_SKIP_AUTOUPDATE
$oldTestError = $env:DIVINEHUNTERS_TEST_ERROR_LOG
$oldGameCheck = $env:DIVINEHUNTERS_SKIP_GAME_CHECK

try {
    foreach ($name in $assetNames) {
        $sourceName = if ($name -eq 'DivineHunters.filter') { 'Divine Hunters.filter' } else { $name }
        Copy-Item -LiteralPath (Join-Path $root $sourceName) -Destination (Join-Path $channel $name) -Force
    }
    Write-TestRelease
    [IO.File]::WriteAllText(
        (Join-Path $target 'poe2_production_Config.ini'),
        "apply_item_filter_to_ritual=false`r`n",
        (New-Object Text.UTF8Encoding($false)))

    $env:DIVINEHUNTERS_FILTER_CHANNEL_API = Get-FileUri $releaseJson
    $env:DIVINEHUNTERS_UPDATER_STATE = $state
    $env:DIVINEHUNTERS_SKIP_AUTOUPDATE = '1'
    $env:DIVINEHUNTERS_TEST_ERROR_LOG = Join-Path $testRoot 'installer-error.log'
    $env:DIVINEHUNTERS_SKIP_GAME_CHECK = '1'

    $exitCode = Invoke-TestExecutable $setup @('--test', $target)
    if ($exitCode -ne 0) {
        $detail = if (Test-Path -LiteralPath $env:DIVINEHUNTERS_TEST_ERROR_LOG) {
            [IO.File]::ReadAllText($env:DIVINEHUNTERS_TEST_ERROR_LOG)
        } else { 'No test error log was produced.' }
        throw "Installer test mode failed with exit code ${exitCode}: $detail"
    }
    foreach ($name in $assetNames) {
        $destinationName = if ($name -eq 'DivineHunters.filter') { 'Divine Hunters.filter' } else { $name }
        $expected = (Get-FileHash -LiteralPath (Join-Path $channel $name) -Algorithm SHA256).Hash
        $actual = (Get-FileHash -LiteralPath (Join-Path $target $destinationName) -Algorithm SHA256).Hash
        Assert ($actual -eq $expected) "Installed asset hash mismatch: $name"
    }
    $config = [IO.File]::ReadAllText((Join-Path $target 'poe2_production_Config.ini'))
    Assert ($config -match 'apply_item_filter_to_ritual=true') 'Installer did not enable Ritual filtering in test mode.'

    $originalFilterHash = (Get-FileHash -LiteralPath (Join-Path $target 'Divine Hunters.filter') -Algorithm SHA256).Hash
    [IO.File]::AppendAllText(
        (Join-Path $channel 'DivineHunters.filter'),
        "`r`n# integration-test channel revision`r`n",
        (New-Object Text.UTF8Encoding($false)))
    Write-TestRelease

    $exitCode = Invoke-TestExecutable $updater @('--target', $target)
    Assert ($exitCode -eq 0) "Updater failed with exit code $exitCode."
    $updatedFilterHash = (Get-FileHash -LiteralPath (Join-Path $target 'Divine Hunters.filter') -Algorithm SHA256).Hash
    $channelFilterHash = (Get-FileHash -LiteralPath (Join-Path $channel 'DivineHunters.filter') -Algorithm SHA256).Hash
    Assert ($updatedFilterHash -eq $channelFilterHash) 'Updater did not install the changed filter.'
    Assert ($updatedFilterHash -ne $originalFilterHash) 'Updater left the original filter unchanged.'

    $backups = @(Get-ChildItem -LiteralPath $target -File -Filter 'Divine Hunters.filter.before-divinehunters-*.bak')
    Assert ($backups.Count -eq 1) 'Updater did not retain exactly one filter backup.'
    Assert ((Get-FileHash -LiteralPath $backups[0].FullName -Algorithm SHA256).Hash -eq $originalFilterHash) 'Filter backup does not match the pre-update filter.'

    $beforeNoOp = (Get-Item -LiteralPath (Join-Path $target 'Divine Hunters.filter')).LastWriteTimeUtc
    $exitCode = Invoke-TestExecutable $updater @('--target', $target)
    Assert ($exitCode -eq 0) "No-op updater run failed with exit code $exitCode."
    $afterNoOp = (Get-Item -LiteralPath (Join-Path $target 'Divine Hunters.filter')).LastWriteTimeUtc
    Assert ($beforeNoOp -eq $afterNoOp) 'No-op updater rewrote an already-current filter.'

    $exitCode = Invoke-TestExecutable $setup @('--update', $target)
    Assert ($exitCode -eq 0) "Legacy migration mode failed with exit code $exitCode."
    $recordedVersion = [IO.File]::ReadAllText((Join-Path $state 'installed-version.txt')).Trim([char]0xFEFF).Trim()
    Assert ($recordedVersion -eq '1.4.0') "Migration mode recorded unexpected version: $recordedVersion"

    [IO.File]::AppendAllText(
        (Join-Path $channel 'DivineHunters.filter'),
        "# integration-test invalid-digest revision`r`n",
        (New-Object Text.UTF8Encoding($false)))
    Write-TestRelease -BadFilterDigest
    $beforeBadDigest = (Get-FileHash -LiteralPath (Join-Path $target 'Divine Hunters.filter') -Algorithm SHA256).Hash
    $exitCode = Invoke-TestExecutable $updater @('--target', $target)
    Assert ($exitCode -eq 1) "Bad-digest updater run returned $exitCode instead of 1."
    $afterBadDigest = (Get-FileHash -LiteralPath (Join-Path $target 'Divine Hunters.filter') -Algorithm SHA256).Hash
    Assert ($beforeBadDigest -eq $afterBadDigest) 'Bad-digest update changed the installed filter.'

    Write-Output 'PASS: installer download, Ritual toggle, updater replacement, backup, no-op, v1.4 migration, and bad-digest rollback.'
    Write-Output "Artifacts: $testRoot"
}
finally {
    $env:DIVINEHUNTERS_FILTER_CHANNEL_API = $oldApi
    $env:DIVINEHUNTERS_UPDATER_STATE = $oldState
    $env:DIVINEHUNTERS_SKIP_AUTOUPDATE = $oldSkip
    $env:DIVINEHUNTERS_TEST_ERROR_LOG = $oldTestError
    $env:DIVINEHUNTERS_SKIP_GAME_CHECK = $oldGameCheck

    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $testRoot)) {
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        $resolvedTest = [IO.Path]::GetFullPath($testRoot)
        if ($resolvedTest.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedTest).StartsWith('DivineHuntersSetupTest-', [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $resolvedTest -Recurse -Force
        }
    }
}
