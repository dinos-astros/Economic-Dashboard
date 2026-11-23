# UPDATE-ECON-GOLD.ps1
# Keeps the Gold page data current with no tokens (written 19 Nov 2026).
# 1) gold-spot.js  every run: the 50 year monthly spot gold chart.
#      Months up to the latest World Bank month come from the World Bank monthly average (open dataset github.com/datasets/gold-prices).
#      The current month is TODAY's spot price: the midpoint of the Swissquote live XAU/USD bid and ask (gold-api.com is the fallback).
# 2) gold-etf.js   once a day after 5 PM (or with -Force): 10 gold ETFs weekly for 12 months plus gold futures for the right axis, 3 year returns, dividends.
# Spot sources (both live bank or dealer quotes that agreed within about a dollar on 19 Nov 2026): Swissquote, then gold-api.com. A daily currency feed was tested and rejected: it was 4 percent off.
# A file is only replaced when every number checks out; otherwise the old file stays and a line says why.
# Plan: workspace/desktop/scratches/processes/ECON-DASHBOARD.md  (section: Gold page automation)

param([switch]$Force, [switch]$TestNasdaq)

$Out = "$env:ECON_OUT"
$spotFile = Join-Path $Out "gold-spot.js"
$etfFile  = Join-Path $Out "gold-etf.js"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$inv  = [Globalization.CultureInfo]::InvariantCulture
$hdr  = @{ "User-Agent" = "Mozilla/5.0" }
$today = Get-Date
$thisMonth = $today.ToString("yyyy-MM")
function N($x, $d) { ([math]::Round([double]$x, $d)).ToString($inv) }
# every web request is tried 3 times before it counts as failed
function Retry($block) { for ($i = 1; $i -le 3; $i++) { try { return (& $block) } catch { if ($i -eq 3) { throw }; Start-Sleep -Seconds (4 * $i) } } }
$asOfText = $today.ToString("yyyy-MM-dd HH:mm")
$spotOk = $false; $etfOk = $false; $problems = @()


# ---------- backup for the ETF data: Nasdaq public quote service (used only when Yahoo fails) ----------
function Nasdaq-Backup {
  $syms = "IAU","GLDM","IAUM","AAAU","GLD","GDX","GDXJ","RING","SGDM","GOAU"
  $oldTxt = [IO.File]::ReadAllText($etfFile)
  $od = [regex]::Match($oldTxt, " dates: \[(.*?)\],"); $og = [regex]::Match($oldTxt, " gold: \[(.*?)\],")
  $oldDates = @([regex]::Matches($od.Groups[1].Value, '\d{4}-\d{2}-\d{2}') | ForEach-Object { $_.Value })
  $oldGold = @($og.Groups[1].Value -split "," | ForEach-Object { [double]::Parse($_.Trim(), $inv) })
  if ($oldDates.Count -ne $oldGold.Count -or $oldDates.Count -lt 40) { throw "old ETF file did not parse" }
  $goldByWeek = @{}; for ($i = 0; $i -lt $oldDates.Count; $i++) { $goldByWeek[$oldDates[$i]] = $oldGold[$i] }
  $dvBlock = [regex]::Match($oldTxt, "(?s) div: \{.*?\r?\n \}").Value
  if (-not $dvBlock) { throw "old dividend block missing" }
  function Rows($s, $from) {
    $u = "https://api.nasdaq.com/api/quote/$s/historical?assetclass=etf&fromdate=$($from.ToString('yyyy-MM-dd'))&limit=1200&todate=$($today.ToString('yyyy-MM-dd'))"
    $r = Retry { Invoke-RestMethod $u -Headers @{ "User-Agent" = "Mozilla/5.0"; "Accept" = "application/json" } -TimeoutSec 40 }
    $rows = @($r.data.tradesTable.rows)
    if ($rows.Count -lt 100) { throw "$s returned only $($rows.Count) rows" }
    $rows | ForEach-Object { [pscustomobject]@{ d = [datetime]::ParseExact($_.date, "MM/dd/yyyy", $inv); c = [double](($_.close -replace '[\$,]', '')) } } | Sort-Object d
  }
  $weeks = @{}; $r3 = @{}; $firstWeeks = $null
  foreach ($s in $syms) {
    $r1 = Rows $s $today.AddDays(-385)
    $w = [ordered]@{}
    foreach ($x in $r1) { $mon = $x.d.AddDays(-((([int]$x.d.DayOfWeek + 6) % 7))).ToString("yyyy-MM-dd"); $w[$mon] = $x.c }
    $weeks[$s] = $w
    $r3rows = Rows $s $today.AddDays(-1105)
    $r3[$s] = "  ${s}: {from:""" + $r3rows[0].d.ToString("yyyy-MM-dd") + """,ret:" + (N (($r3rows[-1].c / $r3rows[0].c - 1) * 100) 1) + "}"
  }
  # the weeks every fund has, last 54 only
  $common = @($weeks["IAU"].Keys | Where-Object { $k = $_; -not ($syms | Where-Object { -not $weeks[$_].Contains($k) }) } | Sort-Object)
  $common = @($common | Select-Object -Last 54)
  if ($common.Count -lt 40) { throw "fewer than 40 common weeks ($($common.Count))" }
  # gold line: keep the old futures line where we have it, otherwise today's spot
  $goldVals = @(); $prevG = $oldGold[0]
  foreach ($wk in $common) {
    if ($goldByWeek.ContainsKey($wk)) { $prevG = $goldByWeek[$wk] }
    elseif ($wk -gt $oldDates[-1]) { $prevG = [double]$spot }
    $goldVals += $prevG
  }
  $etfLines = @($syms | ForEach-Object { $s2 = $_; "  ${s2}: [" + (($common | ForEach-Object { N $weeks[$s2][$_] 2 }) -join ",") + "]" })
  $js = "// Weekly closes: 10 gold ETFs. BACKUP DATA (Nasdaq) written because Yahoo Finance failed: the gold line is the earlier futures line plus today's spot for new weeks, dividends are the earlier figures. Written by UPDATE-ECON-GOLD.ps1, do not edit by hand.`r`n" +
        "var GOLD_ETF = {`r`n updated: ""$($today.ToString('yyyy-MM-dd'))"",`r`n asOf: ""$asOfText"",`r`n dates: [" + (($common | ForEach-Object { """$_""" }) -join ",") + "],`r`n gold: [" + (($goldVals | ForEach-Object { N $_ 2 }) -join ",") + "],`r`n etf: {`r`n" + ($etfLines -join ",`r`n") + "`r`n },`r`n r3: {`r`n" + (($syms | ForEach-Object { $r3[$_] }) -join ",`r`n") + "`r`n },`r`n" + $dvBlock + "`r`n};"
  [IO.File]::WriteAllText($etfFile, $js, $utf8)
  Write-Output "gold ETFs: refreshed 10 funds from the Nasdaq backup, $($common.Count) weeks"
}

# ---------- US Dollar Index monthly averages (Yahoo DX-Y.NYB daily closes, averaged per month; the series starts January 1985) ----------
function Real10-Monthly {
  # Federal Reserve Bank of Cleveland model estimate of the 10-year real interest rate, monthly (percent), from 1982
  $cache = "$env:ECON_OUT\cache"; New-Item -ItemType Directory -Force $cache | Out-Null
  $xf = Join-Path $cache "cleveland-inflation-expectations.xlsx"; $got = $false
  for ($t = 1; $t -le 3 -and -not $got; $t++) { try { Invoke-WebRequest "https://www.clevelandfed.org/-/media/files/webcharts/inflationexpectations/inflation-expectations.xlsx?sc_lang=en" -Headers @{ "User-Agent" = "Mozilla/5.0" } -UseBasicParsing -TimeoutSec 90 -OutFile $xf; $got = $true } catch { Start-Sleep -Seconds 4 } }
  if (-not (Test-Path $xf)) { throw "Cleveland Fed file not reachable" }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::OpenRead($xf)
  try {
    $rd = { param($name) $e = $z.GetEntry($name); $r = New-Object IO.StreamReader($e.Open()); $x = $r.ReadToEnd(); $r.Close(); $x }
    $wb = & $rd "xl/workbook.xml"; $rels = & $rd "xl/_rels/workbook.xml.rels"
    $rid = [regex]::Match($wb, '<sheet [^>]*name="Real Interest Rate"[^>]*r:id="([^"]+)"').Groups[1].Value
    $tgt = [regex]::Match($rels, '<Relationship [^>]*Id="' + $rid + '"[^>]*Target="([^"]+)"').Groups[1].Value
    if (-not $tgt) { $tgt = [regex]::Match($rels, '<Relationship [^>]*Target="([^"]+)"[^>]*Id="' + $rid + '"').Groups[1].Value }
    $sx = & $rd ("xl/" + $tgt.TrimStart("/").Replace("xl/", ""))
  } finally { $z.Dispose() }
  $out = @{}
  foreach ($rw in [regex]::Matches($sx, '<row [^>]*>.*?</row>', 'Singleline')) {
    $ca = [regex]::Match($rw.Value, '<c r="A\d+"[^>]*><v>([\d\.]+)</v>'); $cd = [regex]::Match($rw.Value, '<c r="D\d+"[^>]*><v>(-?[\d\.Ee\-]+)</v>')
    if ($ca.Success -and $cd.Success) { $out[([datetime]"1899-12-30").AddDays([double]$ca.Groups[1].Value).ToString("yyyy-MM")] = [math]::Round([double]::Parse($cd.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) * 100, 2) }
  }
  if ($out.Count -lt 400) { throw "real rate column not read ($($out.Count) months)" }
  $out
}
function Dxy-Monthly($from) {
  $sum = @{}; $cnt = @{}; $start = $from; $stop = $today.Date.AddDays(1)
  while ($start -lt $stop) {
    $end = $start.AddYears(4); if ($end -gt $stop) { $end = $stop }
    $p1 = [DateTimeOffset]::new([datetime]::SpecifyKind($start, [DateTimeKind]::Utc), [TimeSpan]::Zero).ToUnixTimeSeconds(); $p2 = [DateTimeOffset]::new([datetime]::SpecifyKind($end, [DateTimeKind]::Utc), [TimeSpan]::Zero).ToUnixTimeSeconds()
    $res = $null
    foreach ($h in "query1", "query2") {
      try { $res = (Retry { Invoke-RestMethod "https://$h.finance.yahoo.com/v8/finance/chart/DX-Y.NYB?period1=$p1&period2=$p2&interval=1d" -Headers $hdr -TimeoutSec 60 }).chart.result[0]; break } catch {}
    }
    if (-not $res) { throw "dollar index download failed from $($start.ToString('yyyy-MM-dd'))" }
    $ts = @($res.timestamp); $cl = @($res.indicators.quote[0].close)
    for ($i = 0; $i -lt $ts.Count; $i++) { if ($null -ne $cl[$i]) { $k = [DateTimeOffset]::FromUnixTimeSeconds($ts[$i]).ToString("yyyy-MM"); if (-not $sum.ContainsKey($k)) { $sum[$k] = 0.0; $cnt[$k] = 0 }; $sum[$k] += [double]$cl[$i]; $cnt[$k]++ } }
    $start = $end
  }
  $m = @{}; foreach ($k in $sum.Keys) { $m[$k] = $sum[$k] / $cnt[$k] }
  $m
}
# ---------- 1. spot price chart ----------
try {
  # today's spot
  $spot = $null; $src = ""
  try {
    $q = Retry { Invoke-RestMethod "https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD" -Headers $hdr -TimeoutSec 30 }
    $p = $null; foreach ($srv in @($q)) { foreach ($pp in @($srv.spreadProfilePrices)) { if ($pp.bid -and $pp.ask -and -not $p) { $p = $pp } } }
    $spot = [math]::Round(([double]$p.bid + [double]$p.ask) / 2, 0); $src = "Swissquote"
  } catch {}
  if (-not $spot) {
    try { $g = Retry { Invoke-RestMethod "https://api.gold-api.com/price/XAU" -Headers $hdr -TimeoutSec 30 }; $spot = [math]::Round([double]$g.price, 0); $src = "gold-api.com" } catch {}
  }
  if (-not $spot -or $spot -lt 500 -or $spot -gt 20000) { throw "no usable spot price (got '$spot')" }

  # the months already in the file
  $txt = [IO.File]::ReadAllText($spotFile)
  $dm = [regex]::Match($txt, " dates: \[(.*?)\],"); $gm = [regex]::Match($txt, " gold: \[(.*?)\]")
  $dates = @([regex]::Matches($dm.Groups[1].Value, '\d{4}-\d{2}') | ForEach-Object { $_.Value })
  $vals  = @($gm.Groups[1].Value -split "," | ForEach-Object { [double]::Parse($_.Trim(), $inv) })
  if ($dates.Count -ne $vals.Count -or $dates.Count -lt 100) { throw "gold-spot.js did not parse ($($dates.Count) dates, $($vals.Count) values)" }
  $series = [ordered]@{}; for ($i = 0; $i -lt $dates.Count; $i++) { $series[$dates[$i]] = $vals[$i] }
  $first = $dates[0]

  # World Bank monthly averages replace anything provisional
  $csvLast = $null
  try {
    $r = Retry { Invoke-WebRequest "https://raw.githubusercontent.com/datasets/gold-prices/main/data/monthly.csv" -UseBasicParsing -TimeoutSec 30 -Headers $hdr }
    foreach ($l in ($r.Content -split "`r?`n")) {
      if ($l -match '^(\d{4}-\d{2}),([\d.]+)') { $m = $Matches[1]; if ($m -ge $first) { $series[$m] = [math]::Round([double]::Parse($Matches[2], $inv), 1); if (-not $csvLast -or $m -gt $csvLast) { $csvLast = $m } } }
    }
  } catch { Write-Output "gold spot: World Bank file not reachable, kept the months already in the file" }
  if (-not $csvLast) { $csvLast = ($series.Keys | Where-Object { $_ -lt $thisMonth } | Sort-Object | Select-Object -Last 1) }

  # drop any provisional month the official data now covers, then set the current month to today's spot
  foreach ($k in @($series.Keys)) { if ($k -gt $csvLast) { $series.Remove($k) } }
  if ($thisMonth -gt $csvLast) { $series[$thisMonth] = $spot }

  $keys = @($series.Keys | Sort-Object)
  # no gaps allowed
  for ($i = 1; $i -lt $keys.Count; $i++) {
    $a = [int]$keys[$i-1].Substring(0,4) * 12 + [int]$keys[$i-1].Substring(5,2); $b = [int]$keys[$i].Substring(0,4) * 12 + [int]$keys[$i].Substring(5,2)
    if (($b - $a) -ne 1) { throw "gap in the monthly series between $($keys[$i-1]) and $($keys[$i])" }
  }
  $lastKey = $keys[-1]
  # the dollar index line for the same months: keep what is in the file, refresh the last 14 months, or load the whole history the first time
  $dxyOld = @{}
  $dm2 = [regex]::Match($txt, " dxy: \[(.*?)\]")
  if ($dm2.Success) { $vv = @($dm2.Groups[1].Value -split ","); for ($i = 0; $i -lt [Math]::Min($vv.Count, $dates.Count); $i++) { if ($vv[$i].Trim() -ne "null" -and $vv[$i].Trim() -ne "") { $dxyOld[$dates[$i]] = [double]::Parse($vv[$i].Trim(), $inv) } } }
  $dxyFrom = if ($dxyOld.Count -lt 400) { [datetime]"1985-01-01" } else { (Get-Date -Day 1).Date.AddMonths(-14) }
  $rrMap = @{}; try { $rrMap = Real10-Monthly; Write-Output "real rate: $($rrMap.Count) months (Cleveland Fed)" } catch { Write-Output "real rate FAILED: $($_.Exception.Message)" }
  try { $dxyNew = Dxy-Monthly $dxyFrom; foreach ($k in $dxyNew.Keys) { $dxyOld[$k] = [math]::Round($dxyNew[$k], 2) }; Write-Output "dollar index: $($dxyNew.Count) months refreshed from $($dxyFrom.ToString('yyyy-MM'))" }
  catch { Write-Output ("dollar index FAILED, the old values stay: " + $_.Exception.Message); $problems += ("dollar index: " + $_.Exception.Message) }
  $new = "// Spot gold price, monthly average, USD per troy ounce, $($keys[0]) to $csvLast, with the US Dollar Index monthly average (dxy, from 1985), plus the current month ($lastKey) as TODAY's spot price ($src live quote, not an average).`r`n" +
         "// Months up to ${csvLast}: World Bank Commodity Markets (Pink Sheet) via the open dataset github.com/datasets/gold-prices. Written by UPDATE-ECON-GOLD.ps1, do not edit by hand.`r`n" +
         "var GOLD_20Y = {`r`n updated: ""$($today.ToString('yyyy-MM-dd'))"",`r`n asOf: ""$asOfText"",`r`n dates: [" + (($keys | ForEach-Object { """$_""" }) -join ",") + "],`r`n gold: [" + (($keys | ForEach-Object { N $series[$_] 1 }) -join ",") + "],`r`n dxy: [" + (($keys | ForEach-Object { if ($dxyOld.ContainsKey($_)) { N $dxyOld[$_] 2 } else { "null" } }) -join ",") + "],`r`n rr: [" + (($keys | ForEach-Object { if ($rrMap.ContainsKey($_)) { N $rrMap[$_] 2 } else { "null" } }) -join ",") + "]`r`n};"
  [IO.File]::WriteAllText($spotFile, $new, $utf8); Write-Output "gold spot: updated, $($keys.Count) months, today's spot $spot ($src), World Bank through $csvLast"; $spotOk = $true
} catch { Write-Output ("gold spot FAILED, the old file stays: " + $_.Exception.Message); $problems += ("spot price: " + $_.Exception.Message) }

# ---------- 2. ETF charts ----------
$etfStamp = if (Test-Path $etfFile) { (Get-Item $etfFile).LastWriteTime } else { $null }
$preOpt = @{}; if (Test-Path $etfFile) { $preTxt = [IO.File]::ReadAllText($etfFile); foreach ($pm in [regex]::Matches($preTxt, "(?s) opt: \{(.*?)\}")) { foreach ($px in [regex]::Matches($pm.Groups[1].Value, "([A-Z]+):\s*(\d)")) { $preOpt[$px.Groups[1].Value] = $px.Groups[2].Value } } }   # the answers as they stood before this run, so a failed check can never lose one
try {
  $etfToday = $false
  if (Test-Path $etfFile) { $etfToday = ([IO.File]::ReadAllText($etfFile) -match ('updated: "' + $today.ToString("yyyy-MM-dd") + '"')) }
  $etfOld = (-not (Test-Path $etfFile)) -or (((Get-Date) - (Get-Item $etfFile).LastWriteTime).TotalHours -gt 20)
  if (-not $Force -and ($etfToday -or ($today.Hour -lt 17 -and -not $etfOld))) { Write-Output "gold ETFs: not due (refreshed once a day after 5 PM, and every run until it works)"; $etfOk = $true }
  else {
    if ($TestNasdaq) { throw "test: pretending Yahoo is down" }
    $syms = "IAU","GLDM","IAUM","AAAU","GLD","GDX","GDXJ","RING","SGDM","GOAU"
    function Yahoo($s, $range, $interval, $div) {
      $lastErr = $null
      foreach ($h in "query1", "query2") {
        try {
          $u = "https://$h.finance.yahoo.com/v8/finance/chart/" + [uri]::EscapeDataString($s) + "?range=$range&interval=$interval"
          if ($div) { $u += "&events=div" }
          return (Retry { Invoke-RestMethod $u -Headers $hdr -TimeoutSec 60 }).chart.result[0]
        } catch { $lastErr = $_ }
      }
      throw $lastErr
    }
    $gw = Yahoo "GC=F" "1y" "1wk" $false
    $dts = @($gw.timestamp | ForEach-Object { [DateTimeOffset]::FromUnixTimeSeconds($_).ToString("yyyy-MM-dd") })
    $gc = @($gw.indicators.quote[0].close)
    $n = $dts.Count
    if ($n -lt 40) { throw "gold futures weekly series too short ($n)" }
    if (@($gc | Where-Object { $null -eq $_ }).Count -gt 0) { throw "gold futures series has gaps" }
    $etfLines = @(); $r3Lines = @(); $dvLines = @()
    foreach ($s in $syms) {
      $w = Yahoo $s "1y" "1wk" $false
      $c = @($w.indicators.quote[0].close)
      if ($c.Count -ne $n) { throw "$s weekly count $($c.Count) does not match gold $n" }
      if (@($c | Where-Object { $null -eq $_ }).Count -gt 0) { throw "$s weekly series has gaps" }
      $etfLines += "  ${s}: [" + (($c | ForEach-Object { N $_ 2 }) -join ",") + "]"
      $d3 = Yahoo $s "3y" "1d" $false
      $c3 = @($d3.indicators.quote[0].close); $t3 = @($d3.timestamp)
      $i0 = 0; while ($i0 -lt $c3.Count -and $null -eq $c3[$i0]) { $i0++ }; $i1 = $c3.Count - 1; while ($i1 -ge 0 -and $null -eq $c3[$i1]) { $i1-- }
      if ($i0 -ge $i1) { throw "$s 3 year series unusable" }
      $r3Lines += "  ${s}: {from:""" + [DateTimeOffset]::FromUnixTimeSeconds($t3[$i0]).ToString("yyyy-MM-dd") + """,ret:" + (N (($c3[$i1] / $c3[$i0] - 1) * 100) 1) + "}"
      $dv = Yahoo $s "1y" "1d" $true
      $sum = 0.0; $cnt = 0
      if ($dv.events -and $dv.events.dividends) { foreach ($e in $dv.events.dividends.PSObject.Properties) { $sum += [double]$e.Value.amount; $cnt++ } }
      $dvLines += "  ${s}: {sum:" + (N $sum 4) + ",n:$cnt}"
    }
    $js = "// Weekly closes for 12 months: gold front-month futures (GC=F, right axis) and 10 gold ETFs, 3 year price returns, 12 month dividends. Source: Yahoo Finance. Written by UPDATE-ECON-GOLD.ps1, do not edit by hand.`r`n" +
          "var GOLD_ETF = {`r`n updated: ""$($today.ToString('yyyy-MM-dd'))"",`r`n asOf: ""$asOfText"",`r`n dates: [" + (($dts | ForEach-Object { """$_""" }) -join ",") + "],`r`n gold: [" + (($gc | ForEach-Object { N $_ 2 }) -join ",") + "],`r`n etf: {`r`n" + ($etfLines -join ",`r`n") + "`r`n },`r`n r3: {`r`n" + ($r3Lines -join ",`r`n") + "`r`n },`r`n div: {`r`n" + ($dvLines -join ",`r`n") + "`r`n }`r`n};"
    [IO.File]::WriteAllText($etfFile, $js, $utf8)
    Write-Output "gold ETFs: refreshed 10 funds, $n weeks"; $etfOk = $true
  }
} catch {
  $yerr = $_.Exception.Message; Write-Output "gold ETFs: Yahoo failed ($yerr), trying the Nasdaq backup"
  try { Nasdaq-Backup; $etfOk = $true } catch { Write-Output ("gold ETFs FAILED on both sources, the old file stays: " + $_.Exception.Message); $problems += ("ETF data: Yahoo said ' $yerr ' and Nasdaq said ' " + $_.Exception.Message + " '") }
}

# ---------- 2b. which ETFs have listed options (Nasdaq option chain, once per ETF refresh) ----------
try {
  $stampNow = if (Test-Path $etfFile) { (Get-Item $etfFile).LastWriteTime } else { $null }
  $txtNow = if (Test-Path $etfFile) { [IO.File]::ReadAllText($etfFile) } else { "" }
  $haveOpt = @{}; foreach ($hm in [regex]::Matches($txtNow, "(?s) opt: \{(.*?)\}")) { foreach ($hx in [regex]::Matches($hm.Groups[1].Value, "([A-Z]+):\s*(\d)")) { $haveOpt[$hx.Groups[1].Value] = $hx.Groups[2].Value } }
  if ($txtNow -and ($Force -or ($stampNow -ne $etfStamp) -or $haveOpt.Count -lt 10)) {
    $oldOpt = @{}; foreach ($k in $preOpt.Keys) { $oldOpt[$k] = $preOpt[$k] }; foreach ($k in $haveOpt.Keys) { $oldOpt[$k] = $haveOpt[$k] }
    $optLines = @(); $optBad = 0
    foreach ($sy in "IAU","GLDM","IAUM","AAAU","GLD","GDX","GDXJ","RING","SGDM","GOAU") {
      $val = $null
      try {
        $u = "https://api.nasdaq.com/api/quote/$sy/option-chain?assetclass=etf&limit=5&fromdate=$($today.ToString('yyyy-MM-dd'))&todate=$($today.AddYears(2).ToString('yyyy-MM-dd'))&excode=oprac&callput=callput&money=all&type=all"
        $r = Retry { Invoke-RestMethod $u -Headers @{ "User-Agent" = "Mozilla/5.0"; "Accept" = "application/json" } -TimeoutSec 40 }
        if ($r.status.rCode -eq 200 -and $null -ne $r.data.totalRecord) { $val = $(if ([int]$r.data.totalRecord -gt 0) { 1 } else { 0 }) }
      } catch {}
      if ($null -eq $val) { $optBad++; if ($oldOpt.ContainsKey($sy)) { $val = $oldOpt[$sy] } }
      if ($null -ne $val) { $optLines += "  ${sy}: $val" }
    }
    $block = " opt: {`r`n" + ($optLines -join ",`r`n") + "`r`n }"
    $txtNow = [regex]::Replace($txtNow, ",\r?\n opt: \{.*?\r?\n \}", "", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $i = $txtNow.LastIndexOf("`r`n};")
    if ($i -gt 0) { [IO.File]::WriteAllText($etfFile, $txtNow.Substring(0, $i) + ",`r`n" + $block + $txtNow.Substring($i), $utf8) }
    Write-Output ("gold options: checked 10 funds, " + ($optLines | Where-Object { $_ -match ": 1" }).Count + " have listed options" + $(if ($optBad -gt 0) { ", $optBad could not be checked (kept the earlier answer)" } else { "" }))
  }
} catch { Write-Output ("gold options FAILED, the old answers stay: " + $_.Exception.Message) }

# ---------- 3. alert file: present only while something is failing ----------
$alert = Join-Path $Out "GOLD-DATA-ALERT.txt"
if ($problems.Count -gt 0) {
  $msg = "Gold page data did NOT update at $asOfText. " + ($problems -join " | ") + " The page shows its last good numbers and turns the 'as of' line red after 3 days. This script retries every hour automatically."
  [IO.File]::WriteAllText($alert, $msg, $utf8); Write-Output ("ALERT written: " + $msg)
} elseif (Test-Path $alert) { Remove-Item $alert -Force; Write-Output "alert cleared, both updates worked" }
