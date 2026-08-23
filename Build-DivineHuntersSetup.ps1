#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $root 'DivineHuntersSetup.exe'
$source = Join-Path $root 'DivineHuntersSetup.cs'
$versionSource = Join-Path $root 'DivineHuntersVersion.cs'
$updaterSource = Join-Path $root 'DivineHuntersUpdater.cs'
$filterChannelSource = Join-Path $root 'DivineHuntersFilterChannel.cs'
$updaterOutput = Join-Path $root '_filter-cache\DivineHuntersUpdater.build.exe'

$csc = @(
    Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $csc) {
    throw 'Microsoft .NET Framework csc.exe was not found. Install the .NET Framework developer tools, then run this script again.'
}

$frameworkFolder = Split-Path -Parent $csc
$webExtensions = Join-Path $frameworkFolder 'System.Web.Extensions.dll'
if (-not (Test-Path -LiteralPath $webExtensions)) {
    throw 'System.Web.Extensions.dll was not found beside csc.exe; it is required for the GitHub release updater.'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $updaterOutput) -Force | Out-Null

$updaterArguments = @(
    '/nologo'
    '/target:winexe'
    "/out:$updaterOutput"
    '/reference:System.dll'
    "/reference:$webExtensions"
    $versionSource
    $filterChannelSource
    $updaterSource
)

$arguments = @(
    '/nologo'
    '/target:winexe'
    "/out:$output"
    '/reference:System.dll'
    '/reference:System.Drawing.dll'
    '/reference:System.Windows.Forms.dll'
    "/reference:$webExtensions"
    "/resource:$updaterOutput,DivineHuntersUpdater"
    $versionSource
    $filterChannelSource
    $source
)

Push-Location $root
try {
    & $csc @updaterArguments
    if ($LASTEXITCODE -ne 0) { throw "Updater csc.exe failed with exit code $LASTEXITCODE." }

    & $csc @arguments
    if ($LASTEXITCODE -ne 0) { throw "csc.exe failed with exit code $LASTEXITCODE." }
} finally {
    Pop-Location
}

Write-Output "built: $output"
