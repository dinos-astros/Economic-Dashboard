# UPDATE-ECON-SENTIMENT.ps1
# Market Sentiment for the dashboard (built 24 November 2026, the owner's request: AAII Investor Sentiment Survey and the Cboe put/call ratio).
# AAII: the weekly survey results from AAII's own Insights articles (insights.aaii.com), which carry the bullish, neutral and bearish percentages, the spread and the historical averages.
# Cboe: the daily put/call ratios from Cboe's own market statistics files (cdn.cboe.com), total, equity and index.
# Writes sentiment.js. History is kept in the file itself: new AAII weeks and new Cboe days are added, nothing is thrown away, and a source that does not answer keeps what is already there.

$Out = "$env:ECON_OUT"
$ua = @{ 'User-Agent' = 'Mozilla/5.0' }
$file = Join-Path $Out "sentiment.js"
$prev = $null
if (Test-Path $file) { try { $prev = ((Get-Content $file -Raw) -replace '^window\.SENTIMENT = ', '' -replace ';\s*$', '') | ConvertFrom-Json } catch { $prev = $null } }
$maxAaiiWeeks = 60      # about a year plus a few weeks
$maxCboeDays = 262      # about 12 months of trading days
$note = @()

function Get-Page($u) {
  $c = (Invoke-WebRequest -UseBasicParsing $u -Headers $ua -TimeoutSec 40).Content
  if ($c -is [byte[]]) { $c = [Text.Encoding]::UTF8.GetString($c) }
  return [string]$c
}
function Num($s) { return [double]::Parse($s, [Globalization.CultureInfo]::InvariantCulture) }

# ---------- AAII ----------
function Parse-Aaii($html) {
  $t = [System.Net.WebUtility]::HtmlDecode(($html -replace '(?s)<script.*?</script>', ' ' -replace '(?s)<style.*?</style>', ' ' -replace '<[^>]+>', ' ')) -replace '\s+', ' '
  $b = [regex]::Match($t, 'Bullish sentiment,[^%]*?to\s+(\d+\.\d)%[^%]*?historical average of (\d+\.\d)%')
  $n = [regex]::Match($t, 'Neutral sentiment,[^%]*?to\s+(\d+\.\d)%[^%]*?historical average of (\d+\.\d)%')
  $r = [regex]::Match($t, 'Bearish sentiment,[^%]*?to\s+(\d+\.\d)%[^%]*?historical average of (\d+\.\d)%')
  $s = [regex]::Match($t, 'bull-bear spread[^%]*?to\s+([\u2013\u2212-]?)\s*(\d+\.\d)%[^%]*?historical average of (\d+\.\d)%')
  if (-not ($b.Success -and $n.Success -and $r.Success)) { return $null }
  $spread = $null; $avgS = $null
  if ($s.Success) { $spread = Num $s.Groups[2].Value; if ($s.Groups[1].Value -ne '') { $spread = -$spread }; $avgS = Num $s.Groups[3].Value }
  return [ordered]@{ bull = Num $b.Groups[1].Value; neu = Num $n.Groups[1].Value; bear = Num $r.Groups[1].Value; spread = $spread; avgBull = Num $b.Groups[2].Value; avgNeu = Num $n.Groups[2].Value; avgBear = Num $r.Groups[2].Value; avgSpread = $avgS }
}
function Post-Date($html) {
  $m = [regex]::Match($html, '"datePublished":"(\d{4}-\d{2}-\d{2})')
  if (-not $m.Success) { $m = [regex]::Match($html, 'article:published_time" content="(\d{4}-\d{2}-\d{2})') }
  if ($m.Success) { return $m.Groups[1].Value } else { return $null }
}
$aaii = @(); if ($prev -and $prev.aaii) { $aaii = @($prev.aaii) }
$have = @{}; foreach ($w in $aaii) { $have[$w.d] = $true }
try {
  $sm = Get-Page "https://insights.aaii.com/sitemap.xml"
  $urls = @([regex]::Matches($sm, '<loc>([^<]*/p/aaii-sentiment-survey[^<]*)</loc>') | ForEach-Object { $_.Groups[1].Value })
  if ($urls.Count -eq 0) { throw "no AAII survey articles in the sitemap" }
  $look = if ($aaii.Count -eq 0) { [math]::Min($urls.Count, $maxAaiiWeeks) } else { 4 }   # first run reads a year back, later runs only the newest four
  $added = 0
  foreach ($u in ($urls | Select-Object -First $look)) {
    try {
      $html = Get-Page $u
      $d = Post-Date $html; if (-not $d) { continue }
      $pd = [datetime]::ParseExact($d, 'yyyy-MM-dd', $null); while ($pd.DayOfWeek -ne 'Wednesday') { $pd = $pd.AddDays(-1) }; $d = $pd.ToString('yyyy-MM-dd')   # AAII's survey week ends on a Wednesday; the article is posted on or after it
      if ($have.ContainsKey($d)) { continue }
      $p = Parse-Aaii $html; if (-not $p) { continue }
      $row = [ordered]@{ d = $d }; foreach ($k in $p.Keys) { $row[$k] = $p[$k] }
      $aaii += [pscustomobject]$row; $have[$d] = $true; $added++
    } catch { $note += "AAII article skipped: $u" }
  }
  "AAII: $added new week(s), $($aaii.Count) in the file"
} catch { $note += "AAII FAILED: " + $_.Exception.Message; "AAII FAILED: " + $_.Exception.Message }
$aaii = @($aaii | Sort-Object d | Select-Object -Last $maxAaiiWeeks)

# ---------- Cboe put/call ----------
$cboe = @(); if ($prev -and $prev.cboe) { $cboe = @($prev.cboe) }
$haveC = @{}; foreach ($c in $cboe) { $haveC[$c.d] = $true }
$start = (Get-Date).Date
$days = if ($cboe.Count -eq 0) { 400 } else { 10 }   # first run reads back more than a year of calendar days, later runs the last ten
$addedC = 0; $failC = 0
for ($i = 0; $i -lt $days; $i++) {
  $dt = $start.AddDays(-$i)
  if ($dt.DayOfWeek -eq 'Saturday' -or $dt.DayOfWeek -eq 'Sunday') { continue }
  $ds = $dt.ToString('yyyy-MM-dd'); if ($haveC.ContainsKey($ds)) { continue }
  try {
    $j = (Get-Page "https://cdn.cboe.com/data/us/options/market_statistics/daily/${ds}_daily_options") | ConvertFrom-Json
    $tot = ($j.ratios | Where-Object { $_.name -eq 'TOTAL PUT/CALL RATIO' } | Select-Object -First 1).value
    $eq = ($j.ratios | Where-Object { $_.name -eq 'EQUITY PUT/CALL RATIO' } | Select-Object -First 1).value
    $ix = ($j.ratios | Where-Object { $_.name -eq 'INDEX PUT/CALL RATIO' } | Select-Object -First 1).value
    if ($tot -and $eq) { $cboe += [pscustomobject][ordered]@{ d = $ds; t = (Num $tot); e = (Num $eq); i = $(if ($ix) { Num $ix } else { $null }) }; $haveC[$ds] = $true; $addedC++ }
  } catch { if ($_.Exception.Message -notmatch '404|Not Found|403|Forbidden') { $failC++ } }   # holidays have no file
}
"Cboe: $addedC new day(s), $($cboe.Count) in the file" + $(if ($failC) { ", $failC request(s) failed" })
if ($failC -gt 5) { $note += "Cboe: $failC requests failed" }
$cboe = @($cboe | Sort-Object d | Select-Object -Last $maxCboeDays)

# ---------- Write sentiment.js only when something changed ----------
$obj = [ordered]@{ aaii = [object[]]$aaii; cboe = [object[]]$cboe }
$text = "window.SENTIMENT = " + ($obj | ConvertTo-Json -Depth 5 -Compress) + ";"
$old = $null; if (Test-Path $file) { $old = [IO.File]::ReadAllText($file) }
if ($aaii.Count -eq 0 -and $cboe.Count -eq 0) { "SENTIMENT: FAILED nothing read, file left alone"; exit }
if ($old -cne $text) { [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($false))); "UPDATE-ECON-SENTIMENT.ps1: updated, AAII $($aaii[-1].d), Cboe $($cboe[-1].d)" }
else { "UPDATE-ECON-SENTIMENT.ps1: no change" }
