#!/usr/bin/env bash
# Self-hosted VZ soak for 0.9. Does not boot a VM unless --live.
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

DEFAULT_CYCLES=50
GATE_09=0.9
GATE_10=1.0
RUNNER_LABEL=gmak8-vm
NODEPORT_HOST=127.0.0.1
CORE_PROCESS=gmak8-core
HELPERS_DIR=Contents/Helpers
CLI_NAME=gmak8
DISK_ATTACHMENT=nvme
DISK_CACHE=cached
DISK_SYNC=full
DISK_FORBIDDEN=virtio-blk
FSCK_FLAG=-n
IMAGE_SKIP_REASON="no airgap workload blob; refusing Docker Hub pull"
VIRTCTL_DEFERRED="virtctl --stdio soak waits for a Ready VMI (PRs 27-28)"
STEPS_09="startStop,dirtyKillFsck,loadImage,nginxNodePortCurl"
STEPS_10_ONLY="pvcUnderMntData,u1NanoClusterInstancetype,aarch64VMIReady,saVirtiofs,virtctlPortForwardStdio"

BUNDLE_ID=dev.gmak8.app
APP_DEFAULT=/Applications/gmak8.app

die() {
  echo "soak: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: bash scripts/soak.sh --self-test|--plan|--live|--nodeport [--cycles N] [--gate 0.9|1.0]

  --self-test  Unit-test plan/helpers. Does not boot a VM.
  --plan       Print the soak plan. Does not boot a VM.
  --live       Run VZ soak on a self-hosted ${RUNNER_LABEL} runner.
  --nodeport   Curl an already-Running NodePort on ${NODEPORT_HOST} (no start/stop).

Nightly default is ${DEFAULT_CYCLES} start/stop cycles. 1.0 KubeVirt steps are listed
but skipped until a Ready VMI (PRs 27-28). Never pulls from Docker Hub. NodePort curl is ${NODEPORT_HOST} only.
EOF
}

resolve_cycles() {
  local raw=${1:-}
  if [[ -z "${raw}" ]]; then
    echo "${DEFAULT_CYCLES}"
    return 0
  fi
  case "${raw}" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  if [[ "${raw}" -le 0 ]]; then
    return 1
  fi
  echo "${raw}"
}

resolve_gate() {
  local raw=${1:-}
  if [[ -z "${raw}" ]]; then
    echo "${GATE_09}"
    return 0
  fi
  if [[ "${raw}" == "${GATE_09}" || "${raw}" == "${GATE_10}" ]]; then
    echo "${raw}"
    return 0
  fi
  return 1
}

steps_for_gate() {
  local gate=$1
  case "${gate}" in
    "${GATE_09}")
      echo "${STEPS_09}"
      ;;
    "${GATE_10}")
      echo "${STEPS_09},${STEPS_10_ONLY}"
      ;;
    *)
      return 1
      ;;
  esac
}

virtctl_in_gate() {
  local gate=$1
  local steps
  steps=$(steps_for_gate "${gate}")
  case ",${steps}," in
    *,virtctlPortForwardStdio,*)
      return 0
      ;;
  esac
  return 1
}

node_port_url() {
  local port=$1
  local host=${2:-${NODEPORT_HOST}}
  if [[ "${host}" != "${NODEPORT_HOST}" ]]; then
    die "NodePort curl host must be ${NODEPORT_HOST} (got ${host})"
  fi
  case "${port}" in
    ''|*[!0-9]*)
      die "NodePort must be a positive integer (got ${port})"
      ;;
  esac
  if [[ "${port}" -le 0 || "${port}" -gt 65535 ]]; then
    die "NodePort out of range: ${port}"
  fi
  echo "http://${host}:${port}"
}

assert_loopback_url() {
  local url=$1
  case "${url}" in
    http://127.0.0.1:*|https://127.0.0.1:*)
      return 0
      ;;
  esac
  die "NodePort curl target must be ${NODEPORT_HOST}: ${url}"
}

host_paths() {
  local home=${1:-${HOME}}
  APP_SUPPORT="${home}/Library/Application Support/${BUNDLE_ID}"
  ENGINE_SOCK="${APP_SUPPORT}/engine.sock"
  KUBECONFIG_FILE="${APP_SUPPORT}/kubeconfig"
  VM_DIR="${APP_SUPPORT}/vm"
  OS_IMG="${VM_DIR}/os.img"
  DATA_IMG="${VM_DIR}/data.img"
  OS_LOCK="${OS_IMG}.lock"
  DATA_LOCK="${DATA_IMG}.lock"
}

resolve_gmak8_cli() {
  if [[ -n "${GMAK8_CLI:-}" ]]; then
    if [[ -x "${GMAK8_CLI}" ]]; then
      echo "${GMAK8_CLI}"
      return 0
    fi
    die "GMAK8_CLI is not executable: ${GMAK8_CLI}"
  fi
  local app=${GMAK8_APP:-${APP_DEFAULT}}
  local helpers="${app}/${HELPERS_DIR}/${CLI_NAME}"
  if [[ -x "${helpers}" ]]; then
    echo "${helpers}"
    return 0
  fi
  # Contents/Helpers is the pin. Do not search PATH (wrong binary / Team ID).
  return 1
}

normalize_pids() {
  echo "$*" | tr '\n' ' ' | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

pids_still_running() {
  local old live leftover="" pid
  old=$(normalize_pids "$1")
  live=$(normalize_pids "$2")
  for pid in ${old}; do
    if [[ " ${live} " == *" ${pid} "* ]]; then
      leftover="${leftover} ${pid}"
    fi
  done
  normalize_pids "${leftover}"
}

resolve_gmak8_core() {
  # LaunchAgent owns the process. Never resolve gmak8-core from PATH.
  local raw=""
  if command -v pgrep >/dev/null 2>&1; then
    raw=$(pgrep -x "${CORE_PROCESS}" 2>/dev/null || true)
  fi
  normalize_pids "${raw}"
}

find_e2fsck() {
  if [[ -n "${GMAK8_SOAK_E2FSCK:-}" ]]; then
    echo "${GMAK8_SOAK_E2FSCK}"
    return 0
  fi
  local candidate
  for candidate in \
    /opt/homebrew/opt/e2fsprogs/sbin/e2fsck \
    /opt/homebrew/sbin/e2fsck \
    /usr/local/opt/e2fsprogs/sbin/e2fsck \
    /usr/local/sbin/e2fsck \
    /usr/sbin/e2fsck \
    /sbin/e2fsck \
    /opt/homebrew/opt/e2fsprogs/sbin/fsck.ext4 \
    /usr/local/sbin/fsck.ext4
  do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

refuse_github_hosted_live() {
  if [[ "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]]; then
    die "live VZ soak cannot run on GitHub-hosted runners (need self-hosted ${RUNNER_LABEL})"
  fi
  case "${ImageOS:-}" in
    macos*)
      die "live VZ soak cannot run on GitHub-hosted macOS (${ImageOS})"
      ;;
  esac
}

print_plan() {
  local steps
  steps=$(steps_for_gate "${GATE}")
  local virtctl=0
  if virtctl_in_gate "${GATE}"; then
    virtctl=1
  fi
  cat <<EOF
GATE=${GATE}
RUNNER_LABEL=${RUNNER_LABEL}
RUNS_ON=self-hosted,${RUNNER_LABEL}
CYCLES=${CYCLES}
NODEPORT_HOST=${NODEPORT_HOST}
STEPS=${steps}
VIRTCTL=${virtctl}
VIRTCTL_LIVE=0
DOCKER_HUB=0
DISK_ATTACHMENT=${DISK_ATTACHMENT}
DISK_CACHE=${DISK_CACHE}
DISK_SYNC=${DISK_SYNC}
DISK_FORBIDDEN=${DISK_FORBIDDEN}
LOCK_UNLINK=0
FSCK_TARGET=data.img
FSCK_FLAG=${FSCK_FLAG}
WORKFLOW_DISPATCH=1
GITHUB_HOSTED=0
IMAGE_SKIP_REASON=${IMAGE_SKIP_REASON}
VIRTCTL_DEFERRED=${VIRTCTL_DEFERRED}
EOF
}

# Self-test fake sockets only. Live start/stop/status use Contents/Helpers/gmak8
# so PeerAuth sees the gmak8 Team ID (never PATH python/nc on engine.sock).
engine_rpc() {
  local sock=$1
  local op=$2
  python3 - "${sock}" "${op}" <<'PY'
import json
import os
import socket
import sys

def eprint(msg):
    sys.stderr.write(msg + "\n")

path = sys.argv[1]
op = sys.argv[2]
timeout = float(os.environ.get("GMAK8_SOAK_RPC_TIMEOUT", "5"))
if not os.path.exists(path):
    eprint("gmak8-core is not running (engine.sock is missing).")
    sys.exit(2)

payload = {"op": op}
if op == "reset":
    payload["force"] = True

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(timeout)
try:
    sock.connect(path)
except OSError:
    eprint("gmak8-core is not running (engine.sock is missing).")
    sys.exit(2)

def recv_line(buf):
    while b"\n" not in buf:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            eprint("could not talk to gmak8-core.")
            sys.exit(3)
        if not chunk:
            eprint("could not talk to gmak8-core.")
            sys.exit(3)
        buf += chunk
    line, rest = buf.split(b"\n", 1)
    return line, rest

try:
    sock.sendall((json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8"))
    raw, rest = recv_line(b"")
    try:
        reply = json.loads(raw.decode("utf-8"))
    except ValueError:
        eprint("could not talk to gmak8-core.")
        sys.exit(3)
    err = reply.get("error")
    if err:
        eprint("gmak8-core returned error: %s." % err)
        sys.exit(4)
    if op == "status":
        event_raw, _ = recv_line(rest)
        try:
            event = json.loads(event_raw.decode("utf-8"))
        except ValueError:
            eprint("could not talk to gmak8-core.")
            sys.exit(3)
        sys.stdout.write(json.dumps(event, sort_keys=True) + "\n")
    else:
        sys.stdout.write(json.dumps(reply, sort_keys=True) + "\n")
except socket.timeout:
    eprint("could not talk to gmak8-core.")
    sys.exit(3)
finally:
    sock.close()
PY
}

require_cli() {
  if [[ -z "${GMAK8_CLI_BIN:-}" || ! -x "${GMAK8_CLI_BIN}" ]]; then
    die "gmak8 CLI is not resolved under ${HELPERS_DIR}"
  fi
}

engine_state() {
  require_cli
  local out
  out=$("${GMAK8_CLI_BIN}" status) || return $?
  echo "${out}" | awk -F': ' '/^State: / { print $2; exit }' | tr '[:upper:]' '[:lower:]'
}

wait_for_state() {
  local want=$1
  local timeout=$2
  local start=$SECONDS
  local state=""
  while true; do
    if state=$(engine_state 2>/dev/null); then
      if [[ "${state}" == "${want}" ]]; then
        echo "soak: state=${state}"
        return 0
      fi
      if [[ "${state}" == "failed" && "${want}" != "failed" ]]; then
        die "cluster entered failed state (want ${want})"
      fi
    else
      state="(unreachable)"
    fi
    if (( SECONDS - start >= timeout )); then
      die "timeout waiting for state=${want} (last=${state})"
    fi
    sleep 2
  done
}

cluster_start() {
  require_cli
  local rc=0
  local err
  err=$("${GMAK8_CLI_BIN}" start 2>&1) || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    return 0
  fi
  if [[ "${err}" == *conflict* ]]; then
    local state
    state=$(engine_state)
    if [[ "${state}" == "running" || "${state}" == "starting" || "${state}" == "degraded" ]]; then
      return 0
    fi
  fi
  die "start failed (${rc}): ${err}"
}

cluster_stop() {
  require_cli
  local rc=0
  local err
  err=$("${GMAK8_CLI_BIN}" stop 2>&1) || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    return 0
  fi
  die "stop failed (${rc}): ${err}"
}

wait_flock_released() {
  local lock=$1
  local timeout=${2:-60}
  python3 - "${lock}" "${timeout}" <<'PY'
import fcntl
import os
import sys
import time

path = sys.argv[1]
timeout = float(sys.argv[2])
try:
    fd = os.open(path, os.O_RDWR)
except OSError:
    sys.stderr.write("lock file missing: %s\n" % path)
    sys.exit(1)
try:
    os.fchmod(fd, 0o600)
    deadline = time.time() + timeout
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(fd, fcntl.LOCK_UN)
            sys.exit(0)
        except OSError:
            if time.time() >= deadline:
                sys.exit(1)
            time.sleep(0.2)
finally:
    os.close(fd)
    # Never unlink sidecar *.lock files.
PY
}

flock_is_held() {
  python3 - "$1" <<'PY'
import fcntl
import os
import sys

path = sys.argv[1]
try:
    fd = os.open(path, os.O_RDWR)
except OSError:
    sys.exit(2)
try:
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.flock(fd, fcntl.LOCK_UN)
    sys.exit(1)
except OSError:
    sys.exit(0)
finally:
    os.close(fd)
PY
}

assert_lock_exists() {
  local lock=$1
  if [[ ! -e "${lock}" ]]; then
    die "expected lock file to remain: ${lock}"
  fi
}

dirty_kill_core() {
  local pids
  pids=$(resolve_gmak8_core)
  if [[ -z "${pids}" ]]; then
    die "no ${CORE_PROCESS} process to dirty-kill"
  fi
  echo "soak: dirty-kill ${CORE_PROCESS} pids: ${pids}"
  # SIGKILL: no ACPI stop. Disks are live. Do not resolve the binary from PATH.
  # shellcheck disable=SC2086
  kill -9 ${pids} || true
  local start=$SECONDS
  while true; do
    local live leftover
    live=$(resolve_gmak8_core)
    leftover=$(pids_still_running "${pids}" "${live}")
    if [[ -z "${leftover}" ]]; then
      break
    fi
    if (( SECONDS - start >= 30 )); then
      die "${CORE_PROCESS} still alive after SIGKILL: ${leftover}"
    fi
    sleep 0.2
  done
}

fsck_data_image() {
  local img=$1
  local ck
  if ! ck=$(find_e2fsck); then
    die "e2fsck not found; host-side ${FSCK_TARGET} check is e2fsck ${FSCK_FLAG} (NVMe .${DISK_CACHE}+.${DISK_SYNC}, never ${DISK_FORBIDDEN})"
  fi
  echo "soak: ${ck} ${FSCK_FLAG} ${img} (ext4 on NVMe .${DISK_CACHE}+.${DISK_SYNC})"
  local rc=0
  "${ck}" "${FSCK_FLAG}" "${img}" || rc=$?
  # -n cannot replay the journal after dirty-kill; 0 clean, 4 uncorrected (journal).
  if [[ "${rc}" -ge 8 ]]; then
    die "e2fsck ${FSCK_FLAG} failed rc=${rc}"
  fi
  echo "soak: fsck rc=${rc}"
}

skip() {
  echo "soak: skip $*"
}

load_image_or_skip() {
  local blob=${GMAK8_SOAK_IMAGE:-}
  if [[ -z "${blob}" || ! -f "${blob}" ]]; then
    skip "loadImage: ${IMAGE_SKIP_REASON}"
    return 0
  fi
  skip "loadImage: engine loadImage is not available; ${IMAGE_SKIP_REASON}"
}

pick_tcp_node_port() {
  python3 -c '
import json
import sys

data = json.load(sys.stdin)
items = data.get("items") or []
for svc in items:
    spec = svc.get("spec") or {}
    kind = spec.get("type")
    if kind not in ("NodePort", "LoadBalancer"):
        continue
    for port in spec.get("ports") or []:
        proto = str(port.get("protocol") or "TCP").upper()
        node_port = port.get("nodePort")
        if proto != "TCP":
            continue
        if not isinstance(node_port, int) or node_port <= 0:
            continue
        print(node_port)
        sys.exit(0)
sys.exit(1)
'
}

nginx_nodeport_or_skip() {
  host_paths
  if [[ ! -f "${KUBECONFIG_FILE}" ]]; then
    die "kubeconfig missing at ${KUBECONFIG_FILE}"
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    die "kubectl is required for NodePort curl (kubeconfig ${KUBECONFIG_FILE}; never PATH docker)"
  fi
  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required for NodePort soak"
  fi
  local json port url code
  if ! json=$(kubectl --kubeconfig="${KUBECONFIG_FILE}" get svc -A -o json); then
    die "kubectl get svc failed"
  fi
  if ! port=$(printf '%s' "${json}" | pick_tcp_node_port); then
    die "no TCP NodePort or LoadBalancer nodePort on the cluster"
  fi
  url=$(node_port_url "${port}")
  assert_loopback_url "${url}"
  echo "soak: NodePort curl ${url}"
  code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 10 "${url}/" || true)
  if [[ -z "${code}" || "${code}" == "000" ]]; then
    die "NodePort curl ${url} did not connect"
  fi
  echo "soak: NodePort ${url} HTTP ${code}"
}

run_deferred_1_0() {
  skip "pvc under /mnt/data: ${VIRTCTL_DEFERRED}"
  skip "u1.nano ClusterInstancetype: ${VIRTCTL_DEFERRED}"
  skip "aarch64 VMI Ready: ${VIRTCTL_DEFERRED}"
  skip "SA virtiofs: ${VIRTCTL_DEFERRED}"
  skip "virtctl stdio port-forward: ${VIRTCTL_DEFERRED}"
}

run_live() {
  refuse_github_hosted_live
  command -v python3 >/dev/null 2>&1 || die "python3 is required for sidecar flock wait"
  host_paths
  if ! GMAK8_CLI_BIN=$(resolve_gmak8_cli); then
    die "gmak8 CLI missing under ${GMAK8_APP:-${APP_DEFAULT}}/${HELPERS_DIR} (do not use PATH)"
  fi
  echo "soak: cli=${GMAK8_CLI_BIN}"
  echo "soak: socket=${ENGINE_SOCK}"
  if [[ ! -e "${ENGINE_SOCK}" ]]; then
    die "gmak8-core is not running (engine.sock is missing)."
  fi
  if [[ ! -f "${OS_IMG}" ]]; then
    die "os.img missing at ${OS_IMG}; soak does not vendor a guest image"
  fi

  local start_timeout=${GMAK8_SOAK_START_TIMEOUT:-900}
  local stop_timeout=${GMAK8_SOAK_STOP_TIMEOUT:-180}
  local flock_timeout=${GMAK8_SOAK_FLOCK_TIMEOUT:-60}

  local i=1
  while [[ "${i}" -le "${CYCLES}" ]]; do
    echo "soak: start/stop ${i}/${CYCLES}"
    cluster_start
    wait_for_state running "${start_timeout}"
    cluster_stop
    wait_for_state stopped "${stop_timeout}"
    i=$((i + 1))
  done

  echo "soak: dirty-kill fsck"
  cluster_start
  wait_for_state running "${start_timeout}"
  dirty_kill_core
  wait_flock_released "${OS_LOCK}" "${flock_timeout}" || die "os.img.lock still held"
  wait_flock_released "${DATA_LOCK}" "${flock_timeout}" || die "data.img.lock still held"
  assert_lock_exists "${OS_LOCK}"
  assert_lock_exists "${DATA_LOCK}"
  fsck_data_image "${DATA_IMG}"
  assert_lock_exists "${OS_LOCK}"
  assert_lock_exists "${DATA_LOCK}"

  echo "soak: wait for ${CORE_PROCESS} restart after KeepAlive"
  local wait_start=$SECONDS
  while [[ ! -e "${ENGINE_SOCK}" ]] || ! "${GMAK8_CLI_BIN}" status >/dev/null 2>&1; do
    if (( SECONDS - wait_start >= 60 )); then
      die "gmak8-core did not come back after dirty-kill"
    fi
    sleep 1
  done

  cluster_start
  wait_for_state running "${start_timeout}"
  load_image_or_skip
  nginx_nodeport_or_skip
  if [[ "${GATE}" == "${GATE_10}" ]]; then
    run_deferred_1_0
  fi
  cluster_stop
  wait_for_state stopped "${stop_timeout}"
  echo "soak: live 0.9 complete (cycles=${CYCLES})"
}

# --- self-test (no VM) -------------------------------------------------------

assert_eq() {
  local got=$1
  local want=$2
  local msg=$3
  if [[ "${got}" != "${want}" ]]; then
    die "${msg}: got '${got}' want '${want}'"
  fi
}

assert_fails() {
  if ( "$@" ) >/dev/null 2>&1; then
    die "expected failure: $*"
  fi
}

test_cycles() {
  assert_eq "$(resolve_cycles "")" "50" "default cycles"
  assert_eq "$(resolve_cycles 50)" "50" "cycles 50"
  assert_eq "$(resolve_cycles 1)" "1" "cycles 1"
  assert_fails resolve_cycles 0
  assert_fails resolve_cycles -1
  assert_fails resolve_cycles abc
}

test_gate() {
  assert_eq "$(resolve_gate "")" "${GATE_09}" "default gate"
  assert_eq "$(resolve_gate 0.9)" "${GATE_09}" "gate 0.9"
  assert_eq "$(resolve_gate 1.0)" "${GATE_10}" "gate 1.0"
  assert_fails resolve_gate 2.0
}

test_steps() {
  assert_eq "$(steps_for_gate 0.9)" "${STEPS_09}" "0.9 steps"
  local steps10
  steps10=$(steps_for_gate 1.0)
  case "${steps10}" in
    *virtctlPortForwardStdio*) ;;
    *) die "1.0 steps must include virtctlPortForwardStdio" ;;
  esac
  case "${STEPS_09}" in
    *virtctl*)
      die "0.9 steps must not include virtctl"
      ;;
  esac
  if virtctl_in_gate 0.9; then
    die "0.9 must not include virtctl"
  fi
  virtctl_in_gate 1.0 || die "1.0 plan must list virtctl"
}

test_nodeport() {
  assert_eq "$(node_port_url 30080)" "http://127.0.0.1:30080" "nodeport url"
  assert_fails node_port_url 30080 0.0.0.0
  assert_fails node_port_url 30080 192.168.127.2
  assert_loopback_url "http://127.0.0.1:30080"
  assert_fails assert_loopback_url "http://0.0.0.0:30080"
  assert_fails assert_loopback_url "http://192.168.127.2:30080"
  local got
  got=$(
    printf '%s' '{"items":[{"spec":{"type":"LoadBalancer","ports":[{"protocol":"TCP","port":80,"nodePort":31666}]}}]}' \
      | pick_tcp_node_port
  )
  assert_eq "${got}" "31666" "pick traefik nodePort"
  if printf '%s' '{"items":[{"spec":{"type":"ClusterIP","ports":[{"protocol":"TCP","port":80}]}}]}' | pick_tcp_node_port; then
    die "ClusterIP must not yield a NodePort"
  fi
}

test_cli_helpers_not_path() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "${tmp}/gmak8.app/${HELPERS_DIR}" "${tmp}/path"
  printf '#!/bin/sh\necho helpers\n' >"${tmp}/gmak8.app/${HELPERS_DIR}/${CLI_NAME}"
  printf '#!/bin/sh\necho path\n' >"${tmp}/path/${CLI_NAME}"
  chmod 700 "${tmp}/gmak8.app/${HELPERS_DIR}/${CLI_NAME}" "${tmp}/path/${CLI_NAME}"
  local got
  got=$(GMAK8_APP="${tmp}/gmak8.app" PATH="${tmp}/path:/usr/bin:/bin" resolve_gmak8_cli)
  assert_eq "${got}" "${tmp}/gmak8.app/${HELPERS_DIR}/${CLI_NAME}" "cli from Helpers"
  if GMAK8_APP="${tmp}/missing.app" PATH="${tmp}/path:/usr/bin:/bin" resolve_gmak8_cli; then
    rm -rf "${tmp}"
    die "CLI must not resolve from PATH"
  fi
  rm -rf "${tmp}"
}

test_socket_errors() {
  command -v python3 >/dev/null 2>&1 || die "python3 required for socket self-test"
  local tmp
  tmp=$(mktemp -d)
  local missing="${tmp}/missing.sock"
  local rc=0
  set +e
  engine_rpc "${missing}" status >/dev/null 2>"${tmp}/err"
  rc=$?
  set -e
  if [[ "${rc}" -ne 2 ]]; then
    rm -rf "${tmp}"
    die "missing socket must exit 2 (got ${rc})"
  fi
  grep -q "engine.sock is missing" "${tmp}/err" || {
    rm -rf "${tmp}"
    die "missing socket must say engine.sock is missing"
  }

  local sock="${tmp}/engine.sock"
  python3 - "${sock}" <<'PY' &
import os, socket, sys, time
path = sys.argv[1]
if os.path.exists(path):
    os.unlink(path)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
os.chmod(path, 0o600)
s.listen(1)
s.settimeout(8)
conn, _ = s.accept()
# Post-connect stall: client must not classify this as a missing socket.
time.sleep(8)
conn.close()
s.close()
os.unlink(path)
PY
  local server=$!
  local waits=0
  while [[ ! -S "${sock}" ]]; do
    waits=$((waits + 1))
    if [[ "${waits}" -gt 50 ]]; then
      kill "${server}" 2>/dev/null || true
      rm -rf "${tmp}"
      die "test socket did not appear"
    fi
    sleep 0.05
  done
  rc=0
  set +e
  GMAK8_SOAK_RPC_TIMEOUT=0.4 engine_rpc "${sock}" status >/dev/null 2>"${tmp}/err2"
  rc=$?
  set -e
  kill "${server}" 2>/dev/null || true
  wait "${server}" 2>/dev/null || true
  if [[ "${rc}" -ne 3 ]]; then
    rm -rf "${tmp}"
    die "post-connect timeout must exit 3 (got ${rc})"
  fi
  grep -q "could not talk to gmak8-core" "${tmp}/err2" || {
    rm -rf "${tmp}"
    die "post-connect IO must not be classified as missing socket"
  }
  rm -f "${sock}"

  python3 - "${sock}" <<'PY' &
import os, socket, sys
path = sys.argv[1]
if os.path.exists(path):
    os.unlink(path)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
os.chmod(path, 0o600)
s.listen(1)
s.settimeout(5)
conn, _ = s.accept()
conn.sendall(b'{"error":"unauthorized"}\n')
conn.close()
s.close()
os.unlink(path)
PY
  server=$!
  waits=0
  while [[ ! -S "${sock}" ]]; do
    waits=$((waits + 1))
    if [[ "${waits}" -gt 50 ]]; then
      kill "${server}" 2>/dev/null || true
      rm -rf "${tmp}"
      die "auth test socket did not appear"
    fi
    sleep 0.05
  done
  rc=0
  set +e
  engine_rpc "${sock}" status >/dev/null 2>"${tmp}/err3"
  rc=$?
  set -e
  kill "${server}" 2>/dev/null || true
  wait "${server}" 2>/dev/null || true
  if [[ "${rc}" -ne 4 ]]; then
    rm -rf "${tmp}"
    die "unauthorized must exit 4 (got ${rc})"
  fi
  grep -q "unauthorized" "${tmp}/err3" || {
    rm -rf "${tmp}"
    die "auth error must be reported as engine error"
  }
  if grep -q "engine.sock is missing" "${tmp}/err3"; then
    rm -rf "${tmp}"
    die "auth error must not be classified as missing socket"
  fi
  rm -rf "${tmp}"
}

test_lock_not_unlinked() {
  local tmp
  tmp=$(mktemp -d)
  local lock="${tmp}/data.img.lock"
  : >"${lock}"
  chmod 600 "${lock}"
  python3 - "${lock}" <<'PY' &
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_RDWR)
fcntl.flock(fd, fcntl.LOCK_EX)
time.sleep(8)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
PY
  local holder=$!
  local waited=0
  while ! flock_is_held "${lock}"; do
    waited=$((waited + 1))
    if [[ "${waited}" -gt 100 ]]; then
      kill "${holder}" 2>/dev/null || true
      rm -rf "${tmp}"
      die "holder never acquired LOCK_EX"
    fi
    sleep 0.05
  done
  local rc=0
  set +e
  wait_flock_released "${lock}" 0.4
  rc=$?
  set -e
  if [[ "${rc}" -eq 0 ]]; then
    kill "${holder}" 2>/dev/null || true
    rm -rf "${tmp}"
    die "flock wait should fail while held"
  fi
  kill "${holder}" 2>/dev/null || true
  wait "${holder}" 2>/dev/null || true
  wait_flock_released "${lock}" 2 || {
    rm -rf "${tmp}"
    die "flock should release after holder exits"
  }
  if [[ ! -e "${lock}" ]]; then
    rm -rf "${tmp}"
    die "lock file must not be unlinked"
  fi
  if wait_flock_released "${tmp}/missing.lock" 0.2 2>/dev/null; then
    rm -rf "${tmp}"
    die "missing lock file must fail without O_CREAT"
  fi
  if [[ -e "${tmp}/missing.lock" ]]; then
    rm -rf "${tmp}"
    die "wait_flock_released must not create missing lock files"
  fi
  rm -rf "${tmp}"
}

test_pids_still_running_newlines() {
  local old=$'111\n222'
  local live=$'111\n333'
  local gone=$'333\n444'
  assert_eq "$(pids_still_running "${old}" "${live}")" "111" "newline pgrep leftover"
  assert_eq "$(pids_still_running "${old}" "${gone}")" "" "newline pgrep all gone"
  assert_eq "$(pids_still_running "111 222" "111 222 333")" "111 222" "space pids still live"
  assert_eq "$(normalize_pids "${old}")" "111 222" "normalize pgrep newlines"
}

test_live_rpc_is_cli() {
  grep -Fq '"${GMAK8_CLI_BIN}" start' "${SCRIPT_PATH}" || die "live start must use Helpers CLI"
  grep -Fq '"${GMAK8_CLI_BIN}" stop' "${SCRIPT_PATH}" || die "live stop must use Helpers CLI"
  grep -Fq '"${GMAK8_CLI_BIN}" status' "${SCRIPT_PATH}" || die "live status must use Helpers CLI"
  grep -Fq 'cluster_start' "${SCRIPT_PATH}" || die "missing cluster_start"
  if grep -A20 '^cluster_start()' "${SCRIPT_PATH}" | grep -q 'engine_rpc'; then
    die "cluster_start must not call engine_rpc"
  fi
  if grep -A20 '^cluster_stop()' "${SCRIPT_PATH}" | grep -q 'engine_rpc'; then
    die "cluster_stop must not call engine_rpc"
  fi
  if grep -A20 '^engine_state()' "${SCRIPT_PATH}" | grep -q 'engine_rpc'; then
    die "engine_state must not call engine_rpc"
  fi
}

test_fsck_flags() {
  local tmp
  tmp=$(mktemp -d)
  local img="${tmp}/data.img"
  : >"${img}"
  local mock="${tmp}/e2fsck"
  cat >"${mock}" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"${GMAK8_SOAK_E2FSCK_ARGS}"
exit 0
EOF
  chmod 700 "${mock}"
  local args="${tmp}/args"
  GMAK8_SOAK_E2FSCK="${mock}" GMAK8_SOAK_E2FSCK_ARGS="${args}" fsck_data_image "${img}"
  grep -q -- "${FSCK_FLAG}" "${args}" || {
    rm -rf "${tmp}"
    die "e2fsck must be invoked with ${FSCK_FLAG}"
  }
  grep -q -- "${img}" "${args}" || {
    rm -rf "${tmp}"
    die "e2fsck must target data.img"
  }
  rm -rf "${tmp}"
}

test_plan_invariants() {
  local saved_gate=${GATE}
  local saved_cycles=${CYCLES}
  GATE=${GATE_09}
  CYCLES=50
  local plan
  plan=$(print_plan)
  echo "${plan}" | grep -q "^RUNNER_LABEL=${RUNNER_LABEL}$" || die "plan runner label"
  echo "${plan}" | grep -q "^NODEPORT_HOST=127.0.0.1$" || die "plan NodePort host"
  echo "${plan}" | grep -q "^DOCKER_HUB=0$" || die "plan must refuse Docker Hub"
  echo "${plan}" | grep -q "^VIRTCTL_LIVE=0$" || die "plan must not run virtctl live"
  echo "${plan}" | grep -q "^VIRTCTL=0$" || die "0.9 plan must not include virtctl"
  echo "${plan}" | grep -q "^DISK_ATTACHMENT=nvme$" || die "plan NVMe"
  echo "${plan}" | grep -q "^DISK_CACHE=cached$" || die "plan cached"
  echo "${plan}" | grep -q "^DISK_SYNC=full$" || die "plan full"
  echo "${plan}" | grep -q "^DISK_FORBIDDEN=virtio-blk$" || die "plan never virtio-blk"
  echo "${plan}" | grep -q "^LOCK_UNLINK=0$" || die "plan never unlink locks"
  echo "${plan}" | grep -q "^GITHUB_HOSTED=0$" || die "plan not GitHub-hosted"
  if echo "${plan}" | grep -q "virtctlPortForwardStdio"; then
    die "0.9 plan text must not list virtctl step"
  fi
  GATE=${GATE_10}
  plan=$(print_plan)
  echo "${plan}" | grep -q "virtctlPortForwardStdio" || die "1.0 plan must list virtctl step"
  echo "${plan}" | grep -q "^VIRTCTL_LIVE=0$" || die "1.0 virtctl still deferred"
  GATE=${saved_gate}
  CYCLES=${saved_cycles}
}

test_workflow_yaml() {
  local workflows="${REPO_ROOT}/.github/workflows"
  if [[ -d "${workflows}" ]] && ls "${workflows}"/*.yml >/dev/null 2>&1; then
    die "GitHub Actions workflows must not be committed (found ${workflows})"
  fi
  local ci="${REPO_ROOT}/scripts/ci.sh"
  grep -q "scripts/soak.sh --self-test" "${ci}" || die "ci.sh must run soak --self-test"
  if grep -q "soak.sh --live" "${ci}"; then
    die "ci.sh must not invoke live VZ soak"
  fi
}

test_script_forbids() {
  local hits
  hits=$(grep -nE 'docker[.]io|/var/run/docker[.]sock|docker[ ]pull' "${SCRIPT_PATH}" || true)
  if [[ -n "${hits}" ]]; then
    die "soak.sh must not pull from Docker Hub"
  fi
}

test_refuse_github_hosted_live() {
  local err
  err=$(mktemp)
  local rc=0
  set +e
  RUNNER_ENVIRONMENT=github-hosted ImageOS=macos15 \
    bash "${SCRIPT_PATH}" --live --cycles 1 >/dev/null 2>"${err}"
  rc=$?
  set -e
  if [[ "${rc}" -eq 0 ]]; then
    rm -f "${err}"
    die "expected --live to refuse GitHub-hosted macOS"
  fi
  if ! grep -q "GitHub-hosted" "${err}"; then
    cat "${err}" >&2
    rm -f "${err}"
    die "--live refusal must mention GitHub-hosted"
  fi
  rm -f "${err}"
}

run_self_test() {
  test_cycles
  test_gate
  test_steps
  test_nodeport
  test_cli_helpers_not_path
  test_socket_errors
  test_lock_not_unlinked
  test_pids_still_running_newlines
  test_live_rpc_is_cli
  test_fsck_flags
  test_plan_invariants
  test_workflow_yaml
  test_script_forbids
  test_refuse_github_hosted_live
  echo "soak self-test: ok"
}

CYCLES=""
GATE=""
CMD=""
RAW_CYCLES="${GMAK8_SOAK_CYCLES:-}"
RAW_GATE="${GMAK8_SOAK_GATE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)
      CMD=selftest
      shift
      ;;
    --plan)
      CMD=plan
      shift
      ;;
    --live)
      CMD=live
      shift
      ;;
    --nodeport)
      CMD=nodeport
      shift
      ;;
    --cycles)
      RAW_CYCLES=$2
      shift 2
      ;;
    --gate)
      RAW_GATE=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ -z "${CMD}" ]]; then
  usage
  exit 1
fi

if ! CYCLES=$(resolve_cycles "${RAW_CYCLES}"); then
  die "cycles must be a positive integer"
fi
if ! GATE=$(resolve_gate "${RAW_GATE}"); then
  die "gate must be 0.9 or 1.0"
fi

case "${CMD}" in
  selftest)
    run_self_test
    ;;
  plan)
    print_plan
    ;;
  live)
    run_live
    ;;
  nodeport)
    refuse_github_hosted_live
    nginx_nodeport_or_skip
    ;;
  *)
    usage
    exit 1
    ;;
esac
