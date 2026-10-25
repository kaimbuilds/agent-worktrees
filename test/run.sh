#!/usr/bin/env bash
# End-to-end tests for wt. Creates a throwaway repo in a temp dir.
set -euo pipefail

WT="$(cd "$(dirname "$0")/.." && pwd)/bin/wt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
ok()   { pass=$((pass + 1)); printf 'ok %d - %s\n' "$pass" "$1"; }
fail() { printf 'not ok - %s\n' "$1"; exit 1; }

cd "$TMP"
git init -q -b main app && cd app
git config user.email t@example.com && git config user.name test
mkdir -p src/auth src/api
echo "x" > src/auth/login.ts; echo "y" > src/api/routes.ts; echo "z" > .env.example
git add . && git commit -qm init
echo "SECRET=1" > .env            # untracked, should be copied
echo "LOCAL=1" > .env.local       # untracked, should be copied

"$WT" new auth --no-install --port >/dev/null
[ -d "$TMP/app-auth" ] || fail "worktree folder created"; ok "worktree folder created"
[ "$(git -C "$TMP/app-auth" branch --show-current)" = "agent/auth" ] || fail "branch"; ok "branch agent/auth"
grep -q SECRET=1 "$TMP/app-auth/.env" || fail ".env copied"; ok ".env copied"
grep -q 'PORT=3100' "$TMP/app-auth/.env.local" || fail "port"; ok "port 3100 assigned"

"$WT" new api --no-install --port >/dev/null
grep -q 'PORT=3101' "$TMP/app-api/.env.local" || fail "second port"; ok "second agent gets port 3101"

"$WT" new auth --no-install >/dev/null 2>&1 && fail "duplicate allowed"; ok "duplicate name rejected"
"$WT" new 'bad name' >/dev/null 2>&1 && fail "bad name allowed"; ok "invalid name rejected"

"$WT" claim auth src/auth ./src/shared/util.ts >/dev/null
"$WT" claim api src/api/ >/dev/null
"$WT" check >/dev/null 2>&1 || fail "false overlap"; ok "no overlap between src/auth and src/api"

"$WT" claim api src/shared/util.ts >/dev/null 2>&1 || true
"$WT" check >/dev/null 2>&1 && fail "overlap missed"; ok "exact file overlap detected"

"$WT" rm api >/dev/null
"$WT" claim api src/auth/login.ts >/dev/null 2>&1 || true
"$WT" check >/dev/null 2>&1 && fail "dir/file overlap missed"; ok "directory vs file overlap detected"
"$WT" rm api >/dev/null 2>&1 || true

# works from inside a worktree too
(cd "$TMP/app-auth" && "$WT" ls | grep -q 'agent/auth') || fail "ls from worktree"; ok "ls works from inside a worktree"
[ "$("$WT" path auth)" = "$TMP/app-auth" ] || fail "path"; ok "path prints worktree location"

echo "change" >> "$TMP/app-auth/src/auth/login.ts"
"$WT" rm auth >/dev/null 2>&1 && fail "removed dirty worktree"; ok "refuses to remove dirty worktree"
[ -f "$TMP/app-auth/.env" ] || fail "env deleted on refused rm"; ok "refused rm leaves env files alone"
"$WT" rm auth --force --delete-branch >/dev/null
[ ! -d "$TMP/app-auth" ] || fail "force rm"; ok "force remove + branch delete"
git show-ref --verify --quiet refs/heads/agent/auth && fail "branch kept"; ok "branch deleted"

printf '\nall %d tests passed\n' "$pass"
