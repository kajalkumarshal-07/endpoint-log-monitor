# Export.lib.ps1 - HTML and CSV report writers
# Dot-sourced by EndpointLogMonitor.ps1

function ConvertTo-HtmlEncoded {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = "$Text"
    return ($t -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
}

function Export-IssuesToHtml {
    param($Rows, [string]$Path, [string]$Target, [int]$LogsRead, [int]$Lines)

    $errors   = @($Rows | Where-Object { $_.Severity -eq 'Error' }).Count
    $warnings = @($Rows | Where-Object { $_.Severity -eq 'Warning' }).Count
    $fixed    = @($Rows | Where-Object { $_.Fix -eq 'Yes' }).Count
    $targetText = if ([string]::IsNullOrWhiteSpace($Target)) { $env:COMPUTERNAME } else { $Target }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width,initial-scale=1">')
    [void]$sb.AppendLine('<title>Endpoint Log Monitor - report</title>')
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine('body{margin:0;font:14px/1.5 Segoe UI,Helvetica,Arial,sans-serif;color:#0f172a;background:#f8fafc}')
    [void]$sb.AppendLine('header{background:#0B1220;color:#e2e8f0;padding:26px 36px}')
    [void]$sb.AppendLine('header h1{margin:0;font-size:22px}header p{margin:6px 0 0;color:#94a3b8;font-size:13px}')
    [void]$sb.AppendLine('.wrap{max-width:1180px;margin:0 auto;padding:28px 24px 60px}')
    [void]$sb.AppendLine('.cards{display:flex;gap:14px;flex-wrap:wrap;margin-bottom:26px}')
    [void]$sb.AppendLine('.card{background:#fff;border:1px solid #dbe3ee;border-radius:10px;padding:14px 20px;min-width:170px}')
    [void]$sb.AppendLine('.card .n{font-size:26px;font-weight:700}.card .l{color:#64748b;font-size:11px;text-transform:uppercase;letter-spacing:.06em}')
    [void]$sb.AppendLine('table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #dbe3ee}')
    [void]$sb.AppendLine('th{background:#0B1220;color:#e2e8f0;text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.06em;padding:11px 14px}')
    [void]$sb.AppendLine('td{padding:11px 14px;border-top:1px solid #dbe3ee;vertical-align:top}')
    [void]$sb.AppendLine('tr:nth-child(even) td{background:#f8fafc}')
    [void]$sb.AppendLine('.sev{display:inline-block;padding:2px 9px;border-radius:999px;font-size:12px;font-weight:600}')
    [void]$sb.AppendLine('.e{background:#fee2e2;color:#b91c1c}.w{background:#fef3c7;color:#b45309}.i{background:#e2e8f0;color:#475569}')
    [void]$sb.AppendLine('.yes{color:#15803d;font-weight:600}code{background:#eef2ff;padding:1px 6px;border-radius:4px;font-size:12.5px}')
    [void]$sb.AppendLine('.steps{background:#fff;border:1px solid #dbe3ee;border-radius:10px;padding:18px 22px;margin-top:26px}')
    [void]$sb.AppendLine('.steps h3{margin:0 0 10px;font-size:16px}.steps h4{margin:18px 0 6px;font-size:14px}')
    [void]$sb.AppendLine('ol{margin:0;padding-left:20px}ol li{margin:6px 0}')
    [void]$sb.AppendLine('footer{color:#64748b;font-size:12px;margin-top:30px;border-top:1px solid #dbe3ee;padding-top:16px}')
    [void]$sb.AppendLine('</style></head><body>')

    [void]$sb.AppendLine('<header><h1>Endpoint Log Monitor</h1>')
    [void]$sb.AppendLine('<p>Ticket-ready action items &middot; ' + (ConvertTo-HtmlEncoded $targetText) +
        ' &middot; ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '</p></header>')
    [void]$sb.AppendLine('<div class="wrap">')

    [void]$sb.AppendLine('<div class="cards">')
    [void]$sb.AppendLine('<div class="card"><div class="n">' + $Rows.Count + '</div><div class="l">Items need attention</div></div>')
    [void]$sb.AppendLine('<div class="card"><div class="n">' + $errors + '</div><div class="l">Errors</div></div>')
    [void]$sb.AppendLine('<div class="card"><div class="n">' + $warnings + '</div><div class="l">Warnings</div></div>')
    [void]$sb.AppendLine('<div class="card"><div class="n">' + $fixed + '</div><div class="l">With a known fix</div></div>')
    [void]$sb.AppendLine('<div class="card"><div class="n">' + $LogsRead + '</div><div class="l">Logs read</div></div>')
    [void]$sb.AppendLine('</div>')

    [void]$sb.AppendLine('<table><thead><tr><th>Severity</th><th>Issue</th><th>Fix</th><th>Log</th>' +
        '<th>Count</th><th>First</th><th>Last</th></tr></thead><tbody>')
    foreach ($r in $Rows) {
        $cls = switch ($r.Severity) { 'Error' { 'e' } 'Warning' { 'w' } default { 'i' } }
        $yes = if ($r.Fix -eq 'Yes') { '<span class="yes">Yes</span>' } else { '-' }
        $line = '<tr><td><span class="sev ' + $cls + '">' + $r.Severity + '</span></td>' +
            '<td>' + (ConvertTo-HtmlEncoded $r.Issue) + '</td>' +
            '<td>' + $yes + '</td>' +
            '<td><code>' + (ConvertTo-HtmlEncoded $r.Log) + '</code></td>' +
            '<td>' + $r.Count + '</td><td>' + $r.FirstSeen + '</td><td>' + $r.LastSeen + '</td></tr>'
        [void]$sb.AppendLine($line)
    }
    [void]$sb.AppendLine('</tbody></table>')

    $withSteps = @($Rows | Where-Object { $_._steps -and @($_._steps).Count -gt 0 })
    if ($withSteps.Count -gt 0) {
        [void]$sb.AppendLine('<div class="steps"><h3>Troubleshooting steps</h3>')
        foreach ($r in $withSteps) {
            [void]$sb.AppendLine('<h4>' + (ConvertTo-HtmlEncoded $r.Issue) +
                ' <span style="color:#94a3b8;font-weight:400;font-size:13px">' +
                (ConvertTo-HtmlEncoded $r.Log) + '</span></h4>')
            [void]$sb.AppendLine('<ol>')
            foreach ($s in @($r._steps)) { [void]$sb.AppendLine('<li>' + (ConvertTo-HtmlEncoded "$s") + '</li>') }
            [void]$sb.AppendLine('</ol>')
        }
        [void]$sb.AppendLine('</div>')
    }

    [void]$sb.AppendLine('<footer>Generated by Endpoint Log Monitor &middot; ' + $Lines +
        ' log entries processed &middot; local only, nothing was uploaded.</footer>')
    [void]$sb.AppendLine('</div></body></html>')

    [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
}

function Export-IssuesToCsv {
    param($Rows, [string]$Path)

    $esc = {
        param($v)
        $s = "$v"
        if ($s -match '[",\r\n]') { '"' + ($s -replace '"', '""') + '"' } else { $s }
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('Severity,Issue,KnownFix,Log,Count,FirstSeen,LastSeen,ErrorCodes,Steps')
    foreach ($r in $Rows) {
        $line = @(
            (& $esc $r.Severity),
            (& $esc $r.Issue),
            (& $esc $r.Fix),
            (& $esc $r.Log),
            $r.Count,
            (& $esc $r.FirstSeen),
            (& $esc $r.LastSeen),
            (& $esc (@($r._codes) -join ' ')),
            (& $esc (@($r._steps) -join ' | '))
        ) -join ','
        [void]$sb.AppendLine($line)
    }
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
}
