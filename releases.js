// Upcoming market-moving releases, dates and hours read on 6 Nov 2026 from the agencies' own calendars:
// BLS release calendar (jobs, CPI, PPI, JOLTS), BEA schedule (GDP, PCE), Census indicator calendar (retail sales, housing starts),
// ISM release calendar, S&P Global PMI calendar, EIA Weekly Petroleum Status Report schedule (eia.gov/petroleum/supply/weekly/schedule.php: Wednesdays 10:30 AM ET = 9:30 CT, except holiday weeks), University of Michigan site, Conference Board LEI release, Federal Reserve statements.
// at = Central time, 24h. ok = true when the hour was read from the source. Not yet verified: jobless claims hour, Michigan final date/hour, Dallas Fed Texas Manufacturing date.
window.RELEASES = [
  { date: "2026-11-06", at: "07:30", ok: true,  name: "Jobs report (payrolls, unemployment)", src: "BLS", url: "https://www.bls.gov/news.release/empsit.nr0.htm" },
  { date: "2026-11-06", at: "09:00", ok: true,  name: "Michigan consumer sentiment (preliminary)", src: "University of Michigan", url: "https://www.sca.isr.umich.edu/" },
  { date: "2026-11-10", at: "07:30", ok: true,  name: "CPI (consumer prices)", src: "BLS", url: "https://www.bls.gov/news.release/cpi.htm" },
  { date: "2026-11-12", at: "07:30", ok: false, name: "Jobless claims (weekly, Thursdays)", src: "FRED", url: "https://www.dol.gov/ui/data.pdf" },
  { date: "2026-11-12", at: "11:00", ok: true,  name: "EIA crude oil stocks", src: "EIA", url: "https://www.eia.gov/petroleum/supply/weekly/" },
  { date: "2026-11-13", at: "07:30", ok: true,  name: "PPI (producer prices)", src: "BLS", url: "https://www.bls.gov/news.release/ppi.nr0.htm" },
  { date: "2026-11-17", at: "07:30", ok: true,  name: "Retail sales", src: "Census", url: "https://www.census.gov/retail/marts/www/marts_current.pdf" },
  { date: "2026-11-18", at: "07:30", ok: true,  name: "Housing starts and permits", src: "Census", url: "https://www.census.gov/construction/nrc/pdf/newresconst.pdf" },
  { date: "2026-11-18", at: "09:30", ok: true,  name: "EIA crude oil stocks", src: "EIA", url: "https://www.eia.gov/petroleum/supply/weekly/" },
  { date: "2026-11-19", at: "09:00", ok: true,  name: "Conference Board Leading Economic Index", src: "Conference Board", url: "https://www.conference-board.org/topics/us-leading-indicators" },
  { date: "2026-11-20", at: "09:00", ok: false, name: "Michigan consumer sentiment (final)", src: "FRED", url: "https://www.sca.isr.umich.edu/" },
  { date: "2026-11-23", at: "08:45", ok: true,  name: "S&P Global flash US PMI", src: "S&P Global", url: "https://www.pmi.spglobal.com/Public/Release/PressReleases" },
  { date: "2026-11-25", at: "07:30", ok: true,  name: "PCE (personal spending)", src: "BEA", url: "https://www.bea.gov/data/income-saving/personal-income" },
  { date: "2026-11-25", at: "07:30", ok: true,  name: "GDP (second estimate)", src: "BEA", url: "https://www.bea.gov/data/gdp/gross-domestic-product" },
  { date: "2026-11-25", at: "09:30", ok: true,  name: "EIA crude oil stocks", src: "EIA", url: "https://www.eia.gov/petroleum/supply/weekly/" },
  { date: "2026-12-01", at: "08:45", ok: true,  name: "S&P Global US Manufacturing PMI", src: "S&P Global", url: "https://www.pmi.spglobal.com/Public/Release/PressReleases" },
  { date: "2026-12-01", at: "09:00", ok: true,  name: "JOLTS job openings", src: "BLS", url: "https://www.bls.gov/news.release/jolts.htm" },
  { date: "2026-12-01", at: "09:00", ok: true,  name: "ISM Manufacturing PMI", src: "ISM", url: "https://www.prnewswire.com/news/institute-for-supply-management/" },
  { date: "2026-12-02", at: "09:30", ok: false, name: "EIA crude oil stocks", src: "EIA", url: "https://www.eia.gov/petroleum/supply/weekly/" },
  { date: "2026-12-03", at: "08:45", ok: true,  name: "S&P Global US Services PMI", src: "S&P Global", url: "https://www.pmi.spglobal.com/Public/Release/PressReleases" },
  { date: "2026-12-03", at: "09:00", ok: true,  name: "ISM Services PMI", src: "ISM", url: "https://www.prnewswire.com/news/institute-for-supply-management/" },
  { date: "2026-12-04", at: "07:30", ok: true,  name: "Jobs report (payrolls, unemployment)", src: "BLS", url: "https://www.bls.gov/news.release/empsit.nr0.htm" },
  { date: "2026-12-09", at: "09:30", ok: false, name: "EIA crude oil stocks", src: "EIA", url: "https://www.eia.gov/petroleum/supply/weekly/" },
  { date: "2026-12-09", at: "13:00", ok: true,  name: "Fed rate decision (FOMC, Dec 8-9)", src: "Federal Reserve", url: "https://www.federalreserve.gov/newsevents/pressreleases.htm" },
  { date: "2026-12-16", at: "09:30", ok: false, name: "EIA crude oil stocks", src: "EIA", url: "https://www.eia.gov/petroleum/supply/weekly/" },
  { date: "2026-12-23", at: "09:30", ok: false, name: "EIA crude oil stocks", src: "EIA", url: "https://www.eia.gov/petroleum/supply/weekly/" },
  { date: "2026-12-30", at: "09:30", ok: false, name: "EIA crude oil stocks", src: "EIA", url: "https://www.eia.gov/petroleum/supply/weekly/" }
];
