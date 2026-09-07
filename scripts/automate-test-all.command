#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

readonly ROOT="${0:A:h:h}"
cd "$ROOT"

# ANSI Color formatting
if [[ -t 1 ]]; then
  readonly BOLD='\033[1m'
  readonly GREEN='\033[0;32m'
  readonly RED='\033[0;31m'
  readonly YELLOW='\033[0;33m'
  readonly BLUE='\033[0;34m'
  readonly CYAN='\033[0;36m'
  readonly MAGENTA='\033[0;35m'
  readonly NC='\033[0m' # No Color
else
  readonly BOLD=''
  readonly GREEN=''
  readonly RED=''
  readonly YELLOW=''
  readonly BLUE=''
  readonly CYAN=''
  readonly MAGENTA=''
  readonly NC=''
fi

QUICK_MODE=false
VERBOSE=false

for arg in "$@"; do
  case "$arg" in
    --quick|-q)
      QUICK_MODE=true
      ;;
    --verbose|-v)
      VERBOSE=true
      ;;
    --help|-h)
      print "Usage: $0 [options]"
      print ""
      print "Options:"
      print "  --quick, -q    Run Unit Tests and static validations without rebuilding full Release target"
      print "  --verbose, -v  Display detailed command outputs during execution"
      print "  --help, -h     Show this help message"
      exit 0
      ;;
    *)
      print -u2 "Unknown argument: $arg (use --help for options)"
      exit 1
      ;;
  esac
done

START_TIME=$(date +%s)

print ""
print "${CYAN}${BOLD}========================================================================${NC}"
print "${CYAN}${BOLD}       🤖 MACRODROID AUTOMATED TEST SUITE (TEST ALL RUNNER)           ${NC}"
print "${CYAN}${BOLD}========================================================================${NC}"
print "  Root:         $ROOT"
print "  Architecture: $(uname -m)"
print "  Host OS:      $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
print "  Timestamp:    $(date '+%Y-%m-%d %H:%M:%S %Z')"
print "  Mode:         $([[ "$QUICK_MODE" == true ]] && echo "${YELLOW}QUICK (Skip Release Rebuild)${NC}" || echo "${GREEN}FULL (Complete End-to-End)${NC}")"
print "${CYAN}------------------------------------------------------------------------${NC}"

typeset -a PHASE_NAMES
typeset -a PHASE_STATUSES
typeset -a PHASE_DURATIONS
integer TOTAL_PHASES=0

record_phase() {
  local name="$1"
  local p_status="$2"
  local duration="$3"
  PHASE_NAMES+=("$name")
  PHASE_STATUSES+=("$p_status")
  PHASE_DURATIONS+=("$duration")
  (( TOTAL_PHASES += 1 ))
}

run_phase() {
  local phase_num="$1"
  local total_num="$2"
  local title="$3"
  shift 3
  local cmd=("$@")

  print -r -n -- "${BOLD}[${phase_num}/${total_num}] ${title}...${NC} "
  local p_start=$(date +%s)
  local tmp_log
  tmp_log="$(mktemp /tmp/macrodroid-test-phase.XXXXXX)"

  if "${cmd[@]}" > "$tmp_log" 2>&1; then
    local p_end=$(date +%s)
    local p_dur=$(( p_end - p_start ))
    print -r -- "${GREEN}${BOLD}[PASS]${NC} (${p_dur}s)"
    if [[ "$VERBOSE" == true ]]; then
      cat "$tmp_log"
    fi
    rm -f "$tmp_log"
    record_phase "$title" "PASS" "${p_dur}s"
  else
    local p_end=$(date +%s)
    local p_dur=$(( p_end - p_start ))
    print -r -- "${RED}${BOLD}[FAIL]${NC} (${p_dur}s)"
    print ""
    print -r -- "${RED}--- Phase Output Log ---${NC}"
    cat "$tmp_log"
    print -r -- "${RED}------------------------${NC}"
    rm -f "$tmp_log"
    record_phase "$title" "FAIL" "${p_dur}s"
    print -u2 -r -- "${RED}${BOLD}Test run aborted due to failure in: ${title}${NC}"
    exit 1
  fi
}

TOTAL_RUN_PHASES=$([[ "$QUICK_MODE" == true ]] && echo 5 || echo 6)

# 1. Environment & Required Tools
run_phase 1 "$TOTAL_RUN_PHASES" "Environment & Toolchain Integrity" \
  /bin/zsh -c '
    set -euo pipefail
    for tool in git jq node plutil grep shasum xcodebuild zsh; do
      command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool" >&2; exit 1; }
    done
    [[ -f "Macrodroid/Info.plist" ]] || exit 1
    plutil -lint "Macrodroid/Info.plist" >/dev/null
  '

# 2. SwiftLint Static Code Analysis
run_phase 2 "$TOTAL_RUN_PHASES" "SwiftLint Static Code Analysis" \
  /bin/zsh scripts/swiftlint.command

# 3. Scripts Syntax Integrity (zsh -n)
run_phase 3 "$TOTAL_RUN_PHASES" "Shell Scripts Syntax Validation" \
  /bin/zsh -c '
    set -euo pipefail
    while IFS= read -r script; do
      zsh -o NO_BG_NICE -n "$script" || { echo "Syntax error in $script" >&2; exit 1; }
    done < <(find scripts -type f \( -name "*.command" -o -name "*.sh" \) | LC_ALL=C sort)
  '

# 4. Node & Database Engineering Lab Self-Tests
run_phase 4 "$TOTAL_RUN_PHASES" "Direct Control & Engineering Lab Self-Tests" \
  /bin/zsh -c '
    set -euo pipefail
    node --check tools/macrodroid-direct-control.mjs >/dev/null
    node tools/macrodroid-direct-control.mjs engineering-map-selftest >/dev/null
    node tools/macrodroid-direct-control.mjs lab-selftest >/dev/null
  '

# 5. Native Swift Unit Tests (XCTest Debug Target)
run_phase 5 "$TOTAL_RUN_PHASES" "Native Swift Unit Tests (45 Native Tests)" \
  /bin/zsh scripts/test-native-app.command

# 6. Release Build & Full Repository Verification Contract (if not --quick)
if [[ "$QUICK_MODE" == false ]]; then
  run_phase 6 6 "Full Project Contract & Release Verification" \
    /bin/zsh scripts/verify-macrodroid.command
fi

END_TIME=$(date +%s)
TOTAL_DURATION=$(( END_TIME - START_TIME ))

print ""
print -r -- "${CYAN}${BOLD}========================================================================${NC}"
print -r -- "${CYAN}${BOLD}                         TEST EXECUTION SUMMARY                         ${NC}"
print -r -- "${CYAN}${BOLD}========================================================================${NC}"
printf "%-3s | %-50s | %-8s | %-8s\n" "#" "Test Phase" "Result" "Duration"
print -r -- "${CYAN}----+----------------------------------------------------+----------+---------${NC}"

integer idx=1
for (( i=1; i<=TOTAL_PHASES; i++ )); do
  local st="${PHASE_STATUSES[$i]}"
  local color="$GREEN"
  if [[ "$st" != "PASS" ]]; then color="$RED"; fi
  printf "%-3d | %-50s | ${color}%-8s${NC} | %-8s\n" "$i" "${PHASE_NAMES[$i]}" "$st" "${PHASE_DURATIONS[$i]}"
done

print -r -- "${CYAN}========================================================================${NC}"
print -r -- "${GREEN}${BOLD}🎉 ALL AUTOMATED TESTS PASSED SUCCESSFULLY! Total time: ${TOTAL_DURATION}s${NC}"
print -r -- "${CYAN}========================================================================${NC}"
print ""
