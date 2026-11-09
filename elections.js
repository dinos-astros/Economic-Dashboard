// National elections for the dashboard. Written 6 Nov 2026. Dates read from the sources named in each row (no Wikipedia).
// last = when it was last held. date = exact day of the next one, or null when no day is set yet. when = what the page shows in the Next election column.
// srcs = [text, url] pairs shown in Sources and checks. Hand-maintained: update when a date is set or an election is called early.
window.ELECTIONS = [
  { country: "USA", what: "President and Vice President", last: "Tue 5 Nov 2024", date: "2028-11-07", when: "Tue 7 Nov 2028",
    srcs: [["National Archives, 2024 Electoral College results", "https://www.archives.gov/electoral-college/2024"], ["USA.gov, presidential election process", "https://www.usa.gov/presidential-election-process"]] },
  { country: "Canada", what: "House of Commons (the Prime Minister follows from it)", last: "Mon 28 Apr 2025", date: "2029-10-15", when: "Mon 15 Oct 2029, sooner if called early",
    srcs: [["Elections Canada, 45th General Election", "https://www.elections.ca/content.aspx?section=ele&document=index&dir=pas%2F45ge&lang=e"], ["Before You Vote (Elections Canada)", "https://www.beforeyouvote.ca/"]] },
  { country: "UK", what: "General election (Prime Minister follows from it)", last: "Thu 4 Jul 2024", date: "2029-08-15", when: "By 15 Aug 2029, sooner if called early",
    srcs: [["House of Commons Library, General election 2024 results", "https://commonslibrary.parliament.uk/research-briefings/cbp-10009/"], ["East Suffolk Council, UK Parliamentary general elections", "https://www.eastsuffolk.gov.uk/elections-and-voting/elections-and-voting/election-types/uk-parliamentary-general-elections"]] },
  { country: "Germany", what: "Federal President, voted by the Federal Convention", last: "Sun 13 Feb 2022", date: "2027-01-30", when: "Sat 30 Jan 2027",
    srcs: [["Deutscher Bundestag, Bundesversammlung", "https://www.bundestag.de/bundesversammlung"]] },
  { country: "Germany", what: "Bundestag (the Chancellor follows from it)", last: "Sun 23 Feb 2025", date: "2029-01-26", when: "Between 26 Jan and 25 Mar 2029, date not set",
    srcs: [["Die Bundeswahlleiterin, Bundestagswahl 2025", "https://www.bundeswahlleiterin.de/bundestagswahlen/2025.html"], ["Die Bundeswahlleiterin, Bundestagswahl 2029", "https://www.bundeswahlleiterin.de/bundestagswahlen/2029.html"]] },
  { country: "Japan", what: "House of Councillors, half the seats (Prime Minister is chosen by the Diet)", last: "Sun 20 Jul 2025", date: "2028-07-25", when: "Terms end 25 Jul 2028, date not set",
    srcs: [["Shiga Prefecture, 27th House of Councillors election", "https://www.pref.shiga.lg.jp/senkyo/14302.html"], ["Gunma Prefecture election commission, term end dates", "https://www.pref.gunma.jp/page/14566.html"], ["Constitution of Japan, Article 46", "https://www.japaneselawtranslation.go.jp/en/laws/view/174"]] },
  { country: "Japan", what: "House of Representatives", last: "Sun 8 Feb 2026", date: null, when: "Four-year term, so 2030, sooner if dissolved",
    srcs: [["Ministry of Internal Affairs and Communications, 2026 results", "https://www.soumu.go.jp/main_content/001055230.pdf"], ["Constitution of Japan, Article 45", "https://www.japaneselawtranslation.go.jp/en/laws/view/174"]] },
  { country: "China", what: "National People's Congress elects the President", last: "Fri 10 Mar 2023", date: null, when: "March 2028, date not announced",
    srcs: [["Xinhua, Xi elected president 10 Mar 2023", "https://english.www.gov.cn/news/topnews/202303/10/content_WS640a9f49c6d0a757729e7ee1.html"], ["Government of China, Constitution of the People's Republic of China (Article 60, five-year term)", "https://english.www.gov.cn/archive/lawsregulations/201911/20/content_WS5ed8856ec6d0b3f0e9499913.html"]] }
];