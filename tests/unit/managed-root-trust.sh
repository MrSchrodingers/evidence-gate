#!/usr/bin/env bash
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
W="$PWD/install/apply-managed.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"; if command -v sudo >/dev/null 2>&1; then sudo rm -rf "$T.root" 2>/dev/null || true; fi' EXIT
P=0; F=0
pass(){ P=$((P+1)); echo "PASS $1"; }
fail(){ F=$((F+1)); echo "FAIL $1"; }

if ! command -v sudo >/dev/null 2>&1 || ! sudo -n true >/dev/null 2>&1; then
  echo "SKIP managed-root-trust: sudo nao-interativo indisponivel"
  exit 0
fi

# 1. A user-owned privileged source must be rejected before any sibling helper executes.
MARK="$T/should-not-exist"
mkdir -p "$T/fake-repo/install"
cp "$W" "$T/fake-repo/install/apply-managed.sh"
cat > "$T/fake-repo/install/apply-managed-worker.sh" <<SH
#!/usr/bin/env bash
touch '$MARK'
exit 0
SH
chmod +x "$T/fake-repo/install/"*.sh
sudo -n env -u MANAGED_PREFIX -u TOLLENS_MANAGED_WORKER \
  "$T/fake-repo/install/apply-managed.sh" --dry-run >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 78 ] && [ ! -e "$MARK" ]; then pass user-owned-source-rejected; else fail user-owned-source-rejected; fi

# 2. A root-owned, non-writable, symlink-free snapshot is accepted.
ROOT_COPY="$T.root/repo"
sudo mkdir -p "$ROOT_COPY/install"
sudo cp "$W" "$ROOT_COPY/install/apply-managed.sh"
sudo sh -c "cat > '$ROOT_COPY/install/apply-managed-worker.sh' <<'SH'
#!/usr/bin/env bash
exit 0
SH"
sudo chown -R root:root "$T.root"
sudo chmod 0755 "$T.root" "$ROOT_COPY" "$ROOT_COPY/install" "$ROOT_COPY/install/"*.sh
sudo -n env -u MANAGED_PREFIX -u TOLLENS_MANAGED_WORKER \
  "$ROOT_COPY/install/apply-managed.sh" --dry-run >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then pass root-owned-source-accepted; else fail root-owned-source-accepted; fi

# 3. Privileged helper overrides are forbidden on the real root.
sudo -n env -u MANAGED_PREFIX TOLLENS_MANAGED_WORKER="$ROOT_COPY/install/apply-managed-worker.sh" \
  "$ROOT_COPY/install/apply-managed.sh" --dry-run >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 78 ]; then pass privileged-override-rejected; else fail privileged-override-rejected; fi

# 4. Any symlink inside the privileged source closure invalidates the snapshot.
sudo ln -s /etc/passwd "$ROOT_COPY/forbidden-link"
sudo -n env -u MANAGED_PREFIX -u TOLLENS_MANAGED_WORKER \
  "$ROOT_COPY/install/apply-managed.sh" --dry-run >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 78 ]; then pass source-symlink-rejected; else fail source-symlink-rejected; fi
sudo rm -f "$ROOT_COPY/forbidden-link"

# 5. Group/world-writable source material invalidates the privileged snapshot.
sudo chmod 0775 "$ROOT_COPY/install"
sudo -n env -u MANAGED_PREFIX -u TOLLENS_MANAGED_WORKER \
  "$ROOT_COPY/install/apply-managed.sh" --dry-run >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 78 ]; then pass writable-source-rejected; else fail writable-source-rejected; fi
sudo chmod 0755 "$ROOT_COPY/install"

# 6. Ownership postcondition is exercised under real uid 0 against an isolated prefix. The
# deliberately wrong owner with group=root catches the historical find precedence bug.
sudo sh -c "cat > '$ROOT_COPY/install/fake-owner.sh' <<'SH'
#!/usr/bin/env bash
p=\"\${MANAGED_PREFIX}\"
mkdir -p \"\$p/opt/tollens\" \"\$p/etc/claude-code\"
echo x > \"\$p/opt/tollens/x\"
echo '{}' > \"\$p/etc/claude-code/managed-settings.json\"
chmod 0755 \"\$p/opt/tollens\"
chmod 0644 \"\$p/opt/tollens/x\"
chown nobody:root \"\$p/opt/tollens/x\"
SH
chmod 0755 '$ROOT_COPY/install/fake-owner.sh'
chown root:root '$ROOT_COPY/install/fake-owner.sh'"
PFX="$T.root/prefix-owner"
sudo -n env MANAGED_PREFIX="$PFX" TOLLENS_MANAGED_WORKER="$ROOT_COPY/install/fake-owner.sh" \
  "$ROOT_COPY/install/apply-managed.sh" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ] && sudo test ! -e "$PFX/opt/tollens"; then pass wrong-owner-rejected; else fail wrong-owner-rejected; fi

echo "PASS=$P FAIL=$F"
[ "$F" -eq 0 ]
