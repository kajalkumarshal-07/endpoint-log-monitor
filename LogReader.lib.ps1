# LogReader.lib.ps1 - CMTrace / legacy SMS / plain-text parsing, scanning and grouping
# Dot-sourced by EndpointLogMonitor.ps1

$script:LogExtensions = @('*.log', '*.lo_')
$script:MaxCapturedEntries = 400000

function New-LogEntry {
    param($Log, $Component, $Type, $Time, $Message, $Raw)
    [pscustomobject]@{
        Log = $Log; Component = $Component; Type = [int]$Type
        Time = $Time; Message = $Message; Raw = $Raw
    }
}

function Get-SuggestedSeverity {
    param([string]$Message)
    if (-not $Message) { return 1 }
    if ($Message -match '(?i)\b(error|failed|failure|fatal|exception|denied|cannot|could not|unable)\b') { return 3 }
    if ($Message -match '(?i)\b(warning|warn|retry|timeout|timed out|not found|skipping)\b') { return 2 }
    return 1
}

function Test-EntryForCapture {
    param($Entry, [switch]$KeepInfo)
    if ($Entry.Type -ge 2) { return $true }
    if ($KeepInfo) { return $true }
    return $false
}

function ConvertFrom-CMTraceRecord {
    param($Label, [string]$Message, [string]$Attrs, [datetime]$FallbackTime)

    $map = @{}
    foreach ($m in [regex]::Matches($Attrs, '(\w+)="([^"]*)"')) {
        $map[$m.Groups[1].Value.ToLower()] = $m.Groups[2].Value
    }

    $type = 1
    if ($map.ContainsKey('type')) {
        $p = 0
        if ([int]::TryParse($map['type'], [ref]$p)) { $type = $p }
    } else {
        $type = Get-SuggestedSeverity -Message $Message
    }

    $tm = $FallbackTime
    if ($map.ContainsKey('time') -and $map.ContainsKey('date')) {
        $t = $map['time']
        if ($t -match '^(\d{1,2}):(\d{2}):(\d{2})') { $t = '{0:D2}:{1}:{2}' -f [int]$Matches[1], $Matches[2], $Matches[3] }
        $d = $map['date']
        if ($d -match '^(\d{1,2})-(\d{1,2})-(\d{4})$') { $d = '{0:D2}-{1:D2}-{2}' -f [int]$Matches[1], [int]$Matches[2], $Matches[3] }
        $p = [datetime]::MinValue
        if ([datetime]::TryParse("$d $t", [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None, [ref]$p)) { $tm = $p }
    }

    $comp = $Label
    if ($map.ContainsKey('component') -and $map['component']) { $comp = $map['component'] }

    New-LogEntry -Log $Label -Component $comp -Type $type -Time $tm -Message $Message -Raw $Message
}

function Read-CMTraceLogFile {
    <# Streams a CMTrace, legacy SMS or plain-text log and yields only entries worth keeping. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [int]$MaxEntries = 400000,
        [switch]$KeepInfo
    )

    $stream = $null; $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($stream)

        $pending = New-Object System.Text.StringBuilder
        $inMsg = $false
        $count = 0
        $fallback = [datetime]::MinValue

        while ($null -ne ($line = $reader.ReadLine())) {
            if ($inMsg) {
                $end = $line.IndexOf(']LOG]!>')
                if ($end -ge 0) {
                    [void]$pending.Append("`n").Append($line.Substring(0, $end))
                    $msg = $pending.ToString()
                    $attrs = $line.Substring($end + 7)
                    $pending.Clear() | Out-Null
                    $inMsg = $false
                    $e = ConvertFrom-CMTraceRecord -Label $Label -Message $msg -Attrs $attrs -FallbackTime $fallback
                    $count++
                    if (Test-EntryForCapture -Entry $e -KeepInfo:$KeepInfo) { $e }
                    if ($count -ge $MaxEntries) { break }
                } else {
                    [void]$pending.Append("`n").Append($line)
                }
                continue
            }

            if ($line.StartsWith('<![LOG[')) {
                $rest = $line.Substring(7)
                $end = $rest.IndexOf(']LOG]!>')
                if ($end -ge 0) {
                    $msg = $rest.Substring(0, $end)
                    $attrs = $rest.Substring($end + 7)
                    $e = ConvertFrom-CMTraceRecord -Label $Label -Message $msg -Attrs $attrs -FallbackTime $fallback
                    $count++
                    if (Test-EntryForCapture -Entry $e -KeepInfo:$KeepInfo) { $e }
                    if ($count -ge $MaxEntries) { break }
                } else {
                    [void]$pending.Append($rest); $inMsg = $true
                }
                continue
            }

            # legacy SMS:  "message text  $$<Component><MM-DD-YYYY hh:mm:ss.fff-60><thread=...>"
            if ($line -match '\s\$\$<') {
                if ($line -match '^(?<msg>.*?)\s*\$\$<(?<c>[^>]*)><(?<d>[^>]*)><thread=') {
                    $tm = [datetime]::MinValue
                    $stamp = $Matches['d'].Trim()
                    $stamp = $stamp -replace '\s*Coordinated Universal Time$', ''
                    $stamp = $stamp -replace '[+-]\d+$', ''
                    $null = [datetime]::TryParse($stamp,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::None, [ref]$tm)
                    $e = New-LogEntry -Log $Label -Component $Matches['c'] -Type 0 -Time $tm `
                        -Message $Matches['msg'] -Raw $line
                    $e.Type = Get-SuggestedSeverity -Message $e.Message
                    $count++
                    if (Test-EntryForCapture -Entry $e -KeepInfo:$KeepInfo) { $e }
                    if ($count -ge $MaxEntries) { break }
                }
                continue
            }

            if ($line.Trim().Length -eq 0) { continue }
            $e = New-LogEntry -Log $Label -Component $Label -Type 0 -Time $fallback -Message $line -Raw $line
            $e.Type = Get-SuggestedSeverity -Message $line
            $count++
            if (Test-EntryForCapture -Entry $e -KeepInfo:$KeepInfo) { $e }
            if ($count -ge $MaxEntries) { break }
        }
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

function Get-LogRoots {
    param([string]$Computer)
    if ([string]::IsNullOrWhiteSpace($Computer)) {
        return @(
            @{ Label = 'ConfigMgr'; Path = (Join-Path $env:windir 'CCM\Logs') }
            @{ Label = 'Setup';     Path = (Join-Path $env:windir 'ccmsetup\Logs') }
            @{ Label = 'Intune';    Path = (Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs') }
        )
    }
    $c = $Computer.Trim()
    return @(
        @{ Label = 'ConfigMgr'; Path = "\\$c\admin$\Windows\CCM\Logs" }
        @{ Label = 'Setup';     Path = "\\$c\admin$\Windows\ccmsetup\Logs" }
        @{ Label = 'Intune';    Path = "\\$c\C$\ProgramData\Microsoft\IntuneManagementExtension\Logs" }
    )
}

function Get-LogFiles {
    param([string[]]$Roots)
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($root in $Roots) {
        if (-not $root) { continue }
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($ext in $script:LogExtensions) {
            try {
                Get-ChildItem -LiteralPath $root -Filter $ext -File -ErrorAction SilentlyContinue |
                    ForEach-Object { $files.Add($_) }
            } catch { }
        }
    }
    return $files
}

function Get-MdmEventEntries {
    param([string]$Computer, [int]$MaxEvents = 1500)
    $list = New-Object System.Collections.Generic.List[object]
    $logName = 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin'
    try {
        $p = @{ LogName = $logName; MaxEvents = $MaxEvents; ErrorAction = 'Stop' }
        if ($Computer) { $p['ComputerName'] = $Computer }
        Get-WinEvent @p | ForEach-Object {
            $t = switch ($_.LevelDisplayName) { 'Critical' { 3 } 'Error' { 3 } 'Warning' { 2 } default { 1 } }
            $msg = $_.Message; if (-not $msg) { $msg = $_.ToString() }
            $list.Add((New-LogEntry -Log 'MDM-Diagnostics.evtx' -Component $_.ProviderName `
                -Type $t -Time $_.TimeCreated -Message $msg -Raw $msg))
        }
    } catch { }
    return $list
}

function Get-GroupKey {
    param([string]$Message, [string]$Log, [string[]]$Codes, $Index)
    $k = ConvertTo-NormalisedShape -Message $Message

    $known = New-Object System.Collections.Generic.List[string]
    foreach ($c in $Codes) {
        if ($Index.Codes.ContainsKey($c) -or $Index.Msi.ContainsKey($c)) { $known.Add($c) }
    }
    $suffix = ''
    if ($known.Count -gt 0) { $suffix = '|' + ((@($known | Sort-Object)) -join ',') }
    "$Log|$k$suffix"
}

function Add-EntryToGroups {
    param($Groups, $Entry, [string[]]$Codes, [string]$Key)

    if (-not $Groups.ContainsKey($Key)) {
        $Groups[$Key] = [pscustomobject]@{
            Key = $Key; Log = $Entry.Log; Type = $Entry.Type; Message = $Entry.Message
            First = $Entry.Time; Last = $Entry.Time; Count = 0
            Codes = New-Object System.Collections.Generic.List[string]
            Samples = New-Object System.Collections.Generic.List[string]
        }
    }
    $g = $Groups[$Key]
    $g.Count++
    if ($Entry.Time -ne [datetime]::MinValue) {
        if ($g.Count -eq 1) { $g.First = $Entry.Time; $g.Last = $Entry.Time }
        else {
            if ($Entry.Time -lt $g.First) { $g.First = $Entry.Time }
            if ($Entry.Time -gt $g.Last)  { $g.Last  = $Entry.Time }
        }
    }
    if ($Entry.Type -gt $g.Type) { $g.Type = $Entry.Type }
    foreach ($c in $Codes) { if (-not $g.Codes.Contains($c)) { $g.Codes.Add($c) } }
    if ($g.Samples.Count -lt 4) {
        $stamp = if ($Entry.Time -ne [datetime]::MinValue) { $Entry.Time.ToString('HH:mm:ss') } else { '' }
        $g.Samples.Add((($stamp + '  ' + ("$($Entry.Raw)" -replace '\r?\n', ' '))).TrimEnd())
    }
}

function Invoke-LogScan {
    [CmdletBinding()]
    param(
        [string]$Computer,
        $Index,
        [switch]$KeepInfo,
        [scriptblock]$Progress,
        # Explicit folder(s) to scan instead of the real ConfigMgr/Intune roots
        # (used by the Demo data button).
        [string[]]$LogRoots,
        # Skip the MDM event log - set when scanning generated sample logs.
        [switch]$SkipMdm
    )

    $groups = @{}
    $logsRead = 0
    $linesRead = 0
    $hidden = 0

    if ($LogRoots -and @($LogRoots).Count -gt 0) {
        $roots = @(@{ Label = 'Demo'; Path = "$(@($LogRoots)[0])" })
    } else {
        $roots = Get-LogRoots -Computer $Computer
    }
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r.Path)) {
            if ($Progress) { & $Progress "not found: $($r.Path)" }
        }
    }
    $files = Get-LogFiles -Roots @($roots | ForEach-Object { $_.Path })

    foreach ($f in $files) {
        if ($Progress) { & $Progress "reading $($f.FullName)" }
        $logsRead++
        foreach ($e in (Read-CMTraceLogFile -Path $f.FullName -Label $f.Name -KeepInfo:$KeepInfo)) {
            $linesRead++
            if (Test-IsHiddenMessage -Message $e.Message -Index $Index) { $hidden++; continue }
            if (Test-IsNoiseMessage -Message $e.Message -Index $Index) { continue }
            $codes = Get-CodesFromMessage -Message $e.Message
            $key = Get-GroupKey -Message $e.Message -Log $f.Name -Codes $codes -Index $Index
            Add-EntryToGroups -Groups $groups -Entry $e -Codes $codes -Key $key
            if ($groups.Count -gt 20000 -or $linesRead -gt $script:MaxCapturedEntries) { break }
        }
        if ($linesRead -gt $script:MaxCapturedEntries) { break }
    }

    if (-not $SkipMdm) {
        if ($Progress) { & $Progress 'reading MDM diagnostics event log' }
        $logsRead++
        foreach ($e in (Get-MdmEventEntries -Computer $Computer)) {
            if (-not (Test-EntryForCapture -Entry $e -KeepInfo:$KeepInfo)) { continue }
            $linesRead++
            if (Test-IsHiddenMessage -Message $e.Message -Index $Index) { $hidden++; continue }
            if (Test-IsNoiseMessage -Message $e.Message -Index $Index) { continue }
            $codes = Get-CodesFromMessage -Message $e.Message
            $key = Get-GroupKey -Message $e.Message -Log $e.Log -Codes $codes -Index $Index
            Add-EntryToGroups -Groups $groups -Entry $e -Codes $codes -Key $key
        }
    }

    [pscustomobject]@{
        Groups   = @($groups.Values)
        LogsRead = $logsRead
        Lines    = $linesRead
        Hidden   = $hidden
        Files    = @($files | ForEach-Object { $_.FullName })
    }
}

function New-IssueRows {
    param($Groups, $Index)
    $rows = New-Object System.Collections.ArrayList

    foreach ($g in $Groups) {
        $fix = Resolve-FixForCodes -Codes @($g.Codes) -Index $Index
        if (-not $fix) { $fix = Resolve-FixForMessage -Message $g.Message -Index $Index }

        $hexCodes = @($g.Codes | Where-Object { $_ -like '0x*' })
        $codeText = if ($hexCodes.Count -gt 0) { ' (' + $hexCodes[0] + ')' } else { '' }

        $title = if ($fix -and $fix.title) {
            "$($fix.title)$codeText"
        } else {
            $m = "$($g.Message)".Trim() -replace '\s+', ' '
            if ($m.Length -gt 140) { $m.Substring(0, 137) + '...' } else { $m }
        }

        $hasFix = if ($fix -and @($fix.steps).Count -gt 0) { 'Yes' } else { '' }
        $severity = switch ($g.Type) { 3 { 'Error' } 2 { 'Warning' } default { 'Info' } }

        [void]$rows.Add([pscustomobject]@{
            Severity  = $severity
            Issue     = $title
            Fix       = $hasFix
            Log       = $g.Log
            Count     = $g.Count
            FirstSeen = $(if ($g.First -ne [datetime]::MinValue) { $g.First.ToString('HH:mm:ss') } else { '' })
            LastSeen  = $(if ($g.Last -ne [datetime]::MinValue)  { $g.Last.ToString('HH:mm:ss') }  else { '' })
            _fix      = $fix
            _steps    = $(if ($fix) { @($fix.steps) } else { @() })
            _samples  = @($g.Samples)
            _codes    = @($g.Codes)
            _message  = $g.Message
            _key      = $g.Key
            _log      = $g.Log
        })
    }

    $order = @{ Error = 0; Warning = 1; Info = 2 }
    $sorted = $rows | Sort-Object -Property `
        @{ Expression = { $order[$_.Severity] } },
        @{ Expression = { -1 * [int]$_.Count } },
        @{ Expression = { $_.Issue } }

    $result = New-Object System.Collections.ArrayList
    foreach ($s in $sorted) { [void]$result.Add($s) }
    return , $result
}
