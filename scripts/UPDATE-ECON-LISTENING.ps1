# UPDATE-ECON-LISTENING.ps1
# Reads the public YouTube upload feeds (no key needed) and the podcast feeds and writes listening.js
# for the "Listening To" section of the dashboard. Takes a few seconds, so RUN-ECON-RELEASE.ps1 runs it every 5 minutes.
# Morning Filter pick = newest Morningstar upload whose title ends "I <Month d, yyyy>" (the Monday list; fixed 16 Nov 2026, the title no longer always says "Undervalued").
# Eisman pick = newest "The Weekly Wrap" upload (changed 16 Nov 2026 at the owner's word: the Ep 84 interview was taped 4 Nov and posted 16 Nov, the Weekly Wrap is the most current).
# A show is NEVER removed. A run replaces a show's row only when it found a pick; when a lookup fails or finds no match,
# the row from the last run stays. the owner, 9 November 2026: "you don't remove them, you only update them", and nothing is removed after she has listened.

$Out = "$env:ECON_OUT"
$h = @{ 'User-Agent' = 'Mozilla/5.0' }
$tz = [TimeZoneInfo]::FindSystemTimeZoneById("Central Standard Time")

$shows = @(
  @{ show = "Monday Morning Filter (Morningstar)"; what = "Latest undervalued stocks list"; channel = "UChub1tZZuWn9YYHJZZYTbMg"; page = "https://www.youtube.com/@MorningstarInc/videos"; match = "I (January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}\s*$" },
  @{ show = "The Real Eisman Playbook (Steve Eisman)"; what = "Latest episode"; channel = "UCzQ2FFVe7m8yIgzXMZtlSjg"; page = "https://www.youtube.com/@RealEismanPlaybook/videos"; match = "The Weekly Wrap" },
  @{ show = "ARC Energy Research Institute podcast"; what = "Latest episode"; rss = "https://www.arcenergyinstitute.com/section/podcasts/feed/"; page = "https://www.arcenergyinstitute.com/section/podcasts/" },
  @{ show = "The Investor's Podcast (We Study Billionaires)"; what = "Latest episode"; rss = "https://feeds.megaphone.fm/PPLLC8974708240"; page = "https://podcasts.apple.com/us/podcast/the-investors-podcast-we-study-billionaires-the/id928933489" }
)

$items = @(); $failed = 0
foreach ($s in $shows) {
  try {
    if ($s.rss) {
      $rr = Invoke-WebRequest -UseBasicParsing $s.rss -Headers $h -TimeoutSec 30
      $rx = [xml]([Text.Encoding]::UTF8.GetString($rr.RawContentStream.ToArray()).TrimStart([char]0xFEFF))
      $it = $rx.rss.channel.item | Select-Object -First 1
      if ($it) { $utc = [DateTimeOffset]::Parse([string]$it.pubDate).UtcDateTime; $ct = [TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz); $items += [ordered]@{ show = $s.show; what = $s.what; title = [string]$it.title; url = $(if ([string]$it.link) { [string]$it.link } else { $s.page }); page = $s.page; published = $utc.ToString("yyyy-MM-ddTHH:mm:ssZ"); central = $ct.ToString("yyyy-MM-dd HH:mm") } } else { $failed++ }
      continue
    }
    $resp = Invoke-WebRequest -UseBasicParsing ("https://www.youtube.com/feeds/videos.xml?channel_id=" + $s.channel) -Headers $h -TimeoutSec 30
    $ms = New-Object IO.MemoryStream; $resp.RawContentStream.Position = 0; $resp.RawContentStream.CopyTo($ms)
    $raw = [Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
    $x = [xml]$raw
    $pick = $null
    foreach ($e in $x.feed.entry) {
      $url = $e.link.href
      if ($url -match '/shorts/') { continue }
      if ($s.match -and ($e.title -notmatch $s.match)) { continue }
      $pick = $e; break
    }
    if ($pick) {
      $utc = [DateTimeOffset]::Parse($pick.published).UtcDateTime
      $ct = [TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
      $items += [ordered]@{ show = $s.show; what = $s.what; title = [string]$pick.title; url = [string]$pick.link.href; page = $s.page; published = $utc.ToString("yyyy-MM-ddTHH:mm:ssZ"); central = $ct.ToString("yyyy-MM-dd HH:mm") }
    } else { $failed++ }
  } catch { $failed++ }
}

# the rows from the last run, by show
$prev = @{}
try {
  $oldText = [IO.File]::ReadAllText((Join-Path $Out "listening.js"))
  $oj = ($oldText -replace '^\s*window\.LISTEN\s*=\s*', '' -replace ';\s*$', '') | ConvertFrom-Json
  foreach ($o in @($oj.items)) { $prev[[string]$o.show] = $o }
} catch {}

# a new pick replaces the row; no new pick keeps the old row
$final = @()
foreach ($s in $shows) {
  $name = $s.show
  $n = $null
  foreach ($c in $items) { if ($c.show -eq $name) { $n = $c; break } }
  if ($n) { $final += $n }
  elseif ($prev.ContainsKey($name)) {
    $o = $prev[$name]
    $final += [ordered]@{ show = [string]$o.show; what = [string]$o.what; title = [string]$o.title; url = [string]$o.url; page = [string]$o.page; published = [string]$o.published; central = [string]$o.central }
  }
}

if ($final.Count -gt 0) {
  $json = ([ordered]@{ generated = (Get-Date).ToString("yyyy-MM-dd HH:mm"); items = $final } | ConvertTo-Json -Depth 5 -Compress)
  [IO.File]::WriteAllText((Join-Path $Out "listening.js"), "window.LISTEN = " + $json + ";", (New-Object Text.UTF8Encoding($false)))
}
"UPDATE-ECON-LISTENING.ps1: Done. Shows found now: $($items.Count) of $($shows.Count). Rows kept on the page: $($final.Count). Failed: $failed."
if ($failed -gt 0) { "UPDATE-ECON-LISTENING.ps1: FAILED to read $failed of $($shows.Count) shows" }
