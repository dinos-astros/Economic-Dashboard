# UPDATE-ECON-MARKET.ps1
# Daily Market Check for the dashboard: SPY and QQQ daily closes with the 20, 50 and 200 day moving averages (MA), last 92 trading days (3 months drawn plus 29 days of lead-in for the daily checks).
# Source: Yahoo chart data (the same source as the VIX tile). Writes market.js. the owner asked for this on 12 November 2026.
# Only COMPLETED days are used: a day's candle is dropped until 10 minutes after the session ends (4:00 PM Eastern, 1:00 PM on early close days), so the MAs never include a half-finished day.
# The page shows the charts and her rules and works out the call (Bull, Bear, Range bound) from market.js using her definitions; see dashboard.html.

$Out = "$env:ECON_OUT"
$h = @{ 'User-Agent' = 'Mozilla/5.0' }
$show = 92   # 63 trading days (3 months, what the charts draw) plus 29 earlier days, so the 30-day bull, trend and range checks can be made for the first day drawn (the owner, 12 Nov 2026)
$et = [TimeZoneInfo]::FindSystemTimeZoneById("Eastern Standard Time")
$nowET = [TimeZoneInfo]::ConvertTime((Get-Date), $et)

function MA($c, $k, $at) { $s = 0.0; for ($j = $at - $k + 1; $j -le $at; $j++) { $s += $c[$j] }; return [math]::Round($s / $k, 2) }

$result = [ordered]@{}
$asOf = $null
try {
  foreach ($sym in 'SPY', 'QQQ') {
    $r = Invoke-RestMethod ("https://query1.finance.yahoo.com/v8/finance/chart/{0}?range=2y&interval=1d" -f $sym) -Headers $h -TimeoutSec 30
    $res = $r.chart.result[0]
    $off = [int]$res.meta.gmtoffset
    # when today's session ends, from Yahoo: 4:00 PM Eastern on a full day, 1:00 PM on an early close day (27 Nov 2026). A day counts ten minutes after it ends.
    $endET = $nowET.Date.AddHours(16)
    if ($res.meta.currentTradingPeriod.regular.end) { $e1 = [DateTimeOffset]::FromUnixTimeSeconds([long]$res.meta.currentTradingPeriod.regular.end + $off).UtcDateTime; if ($e1.Date -eq $nowET.Date) { $endET = $e1 } }
    $doneAt = $endET.AddMinutes(10)
    $dates = @(); $closes = @(); $opens = @(); $highs = @(); $lows = @(); $vols = @()
    $q = $res.indicators.quote[0]
    for ($i = 0; $i -lt $res.timestamp.Count; $i++) {
      $cl = $q.close[$i]
      # Yahoo can leave today's daily close empty for hours after the bell (24 Nov 2026). The session close is then in meta.regularMarketPrice.
      if ($null -eq $cl -and $i -eq $res.timestamp.Count - 1 -and $null -ne $q.open[$i] -and $res.meta.regularMarketPrice) {
        $mt = [DateTimeOffset]::FromUnixTimeSeconds([long]$res.meta.regularMarketTime + $off).UtcDateTime
        $bd = [DateTimeOffset]::FromUnixTimeSeconds([long]$res.timestamp[$i] + $off).UtcDateTime
        if ($mt.Date -eq $bd.Date -and $mt.TimeOfDay -ge $(if ($mt.Date -eq $nowET.Date) { $endET.TimeOfDay } else { [TimeSpan]::FromHours(13) })) { $cl = [double]$res.meta.regularMarketPrice }
      }
      if ($null -eq $cl) { continue }
      $dates += ([DateTimeOffset]::FromUnixTimeSeconds([long]$res.timestamp[$i] + $off).UtcDateTime.ToString("yyyy-MM-dd"))
      $closes += [double]$cl
      $op = $q.open[$i]; if ($null -eq $op) { $op = $cl }; $opens += [double]$op
      $hi = $q.high[$i]; if ($null -eq $hi) { $hi = [math]::Max($op, $cl) }; $highs += [double]$hi
      $lo = $q.low[$i]; if ($null -eq $lo) { $lo = [math]::Min($op, $cl) }; $lows += [double]$lo
      $vo = $q.volume[$i]; if ($null -eq $vo) { $vo = 0 }; $vols += [double]$vo
    }
    # drop today's candle until the day is finished
    $todayET = $nowET.ToString("yyyy-MM-dd")
    if ($dates[-1] -eq $todayET -and $nowET -lt $doneAt) { $k = $dates.Count - 2; $dates = $dates[0..$k]; $closes = $closes[0..$k]; $opens = $opens[0..$k]; $highs = $highs[0..$k]; $lows = $lows[0..$k]; $vols = $vols[0..$k] }
    $n = $closes.Count
    if ($n -lt 220) { throw "not enough history for $sym" }
    $d = @(); $o = @(); $hh = @(); $ll = @(); $c = @(); $v = @(); $m20 = @(); $m50 = @(); $m200 = @()
    for ($i = $n - $show; $i -lt $n; $i++) {
      $d += $dates[$i]; $o += [math]::Round($opens[$i], 2); $hh += [math]::Round($highs[$i], 2); $ll += [math]::Round($lows[$i], 2); $c += [math]::Round($closes[$i], 2); $v += [long]$vols[$i]
      $m20 += (MA $closes 20 $i); $m50 += (MA $closes 50 $i); $m200 += (MA $closes 200 $i)
    }
    # a finished session that is still missing from the chart must show up as a failure, not pass silently
    $lastTrade = [DateTimeOffset]::FromUnixTimeSeconds([long]$res.meta.regularMarketTime + $off).UtcDateTime
    if ($lastTrade.ToString("yyyy-MM-dd") -gt $dates[-1] -and ($lastTrade.Date -lt $nowET.Date -or $nowET -ge $doneAt)) { "UPDATE-ECON-MARKET.ps1: FAILED $sym session $($lastTrade.ToString('yyyy-MM-dd')) is finished but the chart ends $($dates[-1])" }
    $result[$sym] = [ordered]@{ open = [math]::Round($opens[-1], 2); d = $d; o = $o; h = $hh; l = $ll; c = $c; v = $v; m20 = $m20; m50 = $m50; m200 = $m200 }
    if (-not $asOf -or $dates[-1] -lt $asOf) { $asOf = $dates[-1] }
  }
} catch { Add-Content (Join-Path $Out "update-log.txt") ("{0}  MARKET: FAILED {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $_.Exception.Message); "UPDATE-ECON-MARKET.ps1: FAILED " + $_.Exception.Message; exit }

$obj = [ordered]@{ asOf = $asOf; SPY = $result['SPY']; QQQ = $result['QQQ'] }
$text = "window.MARKET = " + ($obj | ConvertTo-Json -Depth 5 -Compress) + ";"
$file = Join-Path $Out "market.js"
$old = $null; if (Test-Path $file) { $old = [IO.File]::ReadAllText($file) }
# never replace a newer day with an older one: when Yahoo drops a finished close, keep the last good chart and say FAILED (27 Nov 2026)
$oldAsOf = if ($old) { [regex]::Match($old, '"asOf":"(\d{4}-\d{2}-\d{2})"').Groups[1].Value } else { '' }
if ($oldAsOf -and $oldAsOf -gt $asOf) { Add-Content (Join-Path $Out "update-log.txt") ("{0}  MARKET: FAILED source ends {1}, kept the chart ending {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $asOf, $oldAsOf); "UPDATE-ECON-MARKET.ps1: FAILED source ends $asOf, kept the chart ending $oldAsOf"; exit }
if ($old -cne $text) {
  [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($false)))
  "UPDATE-ECON-MARKET.ps1: updated, latest close $asOf"
} else { "UPDATE-ECON-MARKET.ps1: no change, latest close $asOf" }
