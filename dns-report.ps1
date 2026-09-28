#Requires -Version 7.0
<#
.SYNOPSIS
    Consulta DNS (A, MX, NS, PTR) para un dominio o una IP y genera un reporte HTML.
    Al finalizar abre el reporte en el navegador por defecto.

.PARAMETER Target
    Dominio (ej: lacapital.com.ar) o dirección IP (ej: 8.8.8.8).

.PARAMETER OutputPath
    Ruta del archivo HTML de salida. Por defecto se genera en el directorio actual
    con timestamp. Si la ruta falla, el script reintenta en %TEMP% y C:\Temp.

.PARAMETER NoOpen
    Si se especifica, NO abre el reporte HTML en el navegador al finalizar.

.EXAMPLE
    .\dns-report.ps1 -Target lacapital.com.ar

.EXAMPLE
    .\dns-report.ps1 -Target 8.8.8.8 -OutputPath C:\Temp\reporte.html

.EXAMPLE
    .\dns-report.ps1 -Target lacapital.com.ar -NoOpen
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Dominio o dirección IP a consultar")]
    [string]$Target,

    [Parameter(Position = 1)]
    [string]$OutputPath,

    [switch]$NoOpen
)

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------
function ConvertTo-HtmlTable {
    param(
        [string[]]$Headers,
        [System.Collections.IEnumerable]$Rows,
        [string]$EmptyMessage = "Sin resultados"
    )
    $rowsArr = @($Rows)
    if ($rowsArr.Count -eq 0) {
        return "<p class='empty'>$([System.Net.WebUtility]::HtmlEncode($EmptyMessage))</p>"
    }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("<table><thead><tr>")
    foreach ($h in $Headers) {
        [void]$sb.Append("<th>$([System.Net.WebUtility]::HtmlEncode($h))</th>")
    }
    [void]$sb.Append("</tr></thead><tbody>")
    foreach ($row in $rowsArr) {
        [void]$sb.Append("<tr>")
        foreach ($cell in $row) {
            [void]$sb.Append("<td>$([System.Net.WebUtility]::HtmlEncode([string]$cell))</td>")
        }
        [void]$sb.Append("</tr>")
    }
    [void]$sb.Append("</tbody></table>")
    return $sb.ToString()
}

function Save-HtmlReport {
    param(
        [Parameter(Mandatory)] [string]$Content,
        [Parameter(Mandatory)] [string]$PreferredPath
    )

    $utf8NoBom  = New-Object System.Text.UTF8Encoding($false)
    $attempts   = New-Object System.Collections.Generic.List[object]
    $candidates = New-Object System.Collections.Generic.List[string]

    # 1) Ruta pedida, tal cual
    $candidates.Add($PreferredPath)

    # 2) Ruta pedida con prefijo \\?\ (bypass de canonicalización Win32)
    if ($PreferredPath -match '^[A-Za-z]:\\') {
        $candidates.Add("\\?\$PreferredPath")
    }

    # 3) Fallback en %TEMP%
    $leaf = Split-Path -Leaf $PreferredPath
    if (-not $leaf) { $leaf = "DNS-Report.html" }
    $candidates.Add((Join-Path $env:TEMP $leaf))

    # 4) Fallback en C:\Temp
    $candidates.Add((Join-Path "C:\Temp" $leaf))

    foreach ($path in $candidates) {
        $parent = Split-Path -Parent $path

        if ($parent -and $path -notlike '\\?\*') {
            if (-not (Test-Path -LiteralPath $parent)) {
                try {
                    New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
                } catch {
                    $attempts.Add([pscustomobject]@{
                        Path  = $path
                        OK    = $false
                        Error = "No se pudo crear el directorio: $($_.Exception.Message)"
                    })
                    continue
                }
            }
        }

        try {
            [System.IO.File]::WriteAllText($path, $Content, $utf8NoBom)
            $attempts.Add([pscustomobject]@{ Path = $path; OK = $true; Error = $null })
            return [pscustomobject]@{ Success = $true; FinalPath = $path; Attempts = $attempts }
        } catch {
            $err = $_.Exception.Message
            try {
                if (-not (Test-Path -LiteralPath $path)) {
                    New-Item -ItemType File -Path $path -Force -ErrorAction Stop | Out-Null
                }
                Set-Content -LiteralPath $path -Value $Content -Encoding UTF8 -ErrorAction Stop
                $attempts.Add([pscustomobject]@{ Path = $path; OK = $true; Error = $null })
                return [pscustomobject]@{ Success = $true; FinalPath = $path; Attempts = $attempts }
            } catch {
                $err = "$err | Fallback New-Item+Set-Content: $($_.Exception.Message)"
                $attempts.Add([pscustomobject]@{ Path = $path; OK = $false; Error = $err })
            }
        }
    }

    return [pscustomobject]@{ Success = $false; FinalPath = $null; Attempts = $attempts }
}

# ---------------------------------------------------------------
# Ruta de salida por defecto
# ---------------------------------------------------------------
if (-not $OutputPath) {
    $OutputPath = Join-Path -Path (Get-Location).Path `
        -ChildPath ("DNS-Report-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

# ---------------------------------------------------------------
# Datos del reporte
# ---------------------------------------------------------------
$Report = [ordered]@{
    Target     = $Target
    StartedAt  = Get-Date
    IsIP       = $false
    ARecords   = @()
    MXRecords  = @()
    NSRecords  = @()
    PTRRecords = @()
    Warnings   = New-Object System.Collections.Generic.List[string]
    Errors     = New-Object System.Collections.Generic.List[string]
}

$parsedIp = $null
$Report.IsIP = [System.Net.IPAddress]::TryParse($Target, [ref]$parsedIp)

Write-Host "=== Consultas DNS para: $Target ===" -ForegroundColor Cyan
Write-Host "Modo: $(if ($Report.IsIP) { 'IP (solo PTR)' } else { 'Dominio (A, MX, NS, PTR)' })"

$IpForReverse = $null

# ---------------------------------------------------------------
# 1. Registros A (solo si es dominio)
# ---------------------------------------------------------------
if (-not $Report.IsIP) {
    Write-Host "`n[1] Registros A para: $Target"
    try {
        $aResults = Resolve-DnsName -Name $Target -Type A -ErrorAction Stop |
                    Where-Object { $_.Type -eq 'A' }

        if ($aResults) {
            foreach ($r in $aResults) {
                Write-Host ("  A     {0}  ->  {1}  (TTL {2})" -f $r.Name, $r.IPAddress, $r.TTL)
                $Report.ARecords += ,@($r.Name, $r.IPAddress, $r.TTL)
            }
            $IpForReverse = ($aResults | Select-Object -First 1).IPAddress
        } else {
            $Report.Warnings.Add("No se encontraron registros A para $Target.")
            Write-Host "  (sin registros A)" -ForegroundColor Yellow
        }
    } catch {
        $msg = "Error resolviendo A para ${Target}: $($_.Exception.Message)"
        $Report.Errors.Add($msg)
        Write-Host "  $msg" -ForegroundColor Red
    }
} else {
    $IpForReverse = $Target
}

# ---------------------------------------------------------------
# 2. Registros MX (solo si es dominio)
# ---------------------------------------------------------------
if (-not $Report.IsIP) {
    Write-Host "`n[2] Registros MX para: $Target"
    try {
        $mxResults = Resolve-DnsName -Name $Target -Type MX -ErrorAction Stop |
                     Where-Object { $_.Type -eq 'MX' }

        if ($mxResults) {
            foreach ($r in $mxResults) {
                Write-Host ("  MX    {0}  ->  {1}  (Pref {2})" -f $r.Name, $r.NameExchange, $r.Preference)
                $Report.MXRecords += ,@($r.NameExchange, $r.Preference, $r.TTL)
            }
        } else {
            $Report.Warnings.Add("No se encontraron registros MX para $Target.")
            Write-Host "  (sin registros MX)" -ForegroundColor Yellow
        }
    } catch {
        $msg = "Error resolviendo MX para ${Target}: $($_.Exception.Message)"
        $Report.Errors.Add($msg)
        Write-Host "  $msg" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------
# 3. Registros NS (solo si es dominio)
# ---------------------------------------------------------------
if (-not $Report.IsIP) {
    Write-Host "`n[3] Registros NS para: $Target"
    try {
        $nsResults = Resolve-DnsName -Name $Target -Type NS -ErrorAction Stop |
                     Where-Object { $_.Type -eq 'NS' }

        if ($nsResults) {
            foreach ($r in $nsResults) {
                Write-Host ("  NS    {0}  ->  {1}" -f $r.Name, $r.NameHost)
                $Report.NSRecords += ,@($r.NameHost, $r.TTL)
            }
        } else {
            $Report.Warnings.Add("No se encontraron registros NS para $Target.")
            Write-Host "  (sin registros NS)" -ForegroundColor Yellow
        }
    } catch {
        $msg = "Error resolviendo NS para ${Target}: $($_.Exception.Message)"
        $Report.Errors.Add($msg)
        Write-Host "  $msg" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------
# 4. Registros PTR (búsqueda inversa)
# ---------------------------------------------------------------
if ($IpForReverse) {
    Write-Host "`n[4] Registros PTR para: $IpForReverse"
    try {
        $ptrResults = Resolve-DnsName -Name $IpForReverse -Type PTR -ErrorAction Stop |
                      Where-Object { $_.Type -eq 'PTR' }

        if ($ptrResults) {
            foreach ($r in $ptrResults) {
                Write-Host ("  PTR   {0}  ->  {1}" -f $r.Name, $r.NameHost) -ForegroundColor Green
                $Report.PTRRecords += ,@($r.Name, $r.NameHost, $r.TTL)
            }
        } else {
            $Report.Warnings.Add("Sin registros PTR para $IpForReverse.")
            Write-Host "  (sin registros PTR)" -ForegroundColor Yellow
        }
    } catch {
        $msg = "Sin PTR para $IpForReverse. No implica necesariamente Cloudflare; " +
               "muchas IPs (incluido el rango 104.18.0.0/15 de Cloudflare) no publican PTR individual."
        $Report.Warnings.Add($msg)
        Write-Host "  $msg" -ForegroundColor Magenta
    }
} else {
    $Report.Warnings.Add("No hay IP para consultar PTR.")
}

$Report.FinishedAt = Get-Date
$duration = [math]::Round(($Report.FinishedAt - $Report.StartedAt).TotalSeconds, 2)

# ---------------------------------------------------------------
# Generación del HTML
# ---------------------------------------------------------------
$tableA   = ConvertTo-HtmlTable -Headers @('Nombre','Dirección IP','TTL') -Rows $Report.ARecords   -EmptyMessage "No se encontraron registros A"
$tableMX  = ConvertTo-HtmlTable -Headers @('Servidor','Prioridad','TTL')  -Rows $Report.MXRecords  -EmptyMessage "No se encontraron registros MX"
$tableNS  = ConvertTo-HtmlTable -Headers @('Name Server','TTL')           -Rows $Report.NSRecords  -EmptyMessage "No se encontraron registros NS"
$tablePTR = ConvertTo-HtmlTable -Headers @('IP','Host','TTL')             -Rows $Report.PTRRecords -EmptyMessage "No se encontraron registros PTR"

$warningsHtml = if ($Report.Warnings.Count -gt 0) {
    "<ul>" + (($Report.Warnings | ForEach-Object { "<li>$([System.Net.WebUtility]::HtmlEncode($_))</li>" }) -join '') + "</ul>"
} else { "<p class='empty'>Sin advertencias</p>" }

$errorsHtml = if ($Report.Errors.Count -gt 0) {
    "<ul>" + (($Report.Errors | ForEach-Object { "<li>$([System.Net.WebUtility]::HtmlEncode($_))</li>" }) -join '') + "</ul>"
} else { "<p class='empty'>Sin errores</p>" }

$html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Reporte DNS - $([System.Net.WebUtility]::HtmlEncode($Report.Target))</title>
<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; background:#f4f6f8; color:#222; margin:0; padding:30px; }
  h1 { color:#1f3a5f; margin-bottom:0; }
  h2 { color:#1f3a5f; border-bottom:2px solid #d1d9e0; padding-bottom:6px; margin-top:36px; }
  .meta { color:#555; font-size:0.9em; margin-top:4px; }
  .card { background:#fff; border-radius:8px; padding:20px 24px; margin:20px 0;
          box-shadow:0 1px 3px rgba(0,0,0,0.08); }
  table { width:100%; border-collapse:collapse; margin-top:10px; font-size:0.95em; }
  th, td { padding:8px 12px; text-align:left; border-bottom:1px solid #e3e8ec; }
  th { background:#eef2f6; color:#1f3a5f; }
  tr:hover td { background:#f9fbfc; }
  .empty { color:#888; font-style:italic; margin:8px 0 0 0; }
  .warn { color:#8a6d00; }
  .err  { color:#b30000; }
  .badge { display:inline-block; padding:2px 8px; border-radius:12px;
           background:#1f3a5f; color:#fff; font-size:0.8em; margin-left:8px; }
  .badge.ip { background:#8a4b00; }
</style>
</head>
<body>
  <h1>Reporte DNS</h1>
  <div class="meta">
    Objetivo: <strong>$([System.Net.WebUtility]::HtmlEncode($Report.Target))</strong>
    <span class="badge $(if ($Report.IsIP) { 'ip' })">$(if ($Report.IsIP) { 'IP' } else { 'Dominio' })</span><br>
    Inicio: $($Report.StartedAt.ToString('yyyy-MM-dd HH:mm:ss')) &nbsp;|&nbsp;
    Fin: $($Report.FinishedAt.ToString('yyyy-MM-dd HH:mm:ss')) &nbsp;|&nbsp;
    Duración: ${duration}s
  </div>

  $(if (-not $Report.IsIP) { "<div class='card'><h2>Registros A</h2>$tableA</div>" })
  $(if (-not $Report.IsIP) { "<div class='card'><h2>Registros MX</h2>$tableMX</div>" })
  $(if (-not $Report.IsIP) { "<div class='card'><h2>Registros NS</h2>$tableNS</div>" })

  <div class="card">
    <h2>Registros PTR$(if ($IpForReverse) { " (IP: $([System.Net.WebUtility]::HtmlEncode($IpForReverse)))" })</h2>
    $tablePTR
  </div>

  <div class="card warn">
    <h2>Advertencias</h2>
    $warningsHtml
  </div>

  <div class="card err">
    <h2>Errores</h2>
    $errorsHtml
  </div>
</body>
</html>
"@

# ---------------------------------------------------------------
# Guardado con fallback automático
# ---------------------------------------------------------------
$saveResult = Save-HtmlReport -Content $html -PreferredPath $OutputPath

if ($saveResult.Success) {
    if ($saveResult.FinalPath -eq $OutputPath) {
        Write-Host "`nReporte HTML generado en: $($saveResult.FinalPath)" -ForegroundColor Green
    } else {
        Write-Host "`nNo se pudo guardar en la ruta pedida. Reporte generado en:" -ForegroundColor Yellow
        Write-Host "  $($saveResult.FinalPath)" -ForegroundColor Green
        Write-Host "  (Ruta original: $OutputPath)" -ForegroundColor DarkGray
        Write-Host "  Detalle de intentos:" -ForegroundColor DarkGray
        foreach ($a in $saveResult.Attempts) {
            $status = if ($a.OK) { "OK  " } else { "FAIL" }
            Write-Host ("    [$status] {0}" -f $a.Path) -ForegroundColor DarkGray
        }
    }

    # Abrir el reporte por defecto (salvo que se use -NoOpen)
    if (-not $NoOpen) {
        try {
            Start-Process $saveResult.FinalPath
            Write-Host "Abriendo el reporte en el navegador..." -ForegroundColor Cyan
        } catch {
            Write-Host "No se pudo abrir el reporte automáticamente: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "`nNo se pudo guardar el reporte HTML en ninguna ubicación." -ForegroundColor Red
    Write-Host "Detalle de intentos:" -ForegroundColor DarkGray
    foreach ($a in $saveResult.Attempts) {
        $status = if ($a.OK) { "OK  " } else { "FAIL" }
        Write-Host ("  [$status] {0}" -f $a.Path) -ForegroundColor DarkGray
        if (-not $a.OK) {
            Write-Host ("         -> {0}" -f $a.Error) -ForegroundColor DarkRed
        }
    }
}