#!/usr/bin/env bash
# Тот же набор шагов, что у конвейера в задании Dart, и в том же порядке.
# Повод: v0.9.4 упал на Check format, потому что локально гонялся только analyze.
# «Похожая проверка» не проверка: у конвейера свои команды и свои коды возврата.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Flutter, Rust и Go бывают не в PATH оболочки, хотя установлены: сборочные хуки зовут
# rustup и go, и без них шаг тестов падает «Running build hooks failed» — сообщением,
# по которому не догадаешься, что дело в PATH.
for extra in "$HOME/.cargo/bin" "/c/Program Files/Go/bin" "/c/dev/flutter/bin"; do
  [ -d "$extra" ] && case ":$PATH:" in *":$extra:"*) ;; *) PATH="$extra:$PATH";; esac
done
export PATH

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
fail=0
step() {
  local name="$1"; shift
  printf '%-22s ' "$name"
  if "$@" >"$log" 2>&1; then
    echo "OK"
  else
    echo "FAIL (код $?)"
    tail -5 "$log" | sed 's/^/    /'
    fail=1
  fi
}

step "Check format"  dart format --output=none --set-exit-if-changed lib test tool plugins setup.dart
step "Analyze"       flutter analyze --no-fatal-infos
step "Verify changelog" dart run tool/changelog.dart verify
step "Run tests"     flutter test --coverage
step "Check coverage" dart run tool/check_coverage.dart coverage/lcov.info 75

echo
if [ "$fail" -eq 0 ]; then
  echo "ВСЕ ШАГИ КОНВЕЙЕРА ЗЕЛЁНЫЕ"
else
  echo "ЕСТЬ КРАСНЫЕ — пушить нельзя"
fi
exit "$fail"
