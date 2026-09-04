#!/usr/bin/env bash
set -uo pipefail
# TMPDIR DAS SUITES: esta suite nao toma o lock (por desenho), mas cria temporarios igual as
# outras. Sem esta linha ela continuaria escrevendo em `/tmp`, que e tmpfs com teto FIXO de
# inodes - a causa medida de tres travamentos da bancada num dia. Ver tests/lib/tmpdir.sh.
if [ -r "$(dirname "$0")/../lib/tmpdir.sh" ]; then
  . "$(dirname "$0")/../lib/tmpdir.sh"
  _tb="$(tollens_tmpdir_base 2>/dev/null || true)"
  [ -n "$_tb" ] && [ -d "$_tb" ] && [ -w "$_tb" ] && export TMPDIR="$_tb"
  unset _tb
fi
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
W="$ROOT/install/apply-managed.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then P=$((P+1)); echo "PASS $1"; else F=$((F+1)); echo "FAIL $1 got=$2 want=$3"; fi; }

cat > "$T/fake.sh" <<'SH'
#!/usr/bin/env bash
p="${MANAGED_PREFIX}"
mkdir -p "$p/opt/tollens" "$p/etc/claude-code"
echo new > "$p/opt/tollens/x"
echo '{}' > "$p/etc/claude-code/managed-settings.json"
case "${FAKE_MODE:-ok}" in
  fail) exit 1 ;;
  unsafe) chmod 0777 "$p/opt/tollens/x" ;;
  wrongmode) chmod 0600 "$p/opt/tollens/x" ;;
esac
SH
chmod +x "$T/fake.sh"

PFX="$T/p1"
FAKE_MODE=fail MANAGED_PREFIX="$PFX" TOLLENS_MANAGED_WORKER="$T/fake.sh" "$W" >/dev/null 2>&1
rc=$?
chk first-deploy-rc "$rc" 1
chk first-deploy-tree "$([ -e "$PFX/opt/tollens" ] && echo present || echo absent)" absent
chk first-deploy-policy "$([ -e "$PFX/etc/claude-code/managed-settings.json" ] && echo present || echo absent)" absent

PFX="$T/p2"
mkdir -p "$PFX/opt/tollens" "$PFX/etc/claude-code"
echo old > "$PFX/opt/tollens/x"
echo old > "$PFX/etc/claude-code/managed-settings.json"
FAKE_MODE=fail MANAGED_PREFIX="$PFX" TOLLENS_MANAGED_WORKER="$T/fake.sh" "$W" >/dev/null 2>&1
rc=$?
chk existing-rc "$rc" 1
chk existing-tree "$(cat "$PFX/opt/tollens/x")" old
chk existing-policy "$(cat "$PFX/etc/claude-code/managed-settings.json")" old

PFX="$T/p3"
FAKE_MODE=unsafe MANAGED_PREFIX="$PFX" TOLLENS_MANAGED_WORKER="$T/fake.sh" "$W" >/dev/null 2>&1
rc=$?
chk unsafe-rc "$rc" 1
chk unsafe-cleanup "$([ -e "$PFX/opt/tollens" ] && echo present || echo absent)" absent

PFX="$T/p4"
FAKE_MODE=wrongmode MANAGED_PREFIX="$PFX" TOLLENS_MANAGED_WORKER="$T/fake.sh" "$W" >/dev/null 2>&1
rc=$?
chk exact-mode-rc "$rc" 1
chk exact-mode-cleanup "$([ -e "$PFX/opt/tollens" ] && echo present || echo absent)" absent

echo "PASS=$P FAIL=$F"
[ "$F" -eq 0 ]
