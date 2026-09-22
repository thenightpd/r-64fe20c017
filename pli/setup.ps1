# =====================================================
#  유튜브 플리 자동화 챌린지 — 설치 도우미 (윈도우)
#
#  쓰는 법 (설명서의 복사 버튼이 알아서 골라 줍니다):
#    클로드 길 :  irm https://raw.githubusercontent.com/KIMYOUNGIL21/r-64fe20c017/main/pli/setup.ps1 | iex
#    코덱스 길 :  $env:PLI_AI='codex'; irm https://raw.githubusercontent.com/KIMYOUNGIL21/r-64fe20c017/main/pli/setup.ps1 | iex
#
#  하는 일: 필요한 것을 "처음에 전부" 설치한다.
#    Git · Python · ffmpeg · Node.js · Chrome · (클로드코드 또는 Codex) · Orca
#    + 채널 분석용 파이썬 패키지
#    + C:\플리공장 폴더와 재료/완성/기록 만들기
#    + 다운로드 폴더의 셋팅코드 zip 풀어 넣기
#    + 수노용 Playwright 미리 받아 두기
#    마지막에 자가진단 표를 보여주고 로그인 창을 연다.
#
#  여러 번 실행해도 안전합니다 (이미 된 것은 건너뜁니다).
# =====================================================

& {
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'   # winget/다운로드 진행바가 화면을 어지럽히지 않게

# ── 고른 AI (환경변수로 넘어온다. 없으면 클로드) ──
$AI = if ($env:PLI_AI -eq 'codex') { 'codex' } else { 'claude' }
$AI이름 = if ($AI -eq 'codex') { 'Codex' } else { '클로드코드' }
$AI실행모드 = $env:PLI_NONINTERACTIVE -eq '1'

$공장 = 'C:\플리공장'
$패키지이름 = '플리공장_셋팅코드.zip'
$패키지SHA256 = '6232E3344E5AB9A5B9F9D2C7E478E378FA3B808E757018040AE7E5517F58012B'
$코드파일 = @(
  '.gitignore', 'AGENTS.md', 'CLAUDE.md', '곡형식_8가지.md', '공장.py',
  '분석기.py', '샘플재료_이용안내.md', '시작하세요.md', '업로더.py', '작사스킬.md',
  '점검.py', '자주묻는질문.md'
)
$필수재료 = @(
  '재료/배경 - 오늘이 제일 좋은 날.jpg',
  '재료/썸네일 - 오늘이 제일 좋은 날.jpg',
  '재료/오늘이 제일 좋은 날.mp3',
  '재료/오늘이 제일 좋은 날.txt'
)
$결과 = [ordered]@{}

function Say($t)  { Write-Host $t -ForegroundColor Cyan }
function Ok($t)   { Write-Host ("  [OK] "  + $t) -ForegroundColor Green }
function Warn($t) { Write-Host ("  [!] "   + $t) -ForegroundColor Yellow }
function Step($t) { Write-Host ''; Write-Host ("▶ " + $t) -ForegroundColor White }
function Has($n)  { return ($null -ne (Get-Command $n -ErrorAction SilentlyContinue)) }

function Find-Python {
  $후보 = @(
    [pscustomobject]@{ Exe = 'py';      Args = @('-3.12') },
    [pscustomobject]@{ Exe = 'py';      Args = @('-3') },
    [pscustomobject]@{ Exe = 'python';  Args = @() },
    [pscustomobject]@{ Exe = 'python3'; Args = @() }
  )
  foreach ($c in $후보) {
    $명령 = Get-Command $c.Exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $명령 -or $명령.Source -match '[\\/]WindowsApps[\\/]') { continue }
    & $명령.Source @($c.Args) -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
      return [pscustomobject]@{ Exe = $명령.Source; Args = @($c.Args) }
    }
  }
  return $null
}

function Test-OrcaSignature($경로) {
  try {
    $서명 = Get-AuthenticodeSignature -LiteralPath $경로
    $정보 = (Get-Item -LiteralPath $경로).VersionInfo
    return (
      $서명.Status -eq 'Valid' -and
      $null -ne $서명.SignerCertificate -and
      $서명.SignerCertificate.Subject -like 'CN=SignPath Foundation,*' -and
      $정보.ProductName -eq 'Orca' -and
      $정보.CompanyName -eq 'stablyai'
    )
  } catch {
    return $false
  }
}

function Test-PackageStructure($경로) {
  if ([IO.Path]::GetFileName($경로) -cne $패키지이름) {
    Warn ('파일 이름이 정확하지 않습니다. 필요한 이름: ' + $패키지이름)
    return $false
  }
  try {
    $실제SHA256 = (Get-FileHash -LiteralPath $경로 -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($실제SHA256 -cne $패키지SHA256) {
      Warn 'ZIP의 SHA-256이 공식 배포본과 다릅니다. 이 파일은 풀지 않습니다.'
      return $false
    }
  } catch {
    Warn ('ZIP의 SHA-256을 확인하지 못했습니다: ' + $_.Exception.Message)
    return $false
  }

  $압축 = $null
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $압축 = [IO.Compression.ZipFile]::OpenRead($경로)
    $필수 = @($코드파일) + @('설정.json') + @($필수재료)
    $허용루트 = @($코드파일) + @('설정.json')
    $허용재료확장자 = @('.mp3', '.wav', '.m4a', '.flac', '.jpg', '.jpeg', '.png', '.webp', '.txt')
    $본이름 = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $정확한이름 = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $실패 = $false
    [long]$전체크기 = 0

    if ($압축.Entries.Count -gt 200) { $실패 = $true }
    foreach ($항목 in $압축.Entries) {
      $이름 = $항목.FullName
      $null = $정확한이름.Add($이름)
      $전체크기 += $항목.Length
      if (
        [string]::IsNullOrWhiteSpace($이름) -or
        $이름.Contains('\') -or
        $이름.Contains(':') -or
        $이름 -match '[\x00-\x1F]' -or
        $이름.StartsWith('/') -or
        (($이름 -split '/') -contains '..') -or
        -not $본이름.Add($이름) -or
        (($항목.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000 -or
        $항목.Length -gt 536870912
      ) { $실패 = $true; continue }

      if ($이름.EndsWith('/')) {
        if ($이름 -ne '재료/') { $실패 = $true }
      } elseif ($허용루트 -ccontains $이름) {
        # 허용된 공장 코드·문서다.
      } elseif ($이름 -match '^재료/[^/]+$') {
        if ($허용재료확장자 -notcontains [IO.Path]::GetExtension($이름).ToLowerInvariant()) { $실패 = $true }
      } else {
        $실패 = $true
      }
    }

    if ($전체크기 -gt 1073741824) { $실패 = $true }
    foreach ($필수항목 in $필수) {
      if (-not $정확한이름.Contains($필수항목)) { $실패 = $true }
    }
    if ($실패) {
      Warn 'ZIP 구조 검사를 통과하지 못했습니다. 이 파일은 풀지 않습니다.'
      return $false
    }
    return $true
  } catch {
    Warn ('ZIP을 읽지 못했습니다: ' + $_.Exception.Message)
    return $false
  } finally {
    if ($null -ne $압축) { $압축.Dispose() }
  }
}

function Protect-FactoryAcl {
  try {
    $내SID = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $공장 '/inheritance:r' '/grant:r' "*$($내SID):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '/T' '/C' | Out-Null
    $첫결과 = $LASTEXITCODE
    & icacls.exe $공장 '/remove:g' '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' '/T' '/C' | Out-Null
    return ($첫결과 -eq 0 -and $LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Test-AnalysisApiKey {
  $설정경로 = Join-Path $공장 '설정.json'
  if (Test-Path -LiteralPath $설정경로) {
    try {
      $설정값 = Get-Content -LiteralPath $설정경로 -Raw -Encoding UTF8 | ConvertFrom-Json
      if ([string]$설정값.유튜브API키 -match '^AIza[0-9A-Za-z_-]{20,}$') { return $true }
    } catch {}
  }
  foreach ($키파일 in Get-ChildItem -LiteralPath $공장 -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Extension -in @('.txt', '.rtf', '.text') -and ($_.Name -match '키|key')
  }) {
    try {
      if ((Get-Content -LiteralPath $키파일.FullName -Raw -ErrorAction Stop) -match 'AIza[0-9A-Za-z_-]{20,}') { return $true }
    } catch {}
  }
  return $false
}

function RefreshPath {
  $m = [Environment]::GetEnvironmentVariable('Path','Machine')
  $u = [Environment]::GetEnvironmentVariable('Path','User')
  $claudeBin = Join-Path $HOME '.local\bin'
  if (Test-Path -LiteralPath $claudeBin) {
    $사용자경로 = @($u -split ';' | Where-Object { $_ })
    if ($사용자경로 -notcontains $claudeBin) {
      $u = (($사용자경로 + $claudeBin) -join ';')
      [Environment]::SetEnvironmentVariable('Path', $u, 'User')
      Ok '클로드코드 실행 경로를 Windows 사용자 PATH에 추가했습니다'
    }
  }
  $env:Path = $m + ';' + $u
}

# 한글은 화면에서 두 칸을 차지한다 — 그걸 세어서 칸을 맞춘다 (표가 어긋나지 않게)
function 폭맞춤($문자열, $칸) {
  $폭 = 0
  foreach ($c in $문자열.ToCharArray()) { $폭 += if ([int]$c -gt 0x1100) { 2 } else { 1 } }
  return $문자열 + (' ' * [Math]::Max(0, $칸 - $폭))
}

# winget 으로 하나 설치 (이미 있으면 건너뜀)
function Need($id, $이름, $명령) {
  if (Has $명령) { Ok ($이름 + ' - 이미 있음'); $결과[$이름] = '있음'; return }
  Say ('  ' + $이름 + ' 설치 중... 창을 닫지 마세요.')
  winget install -e --id $id --accept-package-agreements --accept-source-agreements --silent | Out-Null
  RefreshPath
  if (Has $명령) { Ok ($이름 + ' 설치 완료'); $결과[$이름] = '방금 설치' }
  else { Warn ($이름 + ' 이 아직 인식되지 않습니다 (창을 닫고 한 번 더 실행하면 대개 잡힙니다)'); $결과[$이름] = '확인 필요' }
}

Say '====================================================='
Say '  유튜브 플리 자동화 챌린지 - 설치 도우미'
Say ('  고른 AI: ' + $AI이름)
Say '  이 창이 알아서 전부 설치합니다. 닫지 말고 기다려 주세요.'
Say '  (10~20분 걸릴 수 있습니다. 중간에 조용해 보여도 진행 중입니다.)'
Say '====================================================='

# ── 0) winget 확인 ─────────────────────────────────────
Step '0/8  앱 설치 관리자 확인'
if (-not (Has 'winget')) {
  Warn 'winget(앱 설치 관리자)이 없는 PC입니다.'
  Warn '지금 열리는 스토어에서 [설치]를 누른 뒤, 이 설치 한 줄을 처음부터 다시 실행해 주세요.'
  Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
  Read-Host '읽었으면 엔터'
  return
}
Ok 'winget 확인'

# ── 1) 기본 도구 한꺼번에 ──────────────────────────────
Step '1/8  기본 도구 설치 (Git · Python · ffmpeg · Node.js · Chrome)'
Need 'Git.Git'             'Git'      'git'
Need 'Gyan.FFmpeg'         'ffmpeg'   'ffmpeg'
Need 'OpenJS.NodeJS.LTS'   'Node.js'  'npm'
Need 'Google.Chrome'       'Chrome'   'chrome'

# Microsoft Store 실행 별칭은 명령이 있어 보여도 실제 Python이 아니다.
$파이썬 = Find-Python
if (-not $파이썬) {
  Say '  Python 설치 중... 창을 닫지 마세요.'
  winget install -e --id 'Python.Python.3.12' --accept-package-agreements --accept-source-agreements --silent | Out-Null
  RefreshPath
  $파이썬 = Find-Python
  if ($파이썬) { Ok 'Python 설치 완료'; $결과['Python'] = '방금 설치' }
  else { Warn 'Python을 실제로 실행하지 못했습니다 (창을 닫고 한 번 더 실행해 주세요)'; $결과['Python'] = '확인 필요' }
} else {
  Ok 'Python - 실제 실행 확인'; $결과['Python'] = '있음'
}

# Chrome 은 PATH 에 안 잡히는 경우가 많아 설치 경로로 한 번 더 확인
if ($결과['Chrome'] -ne '있음' -and $결과['Chrome'] -ne '방금 설치') {
  $크롬 = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($크롬) { Ok 'Chrome - 설치되어 있음'; $결과['Chrome'] = '있음' }
}

# ── 2) 고른 AI 도구 ────────────────────────────────────
Step ('2/8  ' + $AI이름 + ' 설치')
if ($AI -eq 'codex') {
  if (Has 'codex') { Ok 'Codex - 이미 있음'; $결과['Codex'] = '있음' }
  else {
    if (-not (Has 'npm')) {
      Warn 'Node.js 가 아직 인식되지 않아 Codex 를 설치할 수 없습니다.'
      Warn '이 창을 닫고 설치 한 줄을 한 번 더 실행해 주세요. (Node.js 는 이미 깔렸습니다)'
      $결과['Codex'] = '재실행 필요'
    } else {
      Say '  Codex 설치 중... 창을 닫지 마세요.'
      npm.cmd install -g @openai/codex 2>&1 | Out-Null
      RefreshPath
      if (Has 'codex') { Ok 'Codex 설치 완료'; $결과['Codex'] = '방금 설치' }
      else { Warn 'Codex 가 아직 인식되지 않습니다 (창 닫고 한 번 더 실행)'; $결과['Codex'] = '확인 필요' }
    }
  }
} else {
  if (Has 'claude') { Ok '클로드코드 - 이미 있음'; $결과['클로드코드'] = '있음' }
  else {
    Say '  클로드코드 설치 중... 창을 닫지 마세요.'
    try { Invoke-RestMethod 'https://claude.ai/install.ps1' | Invoke-Expression }
    catch { Warn ('설치 중 오류: ' + $_.Exception.Message) }
    RefreshPath
    if (Has 'claude') { Ok '클로드코드 설치 완료'; $결과['클로드코드'] = '방금 설치' }
    else { Warn '클로드코드가 아직 인식되지 않습니다 (창 닫고 한 번 더 실행)'; $결과['클로드코드'] = '확인 필요' }
  }
}

# ── 3) Orca ────────────────────────────────────────────
Step '3/8  Orca 설치'
$orcaExe = Join-Path $env:LOCALAPPDATA 'Programs\orca\Orca.exe'
if ((Test-Path $orcaExe) -and (Test-OrcaSignature $orcaExe)) {
  Ok 'Orca - 설치 및 서명 확인'; $결과['Orca'] = '있음'
} elseif (Test-Path $orcaExe) {
  Warn '기존 Orca의 게시자 서명을 확인하지 못했습니다. 실행하지 말고 공식 설치본으로 다시 설치해 주세요.'
  $결과['Orca'] = '서명 확인 필요'
}
else {
  Say '  Orca 설치 파일 내려받는 중...'
  $tmp = Join-Path $env:TEMP ('orca-windows-setup-' + [guid]::NewGuid().ToString('N') + '.exe')
  try {
    Invoke-WebRequest 'https://github.com/stablyai/orca/releases/latest/download/orca-windows-setup.exe' -OutFile $tmp -UseBasicParsing
    if (-not (Test-OrcaSignature $tmp)) {
      throw 'Orca 설치 파일의 Authenticode 서명 또는 게시자(stablyai/SignPath)를 확인하지 못했습니다.'
    }
    Ok 'Orca 설치 파일 서명 확인'
    Warn 'Orca 설치 창이 열립니다 — [다음] · [설치] · [마침] 을 눌러 주세요. 끝나면 여기가 이어집니다.'
    Start-Process $tmp -Wait
    if ((Test-Path $orcaExe) -and (Test-OrcaSignature $orcaExe)) { Ok 'Orca 설치 완료'; $결과['Orca'] = '방금 설치' }
    else { Warn 'Orca 설치를 확인하지 못했습니다'; $결과['Orca'] = '확인 필요' }
  } catch {
    Warn ('Orca 설치 중단: ' + $_.Exception.Message)
    Warn '공식 다운로드 페이지에서 Windows용 설치 파일을 받은 뒤 게시자 서명을 확인해 주세요.'
    $결과['Orca'] = '확인 필요'
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

# ── 4) 채널 분석용 파이썬 패키지 ──────────────────────
Step '4/8  채널 분석용 파이썬 패키지'
RefreshPath
$파이썬 = Find-Python
if (-not $파이썬) {
  Warn 'Python 이 아직 인식되지 않습니다. 창을 닫고 한 번 더 실행해 주세요.'
  $결과['파이썬 패키지'] = '재실행 필요'
} else {
  $pyExe = $파이썬.Exe
  $pyArgs = @($파이썬.Args)
  $패키지준비 = $false
  $이전오류설정 = $ErrorActionPreference
  try {
    # Windows PowerShell 5.1은 pip의 정상 경고(stderr)도 NativeCommandError로
    # 바꿀 수 있다. 설치기 전체가 4/8에서 끝나지 않도록 여기서만 숨긴다.
    $ErrorActionPreference = 'SilentlyContinue'
    & $pyExe @pyArgs -m pip install --quiet --upgrade google-api-python-client *> $null
    if ($LASTEXITCODE -eq 0) {
      & $pyExe @pyArgs -c 'import googleapiclient' *> $null
      $패키지준비 = ($LASTEXITCODE -eq 0)
    }
  } catch {
    $패키지준비 = $false
  } finally {
    $ErrorActionPreference = $이전오류설정
  }
  if ($패키지준비) { Ok '채널 분석용 패키지 준비 완료'; $결과['파이썬 패키지'] = '준비됨' }
  else { Warn '패키지 설치를 확인하지 못했습니다 (나중에 AI가 다시 시도합니다)'; $결과['파이썬 패키지'] = '확인 필요' }
}

# ── 5) 공장 폴더 ───────────────────────────────────────
Step '5/8  공장 폴더 만들기'
foreach ($p in @($공장, "$공장\재료", "$공장\완성", "$공장\기록")) {
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
Ok ($공장 + ' 준비 완료 (재료 · 완성 · 기록)')
$결과['공장 폴더'] = '준비됨'
if (Protect-FactoryAcl) {
  Ok '공장 폴더 권한 - 현재 Windows 사용자만 접근'
  $결과['폴더 보안'] = '준비됨'
} else {
  Warn '공장 폴더의 사용자 전용 권한을 설정하지 못했습니다.'
  $결과['폴더 보안'] = '확인 필요'
}

# ── 6) 셋팅코드 zip 풀기 ───────────────────────────────
Step '6/8  셋팅코드 넣기'
# 원드라이브를 쓰는 PC는 진짜 바탕화면/다운로드가 OneDrive 아래에 있다 — 둘 다 본다
$받은폴더 = @(
  "$env:USERPROFILE\Downloads",
  "$env:USERPROFILE\Desktop",
  "$env:OneDrive\Downloads",
  "$env:OneDrive\Desktop",
  "$env:USERPROFILE\OneDrive\Downloads",
  "$env:USERPROFILE\OneDrive\Desktop"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
$zip = $받은폴더 | ForEach-Object {
  $후보경로 = Join-Path $_ $패키지이름
  if (Test-Path -LiteralPath $후보경로) { Get-Item -LiteralPath $후보경로 }
} | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($zip) {
  if (-not (Test-PackageStructure $zip.FullName)) {
    $결과['셋팅코드'] = 'ZIP 확인 필요'
  } else {
    $임시폴더 = Join-Path ([IO.Path]::GetTempPath()) ('pli-package-' + [guid]::NewGuid().ToString('N'))
    try {
      New-Item -ItemType Directory -Path $임시폴더 -Force | Out-Null
      Expand-Archive -LiteralPath $zip.FullName -DestinationPath $임시폴더 -Force -ErrorAction Stop

      # 프로그램·안내 문서는 갱신하되 참가자의 설정과 작업물은 덮어쓰지 않는다.
      foreach ($이름 in $코드파일) {
        $상대경로 = $이름.Replace('/', [IO.Path]::DirectorySeparatorChar)
        Copy-Item -LiteralPath (Join-Path $임시폴더 $상대경로) -Destination (Join-Path $공장 $상대경로) -Force -ErrorAction Stop
      }
      if (-not (Test-Path -LiteralPath (Join-Path $공장 '설정.json'))) {
        Copy-Item -LiteralPath (Join-Path $임시폴더 '설정.json') -Destination (Join-Path $공장 '설정.json') -ErrorAction Stop
      }
      foreach ($샘플 in Get-ChildItem -LiteralPath (Join-Path $임시폴더 '재료') -File -ErrorAction Stop) {
        $대상 = Join-Path (Join-Path $공장 '재료') $샘플.Name
        if (-not (Test-Path -LiteralPath $대상)) {
          Copy-Item -LiteralPath $샘플.FullName -Destination $대상 -ErrorAction Stop
        }
      }
      Ok ('셋팅코드 설치·업데이트 완료 (' + $zip.Name + ')')
      $결과['셋팅코드'] = '방금 업데이트'
    } catch {
      Warn ('셋팅코드 업데이트 실패: ' + $_.Exception.Message)
      $결과['셋팅코드'] = '확인 필요'
    } finally {
      if (Test-Path -LiteralPath $임시폴더) {
        $임시루트 = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        $정리대상 = [IO.Path]::GetFullPath($임시폴더)
        if ($정리대상.StartsWith($임시루트, [StringComparison]::OrdinalIgnoreCase) -and
            ([IO.Path]::GetFileName($정리대상) -like 'pli-package-*')) {
          Remove-Item -LiteralPath $정리대상 -Recurse -Force -ErrorAction SilentlyContinue
        } else {
          Warn '패키지 임시 폴더 경로가 안전 범위를 벗어나 자동 정리를 건너뜁니다.'
        }
      }
    }
  }
} elseif (Test-Path -LiteralPath (Join-Path $공장 '공장.py')) {
  Ok ('셋팅코드 - 설치되어 있음 (새 ' + $패키지이름 + ' 없음)')
  $결과['셋팅코드'] = '있음'
} else {
  Ok '셋팅코드 - 오늘은 필요 없습니다 (챌린지 시작할 때 씁니다)'
  Say ('     나중에 받은 ' + $패키지이름 + ' 을 다운로드한 뒤 이 설치 한 줄을 한 번 더 실행하세요.')
  $결과['셋팅코드'] = '나중에'
}

# ── 6-b) 채널 분석 API 키 상태 ─────────────────────────
Step '6-b  채널 분석 API 키 준비 상태'
if (Test-AnalysisApiKey) {
  Ok '채널 분석 API 키 - 준비됨'
  $결과['분석 API 키'] = '준비됨'
} else {
  Ok '채널 분석 API 키 - 나중에 준비해도 됩니다'
  $결과['분석 API 키'] = '나중에'
}

# ── 7) 수노용 Playwright 미리 받기 ─────────────────────
Step '7/8  수노용 브라우저 도구 준비'
RefreshPath
if (-not (Has 'npx')) {
  Warn 'Node.js 가 아직 인식되지 않아 건너뜁니다 (나중에 AI가 처리합니다)'
  $결과['수노 브라우저'] = '나중에'
} else {
  $수노 = "$공장\기록\수노브라우저"
  if (-not (Test-Path $수노)) { New-Item -ItemType Directory -Path $수노 -Force | Out-Null }
  Say '  Playwright 내려받는 중... (처음 한 번만, 몇 분 걸립니다)'
  npx.cmd -y "@playwright/mcp@latest" --browser chrome --user-data-dir $수노 --help 2>&1 | Out-Null
  Ok 'Playwright 준비 완료'
  $결과['수노 브라우저'] = '준비됨'

  # MCP 등록은 공장 폴더 안에서 (실패해도 AI가 나중에 다시 한다)
  Push-Location $공장
  try {
    if ($AI -eq 'codex' -and (Has 'codex')) {
      $이미 = (codex mcp list 2>&1 | Out-String)
      if ($이미 -notmatch 'playwright') {
        codex mcp add playwright -- npx -y "@playwright/mcp@latest" --browser chrome --user-data-dir ".\기록\수노브라우저" 2>&1 | Out-Null
      }
      Ok 'Codex 에 수노 브라우저 연결'
    } elseif ($AI -eq 'claude' -and (Has 'claude')) {
      $이미 = (claude mcp list 2>&1 | Out-String)
      if ($이미 -notmatch 'playwright') {
        claude mcp add --scope local playwright -- npx -y "@playwright/mcp@latest" --browser chrome --user-data-dir ".\기록\수노브라우저" 2>&1 | Out-Null
      }
      Ok '클로드에 수노 브라우저 연결'
    }
  } catch { Warn '수노 브라우저 연결은 나중에 AI가 처리합니다' }
  Pop-Location
}

# ── 8) 자가진단 ────────────────────────────────────────
Step '8/8  설치 결과'
RefreshPath
Write-Host ''
Write-Host '  ┌──────────────────────┬──────────────┐' -ForegroundColor DarkGray
foreach ($k in $결과.Keys) {
  $v = $결과[$k]
  $색 = if ($v -match '있음|방금|준비됨|넣음') { 'Green' } else { 'Yellow' }
  Write-Host ('  │ ' + (폭맞춤 $k 20) + ' │ ') -NoNewline -ForegroundColor DarkGray
  Write-Host (폭맞춤 $v 12) -NoNewline -ForegroundColor $색
  Write-Host '│' -ForegroundColor DarkGray
}
Write-Host '  └──────────────────────┴──────────────┘' -ForegroundColor DarkGray
Write-Host ''

$문제 = @($결과.Keys | Where-Object { $결과[$_] -notmatch '있음|방금|준비됨|넣음|나중에' })
if ($문제.Count -eq 0) {
  Write-Host '  ✅ 설치 준비 완료' -ForegroundColor Green
} else {
  Warn ('아직 확인이 필요한 것: ' + ($문제 -join ', '))
  Warn '대부분은 이 창을 닫고 설치 한 줄을 한 번 더 실행하면 해결됩니다.'
}

# ── 로그인 ─────────────────────────────────────────────
Write-Host ''
Say '─────────────────────────────────────'
if ($AI실행모드) {
  Say 'AI 실행 모드: Day 0 로그인 상태를 사용하므로 로그인 확인을 건너뜁니다.'
  Say '새 AGENTS.md와 CLAUDE.md를 다시 읽고 자가진단을 계속하세요.'
} else {
  if ($AI -eq 'codex' -and (Has 'codex')) {
    Say '마지막 순서: ChatGPT(Codex) 로그인'
    Say '검은 새 창이 열립니다. 안내에 따라 브라우저에서 로그인하세요.'
    Start-Process cmd -ArgumentList '/k','codex login'
  } elseif ($AI -eq 'claude' -and (Has 'claude')) {
    Say '마지막 순서: 클로드 로그인'
    Say '검은 새 창이 열립니다. 안내에 따라 브라우저에서 로그인하세요.'
    Start-Process cmd -ArgumentList '/k','claude'
  } else {
    Warn ($AI이름 + ' 이 인식되지 않아 로그인 단계를 건너뜁니다.')
    Warn '이 창을 닫고 설치 한 줄을 한 번 더 실행해 주세요.'
  }
}

Write-Host ''
Say '여기까지 되었으면 설명서 다음 단계로 가세요.'
Say ('Orca 를 열고 폴더는 ' + $공장 + ' 를 고르면 됩니다.')
if (-not $AI실행모드) {
  Read-Host '다 보셨으면 엔터를 눌러 주세요 (이 창은 저절로 닫히지 않습니다)'
}
}
