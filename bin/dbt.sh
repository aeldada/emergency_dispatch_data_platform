# bin/dbt.sh — run dbt for this repo with the local Postgres connection.
#
# Why: dbt/profiles.yml holds no connection values, only env_var('PG_*')
# placeholders, and dbt does not read .env by itself. This wrapper hands
# the values over.
#
# What it does:
#   1. Reads ONLY the five PG_* lines (PG_HOST, PG_PORT, PG_USER,
#      PG_PASSWORD, PG_DATABASE) from .env as plain text; .env is never
#      sourced, so no other secret is loaded.
#   2. Checks each value (not empty; no quotes, spaces or '#') and stops
#      with a clear message naming the variable. Values are never printed.
#   3. Gives the values to dbt only (not to your shell) and starts
#      dbt <your arguments> --project-dir dbt, with profiles.yml in dbt/.
#
# Usage (repo root, .venv active), arguments are passed through unchanged:
#   bin/dbt.sh debug
#   bin/dbt.sh build
#   bin/dbt.sh test --select call_type_class
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO/.env"
REQUIRED="PG_HOST PG_PORT PG_USER PG_PASSWORD PG_DATABASE"

die() { echo "bin/dbt.sh: ERROR: $*" >&2; exit 2; }

[ -f "$ENV_FILE" ] || die ".env not found at $ENV_FILE"

# .env is the only source for these variables
for name in $REQUIRED; do unset "$name"; done

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  case "$line" in PG_*) ;; *) continue ;; esac
  name="${line%%=*}"
  case " $REQUIRED " in *" $name "*) ;; *) continue ;; esac   # only the 5 connection variables
  [ "$name" != "$line" ] || die "$name: line has no '='"
  value="${line#*=}"
  case "$value" in
    *\"*|*\'*) die "$name: value must not contain quotes" ;;
    *" "*|*$'\t'*) die "$name: value must not contain spaces" ;;
    *"#"*) die "$name: value must not contain '#'" ;;
  esac
  printf -v "$name" '%s' "$value"
  export "$name"
done < "$ENV_FILE"

for name in $REQUIRED; do
  [ -n "${!name:-}" ] || die "$name is missing or empty in .env"
done

export DBT_PROFILES_DIR="$REPO/dbt"
exec dbt ${1+"$@"} --project-dir "$REPO/dbt"   # ${1+"$@"}: bash 3.2-safe under set -u
