#!/usr/bin/env bash

# Read-only MongoDB edition detector.
# Intended for customers to run and paste the output back to support.

set -u

SCRIPT_NAME="$(basename "$0")"
URI=""

usage() {
  cat <<EOF
Usage:
  ./${SCRIPT_NAME} [--uri mongodb://host:port]

What it does:
  - Checks local mongod/mongos binaries, installed packages, and running processes.
  - Optionally connects with mongosh when --uri is provided.
  - Prints whether the evidence indicates MongoDB Community, Enterprise, or is inconclusive.

Examples:
  ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} --uri mongodb://localhost:27017

Notes:
  - This script is read-only.
  - Do not paste credentials into --uri unless your support process allows it.
  - If authentication is required, run without --uri or use a safe support-approved URI.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --uri)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --uri requires a value." >&2
        exit 1
      fi
      URI="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

community_hits=0
enterprise_hits=0
unknown_hits=0

run_with_timeout() {
  # run_with_timeout <seconds> <command> [args...]
  # Uses the platform timeout command when available, with a Perl fallback for macOS.
  seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift @ARGV; exec @ARGV' "$seconds" "$@"
  else
    "$@"
  fi
}

print_header() {
  echo "MongoDB Edition Diagnostic"
  echo "=========================="
  echo "Date: $(date 2>/dev/null || echo unknown)"
  echo "Host: $(hostname 2>/dev/null || echo unknown)"
  echo "User: $(id -un 2>/dev/null || whoami 2>/dev/null || echo unknown)"
  echo
}

record() {
  # record <classification> <source> <detail>
  # classification: community | enterprise | unknown
  classification="$1"
  source="$2"
  detail="$3"

  case "$classification" in
    community) community_hits=$((community_hits + 1)) ;;
    enterprise) enterprise_hits=$((enterprise_hits + 1)) ;;
    *) unknown_hits=$((unknown_hits + 1)) ;;
  esac

  printf '%-12s | %-24s | %s\n' "$classification" "$source" "$detail"
}

classify_text() {
  # classify_text <source> <text>
  source="$1"
  text="$2"

  if printf '%s\n' "$text" | grep -Eiq '"modules"[[:space:]]*:[[:space:]]*\[[^]]*"enterprise"|modules:[[:space:]]*\[[^]]*enterprise|enterprise'; then
    record "enterprise" "$source" "enterprise module/package text found"
  elif printf '%s\n' "$text" | grep -Eiq '"modules"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]|modules:[[:space:]]*\[[[:space:]]*\]|mongodb-org|mongodb-community'; then
    record "community" "$source" "community package or empty modules list found"
  else
    record "unknown" "$source" "no edition marker found"
  fi
}

check_binary_version() {
  binary="$1"
  if command -v "$binary" >/dev/null 2>&1; then
    path="$(command -v "$binary" 2>/dev/null)"
    record "unknown" "${binary} path" "$path"
    version_output="$(run_with_timeout 5 "$binary" --version 2>&1)"
    classify_text "${binary} --version" "$version_output"
  else
    record "unknown" "${binary} path" "not found in PATH"
  fi
}

check_packages() {
  if command -v dpkg-query >/dev/null 2>&1; then
    packages="$(run_with_timeout 5 dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null | grep -Ei 'mongodb|mongod' || true)"
    if [ -n "$packages" ]; then
      classify_text "dpkg packages" "$packages"
      printf '%s\n' "$packages" | sed 's/^/             package: /'
    else
      record "unknown" "dpkg packages" "no MongoDB packages found"
    fi
  fi

  if command -v rpm >/dev/null 2>&1; then
    packages="$(run_with_timeout 5 rpm -qa 2>/dev/null | grep -Ei 'mongodb|mongod' || true)"
    if [ -n "$packages" ]; then
      classify_text "rpm packages" "$packages"
      printf '%s\n' "$packages" | sed 's/^/             package: /'
    else
      record "unknown" "rpm packages" "no MongoDB packages found"
    fi
  fi

  if command -v brew >/dev/null 2>&1; then
    packages="$(run_with_timeout 5 brew list --versions 2>/dev/null | grep -Ei 'mongodb|mongod' || true)"
    if [ -n "$packages" ]; then
      classify_text "brew packages" "$packages"
      printf '%s\n' "$packages" | sed 's/^/             package: /'
    else
      record "unknown" "brew packages" "no MongoDB packages found"
    fi
  fi
}

check_processes() {
  if command -v ps >/dev/null 2>&1; then
    processes="$(run_with_timeout 5 ps -eo pid=,comm=,args= 2>/dev/null | grep -E '[m]ongod|[m]ongos' || true)"
    if [ -n "$processes" ]; then
      classify_text "running processes" "$processes"
      printf '%s\n' "$processes" | sed 's/^/             process: /'
    else
      record "unknown" "running processes" "no mongod/mongos process found"
    fi
  fi
}

check_mongosh() {
  if [ -z "$URI" ]; then
    record "unknown" "mongosh buildInfo" "skipped; pass --uri to query a server"
    return
  fi

  if ! command -v mongosh >/dev/null 2>&1; then
    record "unknown" "mongosh buildInfo" "mongosh not found in PATH"
    return
  fi

  build_info="$(run_with_timeout 10 mongosh "$URI" --quiet --eval 'JSON.stringify(db.adminCommand({buildInfo: 1}))' 2>&1)"
  if printf '%s\n' "$build_info" | grep -Eq '"ok"[[:space:]]*:[[:space:]]*1'; then
    classify_text "mongosh buildInfo" "$build_info"
    version="$(printf '%s\n' "$build_info" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    modules="$(printf '%s\n' "$build_info" | sed -n 's/.*"modules"[[:space:]]*:[[:space:]]*\(\[[^]]*\]\).*/\1/p' | head -n 1)"
    [ -n "$version" ] && echo "             server version: $version"
    [ -n "$modules" ] && echo "             server modules: $modules"
  else
    record "unknown" "mongosh buildInfo" "could not query server; output: $(printf '%s' "$build_info" | tr '\n' ' ' | cut -c 1-180)"
  fi
}

print_result() {
  echo
  echo "Summary"
  echo "======="
  echo "Enterprise evidence: $enterprise_hits"
  echo "Community evidence:  $community_hits"
  echo "Unknown checks:       $unknown_hits"
  echo

  if [ "$enterprise_hits" -gt 0 ]; then
    echo "VERDICT: MongoDB Enterprise indicators were found."
    echo "Reason: Enterprise builds usually report the enterprise module in buildInfo or version output."
    exit 2
  fi

  if [ "$community_hits" -gt 0 ]; then
    echo "VERDICT: MongoDB Community indicators were found."
    echo "Reason: Community builds usually have an empty modules list or are installed as mongodb-org/mongodb-community packages."
    exit 0
  fi

  echo "VERDICT: Inconclusive. No reliable MongoDB edition marker was found."
  echo "Next step: rerun with --uri mongodb://host:port from a machine that can connect to MongoDB, or share package/binary details."
  exit 3
}

print_header
echo "Evidence"
echo "========"
check_binary_version mongod
check_binary_version mongos
check_packages
check_processes
check_mongosh
print_result
