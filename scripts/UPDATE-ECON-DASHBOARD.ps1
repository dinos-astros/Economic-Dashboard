# UPDATE-ECON-DASHBOARD.ps1
# Pulls the indicators that a script can reach, adds dated rows to econ-readings.csv,
# and rewrites data.js, which dashboard.html reads.
# Plan and sources: workspace/desktop/scratches/processes/ECON-DASHBOARD.md
# Free sources only. Nothing here places a trade or edits the owner's workbooks.
# Sources a script cannot reach (FRED, ISM, Conference Board, Baker Hughes, broker reports) are not here.

param(
  [string]$Out = "$env:ECON_OUT"
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$now = Get-Date
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force $Out | Out-Null }

$readings = New-Object System.Collections.Generic.List[object]
$status = New-Object System.Collections.Generic.List[object]
$tiles = New-Object System.Collections.Generic.List[object]

function Add-Reading($date, $indicator, $value, $source) {
  $readings.Add([pscustomobject]@{
    ObservationDate = $date; Indicator = $indicator; Value = $value; Source = $source
    CapturedOn = $now.ToString("yyyy-MM-dd HH:mm")
  })
}
function Add-Status($name, $ok, $note, $stale = $false) {
  $status.Add([ordered]@{ name = $name; ok = $ok; note = $note; stale = $stale })
}
# The last saved data, kept so a source that does not answer today does not blank its chart.
$prev = $null
$prevPath = Join-Path $Out "data.js"
if (Test-Path $prevPath) {
  try { $prev = ((Get-Content $prevPath -Raw) -replace '^window\.DATA = ', '' -replace ';\s*$', '') | ConvertFrom-Json } catch { $prev = $null }
}
function Get-Web($u) {
  $c = (Invoke-WebRequest -UseBasicParsing $u -TimeoutSec 40).Content
  if ($c -is [byte[]]) { $c = [Text.Encoding]::UTF8.GetString($c) }
  return $c
}

# ---------- Yahoo: market tiles with a one-month trend line ----------
function Get-Yahoo([string]$sym) {
  $u = "https://query1.finance.yahoo.com/v8/finance/chart/" + [uri]::EscapeDataString($sym) + "?range=6mo&interval=1d"
  $j = (Get-Web $u) | ConvertFrom-Json
  $r = $j.chart.result[0]
  $ts = @($r.timestamp); $cl = @($r.indicators.quote[0].close)
  # Yahoo can leave the latest daily close empty after the session ends (24 Nov 2026): the session price is then in meta.regularMarketPrice
  $n1 = $ts.Count - 1
  if ($n1 -ge 0 -and $null -eq $cl[$n1] -and $r.meta.regularMarketPrice -and ([DateTimeOffset]::FromUnixTimeSeconds([int64]$r.meta.regularMarketTime).ToLocalTime().Date -eq [DateTimeOffset]::FromUnixTimeSeconds([int64]$ts[$n1]).ToLocalTime().Date) -and ((Get-Date).Hour -ge 16)) { $cl[$n1] = [double]$r.meta.regularMarketPrice }
  $pts = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $ts.Count; $i++) {
    if ($null -ne $cl[$i]) {
      $pts.Add([ordered]@{ d = [DateTimeOffset]::FromUnixTimeSeconds([int64]$ts[$i]).ToLocalTime().ToString("yyyy-MM-dd"); v = [math]::Round([double]$cl[$i], 4) })
    }
  }
  return $pts
}
function Add-Tile($id, $label, $unit, $pts, $source, $note, $decimals, $window = "") {
  $n = $pts.Count
  $last = $pts[$n - 1]; $prev = $pts[$n - 2]
  $tiles.Add([ordered]@{
    id = $id; label = $label; unit = $unit; value = $last.v; prev = $prev.v
    asOf = $last.d; spark = @($pts | ForEach-Object { $_.v }); sd = @($pts | ForEach-Object { $_.d }); source = $source; note = $note; decimals = $decimals; window = $window
  })
  Add-Reading $last.d $label $last.v $source
}

$yahoo = @(
  @("^VIX", "vix", "VIX", "", "Yahoo Finance", "The market's fear gauge", 2),
  @("^GSPC", "spx", "S&P 500", "", "Yahoo Finance", "", 2),
  @("^IXIC", "ndx", "Nasdaq Composite", "", "Yahoo Finance", "", 2),
  @("DX-Y.NYB", "dxy", "US Dollar Index", "", "Yahoo Finance", "", 2),
  @("GC=F", "gld", "Gold (dollars per ounce)", "$", "Yahoo Finance", "The price of one ounce of gold, front-month futures", 2)
)
foreach ($y in $yahoo) {
  try {
    $p = Get-Yahoo $y[0]
    Add-Tile $y[1] $y[2] $y[3] $p $y[4] $y[5] $y[6] "6 months"
    Add-Status $y[2] $true "Yahoo Finance"
  } catch { Add-Status $y[2] $false $_.Exception.Message }
}

# ---------- VIX benchmark: where today sits against its whole history ----------
try {
  # The last year of daily closes, so the tile can show where today sits in the past year's range.
  $j = (Get-Web "https://query1.finance.yahoo.com/v8/finance/chart/%5EVIX?range=1y&interval=1d") | ConvertFrom-Json
  $r = $j.chart.result[0]
  $cl = @($r.indicators.quote[0].close | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
  $vixTile = @($tiles | Where-Object { $_.id -eq "vix" }) | Select-Object -First 1
  if ($vixTile -and $cl.Count -gt 200) {
    $lowV = ($cl | Measure-Object -Minimum).Minimum; $highV = ($cl | Measure-Object -Maximum).Maximum
    $vixTile["range"] = [ordered]@{ low = [math]::Round($lowV, 2); high = [math]::Round([math]::Max($highV, $vixTile.value), 2); label = "1-year range" }
    Add-Status "VIX one-year range" $true ("$($cl.Count) daily closes")
  }
} catch { Add-Status "VIX one-year range" $false $_.Exception.Message }

# ---------- Treasury: yields, spread, real yield ----------
$spread = $null; $realYield = $null
function Get-TreasuryRows([string]$type) {
  # Newest first. Early in the year the current year alone is too short for six months, so add the year before.
  $all = @()
  foreach ($y in @($now.Year, ($now.Year - 1))) {
    $u = "https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/$y/all?type=$type&field_tdr_date_value=$y&page&_format=csv"
    $all += @((Get-Web $u) | ConvertFrom-Csv)
    if ($all.Count -ge 130) { break }
  }
  return $all
}
try {
  $rows = @(Get-TreasuryRows "daily_treasury_yield_curve")
  $pts10 = New-Object System.Collections.Generic.List[object]
  $ptsSp = New-Object System.Collections.Generic.List[object]
  $pts3m = New-Object System.Collections.Generic.List[object]
  $take = [Math]::Min(126, $rows.Count)
  for ($i = $take - 1; $i -ge 0; $i--) {
    $d = [datetime]::ParseExact($rows[$i].Date, "MM/dd/yyyy", $null).ToString("yyyy-MM-dd")
    $v10 = [double]$rows[$i].'10 Yr'; $v2 = [double]$rows[$i].'2 Yr'
    $pts10.Add([ordered]@{ d = $d; v = $v10 })
    $ptsSp.Add([ordered]@{ d = $d; v = [math]::Round($v10 - $v2, 2) })
    if ($rows[$i].'3 Mo' -match '^\d') { $pts3m.Add([ordered]@{ d = $d; v = [double]$rows[$i].'3 Mo' }) }
  }
  if ($pts3m.Count -ge 2) { Add-Tile "t3m" "3-month Treasury bill rate" "%" $pts3m "U.S. Treasury daily par yield curve" "3 month bill rate" 2 "6 months" }
  Add-Tile "t10" "10-year Treasury yield" "%" $pts10 "U.S. Treasury daily par yield curve" "The long-term cost of money" 2 "6 months"
  $last = $ptsSp[$ptsSp.Count - 1]
  $spread = [ordered]@{ asOf = $last.d; value = $last.v; series = @($ptsSp | ForEach-Object { $_.v }) }
  Add-Reading $last.d "10-year minus 2-year Treasury spread" $last.v "U.S. Treasury daily par yield curve"
  Add-Status "Treasury yield curve" $true "home.treasury.gov"
} catch { Add-Status "Treasury yield curve" $false $_.Exception.Message }
# ---------- Federal Reserve H.15: bank prime loan rate ----------
try {
  $c = [string](Get-Web "https://www.federalreserve.gov/releases/h15/")
  $hd = [regex]::Match($c, '<thead.*?</thead>', 'Singleline').Value
  $dates = @([regex]::Matches($hd, '(\d{4})(?:<br\s*/?>|\s|&nbsp;)+([A-Z][a-z]{2})(?:<br\s*/?>|\s|&nbsp;)+(\d{1,2})') | ForEach-Object { [datetime]::ParseExact(("{0} {1} {2}" -f $_.Groups[1].Value, $_.Groups[2].Value, $_.Groups[3].Value), "yyyy MMM d", [Globalization.CultureInfo]::InvariantCulture).ToString("yyyy-MM-dd") })
  $row = [regex]::Match($c, 'Bank prime loan.*?</tr>', 'Singleline').Value
  $vals = @([regex]::Matches($row, '&nbsp;([0-9]+\.[0-9]+)&nbsp;') | ForEach-Object { [double]$_.Groups[1].Value })
  if ($vals.Count -lt 2 -or $vals.Count -ne $dates.Count) { throw "prime rate row not read (dates $($dates.Count), values $($vals.Count))" }
  $pts = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $vals.Count; $i++) { $pts.Add([ordered]@{ d = $dates[$i]; v = $vals[$i] }) }
  try {
    $wk = @((Get-Web "https://www.federalreserve.gov/datadownload/Output.aspx?rel=H15&series=8e83f7f17c5cea4d190d85ae6737639f&lastobs=52&from=&to=&filetype=csv&label=include&layout=seriescolumn&type=package") -split "`n" | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2},' })
    $firstDaily = $pts[0].d
    $wp = @(); foreach ($l in ($wk | Select-Object -Last 26)) { $f = $l.Trim() -split ","; if ($f[0] -lt $firstDaily -and $f[2] -match '^\d+(\.\d+)?$') { $wp += [ordered]@{ d = $f[0]; v = [double]$f[2] } } }
    for ($j = $wp.Count - 1; $j -ge 0; $j--) { $pts.Insert(0, $wp[$j]) }
  } catch { }
  Add-Tile "prime" "Prime rate" "%" $pts "Federal Reserve H.15 release (bank prime loan rate)" "The rate banks charge their best borrowers. Moves only when the Fed moves" 2 ""
  Add-Reading $dates[$dates.Count - 1] "Prime rate" $vals[$vals.Count - 1] "Federal Reserve H.15 release (bank prime loan rate)"
  Add-Status "Prime rate" $true "federalreserve.gov"
} catch { Add-Status "Prime rate" $false $_.Exception.Message }

# ---------- Federal Reserve Bank of Cleveland: 10-year real interest rate (model estimate, monthly) ----------
try {
  $cache = Join-Path $Out "cache"; New-Item -ItemType Directory -Force $cache | Out-Null
  $xf = Join-Path $cache "cleveland-inflation-expectations.xlsx"
  $got = $false
  for ($t = 1; $t -le 3 -and -not $got; $t++) { try { Invoke-WebRequest "https://www.clevelandfed.org/-/media/files/webcharts/inflationexpectations/inflation-expectations.xlsx?sc_lang=en" -Headers @{ "User-Agent" = "Mozilla/5.0" } -UseBasicParsing -TimeoutSec 90 -OutFile $xf; $got = $true } catch { Start-Sleep -Seconds 4 } }
  if (-not $got -and -not (Test-Path $xf)) { throw "Cleveland Fed file not reachable" }
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
  $all = New-Object System.Collections.Generic.List[object]
  foreach ($rw in [regex]::Matches($sx, '<row [^>]*>.*?</row>', 'Singleline')) {
    $ca = [regex]::Match($rw.Value, '<c r="A\d+"[^>]*><v>([\d\.]+)</v>'); $cd = [regex]::Match($rw.Value, '<c r="D\d+"[^>]*><v>(-?[\d\.Ee\-]+)</v>')
    if ($ca.Success -and $cd.Success) { $all.Add([ordered]@{ d = ([datetime]"1899-12-30").AddDays([double]$ca.Groups[1].Value).ToString("yyyy-MM-dd"); v = [math]::Round([double]::Parse($cd.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) * 100, 2) }) }
  }
  if ($all.Count -lt 24) { throw "real rate column not read ($($all.Count) rows)" }
  $pts = New-Object System.Collections.Generic.List[object]
  foreach ($x in ($all | Select-Object -Last 60)) { $pts.Add($x) }
  Add-Tile "real10" "10-year real interest rate" "%" $pts "Federal Reserve Bank of Cleveland (model estimate, monthly)" "" 2 "5 years"
  Add-Status "10-year real interest rate" $true "clevelandfed.org"
} catch { Add-Status "10-year real interest rate" $false $_.Exception.Message }

# ---------- New York Fed: Fed funds ----------
try {
  $r = Invoke-RestMethod "https://markets.newyorkfed.org/api/rates/unsecured/effr/last/260.json" -TimeoutSec 40
  $rates = @($r.refRates); [array]::Reverse($rates)
  $pts = New-Object System.Collections.Generic.List[object]
  foreach ($x in $rates) { $pts.Add([ordered]@{ d = $x.effectiveDate; v = [double]$x.percentRate }) }
  Add-Tile "effr" "Fed funds rate (effective)" "%" $pts "New York Fed" "The Fed's overnight rate" 2 "1 year"
  Add-Status "Fed funds rate" $true "New York Fed"
} catch { Add-Status "Fed funds rate" $false $_.Exception.Message }

# ---------- Freddie Mac: 30-year mortgage ----------
try {
  $rows = @((Get-Web "https://www.freddiemac.com/pmms/docs/PMMS_history.csv") | ConvertFrom-Csv | Where-Object { $_.pmms30 -match '^\d' })
  $take = [Math]::Min(52, $rows.Count); $pts = New-Object System.Collections.Generic.List[object]
  for ($i = $rows.Count - $take; $i -lt $rows.Count; $i++) {
    $pts.Add([ordered]@{ d = ([datetime]::Parse($rows[$i].date)).ToString("yyyy-MM-dd"); v = [double]$rows[$i].pmms30 })
  }
  Add-Tile "mort30" "30-year mortgage rate" "%" $pts "Freddie Mac weekly survey" "The cost of buying a home. Weekly" 2 "1 year"
  Add-Status "30-year mortgage rate" $true "Freddie Mac"
} catch { Add-Status "30-year mortgage rate" $false $_.Exception.Message }

# ---------- Shiller PE ----------
$shiller = $null
try {
  $t = (Get-Web "https://www.multpl.com/shiller-pe") -replace '<script.*?</script>', '' -replace '<[^>]+>', ' ' -replace '&nbsp;', ' ' -replace '\s+', ' '
  $m = [regex]::Match($t, 'Current Shiller PE Ratio\s*:\s*([\d.]+)')
  $mean = [regex]::Match($t, 'Mean:\s*([\d.]+)')
  $med = [regex]::Match($t, 'Median:\s*([\d.]+)')
  if (-not $m.Success) { throw "Shiller PE not found on page" }
  $shiller = [ordered]@{ asOf = $now.ToString("yyyy-MM-dd"); value = [double]$m.Groups[1].Value; mean = [double]$mean.Groups[1].Value; median = [double]$med.Groups[1].Value }
  Add-Reading $shiller.asOf "Shiller PE" $shiller.value "multpl.com"
  Add-Status "Shiller PE" $true "multpl.com"
} catch {
  # multpl.com did not answer: keep the last good reading (with its own date) so the Bubble Watch tile does not vanish (23-24 Nov 2026)
  if ($prev -and $prev.shiller) { $shiller = $prev.shiller; Add-Status "Shiller PE" $false ("kept the reading from " + $prev.shiller.asOf + ": " + $_.Exception.Message) $true }
  else { Add-Status "Shiller PE" $false $_.Exception.Message }
}

# ---------- BLS: jobs and prices, last 36 months ----------
$blsSeries = @(
  @("payrolls", "Nonfarm payrolls (thousands)", "CES0000000001"),
  @("unrate", "Unemployment rate (%)", "LNS14000000"),
  @("jolts", "JOLTS job openings (thousands)", "JTS000000000000000JOL"),
  @("cpi", "CPI-U, all items, seasonally adjusted (index)", "CUSR0000SA0")
)
$bls = New-Object System.Collections.Generic.List[object]
foreach ($s in $blsSeries) {
  try {
    $r = Invoke-RestMethod ("https://api.bls.gov/publicAPI/v2/timeseries/data/" + $s[2] + "?startyear=" + ($now.Year - 6) + "&endyear=" + $now.Year) -TimeoutSec 40
    # Without a free key BLS allows 25 requests a day. One daily run uses 6.
    if ($r.status -ne "REQUEST_SUCCEEDED") { throw ("BLS said: " + ($r.message -join " ")) }
    $d = @($r.Results.series[0].data | Where-Object { $_.period -match '^M(0[1-9]|1[0-2])$' })
    if ($d.Count -eq 0) { throw ("No data. " + ($r.message -join " ")) }
    [array]::Reverse($d)
    # BLS prints "-" for a month with no figure. Keep the month with an empty value so the months line up.
    $pts = @($d | ForEach-Object {
      $val = $null
      if ($_.value -match '^-?\d+(\.\d+)?$') { $val = [double]$_.value }
      [ordered]@{ d = ("{0}-{1}" -f $_.year, $_.period.Substring(1)); v = $val }
    })
    $bls.Add([ordered]@{ id = $s[0]; label = $s[1]; points = $pts })
    $withValue = @($pts | Where-Object { $null -ne $_.v })
    $lastThree = $withValue | Select-Object -Last 3
    foreach ($p in $lastThree) { Add-Reading $p.d $s[1] $p.v "Bureau of Labor Statistics" }
    Add-Status $s[1] $true "BLS public API"
  } catch {
    $old = $null
    if ($prev -and $prev.bls) { $old = @($prev.bls | Where-Object { $_.id -eq $s[0] }) | Select-Object -First 1 }
    if ($old) {
      $bls.Add($old)
      Add-Status $s[1] $true ("BLS did not answer, so this shows the last saved data. " + $_.Exception.Message) $true
    } else { Add-Status $s[1] $false $_.Exception.Message }
  }
}

# ---------- Write the readings file, without duplicating a row ----------
$csv = Join-Path $Out "econ-readings.csv"
$have = @{}
if (Test-Path $csv) { Import-Csv $csv | ForEach-Object { $have[($_.ObservationDate + "|" + $_.Indicator)] = $true } }
$new = @($readings | Where-Object { -not $have.ContainsKey($_.ObservationDate + "|" + $_.Indicator) })
if ($new.Count -gt 0) { $new | Export-Csv -Path $csv -NoTypeInformation -Append -Encoding UTF8 }

# ---------- Write data.js for the page ----------
$data = New-Object System.Collections.Specialized.OrderedDictionary
$data.Add("generated", $now.ToString("yyyy-MM-dd HH:mm"))
$data.Add("tiles", [object[]]$tiles.ToArray())
$data.Add("spread", $spread)
$data.Add("shiller", $shiller)
$data.Add("bls", [object[]]$bls.ToArray())
$data.Add("status", [object[]]$status.ToArray())
$json = $data | ConvertTo-Json -Depth 8 -Compress
Set-Content -Path (Join-Path $Out "data.js") -Value ("window.DATA = " + $json + ";") -Encoding UTF8

"Done. Tiles: $($tiles.Count). New reading rows: $($new.Count). Sources failed: $(@($status | Where-Object { -not $_.ok }).Count)."
$status | Where-Object { -not $_.ok } | ForEach-Object { "FAILED: " + $_.name + " :: " + $_.note }
