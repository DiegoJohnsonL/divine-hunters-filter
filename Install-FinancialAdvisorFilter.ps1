#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$filterFile = 'FinancialAdvisor Filter.filter'
$audioFiles = @(
    'hibdivine.mp3'
    'HibOmenLight.mp3'
    'Echoes.mp3'
    'OrbOfAnnulment.ogg'
)
$requiredFiles = @($filterFile) + $audioFiles
$missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $sourceRoot $_)) })

if ($missingFiles.Count -gt 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "This installer is missing:`r`n`r`n$($missingFiles -join "`r`n")`r`n`r`nDownload the complete repository ZIP and run the installer from the extracted folder.",
        'FinancialAdvisor Filter Setup',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

function Set-Bounds {
    param(
        [System.Windows.Forms.Control] $Control,
        [int] $X,
        [int] $Y,
        [int] $Width,
        [int] $Height
    )
    $Control.Location = New-Object System.Drawing.Point($X, $Y)
    $Control.Size = New-Object System.Drawing.Size($Width, $Height)
}

function New-Page {
    $page = New-Object System.Windows.Forms.Panel
    $page.Dock = [System.Windows.Forms.DockStyle]::Fill
    $page.Visible = $false
    return $page
}

function New-TextLabel {
    param(
        [string] $Text,
        [int] $X,
        [int] $Y,
        [int] $Width,
        [int] $Height,
        [int] $FontSize = 10
    )
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $false
    $label.Font = New-Object System.Drawing.Font('Segoe UI', $FontSize)
    Set-Bounds $label $X $Y $Width $Height
    return $label
}

function Read-ConfigText {
    param([string] $Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [pscustomobject]@{
            Text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
            Encoding = New-Object System.Text.UTF8Encoding($true)
        }
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [pscustomobject]@{
            Text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
            Encoding = New-Object System.Text.UnicodeEncoding($false, $true)
        }
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [pscustomobject]@{
            Text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
            Encoding = New-Object System.Text.UnicodeEncoding($true, $true)
        }
    }
    return [pscustomobject]@{
        Text = [System.Text.Encoding]::UTF8.GetString($bytes)
        Encoding = New-Object System.Text.UTF8Encoding($false)
    }
}

function Enable-RitualFilter {
    param([string] $ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return 'poe2_production_Config.ini was not found; Ritual filtering was not changed.'
    }

    $loaded = Read-ConfigText $ConfigPath
    $pattern = '(?m)^([ \t]*apply_item_filter_to_ritual[ \t]*=[ \t]*)(?:false|true)([ \t]*)(\r?)$'
    if (-not [System.Text.RegularExpressions.Regex]::IsMatch($loaded.Text, $pattern)) {
        return 'The Ritual setting was not found; Ritual filtering was not changed.'
    }

    $updated = [System.Text.RegularExpressions.Regex]::Replace($loaded.Text, $pattern, '$1true$2$3')
    if ($updated -eq $loaded.Text) {
        return 'Ritual filtering was already enabled.'
    }

    $backupPath = "$ConfigPath.before-financialadvisor.bak"
    Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
    [System.IO.File]::WriteAllText($ConfigPath, $updated, $loaded.Encoding)
    return 'Ritual filtering was enabled. A backup of the config was saved beside it.'
}

function Install-FilterFiles {
    param(
        [string] $TargetFolder,
        [bool] $EnableRitual
    )

    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^PathOfExile' })
    if ($running.Count -gt 0) {
        throw 'Path of Exile 2 is running. Close the game completely, then click Install again.'
    }

    if (-not (Test-Path -LiteralPath $TargetFolder)) {
        New-Item -ItemType Directory -Path $TargetFolder -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $targetFilter = Join-Path $TargetFolder $filterFile
    if (Test-Path -LiteralPath $targetFilter) {
        Copy-Item -LiteralPath $targetFilter -Destination "$targetFilter.before-financialadvisor-$stamp.bak" -Force
    }

    Copy-Item -LiteralPath (Join-Path $sourceRoot $filterFile) -Destination $TargetFolder -Force
    foreach ($audioFile in $audioFiles) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot $audioFile) -Destination $TargetFolder -Force
    }

    $ritualMessage = 'Ritual filtering was left unchanged.'
    if ($EnableRitual) {
        $ritualMessage = Enable-RitualFilter (Join-Path $TargetFolder 'poe2_production_Config.ini')
    }

    return [pscustomobject]@{
        Target = $TargetFolder
        Ritual = $ritualMessage
    }
}

$defaultFolder = Join-Path $env:USERPROFILE 'Documents\My Games\Path of Exile 2'

$form = New-Object System.Windows.Forms.Form
$form.Text = 'FinancialAdvisor Filter Setup'
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(700, 430)
$form.BackColor = [System.Drawing.Color]::White

$header = New-Object System.Windows.Forms.Panel
$header.BackColor = [System.Drawing.Color]::FromArgb(42, 58, 76)
Set-Bounds $header 0 0 700 66
$form.Controls.Add($header)

$headerTitle = New-TextLabel 'FinancialAdvisor Filter' 24 12 640 30 16
$headerTitle.ForeColor = [System.Drawing.Color]::White
$header.Controls.Add($headerTitle)
$headerSubtitle = New-TextLabel 'PoE2 installer' 26 40 640 20 9
$headerSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(215, 225, 235)
$header.Controls.Add($headerSubtitle)

$pageHost = New-Object System.Windows.Forms.Panel
Set-Bounds $pageHost 0 66 700 304
$form.Controls.Add($pageHost)

$welcomePage = New-Page
$welcomePage.Controls.Add((New-TextLabel 'Welcome' 24 22 640 32 15))
$welcomePage.Controls.Add((New-TextLabel "This wizard copies the FinancialAdvisor loot filter and its four custom sounds into your Path of Exile 2 folder.`r`n`r`nIt can also enable the filter inside Ritual rewards. Close the game before continuing." 24 68 640 100 11))
$pageHost.Controls.Add($welcomePage)

$folderPage = New-Page
$folderPage.Controls.Add((New-TextLabel 'Choose your Path of Exile 2 folder' 24 22 640 32 15))
$folderPage.Controls.Add((New-TextLabel 'This is normally the folder containing poe2_production_Config.ini.' 24 60 640 26 10))
$folderText = New-Object System.Windows.Forms.TextBox
$folderText.Text = $defaultFolder
Set-Bounds $folderText 24 96 540 28
$folderPage.Controls.Add($folderText)
$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = 'Browse...'
Set-Bounds $browseButton 576 95 96 30
$folderPage.Controls.Add($browseButton)
$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choose the Path of Exile 2 folder'
    $dialog.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath $folderText.Text) { $dialog.SelectedPath = $folderText.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $folderText.Text = $dialog.SelectedPath
    }
    $dialog.Dispose()
})
$pageHost.Controls.Add($folderPage)

$ritualPage = New-Page
$ritualPage.Controls.Add((New-TextLabel 'Ritual rewards' 24 22 640 32 15))
$ritualCheck = New-Object System.Windows.Forms.CheckBox
$ritualCheck.Text = 'Enable the item filter inside Ritual rewards'
$ritualCheck.Checked = $true
$ritualCheck.AutoSize = $true
$ritualCheck.Font = New-Object System.Drawing.Font('Segoe UI', 11)
Set-Bounds $ritualCheck 24 70 640 30
$ritualPage.Controls.Add($ritualCheck)
$ritualPage.Controls.Add((New-TextLabel 'Recommended. The installer changes apply_item_filter_to_ritual to true and saves a backup of your config file. Uncheck this if you want to change it manually later.' 48 116 600 70 10))
$pageHost.Controls.Add($ritualPage)

$readyPage = New-Page
$readyPage.Controls.Add((New-TextLabel 'Ready to install' 24 22 640 32 15))
$summaryLabel = New-TextLabel '' 24 70 640 150 11
$readyPage.Controls.Add($summaryLabel)
$pageHost.Controls.Add($readyPage)

$footer = New-Object System.Windows.Forms.Panel
$footer.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
Set-Bounds $footer 0 370 700 60
$form.Controls.Add($footer)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
Set-Bounds $cancelButton 510 15 78 30
$footer.Controls.Add($cancelButton)
$cancelButton.Add_Click({ $form.Close() })

$backButton = New-Object System.Windows.Forms.Button
$backButton.Text = '< Back'
Set-Bounds $backButton 420 15 78 30
$footer.Controls.Add($backButton)

$nextButton = New-Object System.Windows.Forms.Button
$nextButton.Text = 'Next >'
Set-Bounds $nextButton 596 15 80 30
$footer.Controls.Add($nextButton)

$state = @{ Page = 0 }
$pages = @($welcomePage, $folderPage, $ritualPage, $readyPage)

function Show-Page {
    foreach ($page in $pages) { $page.Visible = $false }
    $pages[$state.Page].Visible = $true
    $backButton.Enabled = $state.Page -gt 0
    $nextButton.Text = if ($state.Page -eq ($pages.Count - 1)) { 'Install' } else { 'Next >' }
    if ($state.Page -eq ($pages.Count - 1)) {
        $summaryLabel.Text = "Install to:`r`n$($folderText.Text.Trim())`r`n`r`nFilter: FinancialAdvisor Filter.filter`r`nCustom sounds: 4 included`r`nRitual filtering: $($(if ($ritualCheck.Checked) { 'Enable' } else { 'Leave unchanged' }))"
    }
}

function Confirm-TargetFolder {
    $path = $folderText.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        [System.Windows.Forms.MessageBox]::Show('Choose a destination folder first.', 'Destination required', 'OK', 'Warning') | Out-Null
        return $false
    }
    try {
        if (-not (Test-Path -LiteralPath $path)) {
            $choice = [System.Windows.Forms.MessageBox]::Show("This folder does not exist:`r`n$path`r`n`r`nCreate it?", 'Create folder', 'YesNo', 'Question')
            if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        $folderText.Text = [System.IO.Path]::GetFullPath($path)
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("The folder could not be used:`r`n$($_.Exception.Message)", 'Invalid destination', 'OK', 'Error') | Out-Null
        return $false
    }
}

$backButton.Add_Click({
    if ($state.Page -gt 0) {
        $state.Page--
        Show-Page
    }
})

$nextButton.Add_Click({
    if ($state.Page -eq 1 -and -not (Confirm-TargetFolder)) { return }
    if ($state.Page -lt ($pages.Count - 1)) {
        $state.Page++
        Show-Page
        return
    }

    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $result = Install-FilterFiles $folderText.Text.Trim() $ritualCheck.Checked
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        [System.Windows.Forms.MessageBox]::Show("Installation complete.`r`n`r`n$($result.Target)`r`n`r`n$($result.Ritual)`r`n`r`nReselect the filter in-game if Path of Exile 2 is already open.", 'FinancialAdvisor Filter Setup', 'OK', 'Information') | Out-Null
        $form.Close()
    } catch {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Installation failed', 'OK', 'Error') | Out-Null
    }
})

$form.AcceptButton = $nextButton
$form.CancelButton = $cancelButton
Show-Page
[void] $form.ShowDialog()
