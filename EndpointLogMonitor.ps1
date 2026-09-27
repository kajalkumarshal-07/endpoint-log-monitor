#Requires -Version 5.1
<#
    Endpoint Log Monitor
    Reads ConfigMgr / Intune / MDM client logs, groups the errors that need action,
    attaches known troubleshooting steps, decodes error codes and exports reports.

    Files in this folder:
      EndpointLogMonitor.ps1   this script - run it
      Rules.json               shared rules file - edit to add your own fixes
      *.lib.ps1                internal modules (dot-sourced, do not run directly)

    Nothing is sent anywhere: every read is local or over your own admin shares.
#>

param(
    [string]$RulesPath,
    [string]$ComputerName
)

$ErrorActionPreference = 'Stop'
$script:Root = $PSScriptRoot
if (-not $script:Root) { $script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $RulesPath)   { $RulesPath = Join-Path $script:Root 'Rules.json' }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

foreach ($f in @('Rules.lib.ps1', 'LogReader.lib.ps1', 'Export.lib.ps1', 'Actions.lib.ps1', 'Demo.lib.ps1', 'Ui.Build.ps1')) {
    . (Join-Path $script:Root $f)
}

# ------------------------------------------------------------------ state ----
$script:State = @{
    Rules     = $null
    Index     = $null
    Rows      = New-Object System.Collections.ArrayList
    LastResult = $null
    LastScan  = '--'
}

function Reload-Rules {
    $script:State.Rules = Import-Rules -Path $RulesPath
    $script:State.Index = Build-RuleIndex -Rules $script:State.Rules
}

# ------------------------------------------------------------- displayers ----
function Set-Status {
    param($Ui, [string]$Text)
    $Ui.LblStatus.Text = $Text
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-Cards {
    param($Ui, $Result, $Rows, $Target)
    $attention = @($Rows | Where-Object { $_.Severity -ne 'Info' }).Count
    if ($Rows.Count -gt 0 -and $attention -eq 0) { $attention = $Rows.Count }
    $Ui.CardAttention.Value.Text = "$attention"
    $Ui.CardFixes.Value.Text     = "$(@($Rows | Where-Object { $_.Fix -eq 'Yes' }).Count)"
    $Ui.CardLogs.Value.Text      = "$($Result.LogsRead)"
    $Ui.CardScan.Value.Text      = $script:State.LastScan
    $name = if ([string]::IsNullOrWhiteSpace($Target)) { $env:COMPUTERNAME } else { $Target.Trim() }
    $Ui.CardTarget.Value.Text = $name
    if ($name.Length -gt 18) {
        $Ui.CardTarget.Value.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    } else {
        $Ui.CardTarget.Value.Font = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
    }
}

function Reset-DetailScroll {
    # WinForms can leave the auto-scrolling detail pane part way down after a
    # scan (a control it tried to bring into view). Always start at the top.
    param($Ui)
    if ($Ui.DetailScroll) { $Ui.DetailScroll.AutoScrollPosition = New-Object System.Drawing.Point(0, 0) }
}

function Show-NothingSelected {
    param($Ui)
    $Ui.LblDetailTitle.Text = 'No matching issues'
    $Ui.Badge.Text = ''
    $Ui.Badge.BackColor = $script:Colors.Pale
    $Ui.Badge.ForeColor = $script:Colors.Slate
    $Ui.Badge2.Text = ''
    $Ui.Badge.Visible = $false
    $Ui.Badge2.Visible = $false
    $Ui.RtbSteps.Clear()
    $Ui.RtbRaw.Clear()
    $Ui.LblRawSub.Text = ''
    Reset-DetailScroll -Ui $Ui
}

function Show-SelectedIssue {
    param($Ui, $Item)
    if (-not $Item) { Show-NothingSelected -Ui $Ui; return }

    $Ui.LblDetailTitle.Text = "$($Item.Issue)"
    if ($Item.Fix -eq 'Yes') {
        $Ui.Badge.Text = 'KNOWN FIX'
        $Ui.Badge.BackColor = $script:Colors.Ok
        $Ui.Badge.ForeColor = $script:Colors.OkTxt
    } else {
        $Ui.Badge.Text = 'NO KNOWN FIX'
        $Ui.Badge.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
        $Ui.Badge.ForeColor = $script:Colors.Slate
    }
    $Ui.Badge.Visible = $true
    $Ui.Badge2.Visible = $true
    $Ui.Badge2.Text = "$($Item.Log)   .   seen $($Item.Count)x   .   $($Item.FirstSeen)-$($Item.LastSeen)"

    $Ui.RtbSteps.Clear()
    $Ui.RtbSteps.SelectionStart = 0
    $steps = @($Item._steps)
    if ($steps.Count -gt 0) {
        for ($i = 0; $i -lt $steps.Count; $i++) {
            $Ui.RtbSteps.SelectionColor = $script:Colors.Accent
            $Ui.RtbSteps.AppendText(('{0}. ' -f ($i + 1)))
            $Ui.RtbSteps.SelectionColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
            $Ui.RtbSteps.AppendText("$($steps[$i])`r`n`r`n")
        }
    } else {
        $Ui.RtbSteps.SelectionColor = $script:Colors.GreyLbl
        $Ui.RtbSteps.AppendText("No known fix for this one yet.`r`n`r`nAdd one to Rules.json and it will appear here.")
    }
    $Ui.RtbSteps.SelectionColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $Ui.RtbSteps.SelectionStart = 0
    $Ui.RtbSteps.SelectionLength = 0

    $Ui.RtbRaw.Clear()
    $Ui.RtbRaw.SelectionColor = $script:Colors.AccentHi
    $Ui.RtbRaw.AppendText("$($Item.Log)`r`n")
    $Ui.RtbRaw.SelectionColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $Ui.RtbRaw.AppendText(('-' * 58) + "`r`n")
    $samples = @($Item._samples)
    if ($samples.Count -gt 0) {
        $Ui.RtbRaw.SelectionColor = $script:Colors.Text
        foreach ($s in $samples) { $Ui.RtbRaw.AppendText("$s`r`n") }
    } else {
        $Ui.RtbRaw.SelectionColor = $script:Colors.Muted
        $Ui.RtbRaw.AppendText('(no sample lines retained)`r`n')
    }
    $Ui.RtbRaw.SelectionStart = 0
    $Ui.RtbRaw.SelectionLength = 0
    $Ui.LblRawSub.Text = "$($Item.Log)  -  $($Item.Count) occurrences"
    Reset-DetailScroll -Ui $Ui
}

function Update-Grid {
    param($Ui, $Rows)
    $q = "$($Ui.TxtFilter.Text)".Trim()
    $filtered = $Rows
    if ($q) {
        $filtered = @($Rows | Where-Object {
            $_.Issue -like "*$q*" -or $_.Log -like "*$q*" -or
            $_.Severity -like "*$q*" -or $_.Fix -like "*$q*"
        })
    }
    $Ui.Grid.DataSource = $null
    $binding = [System.Collections.ArrayList]@($filtered)
    $Ui.Grid.DataSource = $binding
    $Ui.Grid.ClearSelection()
    if ($Ui.Grid.Rows.Count -gt 0) {
        $Ui.Grid.Rows[0].Selected = $true
        Show-SelectedIssue -Ui $Ui -Item $Ui.Grid.Rows[0].DataBoundItem
    } else {
        Show-NothingSelected -Ui $Ui
    }
    return $filtered.Count
}

function Invoke-CodeLookup {
    param($Ui, $Index)
    $Ui.VHex.Text = '-'; $Ui.VSign.Text = '-'; $Ui.VUns.Text = '-'; $Ui.VRaw.Text = '-'
    $Ui.LblResConf.Text = ''
    $Ui.RtbMeaning.Clear(); $Ui.RtbCodeSteps.Clear()

    $res = ConvertFrom-UserErrorCode -InputText $Ui.TxtCode.Text -Index $Index
    if (-not $res) {
        $Ui.LblResTitle.Text = 'Not a recognisable error code.'
        $Ui.RtbMeaning.AppendText('Enter a hexadecimal value like 0x87D00324, a decimal value like -2016410844, or an exit code like 1618.')
        return
    }

    $Ui.LblResTitle.Text = $res.Hex
    $Ui.VHex.Text  = $res.Hex
    $Ui.VSign.Text = "$($res.Signed)"
    $Ui.VUns.Text  = "$($res.Unsigned)"
    if ($res.Msi -ne $null)       { $Ui.VRaw.Text = "$($res.Msi)  (MSI)" }
    elseif ($res.Win32 -ne $null) { $Ui.VRaw.Text = "$($res.Win32)  (Win32)" }
    else                          { $Ui.VRaw.Text = '-' }

    $Ui.RtbMeaning.SelectionColor = $script:Colors.Ink
    $Ui.RtbMeaning.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    if ($res.Meaning) {
        $Ui.LblResConf.Text = switch ($res.Confidence) {
            'verified'  { 'Definition verified against Microsoft documentation.' }
            'community' { 'Definition from community / field reports - a strong lead, not a citation.' }
            default     { 'No authoritative definition published - treat this meaning as unconfirmed.' }
        }
        $Ui.RtbMeaning.AppendText("$($res.Meaning)`r`n`r`n")
    } else {
        $Ui.LblResConf.Text = 'Decoded, but this code is not in Rules.json yet.'
        $Ui.RtbMeaning.AppendText("No entry in the shared rules file for this code.`r`n`r`n")
    }
    $Ui.RtbMeaning.SelectionColor = $script:Colors.Slate
    $Ui.RtbMeaning.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    foreach ($n in @($res.Notes)) { $Ui.RtbMeaning.AppendText("$n`r`n") }
    if (-not $res.Meaning) {
        $Ui.RtbMeaning.AppendText("`r`nAdd a fix for it in Rules.json and it will show up here and on the Health tab.")
    }
    $Ui.RtbMeaning.SelectionStart = 0
    $Ui.RtbMeaning.SelectionLength = 0

    if ($res.Fix -and @($res.Fix.steps).Count -gt 0) {
        $i = 1
        foreach ($s in @($res.Fix.steps)) {
            $Ui.RtbCodeSteps.SelectionColor = $script:Colors.Accent
            $Ui.RtbCodeSteps.AppendText("$i. ")
            $Ui.RtbCodeSteps.SelectionColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
            $Ui.RtbCodeSteps.AppendText("$s`r`n`r`n")
            $i++
        }
    } else {
        $Ui.RtbCodeSteps.SelectionColor = $script:Colors.GreyLbl
        $Ui.RtbCodeSteps.AppendText('No troubleshooting steps recorded for this code yet.')
    }
    $Ui.RtbCodeSteps.SelectionStart = 0
    $Ui.RtbCodeSteps.SelectionLength = 0
}

function Add-ActionLog {
    param($Ui, [string]$Text, [string]$HexColor)
    $Ui.TxtActLog.SelectionStart = $Ui.TxtActLog.TextLength
    if ($HexColor) { $Ui.TxtActLog.SelectionColor = [System.Drawing.Color]::FromArgb([Convert]::ToInt32($HexColor, 16)) }
    $Ui.TxtActLog.AppendText(('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Text) + "`r`n")
    $Ui.TxtActLog.SelectionColor = $script:Colors.Text
    $Ui.TxtActLog.ScrollToCaret()
}

function Show-AboutText {
    param($Box)
    $Box.Clear()

    $emit = {
        param([string]$Text, [double]$Size, [bool]$Bold, [string]$HexColor, [int]$NewLines)
        $Box.SelectionStart = $Box.TextLength
        $Box.SelectionColor = [System.Drawing.Color]::FromArgb([Convert]::ToInt32($HexColor, 16))
        $Box.SelectionFont = New-Object System.Drawing.Font('Segoe UI', $Size,
            $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
        $Box.AppendText($Text)
        if ($NewLines -gt 0) {
            $Box.SelectionFont = New-Object System.Drawing.Font('Segoe UI', 8)
            $Box.AppendText("`r`n" * $NewLines)
        }
    }

    & $emit 'Endpoint Log Monitor' 18 $true '0B1220' 1
    & $emit 'One Windows app for techs and admins. Reads local and remote devices. Nothing leaves your network.' 10 $false '64748B' 2

    & $emit 'WHY IT MATTERS' 8 $true '64748B' 1
    & $emit 'Patches, apps, security baselines and compliance all reach the device through the ConfigMgr client or the Intune Management Extension. When that agent is unhealthy, nothing arrives, and the device often still looks fine in the console.' 10 $false '1E293B' 1
    & $emit 'Most teams only look at client health after a failed rollout or a vulnerability report. By then the answer is buried in more than 150 log files, and a tech has to know which one to open.' 10 $false '1E293B' 1
    & $emit 'Endpoint Log Monitor reads those logs for you. It groups repeated errors, hides known harmless noise and matches each problem to steps your team can follow.' 10 $false '1E293B' 2

    & $emit 'WHAT IT DOES' 8 $true '64748B' 1
    foreach ($f in @(
        'Only what needs a fix - repeated errors collapse into one line with a count and first/last seen times. Known issues are listed first.',
        'Steps next to every known problem - why it happens, what to check and which log to open.',
        'Check any device from your desk - type a computer name to read its logs over the admin share. No agent on the endpoint.',
        'Low noise - harmless messages are filtered out of the box; right-click anything else to hide it for the whole team.',
        'Client actions - trigger policy, app evaluation and update scans, restart services and sync Intune from the same window.',
        'Ticket-ready output - export action items and fixes as an HTML report or CSV.'
    )) { & $emit ("  " + [char]0x2022 + "  " + $f) 10 $false '1E293B' 1 }
    $Box.AppendText("`r`n")

    & $emit 'WHAT IT READS' 8 $true '64748B' 1
    foreach ($f in @(
        'ConfigMgr   C:\Windows\CCM\Logs - AppEnforce, CAS, LocationServices, PolicyAgent, WUAHandler and every other client log',
        'Setup       C:\Windows\ccmsetup\Logs - client installs and upgrades',
        'Intune      C:\ProgramData\Microsoft\IntuneManagementExtension\Logs - Win32 apps, scripts, Remediations',
        'MDM         DeviceManagement-Enterprise-Diagnostics-Provider/Admin - enrollment and configuration profile results'
    )) { & $emit ('  ' + $f) 9 $false '1E293B' 1 }
    $Box.AppendText("`r`n")

    & $emit 'HOW IT FITS' 8 $true '64748B' 1
    foreach ($f in @(
        'One app with nothing else to install.',
        'No telemetry - it reads log files and event logs. Nothing is sent anywhere.',
        'Your own rules - add fixes for your environment in Rules.json. It is never overwritten by this tool.'
    )) { & $emit ("  " + [char]0x2022 + "  " + $f) 10 $false '1E293B' 1 }
    $Box.AppendText("`r`n")
    & $emit 'Microsoft, Configuration Manager and Intune are trademarks of the Microsoft group of companies. This tool is independent and is not affiliated with or endorsed by Microsoft.' 8.5 $false '94A3B8' 0

    $Box.SelectionStart = 0
    $Box.SelectionLength = 0
}

# ---------------------------------------------------------------- actions ----
function Hide-IssuePattern {
    param($Ui, $Item)
    if (-not $Item) { return }

    $rx = ConvertTo-HiddenPattern -Message "$($Item._message)"

    if (-not $script:State.Rules.hidden) {
        $script:State.Rules | Add-Member NoteProperty hidden @() -Force
    }
    $list = @($script:State.Rules.hidden) + @($rx)
    $script:State.Rules | Add-Member NoteProperty hidden $list -Force
    try { Save-Rules -Rules $script:State.Rules -Path $RulesPath } catch { }
    $script:State.Index = Build-RuleIndex -Rules $script:State.Rules
}

function Run-SelectedAction {
    param($Ui)
    $idx = $Ui.ActionList.SelectedIndex
    if ($idx -lt 0) { Add-ActionLog -Ui $Ui -Text 'Select an action first.' -HexColor 'FCA5A5'; return }
    $name = [string]$Ui.ActionList.Items[$idx]
    $computer = $Ui.TxtTarget.Text

    if ($name.StartsWith('---')) { return }
    if ($name -eq 'Restart CCM client service (CcmExec)') {
        Add-ActionLog -Ui $Ui -Text (Invoke-ServiceRestart -Computer $computer -Service 'CcmExec') -HexColor 'FDE68A'; return
    }
    if ($name -eq 'Restart Windows Update service (wuauserv)') {
        Add-ActionLog -Ui $Ui -Text (Invoke-ServiceRestart -Computer $computer -Service 'wuauserv') -HexColor 'FDE68A'; return
    }
    if ($name -eq 'Clear ccmcache') {
        $ans = [System.Windows.Forms.MessageBox]::Show(
            'Delete all cached content in ccmcache? Deployments may need to re-download.',
            'Endpoint Log Monitor', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { return }
        Add-ActionLog -Ui $Ui -Text (Invoke-CcmCacheClear -Computer $computer) -HexColor 'FDE68A'; return
    }
    if ($name -eq 'Trigger Intune / MDM sync') {
        Add-ActionLog -Ui $Ui -Text (Invoke-IntuneSync -Computer $computer) -HexColor '93C5FD'; return
    }

    $action = $script:ScheduleActions[$idx]
    Add-ActionLog -Ui $Ui -Text "Triggering: $($action.Name)" -HexColor '93C5FD'
    foreach ($line in (Invoke-ClientSchedule -Computer $computer -Ids $action.Ids -Name $action.Name)) {
        if ($line -like 'OK*') { Add-ActionLog -Ui $Ui -Text $line -HexColor '86EFAC' }
        else                   { Add-ActionLog -Ui $Ui -Text $line -HexColor 'FCA5A5' }
    }
}

function Run-AllCycles {
    param($Ui)
    $computer = $Ui.TxtTarget.Text
    Add-ActionLog -Ui $Ui -Text '--- Running all ConfigMgr client cycles ---' -HexColor '93C5FD'
    foreach ($a in $script:ScheduleActions) {
        foreach ($line in (Invoke-ClientSchedule -Computer $computer -Ids $a.Ids -Name $a.Name)) {
            if ($line -like 'OK*') { Add-ActionLog -Ui $Ui -Text $line -HexColor '86EFAC' }
            else                   { Add-ActionLog -Ui $Ui -Text $line -HexColor 'FCA5A5' }
        }
    }
    Add-ActionLog -Ui $Ui -Text '--- done ---' -HexColor '93C5FD'
}

# ------------------------------------------------------------------ scan -----
function Invoke-ScanFromUi {
    param($Ui, [switch]$Demo)
    $Ui.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        Set-Status -Ui $Ui -Text 'Scanning...'
        $target = $Ui.TxtTarget.Text
        $keepInfo = $Ui.ChkInfo.Checked

        # hide-noise switch: temporarily empty the noise list when unchecked
        $savedNoise = $script:State.Index.Noise
        if (-not $Ui.ChkNoise.Checked) {
            $script:State.Index = Build-RuleIndex -Rules (
                [pscustomobject]@{
                    version = $script:State.Rules.version
                    fixes   = $script:State.Rules.fixes
                    noise   = @()
                    hidden  = $script:State.Rules.hidden
                })
        }

        $pb = {
            param($m)
            $Ui.LblStatus.Text = "Scanning - $m"
            [System.Windows.Forms.Application]::DoEvents()
        }
        if ($Demo) {
            # Sample SCCM / Intune logs written on the fly - lets the whole
            # pipeline run on a machine with no ConfigMgr client installed.
            $demoRoot = New-DemoLogs -Root (Join-Path $script:Root 'DemoLogs')
            $result = Invoke-LogScan -Index $script:State.Index -KeepInfo:$keepInfo `
                -LogRoots @($demoRoot) -SkipMdm -Progress $pb
        } else {
            $result = Invoke-LogScan -Computer $target -Index $script:State.Index -KeepInfo:$keepInfo -Progress $pb
        }

        if (-not $Ui.ChkNoise.Checked) {
            $script:State.Index = Build-RuleIndex -Rules $script:State.Rules
        } else {
            $script:State.Index.Noise = $savedNoise
        }

        $rows = New-IssueRows -Groups $result.Groups -Index $script:State.Index
        $script:State.LastResult = $result
        $script:State.LastScan = Get-Date -Format 'HH:mm'
        $script:State.Rows = New-Object System.Collections.ArrayList
        foreach ($r in $rows) { [void]$script:State.Rows.Add($r) }

        $count = Update-Grid -Ui $Ui -Rows $script:State.Rows
        Update-Cards -Ui $Ui -Result $result -Rows $script:State.Rows -Target $(if ($Demo) { 'DEMO' } else { $target })
        $summary = ("{0} issues from {1} log files ({2} entries read, {3} hidden by your rules)." -f
            $count, $result.LogsRead, $result.Lines, $result.Hidden)
        if ($Demo) {
            $summary = "Demo data - $summary Click Scan logs to read this machine instead."
        }
        Set-Status -Ui $Ui -Text $summary
        Reset-DetailScroll -Ui $Ui
    } catch {
        Set-Status -Ui $Ui -Text "Scan failed: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("$($_.Exception.Message)", 'Endpoint Log Monitor', 'OK', 'Error') | Out-Null
    } finally {
        $Ui.Form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

# ------------------------------------------------------------------ entry ----
Reload-Rules
$ui = Build-Interface -InitialTarget $ComputerName

$ui.BtnScan.Add_Click({ Invoke-ScanFromUi -Ui $ui })
$ui.BtnRescan.Add_Click({ Invoke-ScanFromUi -Ui $ui })
$ui.BtnDemo.Add_Click({ Invoke-ScanFromUi -Ui $ui -Demo })

$ui.BtnOpenRules.Add_Click({
    if (-not (Test-Path -LiteralPath $RulesPath)) {
        try { Save-Rules -Rules $script:State.Rules -Path $RulesPath } catch { }
    }
    try { Invoke-Item -LiteralPath $RulesPath } catch {
        [System.Windows.Forms.MessageBox]::Show($RulesPath, 'Rules file', 'OK', 'Information') | Out-Null
    }
})

$ui.BtnExportHtml.Add_Click({
    if ($script:State.Rows.Count -eq 0) { Set-Status -Ui $ui -Text 'Nothing to export yet - run a scan first.'; return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'HTML report (*.html)|*.html'
    $dlg.FileName = "EndpointLogMonitor-$(Get-Date -Format 'yyyyMMdd-HHmm').html"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        $target = $ui.TxtTarget.Text
        $lines = if ($script:State.LastResult) { $script:State.LastResult.Lines } else { 0 }
        $logs  = if ($script:State.LastResult) { $script:State.LastResult.LogsRead } else { 0 }
        Export-IssuesToHtml -Rows $script:State.Rows -Path $dlg.FileName -Target $target -LogsRead $logs -Lines $lines
        Set-Status -Ui $ui -Text "Report written to $($dlg.FileName)"
        Invoke-Item -LiteralPath $dlg.FileName
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Export failed', 'OK', 'Error') | Out-Null
    }
})

$ui.BtnExportCsv.Add_Click({
    if ($script:State.Rows.Count -eq 0) { Set-Status -Ui $ui -Text 'Nothing to export yet - run a scan first.'; return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'CSV file (*.csv)|*.csv'
    $dlg.FileName = "EndpointLogMonitor-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        Export-IssuesToCsv -Rows $script:State.Rows -Path $dlg.FileName
        Set-Status -Ui $ui -Text "CSV written to $($dlg.FileName)"
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Export failed', 'OK', 'Error') | Out-Null
    }
})

$ui.TxtFilter.Add_TextChanged({
    if ($script:State.LastResult) { $null = Update-Grid -Ui $ui -Rows $script:State.Rows }
})

$ui.Grid.Add_SelectionChanged({
    if ($ui.Grid.CurrentRow) { Show-SelectedIssue -Ui $ui -Item $ui.Grid.CurrentRow.DataBoundItem }
})

$ui.BtnLookup.Add_Click({ Invoke-CodeLookup -Ui $ui -Index $script:State.Index })
$ui.TxtCode.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Invoke-CodeLookup -Ui $ui -Index $script:State.Index
        $e.SuppressKeyPress = $true
    }
})
foreach ($b in $ui.SampleButtons) {
    $btn = $b
    $btn.Add_Click({
        $ui.TxtCode.Text = $btn.Text
        Invoke-CodeLookup -Ui $ui -Index $script:State.Index
    }.GetNewClosure())
}

$ui.BtnRunAction.Add_Click({ Run-SelectedAction -Ui $ui })
$ui.BtnRunAll.Add_Click({ Run-AllCycles -Ui $ui })

$ui.BtnCopy.Add_Click({
    if ($ui.Grid.CurrentRow) {
        $item = $ui.Grid.CurrentRow.DataBoundItem
        $text = $item.Issue + "`r`n" + ('-' * [Math]::Min(60, $item.Issue.Length)) + "`r`n"
        $i = 1
        foreach ($s in @($item._steps)) { $text += "$i. $s`r`n"; $i++ }
        try { Set-Clipboard -Text $text; Set-Status -Ui $ui -Text 'Steps copied to the clipboard.' } catch { }
    }
})

$ui.BtnCopyCsv.Add_Click({
    if ($ui.Grid.CurrentRow) {
        $r = $ui.Grid.CurrentRow.DataBoundItem
        $esc = { param($v) $s = "$v"; if ($s -match '[",\r\n]') { '"' + ($s -replace '"', '""') + '"' } else { $s } }
        $line = @(
            (& $esc $r.Severity), (& $esc $r.Issue), (& $esc $r.Fix), (& $esc $r.Log),
            $r.Count, (& $esc $r.FirstSeen), (& $esc $r.LastSeen),
            (& $esc (@($r._codes) -join ' ')), (& $esc (@($r._steps) -join ' | '))
        ) -join ','
        try { Set-Clipboard -Text $line; Set-Status -Ui $ui -Text 'CSV row copied to the clipboard.' } catch { }
    }
})

# right-click menu on the issues grid
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miCopy = New-Object System.Windows.Forms.ToolStripMenuItem('Copy issue text')
$miSteps = New-Object System.Windows.Forms.ToolStripMenuItem('Copy troubleshooting steps')
$miHide = New-Object System.Windows.Forms.ToolStripMenuItem('Hide this pattern for the whole team')
$miCode = New-Object System.Windows.Forms.ToolStripMenuItem('Look up the error code')
[void]$menu.Items.AddRange(@($miCopy, $miSteps, $miHide, $miCode))
$ui.Grid.ContextMenuStrip = $menu

$miCopy.Add_Click({
    if ($ui.Grid.CurrentRow) {
        $i = $ui.Grid.CurrentRow.DataBoundItem
        try { Set-Clipboard -Text "$($i.Severity)`t$($i.Issue)`t$($i.Log)`t$($i.Count)x" } catch { }
    }
})
$miSteps.Add_Click({
    if ($ui.Grid.CurrentRow) {
        $i = $ui.Grid.CurrentRow.DataBoundItem
        $text = ($i._steps -join "`r`n")
        try { Set-Clipboard -Text $text } catch { }
    }
})
$miHide.Add_Click({
    if ($ui.Grid.CurrentRow) {
        Hide-IssuePattern -Ui $ui -Item $ui.Grid.CurrentRow.DataBoundItem
        Set-Status -Ui $ui -Text 'Pattern added to Rules.json - re-scanning.'
        Invoke-ScanFromUi -Ui $ui
    }
})
$miCode.Add_Click({
    if ($ui.Grid.CurrentRow) {
        $i = $ui.Grid.CurrentRow.DataBoundItem
        $hex = @($i._codes | Where-Object { $_ -like '0x*' }) | Select-Object -First 1
        if (-not $hex) { $hex = @($i._codes) | Select-Object -First 1 }
        if ($hex) {
            $ui.Tabs.SelectedIndex = 1
            $ui.TxtCode.Text = "$hex"
            Invoke-CodeLookup -Ui $ui -Index $script:State.Index
        }
    }
})

$ui.ChkInfo.Add_CheckedChanged({
    if ($script:State.LastResult) { Invoke-ScanFromUi -Ui $ui }
})
$ui.ChkNoise.Add_CheckedChanged({
    if ($script:State.LastResult) { Invoke-ScanFromUi -Ui $ui }
})

Show-AboutText -Box $ui.About
Set-Status -Ui $ui -Text 'Ready. Click Scan logs to read the client logs on this device.'

$ui.Form.Add_Shown({
    # Anchors are applied only now: before layout WinForms would capture a
    # stale parent size and throw the right-hand controls off screen.
    Set-ResponsiveAnchors -Ui $ui
    if ($ComputerName) { Invoke-ScanFromUi -Ui $ui }
})

[void]$ui.Form.ShowDialog()
