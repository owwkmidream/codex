#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../codex-patch.sh"
fixture=$(mktemp -d -t codex-shell-test.XXXXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

# 实际执行查询适配器，覆盖含空格路径、stderr 反馈、非零退出码和 JSON 输出。
printf 'console.error("fixture-progress"); console.log(JSON.stringify({version:"0.167.0"}));\n' > "$fixture/query with spaces.js"
result=$(capture "$(command -v node)" "$(cygpath -w "$fixture/query with spaces.js")" 2> "$fixture/progress")
[[ $(printf '%s' "$result" | json version) == 0.167.0 ]]
grep -q fixture-progress "$fixture/progress"
printf 'process.exit(7);\n' > "$fixture/fail.js"
if capture "$(command -v node)" "$(cygpath -w "$fixture/fail.js")"; then
  echo '非零退出码被吞掉' >&2
  exit 1
fi
printf 'official\n' > "$fixture/official.exe"
printf 'patched\n' > "$fixture/patched.exe"
[[ $(hash "$fixture/official.exe") != "$(hash "$fixture/patched.exe")" ]]
printf '{"version":"0.167.0","target":"x86_64-pc-windows-msvc","official_sha256":"%s","patched_sha256":"%s"}' \
  "$(hash "$fixture/official.exe")" "$(hash "$fixture/patched.exe")" > "$fixture/remote.json"
http() {
  [[ $1 == */binary-hashes.json ]] || return 1
  cp "$fixture/remote.json" "$2"
}
manifest 0.167.0 "$fixture/summary.json"
[[ $(kind "$fixture/official.exe" "$fixture/summary.json") == 官方版 ]]
[[ $(kind "$fixture/patched.exe" "$fixture/summary.json") == 补丁版 ]]
printf tampered > "$fixture/patched.exe"
[[ $(kind "$fixture/patched.exe" "$fixture/summary.json") == 未知* ]]
[[ $(kind "$fixture/absent.exe" "$fixture/summary.json") == 未安装 ]]
if manifest 0.168.0 "$fixture/wrong-version.json"; then exit 1; fi
printf '{"status":"running","managedCodexPath":"C:/fixture/codex.exe"}' > "$fixture/daemon.json"
[[ $(json status < "$fixture/daemon.json") == running ]]
if json missing < "$fixture/daemon.json"; then exit 1; fi
echo 'PASS: 查询反馈、空格路径、失败退出、摘要计算及 JSON 字段解析'

# 运行真实 main，替换网络和 daemon 边界；文件替换仍使用真实 Node rename。
script_path=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/codex-patch.sh
prefix="$fixture/npm prefix"
test_root="$prefix/node_modules"
test_binary="$test_root/@openai/codex/node_modules/@openai/codex-win32-x64/vendor/$target/bin/codex.exe"
mkdir -p "$(dirname "$test_binary")" "$prefix/node_modules/npm/bin" "$fixture/package/vendor/$target/bin" "$fixture/zip"
printf '{"version":"0.167.0"}' > "$test_root/@openai/codex/package.json"
touch "$prefix/npm.cmd" "$prefix/node_modules/npm/bin/npm-cli.js" "$prefix/codex"
chmod +x "$prefix/npm.cmd" "$prefix/codex"
printf official > "$fixture/package/vendor/$target/bin/codex.exe"
printf patched > "$fixture/zip/codex.exe"
tar.exe -czf "$(cygpath -w "$fixture/official.tgz")" -C "$(cygpath -w "$fixture")" package
tar.exe -a -cf "$(cygpath -w "$fixture/patched.zip")" -C "$(cygpath -w "$fixture/zip")" codex.exe
printf '{"version":"0.167.0","target":"%s","official_sha256":"%s","patched_sha256":"%s"}' \
  "$target" "$(hash "$fixture/package/vendor/$target/bin/codex.exe")" "$(hash "$fixture/zip/codex.exe")" > "$fixture/remote.json"
node -e 'const fs=require("fs"),c=require("crypto");console.log(JSON.stringify({dist:{tarball:"https://registry.npmjs.org/fixture.tgz",integrity:"sha512-"+c.createHash("sha512").update(fs.readFileSync(process.argv[1])).digest("base64")}}))' \
  "$(cygpath -w "$fixture/official.tgz")" > "$fixture/npm.json"
run_fixture() (
  source "$script_path"
  export PATH="$prefix:$PATH"
  http() {
    echo "$1" >> "$fixture/requests"
    case "$1" in
      */binary-hashes.json) cp "$fixture/remote.json" "$2" ;;
      *.zip) cp "$fixture/patched.zip" "$2" ;;
      */0.167.0-win32-x64) cp "$fixture/npm.json" "$2" ;;
      */fixture.tgz) cp "$fixture/official.tgz" "$2" ;;
      *) return 1 ;;
    esac
  }
  capture() {
    if [[ ${*: -2} == 'root --global' ]]; then cygpath -w "$test_root"
    elif [[ ${*: -1} == --version ]]; then echo 'codex-cli 0.167.0'
    else return 1; fi
  }
  powershell.exe() { :; }
  read_daemon() {
    printf '{"managedCodexPath":"%s","managedCodexVersion":"0.167.0","status":"%s","pid":0}' \
      "$(cygpath -m "$fixture/daemon.exe")" "$(cat "$fixture/state")"
  }
  daemon() {
    echo "$*" >> "$fixture/daemon-calls"
    case "$1" in
      stop) echo notRunning > "$fixture/state" ;;
      start) echo running > "$fixture/state" ;;
      update) cp "$test_binary" "$fixture/daemon.exe" ;;
    esac
  }
  main "$@"
)
for initial in running notRunning; do
  echo "$initial" > "$fixture/state"
  cp "$fixture/package/vendor/$target/bin/codex.exe" "$test_binary"
  cp "$test_binary" "$fixture/daemon.exe"
  : > "$fixture/requests"
  run_fixture install --yes
  [[ $(hash "$test_binary") == "$(hash "$fixture/zip/codex.exe")" ]]
  [[ $(cat "$fixture/state") == "$initial" ]]
  ! grep -q registry.npmjs "$fixture/requests"
  run_fixture restore --yes
  [[ $(hash "$test_binary") == "$(hash "$fixture/package/vendor/$target/bin/codex.exe")" ]]
  [[ $(cat "$fixture/state") == "$initial" ]]
done
grep -qx 'update --from-cli --yes' "$fixture/daemon-calls"
grep -qx update "$fixture/daemon-calls"
: > "$fixture/requests"
run_fixture status > "$fixture/status"
grep -q 官方版 "$fixture/status"
! grep -Ev '/binary-hashes.json$' "$fixture/requests"
echo 'PASS: 安装仅下载补丁、npm 还原、状态只取摘要、daemon 原运行状态保持'
