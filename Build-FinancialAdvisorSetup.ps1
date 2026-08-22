#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $root 'FinancialAdvisorFilterSetup.exe'
$source = Join-Path $root 'FinancialAdvisorFilterSetup.cs'

$csc = @(
    Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $csc) {
    throw 'Microsoft .NET Framework csc.exe was not found. Install the .NET Framework developer tools, then run this script again.'
}

$arguments = @(
    '/nologo'
    '/target:winexe'
    "/out:$output"
    '/reference:System.dll'
    '/reference:System.Drawing.dll'
    '/reference:System.Windows.Forms.dll'
    "/resource:$(Join-Path $root 'FinancialAdvisor Filter.filter'),FinancialAdvisorFilter"
    "/resource:$(Join-Path $root 'hibdivine.mp3'),hibdivine.mp3"
    "/resource:$(Join-Path $root 'HibOmenLight.mp3'),HibOmenLight.mp3"
    "/resource:$(Join-Path $root 'Echoes.mp3'),Echoes.mp3"
    "/resource:$(Join-Path $root 'OrbOfAnnulment.mp3'),OrbOfAnnulment.mp3"
    $source
)

Push-Location $root
try {
    & $csc @arguments
    if ($LASTEXITCODE -ne 0) { throw "csc.exe failed with exit code $LASTEXITCODE." }
} finally {
    Pop-Location
}

Write-Output "built: $output"
