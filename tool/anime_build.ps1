# Drives Codex through design/anime/steps/*.md, one step at a time, on branch `anime`.
# Per step: pack context -> codex (bridge mode) -> apply files -> gates -> commit, or resume
# Codex with the failures (3 tries) and stop. Needs no Claude; the log is for the monitor.
#   pwsh -File tool/anime_build.ps1 [-From 1] [-To 8]
param([int]$From = 1, [int]$To = 99)
$ErrorActionPreference = 'Continue'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$root = (Resolve-Path "$PSScriptRoot/..").Path
Set-Location $root
$skill = "$HOME/.claude/skills/build-mobile/scripts"
$runs = "$root/build/anime-runs"
New-Item -ItemType Directory -Force "$runs/ref" | Out-Null
$log = "$runs/build.log"
function Log($m) { $line = "$(Get-Date -Format 'HH:mm:ss') $m"; Add-Content $log $line; Write-Host $line }
function Stop-Build($m) {
  Log "STOP $m"
  Set-Content "$root/design/anime/STATUS.md" "# Anime build status`n`nStopped $(Get-Date -Format s): $m`n`nLog: build/anime-runs/build.log. Resume: pwsh -File tool/anime_build.ps1 -From <step>`n"
  git add design/anime/STATUS.md; git commit -q -m "anime: build stopped ($m)"
  exit 1
}

if ((git branch --show-current) -ne 'anime') { Log 'STOP not on branch anime'; exit 1 }

# Reference code from repo B (Shineii86/MiruroAPI, MIT).
foreach ($f in 'src/helpers/pipe.js', 'src/routes/apiRoutes.js', 'api/proxy.js', 'src/helpers/anilist.js') {
  $out = "$runs/ref/" + ($f -replace '/', '_')
  if (-not (Test-Path $out)) { curl.exe -sL "https://raw.githubusercontent.com/Shineii86/MiruroAPI/main/$f" -o $out }
}

function GateHits {
  $h = @{}
  python "$skill/gates.py" . 2>&1 | ForEach-Object {
    if ($_ -match '^\s*(\S+?):\d+:') { $h[$Matches[1]] = 1 + [int]$h[$Matches[1]] }
  }
  $h
}
$baseline = GateHits

function Run-Gates([string]$check) {
  $fail = @()
  $a = flutter analyze 2>&1 | Out-String
  if ($a -notmatch 'No issues found!') { $fail += "flutter analyze:`n$($a.Trim())" }
  $t = flutter test 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { $fail += "flutter test (last 80 lines):`n" + (($t -split "`n") | Select-Object -Last 80 | Out-String) }
  else { Log ("  tests: " + (($t -split "`n") | Where-Object { $_ -match 'All tests passed|\+\d+' } | Select-Object -Last 1)) }
  $now = GateHits
  foreach ($k in $now.Keys) {
    if ([int]$now[$k] -gt [int]$baseline[$k]) { $fail += "design gates: $k has $($now[$k]) hits (baseline $([int]$baseline[$k])):`n" + (python "$skill/gates.py" . 2>&1 | Select-String -SimpleMatch $k | Out-String) }
  }
  if ($check) {
    $c = pwsh -NoProfile -Command $check 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { $fail += "step check ``$check`` failed:`n" + (($c -split "`n") | Select-Object -Last 60 | Out-String) }
  }
  $fail -join "`n`n"
}

$common = @'
You are Codex, building the Anime feature of Flick (Flutter 3.41 / Dart 3.11 Android app) on branch `anime`.
The full plan is design/anime.md; the hard UI rules are design/RULES.md; the project handoff is CLAUDE.md. All are in <stdin>,
with every file you need for THIS step, plus reference code from Shineii86/MiruroAPI (MIT) under ref/.
You cannot run commands. Implement ONLY the step below. Rules:
- No new packages (deps: http, shared_preferences, flutter_secure_storage, media_kit, background_downloader, path_provider).
- Match the surrounding code style and comment density. Do not reformat existing code; only lib/screens/player.dart is dart-formatted.
- UI: Afterglow tokens only (FlickTokens, FlickText, context.flick, monoStyle, streamMonoStyle); no raw colours, showDialog, SnackBar or CircularProgressIndicator; sheets via showFlickSheet; skeletons not spinners; 48 dp targets; honour MediaQuery.disableAnimationsOf.
- Every non-trivial pure function gets a test. Never weaken or delete an existing test.
- A port of MiruroAPI code carries a one-line credit comment: // Ported from Shineii86/MiruroAPI (MIT).
Reply with every created or changed file COMPLETE, as
=== FILE: <repo-relative path> ===
<full content>
=== END FILE ===
and nothing else after the files except one line `NOTES: <decisions the reviewer should check>`.
'@

$steps = Get-ChildItem "$root/design/anime/steps/*.md" | Sort-Object Name
foreach ($s in $steps) {
  $n = [int]($s.BaseName -split '-')[0]
  if ($n -lt $From) { continue }
  if ($n -gt $To) { Log "STOP after -To $To"; exit 0 }
  $body = Get-Content $s.FullName -Raw
  $files = if ($body -match '(?m)^files:\s*(.+)$') { $Matches[1].Trim() -split '\s+' } else { @() }
  $check = if ($body -match '(?m)^check:\s*(.+)$') { $Matches[1].Trim() } else { '' }
  Log "STEP $($s.BaseName) start"
  $packed = python "$skill/codex_files.py" pack . design/anime.md design/RULES.md CLAUDE.md @($files | Where-Object { Test-Path $_ }) | Out-String
  $refs = Get-ChildItem "$runs/ref" | ForEach-Object { "=== FILE: ref/$($_.Name) ===`n$(Get-Content $_.FullName -Raw)`n=== END FILE ===`n" } | Out-String
  $prompt = "$common`n`n# STEP`n$body"
  $reply = "$runs/$($s.BaseName).md"
  $out = ($prompt + "`n`n" + $packed + $refs) | codex exec -s read-only -o $reply - 2>&1 | Out-String
  $sid = if ($out -match 'session id:\s*([0-9a-f-]{36})') { $Matches[1] } else { '' }
  Log "  codex session $sid"
  $ok = $false
  for ($try = 1; $try -le 3; $try++) {
    $applied = python "$skill/codex_files.py" apply . $reply 2>&1 | Out-String
    Log ("  try $try applied: " + (($applied -split "`n" | Where-Object { $_ }) -join ', '))
    $fail = if ($applied -match 'no FILE blocks|refusing') { "Your reply could not be applied: $applied" } else { Run-Gates $check }
    if (-not $fail) { $ok = $true; break }
    Log "  try $try FAILED: $((($fail -split "`n") | Select-Object -First 3) -join ' | ')"
    if ($try -eq 3 -or -not $sid) { break }
    $fix = "The gates failed after applying your files. Fix every failure. Reply again with every changed file COMPLETE in the same FILE-block format.`n`n$fail"
    $out = $fix | codex exec -s read-only -o $reply resume $sid - 2>&1 | Out-String
  }
  if (-not $ok) { git checkout -q -- .; git clean -fdq -e build/; Stop-Build "step $($s.BaseName) failed 3 tries; reply in $reply" }
  $notes = (Select-String -Path $reply -Pattern '^NOTES:' | Select-Object -Last 1).Line
  git add -A; git commit -q -m "anime: step $($s.BaseName)" -m "Built by Codex via tool/anime_build.ps1. $notes"
  Log "STEP $($s.BaseName) DONE $(git rev-parse --short HEAD) $notes"
}
Set-Content "$root/design/anime/STATUS.md" "# Anime build status`n`nAll steps done $(Get-Date -Format s). Owed: device spike, mobile-qa-critic on A1-A3, fresh review, device acceptance.`n"
git add design/anime/STATUS.md; git commit -q -m "anime: all scripted steps done"
Log 'ALL DONE'
