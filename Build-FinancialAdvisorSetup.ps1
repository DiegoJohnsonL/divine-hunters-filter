#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $root 'FinancialAdvisorFilterSetup.exe'
$source = Join-Path $root 'FinancialAdvisorFilterSetup.cs'
$versionSource = Join-Path $root 'FinancialAdvisorFilterVersion.cs'
$updaterSource = Join-Path $root 'FinancialAdvisorFilterUpdater.cs'
$updaterOutput = Join-Path $root '_filter-cache\FinancialAdvisorFilterUpdater.build.exe'

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
    $updaterSource
)

$arguments = @(
    '/nologo'
    '/target:winexe'
    "/out:$output"
    '/reference:System.dll'
    '/reference:System.Drawing.dll'
    '/reference:System.Windows.Forms.dll'
    "/resource:$updaterOutput,FinancialAdvisorFilterUpdater"
    "/resource:$(Join-Path $root 'FinancialAdvisor Filter.filter'),FinancialAdvisorFilter"
    "/resource:$(Join-Path $root 'hibdivine.mp3'),hibdivine.mp3"
    "/resource:$(Join-Path $root 'HibOmenLight.mp3'),HibOmenLight.mp3"
    "/resource:$(Join-Path $root 'Echoes.mp3'),Echoes.mp3"
    "/resource:$(Join-Path $root 'OmenOfTheLiege.mp3'),OmenOfTheLiege.mp3"
    "/resource:$(Join-Path $root 'OrbOfAnnulment.mp3'),OrbOfAnnulment.mp3"
    $versionSource
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
