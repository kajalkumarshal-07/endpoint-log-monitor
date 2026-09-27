# Rules.lib.ps1 - shared rules file handling + error-code decoding
# Dot-sourced by EndpointLogMonitor.ps1

# 0x80070000 and 0x8007FFFF are typed as negative Int32 by the PowerShell
# parser, so they must be compared as explicit unsigned values.
$script:Win32HResultBase = [uint32]2147942400   # 0x80070000
$script:Win32HResultMax  = [uint32]2147991551   # 0x8007FFFF

function Get-DefaultRulesObject {
    [pscustomobject]@{ version = 1; fixes = @(); noise = @(); hidden = @() }
}

function Save-Rules {
    param([Parameter(Mandatory)]$Rules, [Parameter(Mandatory)][string]$Path)
    $json = $Rules | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Import-Rules {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        $starter = Get-DefaultRulesObject
        try { Save-Rules -Rules $starter -Path $Path } catch { }
        return $starter
    }
    try {
        $rules = ([System.IO.File]::ReadAllText($Path)) | ConvertFrom-Json
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Rules.json could not be parsed:`n`n$($_.Exception.Message)",
            'Endpoint Log Monitor', 'OK', 'Error') | Out-Null
        return (Get-DefaultRulesObject)
    }
    if (-not $rules.fixes)  { $rules | Add-Member NoteProperty fixes  @() -Force }
    if (-not $rules.noise)  { $rules | Add-Member NoteProperty noise  @() -Force }
    if (-not $rules.hidden) { $rules | Add-Member NoteProperty hidden @() -Force }
    return $rules
}

function ConvertTo-NormalisedShape {
    <# Collapses the volatile parts of a message (GUIDs, timestamps, hex codes,
       long numbers) into stable tokens so the same real-world problem always
       produces the same shape. Braces and parentheses around a GUID are kept,
       so {GUID} and (GUID) still normalise to the same surrounding text. #>
    param([string]$Message)

    $s = $Message
    $s = [regex]::Replace($s, '(?<![\w-])[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?![\w-])', '<G>')
    $s = [regex]::Replace($s, '(?<![\d:.])\d{1,2}:\d{2}:\d{2}(\.\d+)?(?![\d:])', '<T>')
    $s = [regex]::Replace($s, '0[xX][0-9A-Fa-f]{4,8}', '<H>')
    $s = [regex]::Replace($s, '\b\d{4,}\b', '<N>')
    $s = [regex]::Replace($s, '\s+', ' ').Trim()
    $s
}

function ConvertTo-HiddenPattern {
    <# Builds a regex matching the normalised shape of a message, so it still
       matches after GUIDs / timestamps / error codes change. #>
    param([string]$Message)

    $shape = ConvertTo-NormalisedShape -Message $Message

    # Escaping is done first, then the tokens are swapped for regex pieces; the
    # braces around a GUID survive from the original text, not from the token.
    $rx = [regex]::Escape($shape)
    $rx = $rx.Replace('<G>', '[0-9a-fA-F\-]+')
    $rx = $rx.Replace('<H>', '0[xX][0-9A-Fa-f]{4,8}')
    $rx = $rx.Replace('<T>', '\d{1,2}:\d{2}:\d{2}(\.\d+)?')
    $rx = $rx.Replace('<N>', '\d+')
    $rx
}

function ConvertTo-CanonicalHex {
    <# 0x87D00324 / -2016410844 / 2278556452 / 1618  ->  '0x........' #>
    param([string]$Code)
    $Code = "$Code".Trim()
    if (-not $Code) { return $null }

    if ($Code -match '^0[xX]([0-9A-Fa-f]{1,8})$') {
        return ('0x{0:X8}' -f [uint32]('0x' + $Matches[1]))
    }
    if ($Code -match '^-?\d{1,11}$') {
        $v = 0L
        try { $v = [int64]$Code } catch { return $null }
        if ($v -lt 0) {
            if ($v -lt -2147483648) { return $null }
            return ('0x{0:X8}' -f [uint64]($v + 4294967296))
        }
        if ($v -gt 4294967295) { return $null }
        return ('0x{0:X8}' -f [uint64]$v)
    }
    return $null
}

function Build-RuleIndex {
    param($Rules)

    $codeIndex = @{}
    $msiIndex  = @{}

    $addFix = {
        param([string]$code, $fix)
        if (-not $code) { return }
        $canon = ConvertTo-CanonicalHex -Code $code
        if ($canon -and -not $codeIndex.ContainsKey($canon)) { $codeIndex[$canon] = $fix }
        if ("$code" -match '^\d{1,5}$') {
            $k = "MSI:$code"
            if (-not $msiIndex.ContainsKey($k)) { $msiIndex[$k] = $fix }
        }
    }

    foreach ($fix in @($Rules.fixes)) {
        foreach ($c in @($fix.codes))     { & $addFix "$c" $fix }
        foreach ($a in @($fix.aliasCodes)) { & $addFix "$a" $fix }
    }

    [pscustomobject]@{
        Codes  = $codeIndex
        Msi    = $msiIndex
        Fixes  = @($Rules.fixes)
        Noise  = @($Rules.noise)
        Hidden = @($Rules.hidden)
    }
}

function ConvertTo-Int32Bits {
    <# Reinterprets a 32-bit unsigned pattern as a signed value. #>
    param([uint32]$Unsigned)
    if ($Unsigned -gt [int]::MaxValue) { return [int]($Unsigned - 4294967296L) }
    return [int]$Unsigned
}

function ConvertFrom-UserErrorCode {
    <# Turns whatever the user typed into every representation plus its meaning. #>
    param([string]$InputText, $Index)
    $t = "$InputText".Trim()
    if (-not $t) { return $null }

    $hex = $null; $signed = $null; $unsigned = $null
    $notes = New-Object System.Collections.Generic.List[string]

    if ($t -match '^0[xX]([0-9A-Fa-f]{1,8})$') {
        $unsigned = [uint32]('0x' + $Matches[1])
        $signed   = ConvertTo-Int32Bits -Unsigned $unsigned
        $hex      = '0x{0:X8}' -f $unsigned
    }
    elseif ($t -match '^-?\d+$') {
        $v = [int64]$t
        if ($v -lt 0) {
            if ($v -lt -2147483648) { return $null }
            $signed   = [int32]$v
            $unsigned = [uint32]($v + 4294967296)
            $hex      = '0x{0:X8}' -f $unsigned
        }
        elseif ($v -gt 4294967295) { return $null }
        elseif ($v -gt 2147483647) {
            $unsigned = [uint32]$v
            $signed   = ConvertTo-Int32Bits -Unsigned $unsigned
            $hex      = '0x{0:X8}' -f $unsigned
            $notes.Add('Read as an unsigned 32-bit value - bit 31 is set, so the signed form is negative.')
        }
        else {
            $unsigned = [uint32]$v
            $signed   = [int32]$v
            $hex      = '0x{0:X8}' -f $unsigned
            if ($v -le 65535) {
                $notes.Add('Small positive integer - read as a raw Windows Installer / Win32 exit code.')
            }
        }
    }
    else { return $null }

    $win32 = $null; $msi = $null
    if ($unsigned -ge $script:Win32HResultBase -and $unsigned -le $script:Win32HResultMax) {
        $win32 = [int]($unsigned - $script:Win32HResultBase)
        $notes.Add("0x8007xxxx is HRESULT_FROM_WIN32 - subtract 0x80070000 to get the raw number ($win32).")
        if ($win32 -le 65535) { $msi = $win32 }
    }
    elseif ($unsigned -le 65535) { $msi = [int]$unsigned }

    $hit = $null
    if ($Index.Codes.ContainsKey($hex)) { $hit = $Index.Codes[$hex] }
    elseif ($msi -ne $null -and $Index.Msi.ContainsKey("MSI:$msi")) { $hit = $Index.Msi["MSI:$msi"] }
    elseif ($msi -ne $null) {
        $wrapped = ConvertTo-CanonicalHex -Code ([string]([int64]$script:Win32HResultBase + $msi))
        if ($wrapped -and $Index.Codes.ContainsKey($wrapped)) { $hit = $Index.Codes[$wrapped] }
    }

    [pscustomobject]@{
        Input      = $t
        Hex        = $hex
        Signed     = $signed
        Unsigned   = $unsigned
        Win32      = $win32
        Msi        = $msi
        Meaning    = $(if ($hit) { "$($hit.title)" } else { $null })
        Confidence = $(if ($hit) { "$($hit.confidence)" } else { $null })
        Fix        = $hit
        Notes      = @($notes)
    }
}

function Get-CodesFromMessage {
    <# Every plausible error code found in a log message. #>
    param([string]$Message)
    $out = New-Object System.Collections.Generic.List[string]
    if (-not $Message) { return $out }

    foreach ($m in [regex]::Matches($Message, '0[xX][0-9A-Fa-f]{4,8}')) {
        $c = ConvertTo-CanonicalHex -Code $m.Value
        if ($c -and -not $out.Contains($c)) { $out.Add($c) }
    }
    foreach ($m in [regex]::Matches($Message, '(?<![\w.])-?\d{6,10}(?![\w.])')) {
        $c = ConvertTo-CanonicalHex -Code $m.Value
        if ($c -and -not $out.Contains($c)) { $out.Add($c) }
    }
    $rxExit = '(?i)(exit\s*code|exitcode|return(?:ed)?\s*code|error\s*code|result(?:ed)?\s*code)\D{0,8}(\d{1,5})\b'
    foreach ($m in [regex]::Matches($Message, $rxExit)) {
        $n = [int]$m.Groups[2].Value
        $k = "MSI:$n"
        if (-not $out.Contains($k)) { $out.Add($k) }
        $wrapped = ConvertTo-CanonicalHex -Code ([string]([int64]$script:Win32HResultBase + $n))
        if ($wrapped -and -not $out.Contains($wrapped)) { $out.Add($wrapped) }
    }
    return $out
}

function Resolve-FixForCodes {
    param([string[]]$Codes, $Index)
    foreach ($c in $Codes) {
        if ($Index.Codes.ContainsKey($c)) { return $Index.Codes[$c] }
        if ($Index.Msi.ContainsKey($c))   { return $Index.Msi[$c] }
    }
    return $null
}

function Resolve-FixForMessage {
    param([string]$Message, $Index)
    foreach ($fx in $Index.Fixes) {
        if (-not $fx.match) { continue }
        try {
            if ([regex]::IsMatch($Message, "$($fx.match)")) { return $fx }
        } catch { }
    }
    return $null
}

function Test-IsHiddenMessage {
    param([string]$Message, $Index)
    foreach ($p in @($Index.Hidden)) {
        if (-not $p) { continue }
        try { if ([regex]::IsMatch($Message, "$p")) { return $true } } catch { }
    }
    return $false
}

function Test-IsNoiseMessage {
    param([string]$Message, $Index)
    foreach ($p in @($Index.Noise)) {
        if (-not $p) { continue }
        try { if ([regex]::IsMatch($Message, "$p")) { return $true } } catch { }
    }
    return $false
}
