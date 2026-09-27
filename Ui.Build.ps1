# Ui.Build.ps1 - WinForms control construction
# Dot-sourced by EndpointLogMonitor.ps1

$script:Colors = @{
    Dark     = [System.Drawing.Color]::FromArgb(11, 18, 32)
    Dark2    = [System.Drawing.Color]::FromArgb(17, 26, 45)
    Accent   = [System.Drawing.Color]::FromArgb(37, 99, 235)
    AccentHi = [System.Drawing.Color]::FromArgb(96, 165, 250)
    Text     = [System.Drawing.Color]::FromArgb(226, 232, 240)
    Muted    = [System.Drawing.Color]::FromArgb(148, 163, 184)
    Line     = [System.Drawing.Color]::FromArgb(203, 213, 225)
    Error    = [System.Drawing.Color]::FromArgb(185, 28, 28)
    Warn     = [System.Drawing.Color]::FromArgb(180, 83, 9)
    Ok       = [System.Drawing.Color]::FromArgb(21, 128, 61)
    OkTxt    = [System.Drawing.Color]::FromArgb(220, 252, 231)
    Surface  = [System.Drawing.Color]::FromArgb(248, 250, 252)
    White    = [System.Drawing.Color]::White
    Ink      = [System.Drawing.Color]::FromArgb(15, 23, 42)
    Slate    = [System.Drawing.Color]::FromArgb(71, 85, 105)
    GreyLbl  = [System.Drawing.Color]::FromArgb(100, 116, 139)
    Pale     = [System.Drawing.Color]::FromArgb(241, 245, 249)
}

function Set-ResponsiveAnchors {
    <# Applied once the form has actually been laid out (see the Add_Shown hook
       in EndpointLogMonitor.ps1). Setting Anchor while the form is still being
       built is unreliable: WinForms records the parent's size before the
       TabPage has its final width, then shifts every anchored control by that
       delta, which pushes them far off screen. #>
    param($Ui)
    if (-not $Ui -or -not $script:UiAnchors) { return }
    foreach ($a in $script:UiAnchors) {
        try { $a.Ctrl.Anchor = $a.Anchor } catch { }
    }
}

function New-Panel {
    param([string]$Name, $Parent, [System.Drawing.Rectangle]$Bounds, [System.Drawing.Color]$BackColor)
    $p = New-Object System.Windows.Forms.Panel
    $p.Name = $Name
    if ($Bounds) { $p.Location = $Bounds.Location; $p.Size = $Bounds.Size }
    if ($BackColor -ne [System.Drawing.Color]::Empty) { $p.BackColor = $BackColor }
    if ($Parent) { $Parent.Controls.Add($p) }
    return $p
}

function New-Label {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [double]$Size = 9,
          [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular,
          [System.Drawing.Color]$Color = [System.Drawing.Color]::Empty)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, $H)
    $l.Font = New-Object System.Drawing.Font('Segoe UI', $Size, $Style)
    $l.ForeColor = if ($Color -eq [System.Drawing.Color]::Empty) { $script:Colors.Ink } else { $Color }
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.AutoSize = $false
    if ($Parent) { $Parent.Controls.Add($l) }
    return $l
}

function New-Button {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H,
          [System.Drawing.Color]$Back = [System.Drawing.Color]::Empty,
          [System.Drawing.Color]$Fore = [System.Drawing.Color]::Empty,
          [switch]$Outline)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.FlatStyle = 'Flat'
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand

    if ($Back -eq [System.Drawing.Color]::Empty) { $Back = $script:Colors.Accent }
    if ($Fore -eq [System.Drawing.Color]::Empty) { $Fore = [System.Drawing.Color]::White }
    $b.BackColor = $Back
    $b.ForeColor = $Fore
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $(if ($Outline) { $script:Colors.Line } else { $Back })
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
        [Math]::Min(255, [int]$Back.R + 16),
        [Math]::Min(255, [int]$Back.G + 16),
        [Math]::Min(255, [int]$Back.B + 16))
    if ($Parent) { $Parent.Controls.Add($b) }
    return $b
}

function New-StatCard {
    param($Parent, [string]$Name, [int]$X, [int]$W, [string]$Value, [string]$LabelText, $ValueColor)
    $c = New-Panel -Name $Name -Parent $Parent -BackColor $script:Colors.White `
        -Bounds (New-Object System.Drawing.Rectangle($X, 12, $W, 68))
    $c.BorderStyle = 'FixedSingle'
    $v = New-Label -Parent $c -Text $Value -X 16 -Y 10 -W ($W - 32) -H 30 -Size 17 -Style Bold `
        -Color $(if ($ValueColor) { $ValueColor } else { $script:Colors.Ink })
    New-Label -Parent $c -Text $LabelText.ToUpper() -X 16 -Y 42 -W ($W - 32) -H 18 -Size 8 -Style Bold `
        -Color $script:Colors.GreyLbl | Out-Null
    return [pscustomobject]@{ Panel = $c; Value = $v }
}

function New-MonoField {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [double]$Size)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($X, $Y)
    $t.Size = New-Object System.Drawing.Size($W, $H)
    $t.Font = New-Object System.Drawing.Font('Consolas', $Size)
    $t.BorderStyle = 'FixedSingle'
    if ($Parent) { $Parent.Controls.Add($t) }
    return $t
}

function Build-Interface {
    param([string]$InitialTarget)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Endpoint Log Monitor - ConfigMgr & Intune client log analysis'

    # Fit the window to the screen it opens on: never larger than the working
    # area (the part not covered by the taskbar) and never smaller than the
    # layout needs, so nothing is cut off and nothing overflows.
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $formW = [Math]::Min(1340, $wa.Width)
    $formH = [Math]::Min(860,  $wa.Height)
    $form.Size = New-Object System.Drawing.Size($formW, $formH)
    $form.MinimumSize = New-Object System.Drawing.Size(
        [Math]::Min(1320, $formW), [Math]::Min(760, $formH))
    $form.StartPosition = 'CenterScreen'
    $form.MaximizeBox = $true
    $form.BackColor = $script:Colors.Surface
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    # ------------------------------------------------------------- header ---
    $header = New-Panel -Name 'Header' -Parent $form -BackColor $script:Colors.Dark
    $header.Dock = 'Top'; $header.Height = 68

    $t1 = New-Label -Parent $header -Text 'Endpoint Log Monitor' -X 24 -Y 12 -W 460 -H 26 -Size 15 -Style Bold -Color $script:Colors.Text
    $t1.AutoSize = $true
    # Fixed width (not AutoSize) and Right-anchored so it always stops short of
    # the DEVICE box and simply ellipsises on a narrow screen.
    $t2 = New-Label -Parent $header -Text 'Reads ConfigMgr, ccmsetup, Intune and MDM logs. Groups the errors that need action. Nothing leaves your network.' `
        -X 26 -Y 40 -W 870 -H 20 -Size 9 -Color $script:Colors.Muted
    $t2.AutoEllipsis = $true

    $lblTarget = New-Label -Parent $header -Text 'DEVICE' -X 916 -Y 12 -W 200 -H 16 -Size 8 -Style Bold -Color $script:Colors.Muted
    $txtTarget = New-MonoField -Parent $header -Text $InitialTarget -X 916 -Y 30 -W 210 -H 26 -Size 10
    $txtTarget.BackColor = $script:Colors.Dark2
    $txtTarget.ForeColor = $script:Colors.Text
    $txtTarget.Text = $InitialTarget
    # .NET Framework's WinForms TextBox has no PlaceHolderText property, so use a tooltip.
    $targetTip = New-Object System.Windows.Forms.ToolTip
    $targetTip.SetToolTip($txtTarget, 'Leave blank to scan this machine, or type a computer name')
    $btnScan = New-Button -Parent $header -Text 'Scan logs' -X 1148 -Y 28 -W 140 -H 32 -Back $script:Colors.Accent

    # --------------------------------------------------------------- tabs ---
    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'
    $tabs.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $tabs.Padding = New-Object System.Drawing.Point(16, 6)
    $form.Controls.Add($tabs)
    $tabs.BringToFront()

    # =========================================================== HEALTH tab ==
    $tabHealth = New-Object System.Windows.Forms.TabPage
    $tabHealth.Text = '  Health  '
    $tabHealth.BackColor = $script:Colors.Surface
    $tabs.TabPages.Add($tabHealth)

    $toolbar = New-Panel -Name 'Toolbar' -Parent $tabHealth -BackColor $script:Colors.White
    $toolbar.Dock = 'Top'; $toolbar.Height = 54

    $chkInfo = New-Object System.Windows.Forms.CheckBox
    $chkInfo.Text = 'Include informational lines'; $chkInfo.AutoSize = $true
    $chkInfo.Location = New-Object System.Drawing.Point(16, 18)
    $chkInfo.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $toolbar.Controls.Add($chkInfo)

    $chkNoise = New-Object System.Windows.Forms.CheckBox
    $chkNoise.Text = 'Hide known noise'; $chkNoise.AutoSize = $true; $chkNoise.Checked = $true
    $chkNoise.Location = New-Object System.Drawing.Point(210, 18)
    $chkNoise.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $toolbar.Controls.Add($chkNoise)

    $outlineStyle = @{ Outline = $true; Back = $script:Colors.White; Fore = $script:Colors.Ink }
    $btnExportHtml = New-Button -Parent $toolbar -Text 'Export HTML report' -X 366 -Y 11 -W 150 -H 32 @outlineStyle
    $btnExportCsv  = New-Button -Parent $toolbar -Text 'Export CSV' -X 522 -Y 11 -W 112 -H 32 @outlineStyle
    $btnRescan     = New-Button -Parent $toolbar -Text 'Re-scan' -X 640 -Y 11 -W 96 -H 32 @outlineStyle
    $btnOpenRules  = New-Button -Parent $toolbar -Text 'Open rules file' -X 742 -Y 11 -W 134 -H 32 @outlineStyle
    $btnDemo       = New-Button -Parent $toolbar -Text 'Demo data' -X 884 -Y 11 -W 96 -H 32 @outlineStyle

    # Right-hand group is Right-anchored so it stays on screen when the window
    # narrows; the buttons on the left stay put, and the widths leave a clear
    # gap between the two at the narrowest supported size.
    $lblFilter = New-Label -Parent $toolbar -Text 'Filter:' -X 1016 -Y 19 -W 46 -H 18 -Size 9 -Style Bold
    $txtFilter = New-Object System.Windows.Forms.TextBox
    $txtFilter.Location = New-Object System.Drawing.Point(1070, 15)
    $txtFilter.Size = New-Object System.Drawing.Size(200, 26)
    $txtFilter.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $toolbar.Controls.Add($txtFilter)

    $cards = New-Panel -Name 'Cards' -Parent $tabHealth -BackColor $script:Colors.Surface
    $cards.Dock = 'Top'; $cards.Height = 92

    $cardAttention = New-StatCard -Parent $cards -Name 'CardAttention' -X 16  -W 260 -Value '0'    -LabelText 'items need attention' -ValueColor $script:Colors.Error
    $cardFixes     = New-StatCard -Parent $cards -Name 'CardFixes'     -X 292 -W 210 -Value '0'    -LabelText 'with a known fix'     -ValueColor $script:Colors.Ok
    $cardLogs      = New-StatCard -Parent $cards -Name 'CardLogs'      -X 518 -W 210 -Value '0'    -LabelText 'logs read'            -ValueColor $script:Colors.Accent
    $cardScan      = New-StatCard -Parent $cards -Name 'CardScan'      -X 744 -W 210 -Value '--'   -LabelText 'last scan'            -ValueColor $script:Colors.Ink
    $cardTarget    = New-StatCard -Parent $cards -Name 'CardTarget'    -X 970  -W 300 -Value 'LOCAL' -LabelText 'target device'        -ValueColor $script:Colors.Ink

    $split = New-Object System.Windows.Forms.SplitContainer
    # WinForms validates SplitterDistance against the min sizes whenever either
    # is assigned, so give it a realistic size first - Dock = Fill only takes
    # effect later, during layout. Panel2MinSize keeps the detail pane wide
    # enough for its text; the container clamps the splitter as it narrows.
    $split.Size = New-Object System.Drawing.Size(1308, 640)
    $split.SplitterDistance = 760
    $split.Orientation = [System.Windows.Forms.Orientation]::Vertical
    $split.BackColor = $script:Colors.Line
    $split.Panel1MinSize = 440
    $split.Panel2MinSize = 540
    $split.Dock = 'Fill'
    $tabHealth.Controls.Add($split)
    $split.BringToFront()

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false
    $grid.AutoGenerateColumns = $false
    $grid.BackgroundColor = $script:Colors.White
    $grid.BorderStyle = 'None'
    $grid.CellBorderStyle = 'SingleHorizontal'
    $grid.GridColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $grid.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $grid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
    $grid.ColumnHeadersHeight = 38
    $grid.EnableHeadersVisualStyles = $false
    $grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(219, 234, 254)
    $grid.DefaultCellStyle.SelectionForeColor = $script:Colors.Ink
    $grid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
    $grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)

    $grid.ColumnHeadersDefaultCellStyle.BackColor = $script:Colors.Dark
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $script:Colors.Text
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)

    $mk = {
        param($prop, $head, $width, $center, $fill, $weight)
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.DataPropertyName = $prop
        $c.HeaderText = $head
        $c.Width = $width
        $c.SortMode = 'NotSortable'
        if ($fill) { $c.AutoSizeMode = 'Fill'; $c.FillWeight = $weight }
        if ($center) {
            $s = New-Object System.Windows.Forms.DataGridViewCellStyle
            $s.Alignment = 'MiddleCenter'
            $c.DefaultCellStyle = $s
        }
        return $c
    }
    $colSev   = & $mk 'Severity' 'Severity' 86  $false $false 0
    $colIssue = & $mk 'Issue'    'Issue'    300 $false $true  60
    $colFix   = & $mk 'Fix'      'Fix'      54  $true  $false 0
    $colLog   = & $mk 'Log'      'Log'      170 $false $true  24
    $colCount = & $mk 'Count'    'Count'    62  $true  $false 0
    [void]$grid.Columns.AddRange($colSev, $colIssue, $colFix, $colLog, $colCount)
    $split.Panel1.Controls.Add($grid)

    $detail = New-Panel -Name 'Detail' -Parent $split.Panel2 -BackColor $script:Colors.White
    $detail.Dock = 'Fill'

    $scroll = New-Object System.Windows.Forms.Panel
    $scroll.Dock = 'Fill'
    $scroll.AutoScroll = $true
    $scroll.BackColor = $script:Colors.White
    $detail.Controls.Add($scroll)

    New-Label -Parent $scroll -Text 'WHAT TO DO' -X 24 -Y 22 -W 300 -H 18 -Size 8 -Style Bold -Color $script:Colors.GreyLbl | Out-Null
    $lblDetailTitle = New-Label -Parent $scroll -Text 'Select an issue on the left' -X 24 -Y 44 -W 496 -H 70 -Size 13 -Style Bold

    $lblDetailTitle.AutoEllipsis = $true

    $badge = New-Object System.Windows.Forms.Label
    $badge.Location = New-Object System.Drawing.Point(24, 122)
    $badge.Size = New-Object System.Drawing.Size(132, 24)
    $badge.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $badge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $badge.BackColor = $script:Colors.Pale
    $badge.ForeColor = $script:Colors.Slate
    $badge.Visible = $false
    $scroll.Controls.Add($badge)

    $badge2 = New-Object System.Windows.Forms.Label
    $badge2.Location = New-Object System.Drawing.Point(166, 122)
    $badge2.Size = New-Object System.Drawing.Size(320, 24)
    $badge2.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $badge2.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $badge2.BackColor = $script:Colors.Pale
    $badge2.ForeColor = $script:Colors.Slate
    $scroll.Controls.Add($badge2)
    $badge2.Visible = $false

    $rtbSteps = New-Object System.Windows.Forms.RichTextBox
    $rtbSteps.Location = New-Object System.Drawing.Point(24, 160)
    $rtbSteps.Size = New-Object System.Drawing.Size(496, 194)
    $rtbSteps.ReadOnly = $true
    $rtbSteps.BorderStyle = 'None'
    $rtbSteps.BackColor = $script:Colors.White
    $rtbSteps.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $rtbSteps.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $scroll.Controls.Add($rtbSteps)

    New-Label -Parent $scroll -Text 'WHAT YOUR TECH SEES TODAY' -X 24 -Y 372 -W 340 -H 18 -Size 8 -Style Bold -Color $script:Colors.GreyLbl | Out-Null
    $lblRawSub = New-Label -Parent $scroll -Text '' -X 24 -Y 392 -W 496 -H 18 -Size 9 -Style Italic -Color $script:Colors.GreyLbl

    $rtbRaw = New-Object System.Windows.Forms.RichTextBox
    $rtbRaw.Location = New-Object System.Drawing.Point(24, 416)
    $rtbRaw.Size = New-Object System.Drawing.Size(496, 168)
    $rtbRaw.ReadOnly = $true
    $rtbRaw.BorderStyle = 'FixedSingle'
    $rtbRaw.BackColor = $script:Colors.Dark
    $rtbRaw.ForeColor = $script:Colors.Text
    $rtbRaw.Font = New-Object System.Drawing.Font('Consolas', 9)
    $scroll.Controls.Add($rtbRaw)

    $btnCopy    = New-Button -Parent $scroll -Text 'Copy steps' -X 24 -Y 598 -W 124 -H 32 -Outline -Back $script:Colors.White -Fore $script:Colors.Ink
    $btnCopyCsv = New-Button -Parent $scroll -Text 'Copy as CSV row' -X 158 -Y 598 -W 156 -H 32 -Outline -Back $script:Colors.White -Fore $script:Colors.Ink

    New-Label -Parent $scroll -Text 'WHY IT MATTERS' -X 24 -Y 648 -W 300 -H 18 -Size 8 -Style Bold -Color $script:Colors.GreyLbl | Out-Null
    $txtWhy = New-Object System.Windows.Forms.TextBox
    $txtWhy.Location = New-Object System.Drawing.Point(24, 670)
    $txtWhy.Size = New-Object System.Drawing.Size(496, 92)
    $txtWhy.Multiline = $true; $txtWhy.ReadOnly = $true; $txtWhy.BorderStyle = 'None'
    $txtWhy.BackColor = $script:Colors.Pale
    $txtWhy.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $txtWhy.ForeColor = $script:Colors.Slate
    $txtWhy.Text = 'Patches, apps, security baselines and compliance all reach the device through the ConfigMgr client or the Intune Management Extension. When that agent is unhealthy, nothing arrives, and the device often still looks fine in the console. Most teams only look after a failed rollout - by then the answer is buried in more than 150 log files.'
    $scroll.Controls.Add($txtWhy)

    $status = New-Object System.Windows.Forms.StatusStrip
    $status.BackColor = $script:Colors.Dark
    $lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
    $lblStatus.Text = 'Ready.'
    $lblStatus.ForeColor = $script:Colors.Text
    $lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    [void]$status.Items.Add($lblStatus)
    $tabHealth.Controls.Add($status)

    # ====================================================== ERROR CODES tab ==
    $tabCodes = New-Object System.Windows.Forms.TabPage
    $tabCodes.Text = '  Error codes  '
    $tabCodes.BackColor = $script:Colors.White
    $tabs.TabPages.Add($tabCodes)

    $codesBody = New-Panel -Name 'CodesBody' -Parent $tabCodes -BackColor $script:Colors.White
    $codesBody.Dock = 'Fill'

    New-Label -Parent $codesBody -Text 'ERROR CODE LOOKUP' -X 40 -Y 30 -W 400 -H 20 -Size 8 -Style Bold -Color $script:Colors.GreyLbl | Out-Null
    New-Label -Parent $codesBody -Text 'What does that code mean again?' -X 40 -Y 52 -W 760 -H 34 -Size 17 -Style Bold | Out-Null
    New-Label -Parent $codesBody -Text 'Accepts hex (0x87D00324), signed decimal (-2016410844), unsigned decimal (2278556452) and MSI / Win32 exit codes (1618).' `
        -X 40 -Y 90 -W 900 -H 22 -Size 9.5 -Color $script:Colors.Slate | Out-Null

    $txtCode = New-MonoField -Parent $codesBody -Text '' -X 40 -Y 122 -W 384 -H 34 -Size 13
    $btnLookup = New-Button -Parent $codesBody -Text 'Look up' -X 436 -Y 121 -W 122 -H 36 -Back $script:Colors.Accent

    New-Label -Parent $codesBody -Text 'Try:' -X 40 -Y 176 -W 40 -H 20 -Size 9 -Style Bold -Color $script:Colors.GreyLbl | Out-Null
    $sampleButtons = @()
    $sx = 76
    foreach ($s in @('0x87D00324', '-2016345060', '0x80244022', '1618', '0x8018002b', '3010', '0x80070643')) {
        $b = New-Button -Parent $codesBody -Text $s -X $sx -Y 171 -W 120 -H 28 `
            -Outline -Back $script:Colors.Pale -Fore $script:Colors.Ink
        $sampleButtons += $b
        $sx += 128
    }

    $resultPanel = New-Panel -Name 'Result' -Parent $codesBody -BackColor $script:Colors.Pale `
        -Bounds (New-Object System.Drawing.Rectangle(40, 218, 1240, 442))
    $resultPanel.BorderStyle = 'FixedSingle'

    $lblResTitle = New-Label -Parent $resultPanel -Text 'Enter a code above to decode it.' -X 24 -Y 20 -W 1190 -H 34 -Size 15 -Style Bold
    $lblResConf  = New-Label -Parent $resultPanel -Text '' -X 24 -Y 56 -W 1190 -H 20 -Size 9 -Style Italic -Color $script:Colors.GreyLbl

    $repr = New-Panel -Name 'Repr' -Parent $resultPanel -BackColor $script:Colors.White `
        -Bounds (New-Object System.Drawing.Rectangle(24, 86, 1192, 96))
    $repr.BorderStyle = 'FixedSingle'

    $mkRepr = {
        param($parent, $x, $label)
        New-Label -Parent $parent -Text $label -X $x -Y 16 -W 270 -H 16 -Size 8 -Style Bold -Color $script:Colors.GreyLbl | Out-Null
        $v = New-Label -Parent $parent -Text '-' -X $x -Y 40 -W 270 -H 32 -Size 12 -Style Bold
        $v.Font = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
        return $v
    }
    $vHex  = & $mkRepr $repr 24   'HEX'
    $vSign = & $mkRepr $repr 304  'SIGNED DECIMAL'
    $vUns  = & $mkRepr $repr 584  'UNSIGNED DECIMAL'
    $vRaw  = & $mkRepr $repr 864  'RAW WIN32 / MSI'

    $lblPlain = New-Label -Parent $resultPanel -Text 'PLAIN ENGLISH' -X 24 -Y 198 -W 300 -H 18 -Size 8 -Style Bold -Color $script:Colors.GreyLbl
    $rtbMeaning = New-Object System.Windows.Forms.RichTextBox
    $rtbMeaning.Location = New-Object System.Drawing.Point(24, 222)
    $rtbMeaning.Size = New-Object System.Drawing.Size(574, 194)
    $rtbMeaning.ReadOnly = $true; $rtbMeaning.BorderStyle = 'FixedSingle'
    $rtbMeaning.BackColor = $script:Colors.White
    $rtbMeaning.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $rtbMeaning.ForeColor = $script:Colors.Ink
    $resultPanel.Controls.Add($rtbMeaning)

    $lblWhatToDo = New-Label -Parent $resultPanel -Text 'WHAT TO DO' -X 622 -Y 198 -W 300 -H 18 -Size 8 -Style Bold -Color $script:Colors.GreyLbl
    $rtbCodeSteps = New-Object System.Windows.Forms.RichTextBox
    $rtbCodeSteps.Location = New-Object System.Drawing.Point(622, 222)
    $rtbCodeSteps.Size = New-Object System.Drawing.Size(594, 194)
    $rtbCodeSteps.ReadOnly = $true; $rtbCodeSteps.BorderStyle = 'FixedSingle'
    $rtbCodeSteps.BackColor = $script:Colors.White
    $rtbCodeSteps.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $rtbCodeSteps.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $resultPanel.Controls.Add($rtbCodeSteps)

    # ==================================================== CLIENT ACTIONS tab ==
    $tabActions = New-Object System.Windows.Forms.TabPage
    $tabActions.Text = '  Client actions  '
    $tabActions.BackColor = $script:Colors.White
    $tabs.TabPages.Add($tabActions)

    $actBody = New-Panel -Name 'ActBody' -Parent $tabActions -BackColor $script:Colors.White
    $actBody.Dock = 'Fill'

    New-Label -Parent $actBody -Text 'FIX IT FROM THE SAME WINDOW' -X 40 -Y 30 -W 400 -H 20 -Size 8 -Style Bold -Color $script:Colors.GreyLbl | Out-Null
    New-Label -Parent $actBody -Text 'Trigger client cycles, restart services and sync the device.' -X 40 -Y 52 -W 860 -H 30 -Size 17 -Style Bold | Out-Null
    New-Label -Parent $actBody -Text 'Target comes from the DEVICE box in the header. Leave it blank for this machine, or type a computer name that allows administrative share access.' `
        -X 40 -Y 90 -W 1000 -H 22 -Size 9.5 -Color $script:Colors.Slate | Out-Null

    $actionSplit = New-Object System.Windows.Forms.SplitContainer
    $actionSplit.Location = New-Object System.Drawing.Point(40, 124)
    $actionSplit.Size = New-Object System.Drawing.Size(1240, 540)
    $actionSplit.Orientation = [System.Windows.Forms.Orientation]::Vertical
    $actionSplit.SplitterDistance = 440
    $actionSplit.Panel1MinSize = 340
    $actionSplit.Panel2MinSize = 420
    $actBody.Controls.Add($actionSplit)

    $actionList = New-Object System.Windows.Forms.ListBox
    $actionList.Dock = 'Fill'
    $actionList.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $actionList.BorderStyle = 'FixedSingle'
    $actionList.IntegralHeight = $false
    foreach ($a in $script:ScheduleActions) { [void]$actionList.Items.Add($a.Name) }
    [void]$actionList.Items.Add('--- Services ---')
    [void]$actionList.Items.Add('Restart CCM client service (CcmExec)')
    [void]$actionList.Items.Add('Restart Windows Update service (wuauserv)')
    [void]$actionList.Items.Add('--- Maintenance ---')
    [void]$actionList.Items.Add('Clear ccmcache')
    [void]$actionList.Items.Add('Trigger Intune / MDM sync')
    $actionList.SelectedIndex = 0
    $actionSplit.Panel1.Controls.Add($actionList)

    $right = New-Panel -Name 'ActRight' -Parent $actionSplit.Panel2 -BackColor $script:Colors.White
    $right.Dock = 'Fill'

    $btnRunAction = New-Button -Parent $right -Text 'Run selected action' -X 0 -Y 0 -W 194 -H 36 -Back $script:Colors.Accent
    $btnRunAll    = New-Button -Parent $right -Text 'Run all client cycles' -X 204 -Y 0 -W 194 -H 36 -Outline -Back $script:Colors.White -Fore $script:Colors.Ink

    $txtActLog = New-Object System.Windows.Forms.RichTextBox
    $txtActLog.Location = New-Object System.Drawing.Point(0, 50)
    $txtActLog.Size = New-Object System.Drawing.Size(780, 470)
    $txtActLog.Anchor = 'Top,Bottom,Left,Right'
    $txtActLog.ReadOnly = $true
    $txtActLog.BorderStyle = 'FixedSingle'
    $txtActLog.BackColor = $script:Colors.Dark
    $txtActLog.ForeColor = $script:Colors.Text
    $txtActLog.Font = New-Object System.Drawing.Font('Consolas', 9.5)
    $right.Controls.Add($txtActLog)

    # ============================================================== ABOUT tab =
    $tabAbout = New-Object System.Windows.Forms.TabPage
    $tabAbout.Text = '  About  '
    $tabAbout.BackColor = $script:Colors.White
    $tabs.TabPages.Add($tabAbout)

    $about = New-Object System.Windows.Forms.RichTextBox
    $about.Dock = 'Fill'
    $about.ReadOnly = $true
    $about.BorderStyle = 'None'
    $about.BackColor = $script:Colors.White
    $about.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $about.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $about.Padding = New-Object System.Windows.Forms.Padding(40)
    $tabAbout.Controls.Add($about)

    # Registered here, applied once layout has run - see Set-ResponsiveAnchors.
    $script:UiAnchors = @(
        @{ Ctrl = $t2;              Anchor = 'Top,Left,Right' }
        @{ Ctrl = $lblTarget;       Anchor = 'Top,Right' }
        @{ Ctrl = $txtTarget;       Anchor = 'Top,Right' }
        @{ Ctrl = $btnScan;         Anchor = 'Top,Right' }
        @{ Ctrl = $lblFilter;       Anchor = 'Top,Right' }
        @{ Ctrl = $txtFilter;       Anchor = 'Top,Right' }
        @{ Ctrl = $resultPanel;     Anchor = 'Top,Left,Right,Bottom' }
        @{ Ctrl = $lblResTitle;     Anchor = 'Top,Left,Right' }
        @{ Ctrl = $lblResConf;      Anchor = 'Top,Left,Right' }
        @{ Ctrl = $repr;            Anchor = 'Top,Left,Right' }
        @{ Ctrl = $vRaw;            Anchor = 'Top,Right' }
        @{ Ctrl = $lblWhatToDo;     Anchor = 'Top,Right' }
        @{ Ctrl = $rtbCodeSteps;    Anchor = 'Top,Left,Right,Bottom' }
        @{ Ctrl = $actionSplit;     Anchor = 'Top,Left,Right,Bottom' }
    )

    # -------------------------------------------------------------- result ---
    [pscustomobject]@{
        Form = $form; Tabs = $tabs
        TxtTarget = $txtTarget; TargetTip = $targetTip; BtnScan = $btnScan
        ChkInfo = $chkInfo; ChkNoise = $chkNoise
        BtnExportHtml = $btnExportHtml; BtnExportCsv = $btnExportCsv
        BtnRescan = $btnRescan; BtnOpenRules = $btnOpenRules; BtnDemo = $btnDemo
        TxtFilter = $txtFilter; LblFilter = $lblFilter
        CardAttention = $cardAttention; CardFixes = $cardFixes
        CardLogs = $cardLogs; CardScan = $cardScan; CardTarget = $cardTarget
        Grid = $grid; Split = $split; ResultPanel = $resultPanel
        ActionSplit = $actionSplit
        LblDetailTitle = $lblDetailTitle; Badge = $badge; Badge2 = $badge2
        RtbSteps = $rtbSteps; RtbRaw = $rtbRaw; LblRawSub = $lblRawSub
        DetailScroll = $scroll
        BtnCopy = $btnCopy; BtnCopyCsv = $btnCopyCsv
        LblStatus = $lblStatus
        TxtCode = $txtCode; BtnLookup = $btnLookup; SampleButtons = $sampleButtons
        LblResTitle = $lblResTitle; LblResConf = $lblResConf
        VHex = $vHex; VSign = $vSign; VUns = $vUns; VRaw = $vRaw
        RtbMeaning = $rtbMeaning; RtbCodeSteps = $rtbCodeSteps
        ActionList = $actionList; BtnRunAction = $btnRunAction; BtnRunAll = $btnRunAll
        TxtActLog = $txtActLog; About = $about
    }
}
