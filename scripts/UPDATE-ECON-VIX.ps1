# UPDATE-ECON-VIX.ps1
# Refreshes ONLY the VIX tile in data.js with the latest Yahoo Finance quote (about every 5 minutes through RUN-ECON-RELEASE.ps1).
# the owner asked for this on 8 November 2026 ("you need to change the scheduled task for VIX").
# It changes the tile's value, previous close, date, time of the quote, the last point of its line and the one-year range. Nothing else in data.js is touched.
# When nothing changed it writes nothing. Failures go to update-log.txt with the word VIX.

$Out  = "$env:ECON_OUT"
$path = Join-Path $Out "data.js"
$log  = Join-Path $Out "update-log.txt"
function Log($t) { Add-Content -Path $log -Value ("{0}  VIX: {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $t); if ($t -cmatch 'FAILED') { Write-Output "UPDATE-ECON-VIX.ps1: $t" } }   # failures are also printed, so the cloud status shows CHECK
$inv = [Globalization.CultureInfo]::InvariantCulture

try {
  $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120 Safari/537.36"
  $r  = Invoke-WebRequest "https://query1.finance.yahoo.com/v8/finance/chart/%5EVIX?range=1d&interval=5m" -UseBasicParsing -TimeoutSec 30 -UserAgent $ua
  $m  = ($r.Content | ConvertFrom-Json).chart.result[0].meta
  $price = [math]::Round([double]$m.regularMarketPrice, 2)
  $prev  = [math]::Round([double]$m.chartPreviousClose, 2)
  if ($price -le 0 -or $prev -le 0) { Log "FAILED quote looked wrong, skipped"; exit }
  $dt    = [DateTimeOffset]::FromUnixTimeSeconds([int64]$m.regularMarketTime).LocalDateTime
  $asOf  = $dt.ToString("yyyy-MM-dd")
  $clock = $dt.ToString("h:mm tt", $inv)

  $text = [IO.File]::ReadAllText($path)
  $s = $text.IndexOf('{"id":"vix"'); if ($s -lt 0) { Log "FAILED no VIX tile in data.js"; exit }
  $e = $text.IndexOf('{"id":"', $s + 5); if ($e -lt 0) { $e = $text.Length }
  $seg = $text.Substring($s, $e - $s)
  $new = $seg

  $oldAsOf = [regex]::Match($seg, '"asOf":"([^"]*)"').Groups[1].Value
  $new = [regex]::Replace($new, '"value":[-\d.]+', ('"value":' + $price.ToString($inv)), 1)
  $new = [regex]::Replace($new, '"prev":[-\d.]+', ('"prev":' + $prev.ToString($inv)), 1)
  $new = [regex]::Replace($new, '"asOf":"[^"]*"(,"asOfTime":"[^"]*")?', ('"asOf":"' + $asOf + '","asOfTime":"' + $clock + '"'), 1)

  # the line: a new day adds a point and drops the oldest, the same day replaces the last point
  $sp = [regex]::Match($new, '"spark":\[([^\]]*)\]')
  if ($sp.Success) {
    $vals = @($sp.Groups[1].Value -split ',' | Where-Object { $_ -ne '' })
    if ($oldAsOf -ne $asOf) { $vals = @($vals | Select-Object -Skip 1) + $price.ToString($inv) } else { $vals[$vals.Count - 1] = $price.ToString($inv) }
    $new = $new.Replace($sp.Value, '"spark":[' + ($vals -join ',') + ']')
  }
  # the one-year range widens if the quote is outside it
  $rg = [regex]::Match($new, '"low":([-\d.]+),"high":([-\d.]+)')
  if ($rg.Success) {
    $lo = [math]::Min([double]::Parse($rg.Groups[1].Value, $inv), $price); $hi = [math]::Max([double]::Parse($rg.Groups[2].Value, $inv), $price)
    $new = $new.Replace($rg.Value, '"low":' + $lo.ToString($inv) + ',"high":' + $hi.ToString($inv))
  }

  if ($new -ceq $seg) { exit }
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($path, $text.Substring(0, $s) + $new + $text.Substring($e), $utf8)
} catch { Log ("FAILED: " + $_.Exception.Message) }
