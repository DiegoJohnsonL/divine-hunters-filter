#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$themeWindow = [System.Drawing.Color]::FromArgb(9, 10, 12)
$themeHeader = [System.Drawing.Color]::FromArgb(45, 44, 42)
$themeSurface = [System.Drawing.Color]::FromArgb(32, 33, 36)
$themeInset = [System.Drawing.Color]::FromArgb(14, 15, 18)
$themeFooter = [System.Drawing.Color]::FromArgb(19, 20, 22)
$themeGold = [System.Drawing.Color]::FromArgb(184, 134, 58)
$themeGoldBright = [System.Drawing.Color]::FromArgb(240, 195, 107)
$themeText = [System.Drawing.Color]::FromArgb(246, 237, 219)
$themeMuted = [System.Drawing.Color]::FromArgb(200, 188, 168)

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$filterFile = 'FinancialAdvisor Filter.filter'
$audioFiles = @(
    'hibdivine.mp3'
    'HibOmenLight.mp3'
    'Echoes.mp3'
    'OmenOfTheLiege.mp3'
    'OrbOfAnnulment.mp3'
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
    $label.ForeColor = $themeText
    $label.BackColor = [System.Drawing.Color]::Transparent
    Set-Bounds $label $X $Y $Width $Height
    return $label
}

function New-PoEButton {
    param([string] $Text, [bool] $Primary = $false)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = if ($Primary) { $themeGoldBright } else { $themeGold }
    $button.UseVisualStyleBackColor = $false
    $button.BackColor = if ($Primary) { $themeGold } else { $themeSurface }
    $button.ForeColor = if ($Primary) { [System.Drawing.Color]::FromArgb(24, 21, 17) } else { $themeText }
    $button.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
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
$form.ClientSize = New-Object System.Drawing.Size(720, 440)
$form.BackColor = $themeWindow

$header = New-Object System.Windows.Forms.Panel
$header.BackColor = $themeHeader
Set-Bounds $header 0 0 720 76
$header.Add_Paint({
    param($sender, $paintEvent)
    $pen = New-Object System.Drawing.Pen($themeGoldBright, 1.4)
    $paintEvent.Graphics.DrawEllipse($pen, 18, 16, 38, 38)
    $paintEvent.Graphics.DrawEllipse($pen, 25, 23, 24, 24)
    $paintEvent.Graphics.DrawPolygon($pen, @([System.Drawing.Point]::new(37, 13), [System.Drawing.Point]::new(47, 35), [System.Drawing.Point]::new(37, 57), [System.Drawing.Point]::new(27, 35)))
    $paintEvent.Graphics.DrawLine((New-Object System.Drawing.Pen($themeGold, 1)), 0, 74, 720, 74)
    $pen.Dispose()
})
$form.Controls.Add($header)

$headerTitle = New-TextLabel 'FinancialAdvisor Filter' 72 10 600 30 18
$headerTitle.Font = New-Object System.Drawing.Font('Georgia', 18, [System.Drawing.FontStyle]::Bold)
$headerTitle.ForeColor = $themeGoldBright
$header.Controls.Add($headerTitle)
$headerSubtitle = New-TextLabel 'PATH OF EXILE 2  //  FILTER INSTALLATION' 74 43 500 18 9
$headerSubtitle.ForeColor = $themeMuted
$header.Controls.Add($headerSubtitle)
$stepLabel = New-TextLabel 'STEP 1 OF 4' 590 43 105 18 9
$stepLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$stepLabel.ForeColor = $themeGold
$header.Controls.Add($stepLabel)

$pageHost = New-Object System.Windows.Forms.Panel
$pageHost.BackColor = $themeSurface
Set-Bounds $pageHost 18 92 684 258
$pageHost.Add_Paint({
    param($sender, $paintEvent)
    $paintEvent.Graphics.DrawRectangle((New-Object System.Drawing.Pen($themeGold, 1)), 0, 0, 683, 257)
    $paintEvent.Graphics.DrawRectangle((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(59, 53, 43), 1)), 4, 4, 675, 247)
})
$form.Controls.Add($pageHost)

$welcomePage = New-Page
$welcomeTitle = New-TextLabel 'WELCOME, EXILE' 26 16 630 32 18
$welcomeTitle.Font = New-Object System.Drawing.Font('Georgia', 18, [System.Drawing.FontStyle]::Bold)
$welcomeTitle.ForeColor = $themeGoldBright
$welcomePage.Controls.Add($welcomeTitle)
$welcomePage.Controls.Add((New-TextLabel "This wizard copies the FinancialAdvisor loot filter and five custom drop sounds into your Path of Exile 2 folder.`r`n`r`nIt can also enable the filter inside Ritual rewards. Close the game before continuing." 28 62 630 90 12))
$welcomePage.Controls.Add((New-TextLabel "Filter + 4 custom sounds + optional Ritual setting" 28 168 630 34 10))
$welcomePage.Controls[2].BackColor = $themeInset
$welcomePage.Controls[2].ForeColor = $themeMuted
$welcomePage.Controls[2].Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 5)
$pageHost.Controls.Add($welcomePage)

$folderPage = New-Page
$folderTitle = New-TextLabel 'CHOOSE DESTINATION' 26 16 630 32 18
$folderTitle.Font = New-Object System.Drawing.Font('Georgia', 18, [System.Drawing.FontStyle]::Bold)
$folderTitle.ForeColor = $themeGoldBright
$folderPage.Controls.Add($folderTitle)
$folderPage.Controls.Add((New-TextLabel 'Choose the folder containing poe2_production_Config.ini.' 28 56 630 26 12))
$folderText = New-Object System.Windows.Forms.TextBox
$folderText.Text = $defaultFolder
$folderText.BackColor = $themeInset
$folderText.ForeColor = $themeText
$folderText.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$folderText.Font = New-Object System.Drawing.Font('Segoe UI', 12)
Set-Bounds $folderText 28 88 520 34
$folderPage.Controls.Add($folderText)
$browseButton = New-PoEButton 'BROWSE...'
Set-Bounds $browseButton 558 89 100 34
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
$folderPage.Controls.Add((New-TextLabel 'Usually: Documents\My Games\Path of Exile 2' 28 144 630 34 10))
$folderPage.Controls[4].BackColor = $themeInset
$folderPage.Controls[4].ForeColor = $themeMuted
$folderPage.Controls[4].Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 5)
$pageHost.Controls.Add($folderPage)

$ritualPage = New-Page
$ritualTitle = New-TextLabel 'RITUAL REWARDS' 26 16 630 32 18
$ritualTitle.Font = New-Object System.Drawing.Font('Georgia', 18, [System.Drawing.FontStyle]::Bold)
$ritualTitle.ForeColor = $themeGoldBright
$ritualPage.Controls.Add($ritualTitle)
$ritualCheck = New-Object System.Windows.Forms.CheckBox
$ritualCheck.Text = 'Enable the item filter inside Ritual rewards'
$ritualCheck.Checked = $true
$ritualCheck.AutoSize = $true
$ritualCheck.Font = New-Object System.Drawing.Font('Segoe UI', 12)
$ritualCheck.ForeColor = $themeText
$ritualCheck.BackColor = $themeSurface
$ritualCheck.Cursor = [System.Windows.Forms.Cursors]::Hand
Set-Bounds $ritualCheck 28 64 640 32
$ritualPage.Controls.Add($ritualCheck)
$ritualPage.Controls.Add((New-TextLabel 'Recommended. The installer changes apply_item_filter_to_ritual to true and saves a backup of your config file. Uncheck this if you want to change it manually later.' 52 106 610 66 12))
$ritualPage.Controls.Add((New-TextLabel 'The game must be closed while this setting is changed.' 28 186 630 34 10))
$ritualPage.Controls[3].BackColor = $themeInset
$ritualPage.Controls[3].ForeColor = $themeMuted
$ritualPage.Controls[3].Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 5)
$pageHost.Controls.Add($ritualPage)

$readyPage = New-Page
$readyTitle = New-TextLabel 'READY TO DEPLOY' 26 16 630 32 18
$readyTitle.Font = New-Object System.Drawing.Font('Georgia', 18, [System.Drawing.FontStyle]::Bold)
$readyTitle.ForeColor = $themeGoldBright
$readyPage.Controls.Add($readyTitle)
$summaryLabel = New-TextLabel '' 28 60 630 150 11
$summaryLabel.BackColor = $themeInset
$summaryLabel.ForeColor = $themeMuted
$summaryLabel.Font = New-Object System.Drawing.Font('Consolas', 11)
$summaryLabel.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 5)
$readyPage.Controls.Add($summaryLabel)
$pageHost.Controls.Add($readyPage)

$footer = New-Object System.Windows.Forms.Panel
$footer.BackColor = $themeFooter
Set-Bounds $footer 0 368 720 72
$footer.Add_Paint({
    param($sender, $paintEvent)
    $paintEvent.Graphics.DrawLine((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(67, 55, 39), 1)), 0, 0, 720, 0)
})
$form.Controls.Add($footer)

$cancelButton = New-PoEButton 'CANCEL'
Set-Bounds $cancelButton 458 19 86 34
$footer.Controls.Add($cancelButton)
$cancelButton.Add_Click({ $form.Close() })

$backButton = New-PoEButton '< BACK'
Set-Bounds $backButton 366 19 86 34
$footer.Controls.Add($backButton)

$nextButton = New-PoEButton 'NEXT >' $true
Set-Bounds $nextButton 554 19 112 34
$footer.Controls.Add($nextButton)

$state = @{ Page = 0 }
$pages = @($welcomePage, $folderPage, $ritualPage, $readyPage)

function Show-Page {
    foreach ($page in $pages) { $page.Visible = $false }
    $pages[$state.Page].Visible = $true
    $backButton.Enabled = $state.Page -gt 0
    $nextButton.Text = if ($state.Page -eq ($pages.Count - 1)) { 'INSTALL' } else { 'NEXT >' }
    $stepLabel.Text = "STEP $($state.Page + 1) OF $($pages.Count)"
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
