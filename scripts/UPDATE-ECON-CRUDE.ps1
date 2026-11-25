# UPDATE-ECON-CRUDE.ps1
# Weekly US commercial crude oil stocks (excluding the Strategic Petroleum Reserve) from the U.S. Energy Information Administration,
# series WCESTUS1, read from the EIA's own history page. Writes crude.js: every week since 2020 in million barrels.
# The page builds the current year against the 5-year range (maximum, minimum, average) from these weeks.
# EIA publishes new weekly stocks on Wednesdays, so the daily run picks up each new week.

$Out = "$env:ECON_OUT"
$h = @{ 'User-Agent' = 'Mozilla/5.0' }
$url = 'https://www.eia.gov/dnav/pet/hist/LeafHandler.ashx?n=PET&s=WCESTUS1&f=W'
$mon = @{ Jan = 1; Feb = 2; Mar = 3; Apr = 4; May = 5; Jun = 6; Jul = 7; Aug = 8; Sep = 9; Oct = 10; Nov = 11; Dec = 12 }
try {
  $html = (Invoke-WebRequest -UseBasicParsing $url -Headers $h -TimeoutSec 60).Content
  $t = [regex]::Replace($html, '(?s)<script.*?</script>|<style.*?</style>', ' ')
  $t = [regex]::Replace($t, '<[^>]+>', ' ')
  $t = $t -replace '&nbsp;', ' '
  $t = [regex]::Replace($t, '\s+', ' ')
  $weeks = New-Object System.Collections.Generic.List[object]
  $year = 0
  foreach ($m in [regex]::Matches($t, '(\d{4})-([A-Z][a-z]{2})|(\d{2})/(\d{2}) ([\d,]{6,9})')) {
    if ($m.Groups[1].Success) { $year = [int]$m.Groups[1].Value; $ym = $mon[$m.Groups[2].Value]; continue }
    if ($year -lt 2020) { continue }
    $mm = [int]$m.Groups[3].Value; $dd = [int]$m.Groups[4].Value
    $v = [double](($m.Groups[5].Value) -replace ',', '')
    # A week's date can fall in the next month's row heading only at year ends; the heading year is the calendar year of the week
    $weeks.Add([ordered]@{ d = ("{0}-{1:00}-{2:00}" -f $year, $mm, $dd); v = [math]::Round($v / 1000, 3) })
  }
  if ($weeks.Count -lt 300) { throw "Only $($weeks.Count) weeks found" }
  $sorted = @($weeks | Sort-Object { $_.d })
  # only write crude.js when the weekly numbers changed, so the website is not sent a new file every hour just for the timestamp
  $weeksJson = ConvertTo-Json -InputObject @($sorted) -Depth 5 -Compress
  $oldFile = Join-Path $Out "crude.js"; $oldText = $null; if (Test-Path $oldFile) { $oldText = [IO.File]::ReadAllText($oldFile) }
  if ($oldText -and $oldText.Contains('"weeks":' + $weeksJson)) { "UPDATE-ECON-CRUDE.ps1: no change, latest $($sorted[-1].d) $($sorted[-1].v) million barrels."; return }
  $json = ([ordered]@{ generated = (Get-Date).ToString("yyyy-MM-dd HH:mm"); source = "U.S. Energy Information Administration, weekly U.S. ending stocks of crude oil excluding SPR (WCESTUS1)"; sourceUrl = $url; weeks = $sorted } | ConvertTo-Json -Depth 5 -Compress)
  [IO.File]::WriteAllText((Join-Path $Out "crude.js"), "window.CRUDE = " + $json + ";", (New-Object Text.UTF8Encoding($false)))
  "UPDATE-ECON-CRUDE.ps1: Done. Weeks: $($sorted.Count), latest $($sorted[-1].d) $($sorted[-1].v) million barrels."
} catch { "UPDATE-ECON-CRUDE.ps1: FAILED: " + $_.Exception.Message }
# the EIA publishes a new week every Wednesday for the week ending the Friday before: 13 days or more behind means a release was missed (24 Nov 2026)
try { $cj = ((Get-Content (Join-Path $Out "crude.js") -Raw) -replace '^window\.CRUDE = ', '' -replace ';\s*$', '') | ConvertFrom-Json; $age = [int]((Get-Date).Date - [datetime]$cj.weeks[-1].d).TotalDays; if ($age -gt 13) { "UPDATE-ECON-CRUDE.ps1: FAILED latest week $($cj.weeks[-1].d) is $age days old" } } catch { "UPDATE-ECON-CRUDE.ps1: FAILED cannot read crude.js: " + $_.Exception.Message }
