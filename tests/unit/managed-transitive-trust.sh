#!/usr/bin/env bash
# G25 - managed guidance must not point back to actor-writable helper/registry paths.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# TMPDIR DAS SUITES: esta suite nao toma o lock (por desenho), mas cria temporarios igual as
# outras. Sem esta linha ela continuaria escrevendo em `/tmp`, que e tmpfs com teto FIXO de
# inodes - a causa medida de tres travamentos da bancada num dia. Ver tests/lib/tmpdir.sh.
if [ -r "$(dirname "$0")/../lib/tmpdir.sh" ]; then
  . "$(dirname "$0")/../lib/tmpdir.sh"
  _tb="$(tollens_tmpdir_base 2>/dev/null || true)"
  [ -n "$_tb" ] && [ -d "$_tb" ] && [ -w "$_tb" ] && export TMPDIR="$_tb"
  unset _tb
fi
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "NOT_VERIFIED: jq ausente" >&2; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

DATA="$T/sample.g25"
python3 - "$DATA" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text("x" * 400000)
PY
INPUT="$(jq -nc --arg f "$DATA" '{tool_name:"Read",tool_input:{file_path:$f}}')"

mk_adapter(){
  local dir="$1" id="$2"
  mkdir -p "$dir"
  jq -n --arg id "$id" '{id:$id,extensions:[".g25"],plans:[{id:"probe"}]}' > "$dir/g25.json"
}

run_hook(){
  local hook="$1" home="$2" dt="$3" dr="$4" out rc
  out="$(printf '%s' "$INPUT" | HOME="$home" DOCTOOL_BIN="$dt" DOC_ADAPTERS_DIR="$dr" bash "$hook" 2>&1)"; rc=$?
  printf '%s\n__RC__=%s\n' "$out" "$rc"
}

echo "== G25. managed copy derives helpers from its physical trust root =="
MROOT="$T/root with space/opt/tollens"
mkdir -p "$MROOT/hooks" "$MROOT/document-tools" "$MROOT/adapters/documents"
cp execution/hooks/read-budget.sh "$MROOT/hooks/read-budget.sh"
chmod +x "$MROOT/hooks/read-budget.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$MROOT/document-tools/doctool.sh"; chmod +x "$MROOT/document-tools/doctool.sh"
mk_adapter "$MROOT/adapters/documents" managed-g25

HOME_FAKE="$T/home"
mkdir -p "$HOME_FAKE/.claude/tollens/document-tools" "$HOME_FAKE/.claude/tollens/adapters/documents"
ACTOR_DT="$HOME_FAKE/.claude/tollens/document-tools/doctool.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$ACTOR_DT"; chmod +x "$ACTOR_DT"
mk_adapter "$HOME_FAKE/.claude/tollens/adapters/documents" hostile-g25

MO="$(run_hook "$MROOT/hooks/read-budget.sh" "$HOME_FAKE" "$ACTOR_DT" "$HOME_FAKE/.claude/tollens/adapters/documents")"
MRC="$(printf '%s\n' "$MO" | sed -n 's/^__RC__=//p')"
chk "managed hook reaches the adapter decision" "$MRC" 2
chk "managed registry wins over hostile overrides" "$(printf '%s' "$MO" | grep -c "adaptador 'managed-g25'" || true)" 1
chk "hostile user registry is not consumed" "$(printf '%s' "$MO" | grep -c 'hostile-g25' || true)" 0
chk "published doctool path is under managed root" "$(printf '%s' "$MO" | grep -F -c "$MROOT/document-tools/doctool.sh" || true)" 3
chk "actor doctool path is not published" "$(printf '%s' "$MO" | grep -F -c "$ACTOR_DT" || true)" 0

echo "== G25. user copy preserves user-scope semantics =="
UROOT="$T/user/hooks"; mkdir -p "$UROOT"; cp execution/hooks/read-budget.sh "$UROOT/read-budget.sh"; chmod +x "$UROOT/read-budget.sh"
UO="$(run_hook "$UROOT/read-budget.sh" "$HOME_FAKE" "$ACTOR_DT" "$HOME_FAKE/.claude/tollens/adapters/documents")"
URC="$(printf '%s\n' "$UO" | sed -n 's/^__RC__=//p')"
chk "user hook reaches the adapter decision" "$URC" 2
chk "user scope still honors its configured registry" "$(printf '%s' "$UO" | grep -c "adaptador 'hostile-g25'" || true)" 1
chk "user scope still publishes its configured doctool" "$(printf '%s' "$UO" | grep -F -c "$ACTOR_DT" || true)" 3

echo
printf 'PASS=%s FAIL=%s\n' "$P" "$F"
EXPECTED=8
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED" >&2
  exit 1
fi
[ "$F" -eq 0 ]
