#!/bin/bash
# =====================================================
#  유튜브 플리 자동화 챌린지 — 설치 도우미 (맥)
#
#  쓰는 법 (설명서의 복사 버튼이 알아서 넣어 줍니다):
#    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thenightpd/r-64fe20c017/main/pli/setup-mac.sh)"
#
#  하는 일: 필요한 것을 "처음에 전부" 설치한다.
#    Homebrew · Git · Python · ffmpeg · Node.js · Chrome · Codex(또는 클로드코드) · Orca
#    + 채널 분석용 파이썬 패키지
#    + ~/플리공장 폴더와 재료/완성/기록 만들기
#    + 셋팅코드 zip 이 있으면 풀어 넣기 (없어도 정상 — 챌린지 시작할 때 씀)
#    + 수노용 Playwright 미리 받아 두기
#
#  여러 번 실행해도 안전합니다 (이미 된 것은 건너뜁니다).
#
#  ⚠ 주의: bash 는 한글 변수명을 못 쓴다. 변수·함수 이름은 반드시 영문.
#          (화면에 보이는 글자만 한글)
# =====================================================

# 일부러 set -e 를 쓰지 않는다 — 하나 실패해도 나머지는 계속 설치해야 한다.
umask 077

AI="${PLI_AI:-codex}"
if [ "$AI" = "codex" ]; then AI_NAME="Codex"; else AI_NAME="클로드코드"; fi
NONINTERACTIVE="${PLI_NONINTERACTIVE:-0}"

FACTORY="$HOME/플리공장"
ZIP_NAME="플리공장_셋팅코드.zip"
ZIP_SHA256="28446568F60C069A1E9C9BE5394FE3EA43E8F7892E1E8F8FB2A9CCBFAACDBB90"
CODE_FILES=".gitignore
AGENTS.md
CLAUDE.md
곡형식_8가지.md
공장.py
분석기.py
샘플재료_이용안내.md
시작하세요.md
업로더.py
작사스킬.md
점검.py
자주묻는질문.md"
RESULT=""

say()  { printf '\033[36m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m[!]\033[0m %s\n' "$1"; }
step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
has()  { command -v "$1" >/dev/null 2>&1; }
record() { RESULT="${RESULT}${1}|${2}"$'\n'; }

find_python() {
  SYSTEM_PYTHON="$(command -v python3 2>/dev/null)"
  for CANDIDATE in \
    "$BREW_BIN/python3.12" \
    "$BREW_BIN/python3" \
    "/opt/homebrew/opt/python@3.12/bin/python3.12" \
    "/usr/local/opt/python@3.12/bin/python3.12" \
    "$SYSTEM_PYTHON"
  do
    [ -n "$CANDIDATE" ] && [ -x "$CANDIDATE" ] || continue
    if "$CANDIDATE" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
      printf '%s\n' "$CANDIDATE"
      return 0
    fi
  done
  return 1
}

verify_orca_app() {
  APP_PATH="$1"
  [ -d "$APP_PATH" ] || return 1
  codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1 &&
    spctl --assess --type execute --verbose=2 "$APP_PATH" >/dev/null 2>&1
}

validate_package() {
  PACKAGE_PATH="$1"
  [ "$(basename "$PACKAGE_PATH")" = "$ZIP_NAME" ] || {
    warn "ZIP 파일 이름은 정확히 $ZIP_NAME 이어야 합니다."
    return 1
  }
  ACTUAL_SHA256="$(shasum -a 256 "$PACKAGE_PATH" 2>/dev/null | awk '{print toupper($1)}')"
  [ "$ACTUAL_SHA256" = "$ZIP_SHA256" ] || {
    warn 'ZIP의 SHA-256이 공식 배포본과 다릅니다. 이 파일은 풀지 않습니다.'
    return 1
  }
  "$PYTHON" - "$PACKAGE_PATH" <<'PY'
import os
import stat
import sys
import zipfile

path = sys.argv[1]
code_files = {
    ".gitignore", "AGENTS.md", "CLAUDE.md", "곡형식_8가지.md", "공장.py",
    "분석기.py", "샘플재료_이용안내.md", "설정.json", "시작하세요.md", "업로더.py", "작사스킬.md",
    "점검.py", "자주묻는질문.md",
}
required_materials = {
    "재료/배경 - 오늘이 제일 좋은 날.jpg",
    "재료/썸네일 - 오늘이 제일 좋은 날.jpg",
    "재료/오늘이 제일 좋은 날.mp3",
    "재료/오늘이 제일 좋은 날.txt",
}
allowed_material_extensions = {
    ".mp3", ".wav", ".m4a", ".flac", ".jpg", ".jpeg", ".png", ".webp", ".txt",
}
errors = []
try:
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        seen = set()
        total_size = 0
        if len(entries) > 200:
            errors.append("파일 수가 200개를 넘습니다")
        for entry in entries:
            name = entry.filename
            folded = name.casefold()
            total_size += entry.file_size
            parts = name.split("/")
            unix_type = stat.S_IFMT(entry.external_attr >> 16)
            if (
                not name
                or "\\" in name
                or ":" in name
                or any(ord(character) < 32 for character in name)
                or name.startswith("/")
                or ".." in parts
                or folded in seen
                or unix_type == stat.S_IFLNK
                or entry.file_size > 512 * 1024 * 1024
            ):
                errors.append(f"안전하지 않은 항목: {name!r}")
                continue
            seen.add(folded)
            if entry.is_dir():
                if name != "재료/":
                    errors.append(f"허용되지 않은 폴더: {name}")
            elif name in code_files:
                pass
            elif name.startswith("재료/") and name.count("/") == 1:
                if os.path.splitext(name)[1].lower() not in allowed_material_extensions:
                    errors.append(f"허용되지 않은 재료 형식: {name}")
            else:
                errors.append(f"허용되지 않은 경로: {name}")
        if total_size > 1024 * 1024 * 1024:
            errors.append("압축 해제 크기가 1GB를 넘습니다")
        names = {entry.filename for entry in entries}
        for missing in sorted((code_files | required_materials) - names):
            errors.append(f"필수 파일 누락: {missing}")
        if not errors:
            broken = archive.testzip()
            if broken:
                errors.append(f"손상된 항목: {broken}")
except (OSError, zipfile.BadZipFile) as exc:
    errors.append(f"ZIP을 읽지 못함: {exc}")

if errors:
    print("  [!] ZIP 구조 검사를 통과하지 못했습니다. 이 파일은 풀지 않습니다.")
    for error in errors[:10]:
        print(f"      - {error}")
    raise SystemExit(1)
raise SystemExit(0)
PY
}

api_key_ready() {
  if [ -f "$FACTORY/설정.json" ] && \
     grep -Eq '"유튜브API키"[[:space:]]*:[[:space:]]*"AIza[0-9A-Za-z_-]{20,}"' "$FACTORY/설정.json" 2>/dev/null; then
    return 0
  fi
  find "$FACTORY" -maxdepth 1 -type f \( -iname '*key*.txt' -o -name '*키*.txt' -o -name '*키*.rtf' \) \
    -exec grep -Eql 'AIza[0-9A-Za-z_-]{20,}' {} \; -print -quit 2>/dev/null | grep -q .
}

say '====================================================='
say '  유튜브 플리 자동화 챌린지 - 설치 도우미 (맥)'
say "  고른 AI: $AI_NAME"
say '  이 창이 알아서 전부 설치합니다. 닫지 말고 기다려 주세요.'
say '  (15~30분 걸릴 수 있습니다. 조용해 보여도 진행 중입니다.)'
say '====================================================='

# ── 0) 내 맥이 어떤 종류인지 ───────────────────────────
step '0/8  내 맥 확인'
CHIP="$(uname -m)"
if [ "$CHIP" = "arm64" ]; then
  KIND="애플 실리콘 (M칩)"; BREW_BIN="/opt/homebrew/bin"; ORCA_DMG="orca-macos-arm64.dmg"
else
  KIND="인텔"; BREW_BIN="/usr/local/bin"; ORCA_DMG="orca-macos-x64.dmg"
fi
ok "$KIND 맥입니다"
# 맥 종류는 합격·불합격 항목이 아니므로 결과 표에는 넣지 않는다 (인텔이 오류로 잡히던 문제)

# ── 1) Homebrew (맥의 앱 설치 관리자) ──────────────────
step '1/8  Homebrew 설치 (맥의 앱 설치 관리자)'
[ -x "$BREW_BIN/brew" ] && eval "$("$BREW_BIN/brew" shellenv)"
if has brew; then
  ok 'Homebrew - 이미 있음'
  record "Homebrew" "있음"
else
  warn '설치 중에 맥 로그인 비밀번호를 물어봅니다.'
  warn '입력해도 화면에 아무것도 안 보이는 게 정상입니다. 그대로 치고 Enter 를 누르세요.'
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  [ -x "$BREW_BIN/brew" ] && eval "$("$BREW_BIN/brew" shellenv)"
  if has brew; then
    ok 'Homebrew 설치 완료'; record "Homebrew" "방금 설치"
    # 다음에 터미널을 열어도 brew 가 잡히도록
    for PROFILE in "$HOME/.zprofile" "$HOME/.bash_profile"; do
      grep -q 'brew shellenv' "$PROFILE" 2>/dev/null || \
        echo "eval \"\$($BREW_BIN/brew shellenv)\"" >> "$PROFILE"
    done
  else
    warn 'Homebrew 설치를 확인하지 못했습니다.'
    warn '터미널을 닫고 설치 한 줄을 한 번 더 실행해 주세요.'
    exit 1
  fi
fi

# ── 2) 기본 도구 ───────────────────────────────────────
step '2/8  기본 도구 설치 (Git · Python · ffmpeg · Node.js)'
brew_need() {  # brew_need <brew이름> <표시이름> <확인명령>
  if has "$3"; then ok "$2 - 이미 있음"; record "$2" "있음"; return; fi
  say "  $2 설치 중... 창을 닫지 마세요."
  brew install "$1" >/dev/null 2>&1
  hash -r 2>/dev/null
  if has "$3"; then ok "$2 설치 완료"; record "$2" "방금 설치"
  else warn "$2 이 아직 인식되지 않습니다 (터미널을 닫고 한 번 더 실행하면 대개 잡힙니다)"; record "$2" "확인 필요"; fi
}
brew_need git         'Git'     git
brew_need ffmpeg      'ffmpeg'  ffmpeg
brew_need node        'Node.js' npm

PYTHON="$(find_python)"
if [ -n "$PYTHON" ]; then
  ok 'Python - 실제 실행 확인'; record "Python" "있음"
else
  say '  Python 설치 중... 창을 닫지 마세요.'
  brew install python@3.12 >/dev/null 2>&1
  hash -r 2>/dev/null
  PYTHON="$(find_python)"
  if [ -n "$PYTHON" ]; then ok 'Python 설치 완료'; record "Python" "방금 설치"
  else warn 'Python을 실제로 실행하지 못했습니다 (터미널을 닫고 한 번 더 실행해 주세요)'; record "Python" "확인 필요"; fi
fi

step '3/8  Chrome 설치'
if [ -d "/Applications/Google Chrome.app" ]; then
  ok 'Chrome - 이미 있음'; record "Chrome" "있음"
else
  say '  Chrome 설치 중...'
  brew install --cask google-chrome >/dev/null 2>&1
  if [ -d "/Applications/Google Chrome.app" ]; then ok 'Chrome 설치 완료'; record "Chrome" "방금 설치"
  else warn 'Chrome 설치를 확인하지 못했습니다'; record "Chrome" "확인 필요"; fi
fi

# ── 4) 고른 AI 도구 ────────────────────────────────────
step "4/8  $AI_NAME 설치"
if [ "$AI" = "codex" ]; then
  if has codex; then
    ok 'Codex - 이미 있음'; record "Codex" "있음"
  elif ! has npm; then
    warn 'Node.js 가 아직 인식되지 않아 Codex 를 설치할 수 없습니다.'
    warn '터미널을 닫고 설치 한 줄을 한 번 더 실행해 주세요.'
    record "Codex" "재실행 필요"
  else
    say '  Codex 설치 중... 창을 닫지 마세요.'
    npm install -g @openai/codex >/dev/null 2>&1
    hash -r 2>/dev/null
    if has codex; then ok 'Codex 설치 완료'; record "Codex" "방금 설치"
    else warn 'Codex 가 아직 인식되지 않습니다 (터미널 닫고 한 번 더 실행)'; record "Codex" "확인 필요"; fi
  fi
else
  if has claude; then
    ok '클로드코드 - 이미 있음'; record "클로드코드" "있음"
  else
    say '  클로드코드 설치 중...'
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1
    export PATH="$HOME/.local/bin:$PATH"; hash -r 2>/dev/null
    if has claude; then ok '클로드코드 설치 완료'; record "클로드코드" "방금 설치"
    else warn '클로드코드가 아직 인식되지 않습니다 (터미널 닫고 한 번 더 실행)'; record "클로드코드" "확인 필요"; fi
  fi
fi

# ── 5) Orca ────────────────────────────────────────────
step '5/8  Orca 설치'
if verify_orca_app "/Applications/Orca.app"; then
  ok 'Orca - 설치 및 서명 확인'; record "Orca" "있음"
elif [ -d "/Applications/Orca.app" ]; then
  warn '기존 Orca의 코드 서명 또는 Gatekeeper 승인을 확인하지 못했습니다.'
  warn '앱을 실행하지 말고 공식 설치본으로 다시 설치해 주세요.'
  record "Orca" "서명 확인 필요"
else
  say '  Orca 내려받는 중...'
  TMPDIR_PLI="$(mktemp -d)"
  if curl -fsSL "https://github.com/stablyai/orca/releases/latest/download/$ORCA_DMG" -o "$TMPDIR_PLI/orca.dmg"; then
    # -quiet 를 주면 hdiutil 이 마운트 지점을 출력하지 않아 MOUNT 가 항상 빈 값이 된다.
    MOUNT="$(hdiutil attach "$TMPDIR_PLI/orca.dmg" -nobrowse | grep -o '/Volumes/.*' | head -n 1)"
    APP="$(find "$MOUNT" -maxdepth 1 -name '*.app' 2>/dev/null | head -n 1)"
    if [ -n "$APP" ] && verify_orca_app "$APP"; then
      say '  Orca 코드 서명과 Gatekeeper 승인 확인 완료'
      ditto "$APP" "/Applications/$(basename "$APP")" 2>/dev/null
      if verify_orca_app "/Applications/$(basename "$APP")"; then
        ok 'Orca 설치 완료'; record "Orca" "방금 설치"
      else
        warn '복사된 Orca의 서명을 확인하지 못했습니다'; record "Orca" "확인 필요"
      fi
    else
      warn 'Orca 앱을 찾지 못했거나 코드 서명·Gatekeeper 검사를 통과하지 못했습니다'
      printf '     브라우저에서 직접 받아 설치해 주세요: https://onorca.dev/download\n'
      record "Orca" "확인 필요"
    fi
    [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet 2>/dev/null
  else
    warn '자동 다운로드 실패. 브라우저에서 직접 받아 주세요: https://onorca.dev/download'
    record "Orca" "직접 설치"
  fi
  if [ -n "$TMPDIR_PLI" ] && [ -d "$TMPDIR_PLI" ] && [ ! -L "$TMPDIR_PLI" ]; then
    rm -f -- "$TMPDIR_PLI/orca.dmg"
    rmdir -- "$TMPDIR_PLI" 2>/dev/null || warn 'Orca 임시 폴더 정리를 건너뜁니다.'
  fi
fi

# ── 6) 채널 분석용 파이썬 패키지 ──────────────────────
step '6/8  채널 분석용 파이썬 패키지'
if [ -z "$PYTHON" ]; then
  warn 'Python 이 아직 인식되지 않습니다. 터미널을 닫고 한 번 더 실행해 주세요.'
  record "파이썬 패키지" "재실행 필요"
else
  "$PYTHON" -m pip install --user --quiet --upgrade google-api-python-client >/dev/null 2>&1 \
    || "$PYTHON" -m pip install --user --quiet --upgrade --break-system-packages google-api-python-client >/dev/null 2>&1
  if "$PYTHON" -c 'import googleapiclient' >/dev/null 2>&1; then
    ok '채널 분석용 패키지 준비 완료'; record "파이썬 패키지" "준비됨"
  else
    warn '패키지 설치를 확인하지 못했습니다 (챌린지 시작할 때 AI가 다시 시도합니다)'
    record "파이썬 패키지" "나중에"
  fi
fi

# ── 7) 공장 폴더 + 셋팅코드 ────────────────────────────
step '7/8  공장 폴더 만들기'
mkdir -p "$FACTORY/재료" "$FACTORY/완성" "$FACTORY/기록"
ok "$FACTORY 준비 완료 (재료 · 완성 · 기록)"
record "공장 폴더" "준비됨"
if chmod 700 "$FACTORY" "$FACTORY/재료" "$FACTORY/완성" "$FACTORY/기록" 2>/dev/null &&
   find "$FACTORY" -type d -exec chmod 700 {} + 2>/dev/null &&
   find "$FACTORY" -type f -exec chmod 600 {} + 2>/dev/null; then
  ok '공장 폴더 권한 - 현재 macOS 사용자만 접근'
  record "폴더 보안" "준비됨"
else
  warn '공장 폴더의 사용자 전용 권한을 설정하지 못했습니다.'
  record "폴더 보안" "확인 필요"
fi

ZIPFILE=""
ZIP_MTIME=0
for CANDIDATE in "$HOME/Downloads/$ZIP_NAME" "$HOME/Desktop/$ZIP_NAME"; do
  [ -f "$CANDIDATE" ] || continue
  CANDIDATE_MTIME="$(stat -f '%m' "$CANDIDATE" 2>/dev/null)"
  [ -n "$CANDIDATE_MTIME" ] || CANDIDATE_MTIME=0
  if [ "$CANDIDATE_MTIME" -ge "$ZIP_MTIME" ]; then
    ZIPFILE="$CANDIDATE"
    ZIP_MTIME="$CANDIDATE_MTIME"
  fi
done

if [ -n "$ZIPFILE" ]; then
  if [ -z "$PYTHON" ] || ! validate_package "$ZIPFILE"; then
    record "셋팅코드" "ZIP 확인 필요"
  else
    PACKAGE_TMP_BASE="${TMPDIR:-/tmp}"
    case "$PACKAGE_TMP_BASE" in
      /*) PACKAGE_TMP_BASE="$(cd "$PACKAGE_TMP_BASE" 2>/dev/null && pwd -P)" ;;
      *) PACKAGE_TMP_BASE="" ;;
    esac
    PACKAGE_TMP_PREFIX="${PACKAGE_TMP_BASE%/}/pli-package."
    PACKAGE_TMP=""
    [ -n "$PACKAGE_TMP_BASE" ] && \
      PACKAGE_TMP="$(mktemp -d "${PACKAGE_TMP_PREFIX}XXXXXX" 2>/dev/null)"
    UPDATE_OK=1
    if [ -z "$PACKAGE_TMP" ] || [ ! -d "$PACKAGE_TMP" ] || [ -L "$PACKAGE_TMP" ]; then
      warn '안전한 패키지 임시 폴더를 만들지 못했습니다.'
      UPDATE_OK=0
    elif ! unzip -q "$ZIPFILE" -d "$PACKAGE_TMP" 2>/dev/null; then
      UPDATE_OK=0
    elif find "$PACKAGE_TMP" -type l -print -quit 2>/dev/null | grep -q .; then
      warn 'ZIP 안에서 심볼릭 링크를 발견해 설치를 중단합니다.'
      UPDATE_OK=0
    else
      while IFS= read -r RELATIVE; do
        [ -n "$RELATIVE" ] || continue
        cp -f "$PACKAGE_TMP/$RELATIVE" "$FACTORY/$RELATIVE" 2>/dev/null || UPDATE_OK=0
      done <<< "$CODE_FILES"

      # 개인 설정과 참가자가 만든 재료·완성·기록은 보존한다.
      if [ ! -f "$FACTORY/설정.json" ]; then
        cp "$PACKAGE_TMP/설정.json" "$FACTORY/설정.json" 2>/dev/null || UPDATE_OK=0
      fi
      for SAMPLE in "$PACKAGE_TMP/재료"/*; do
        [ -f "$SAMPLE" ] || continue
        TARGET="$FACTORY/재료/$(basename "$SAMPLE")"
        [ -e "$TARGET" ] || cp "$SAMPLE" "$TARGET" 2>/dev/null || UPDATE_OK=0
      done
    fi

    case "$PACKAGE_TMP" in
      "$PACKAGE_TMP_PREFIX"*)
        if [ -d "$PACKAGE_TMP" ] && [ ! -L "$PACKAGE_TMP" ]; then
          rm -rf -- "$PACKAGE_TMP" || UPDATE_OK=0
        else
          warn '패키지 임시 폴더가 바뀌어 자동 정리를 건너뜁니다.'
          UPDATE_OK=0
        fi
        ;;
      *)
        warn '패키지 임시 폴더 경로가 안전 범위를 벗어나 자동 정리를 건너뜁니다.'
        UPDATE_OK=0
        ;;
    esac
    if [ "$UPDATE_OK" -eq 1 ]; then
      ok "셋팅코드 설치·업데이트 완료 ($ZIP_NAME)"; record "셋팅코드" "방금 업데이트"
    else
      warn '셋팅코드 업데이트에 실패했습니다'; record "셋팅코드" "확인 필요"
    fi
  fi
elif [ -f "$FACTORY/공장.py" ]; then
  ok "셋팅코드 - 설치되어 있음 (새 $ZIP_NAME 없음)"; record "셋팅코드" "있음"
else
  warn "셋팅코드 - $ZIP_NAME 을 찾지 못했습니다"
  printf '     1장 첫 샘플 영상을 만들려면 이 파일이 있어야 합니다.\n'
  printf '     다운로드 폴더나 바탕화면에 %s 이름 그대로 있는지 확인하고 이 설치 한 줄을 다시 실행하세요.\n' "$ZIP_NAME"
  printf '     이름 뒤에 (1) 이 붙었다면 원래 이름으로 바꿔 주세요.\n'
  printf '     Safari가 자동으로 압축을 풀었다면 원본 zip을 다시 다운로드해 주세요.\n'
  record "셋팅코드" "확인 필요"
fi

# ── 7-b) 채널 분석 API 키 상태 ─────────────────────────
step '7-b  채널 분석 API 키 준비 상태'
if api_key_ready; then
  ok '채널 분석 API 키 - 준비됨'
  record "분석 API 키" "준비됨"
else
  ok '채널 분석 API 키 - 나중에 준비해도 됩니다'
  record "분석 API 키" "나중에"
fi

# ── 8) 수노용 Playwright ───────────────────────────────
step '8/8  수노용 브라우저 도구 준비'
if ! has npx; then
  warn 'Node.js 가 아직 인식되지 않아 건너뜁니다 (나중에 AI가 처리합니다)'
  record "수노 브라우저" "나중에"
else
  SUNO="$FACTORY/기록/수노브라우저"
  mkdir -p "$SUNO"
  say '  Playwright 내려받는 중... (처음 한 번만, 몇 분 걸립니다)'
  npx -y "@playwright/mcp@latest" --browser chrome --user-data-dir "$SUNO" --help >/dev/null 2>&1
  ok 'Playwright 준비 완료'
  record "수노 브라우저" "준비됨"
  ( cd "$FACTORY" 2>/dev/null || exit 0
    if [ "$AI" = "codex" ] && has codex; then
      codex mcp list 2>/dev/null | grep -q playwright || \
        codex mcp add playwright -- npx -y "@playwright/mcp@latest" --browser chrome --user-data-dir "./기록/수노브라우저" >/dev/null 2>&1
    elif [ "$AI" = "claude" ] && has claude; then
      claude mcp list 2>/dev/null | grep -q playwright || \
        claude mcp add --scope local playwright -- npx -y "@playwright/mcp@latest" --browser chrome --user-data-dir "./기록/수노브라우저" >/dev/null 2>&1
    fi )
fi

# ── 결과 표 ────────────────────────────────────────────
step '설치 결과'
printf '\n  내 맥: %s\n\n' "$KIND"
PROBLEMS=0
while IFS='|' read -r NAME STATE; do
  [ -z "$NAME" ] && continue
  case "$STATE" in
    있음|"방금 설치"|준비됨|"방금 넣음"|"방금 업데이트"|나중에) printf '  \033[32m[OK]\033[0m %s — %s\n' "$NAME" "$STATE" ;;
    *) printf '  \033[33m[확인]\033[0m %s — %s\n' "$NAME" "$STATE"; PROBLEMS=$((PROBLEMS+1)) ;;
  esac
done <<< "$RESULT"
printf '\n'

if [ "$PROBLEMS" -eq 0 ]; then
  printf '  \033[32m✅ 설치 준비 완료\033[0m\n'
else
  warn "확인이 필요한 항목이 ${PROBLEMS}개 있습니다."
  warn '대부분은 터미널을 닫고 설치 한 줄을 한 번 더 실행하면 해결됩니다.'
fi

# ── 로그인 ─────────────────────────────────────────────
printf '\n'
say '─────────────────────────────────────'
if [ "$NONINTERACTIVE" = "1" ]; then
  say 'AI 실행 모드: Day 0 로그인 상태를 사용하므로 로그인 확인을 건너뜁니다.'
  say '새 AGENTS.md와 CLAUDE.md를 다시 읽고 자가진단을 계속하세요.'
elif [ "$AI" = "codex" ] && has codex; then
  say '마지막 순서: ChatGPT(Codex) 로그인'
  say '브라우저가 열리면 평소 쓰는 계정으로 로그인하세요.'
  codex login
elif [ "$AI" = "claude" ] && has claude; then
  say '마지막 순서: 클로드 로그인'
  say '브라우저가 열리면 평소 쓰는 계정으로 로그인하세요.'
  claude
else
  warn "$AI_NAME 이 인식되지 않아 로그인 단계를 건너뜁니다."
  warn '터미널을 닫고 설치 한 줄을 한 번 더 실행해 주세요.'
fi

printf '\n'
say '여기까지 되었으면 설명서 다음 단계로 가세요.'
say "Orca 를 열고 폴더는 $FACTORY 을 고르면 됩니다."
