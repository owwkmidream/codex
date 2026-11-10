#!/usr/bin/env bash
set -Eeuo pipefail

usage() { echo '用法：bash codex-patch.sh [install|restore|status|sync] [--yes]'; }
fail() { echo "错误：$*" >&2; exit 1; }
step() { echo "→ $*" >&2; }

# JSON 和 Windows 路径交给已有 Node.js，避免依赖额外安装的 jq。
json() {
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let v=JSON.parse(s);for(const k of process.argv[1].split("."))v=v?.[k];if(v===undefined||v===null)process.exit(2);console.log(typeof v==="object"?JSON.stringify(v):v)})' "$1"
}
hash() { sha256sum "$1" | cut -d ' ' -f1; }
http() { curl --fail --location --show-error --connect-timeout 15 --max-time 600 --progress-bar "$1" -o "$2"; }
capture() {
  step "执行：$*"
  local executable=$1
  shift
  executable=$(cygpath -w "$executable")
  # 查询有超时；stderr 实时显示，stdout 留给 JSON/路径解析。
  node -e 'const r=require("child_process").spawnSync(process.argv[1],process.argv.slice(2),{encoding:"utf8",timeout:120000,stdio:["ignore","pipe","inherit"]});if(r.error){console.error(r.error.message);process.exit(1)}if(r.status!==0)process.exit(r.status||1);process.stdout.write(r.stdout.replace(/\r\n/g,"\n"))' "$executable" "$@"
}
daemon() { step "daemon $*"; "$binary" app-server daemon "$@"; }
read_daemon() { capture "$binary" app-server daemon version; }
field() { printf '%s' "$1" | json "$2"; }
release_base='https://github.com/owwkmidream/codex/releases/download'
target='x86_64-pc-windows-msvc'
# 只取小型摘要清单；状态查询绝不下载二进制包。
manifest() {
  local v=$1 out=$2
  http "$release_base/rust-v$v/binary-hashes.json" "$out" || return 1
  node -e 'const m=require(process.argv[1]);if(m.version!==process.argv[2]||m.target!=="x86_64-pc-windows-msvc"||![m.official_sha256,m.patched_sha256].every(x=>/^[a-f0-9]{64}$/.test(x)))process.exit(1)' "$(cygpath -w "$out")" "$v"
}
kind() {
  local file=$1 summary=$2 actual
  [[ -f "$file" ]] || { echo '未安装'; return; }
  [[ -f "$summary" ]] || { echo '未知（无对应摘要）'; return; }
  actual=$(hash "$file")
  if [[ $actual == "$(json patched_sha256 < "$summary")" ]]; then echo '补丁版'
  elif [[ $actual == "$(json official_sha256 < "$summary")" ]]; then echo '官方版'
  else echo '未知（hash 不匹配）'; fi
}
main() {
action=${1:-menu}
yes=false
[[ $# -eq 0 ]] || shift
if [[ ${1:-} == --yes ]]; then yes=true; shift; fi
[[ $# -eq 0 ]] || { usage; exit 2; }
case "$action" in
  -h|--help) usage; exit 0 ;;
  menu)
    printf '1 安装补丁\n2 还原官方\n3 查看状态\n4 同步 daemon\n0 退出\n'
    read -r -p '选择：' choice
    case "$choice" in 1) action=install;; 2) action=restore;; 3) action=status;; 4) action=sync;; 0) exit 0;; *) fail '无效选项';; esac ;;
  install|restore|status|sync) ;;
  *) usage; exit 2 ;;
esac

for tool in node curl cygpath sha256sum tar.exe powershell.exe; do command -v "$tool" >/dev/null || fail "缺少命令：$tool"; done
node -e 'if(process.platform!=="win32"||process.arch!=="x64")process.exit(1)' || fail '需要 Windows x64 Node.js。'
archive_tool="$(cygpath -u "$SYSTEMROOT")/System32/tar.exe"
[[ -f "$archive_tool" ]] || fail '缺少 Windows 系统 tar.exe。'
npm_cmd=$(command -v npm.cmd) || fail '找不到 npm.cmd，请先安装 Node.js/npm 和 Codex。'
npm_cli="$(dirname "$npm_cmd")/node_modules/npm/bin/npm-cli.js"
[[ -f "$npm_cli" ]] || fail "找不到 npm 入口：$npm_cli"
root=$(capture "$(command -v node)" "$(cygpath -w "$npm_cli")" root --global)
root=$(cygpath -u "${root//$'\r'/}")
wrapper="$root/@openai/codex"
[[ -f "$wrapper/package.json" ]] || fail '当前 npm 环境未安装 Codex，请先通过 npm 安装。'
version=$(json version < "$wrapper/package.json")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "不支持的版本：$version"
platform="$wrapper/node_modules/@openai/codex-win32-x64"
[[ -d "$platform" ]] || platform="$root/@openai/codex-win32-x64"
[[ -d "$platform" ]] || platform="$wrapper"
binary="$platform/vendor/$target/bin/codex.exe"
[[ -f "$binary" ]] || fail '找不到当前安装的 Windows 二进制。'
active=$(command -v codex) || fail 'PATH 中找不到 codex。'
expected="$(dirname "$root")/codex"
[[ $(cygpath -am "$active") == "$(cygpath -am "$expected")" ]] || fail 'PATH 中的 codex 与当前 npm 安装不一致。'

work=$(mktemp -d -t codex-patch.XXXXXXXX)
stage=''
daemon_touched=false
cleanup() {
  local result=$?
  trap - ERR
  set +e
  if $daemon_touched; then
    if $was_running; then daemon start; else daemon stop; fi
  fi
  [[ -z "$stage" ]] || rm -f -- "$stage"
  rm -rf -- "$work"
  return "$result"
}
trap cleanup EXIT
trap 'echo "操作失败，未自动回滚。CLI 若已替换，可重新运行 sync 或 restore；具体失败步骤见上方输出。" >&2' ERR

summary="$work/hashes.json"
if [[ $action == status ]]; then
  if ! manifest "$version" "$summary"; then rm -f "$summary"; fi
  info=$(read_daemon)
  daemon_path=$(field "$info" managedCodexPath)
  daemon_version=$(field "$info" managedCodexVersion || true)
  daemon_summary=$summary
  if [[ -n "$daemon_version" && $daemon_version != "$version" ]]; then
    daemon_summary="$work/daemon-hashes.json"
    if ! manifest "$daemon_version" "$daemon_summary"; then rm -f "$daemon_summary"; fi
  fi
  echo "CLI：$version / $(kind "$binary" "$summary")"
  echo "文件：$binary"
  echo "daemon：${daemon_version:-未知} / $(kind "$(cygpath -u "$daemon_path")" "$daemon_summary")"
  echo "状态：$(field "$info" status)"
  echo "文件：$daemon_path"
  exit 0
fi

if ! $yes; then
  echo "操作：$action；CLI 版本：$version。将修改二进制或 daemon，保留原运行状态；不创建备份。"
  read -r -p '请先关闭其他 Codex CLI；确认继续？[y/N] ' answer
  [[ $answer == y || $answer == Y ]] || exit 0
fi
info=$(read_daemon)
daemon_status=$(field "$info" status)
was_running=false
case "$daemon_status" in running|alreadyRunning|started|restarted) was_running=true;; esac
# 用实际路径检查占用，避免覆盖正在运行的 CLI；daemon 在替换前单独停止。
CODEX_PATCH_BINARY=$(cygpath -w "$binary") CODEX_PATCH_DAEMON_PID=$(field "$info" pid || echo 0) \
  powershell.exe -NoProfile -NonInteractive -Command '
    $ErrorActionPreference="Stop"
    $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw "请使用普通用户终端"}
    $busy=@(Get-Process -Name codex -ErrorAction SilentlyContinue | Where-Object {$_.Id -ne [int]$env:CODEX_PATCH_DAEMON_PID -and $_.Path -eq $env:CODEX_PATCH_BINARY})
    if($busy.Count){throw "请先关闭使用目标文件的 Codex CLI"}
  '

if [[ $action == install ]]; then
  step "获取 $version 补丁摘要"
  manifest "$version" "$summary" || fail "没有可用的 $version 补丁或摘要；请等待对应 Release。"
  http "$release_base/rust-v$version/codex-rust-v$version-windows-x64.zip" "$work/patched.zip"
  "$archive_tool" -xOf "$(cygpath -w "$work/patched.zip")" codex.exe > "$work/codex.exe"
  [[ $(hash "$work/codex.exe") == "$(json patched_sha256 < "$summary")" ]] || fail '补丁二进制 SHA-256 不匹配。'
elif [[ $action == restore ]]; then
  step "获取 npm 官方二进制 $version"
  http "https://registry.npmjs.org/@openai/codex/$version-win32-x64" "$work/npm.json"
  url=$(json dist.tarball < "$work/npm.json")
  [[ $url == https://registry.npmjs.org/* ]] || fail 'npm 包下载地址异常。'
  http "$url" "$work/official.tgz"
  # npm integrity 校验整个包，恢复无需依赖我们的 Release 是否存在。
  node -e 'const fs=require("fs"),c=require("crypto"),m=JSON.parse(fs.readFileSync(process.argv[1]));const [a,h]=m.dist.integrity.split("-");if(a!=="sha512"||c.createHash(a).update(fs.readFileSync(process.argv[2])).digest("base64")!==h)throw Error("npm integrity 不匹配")' "$(cygpath -w "$work/npm.json")" "$(cygpath -w "$work/official.tgz")"
  "$archive_tool" -xOf "$(cygpath -w "$work/official.tgz")" "package/vendor/$target/bin/codex.exe" > "$work/codex.exe"
fi

if [[ $action != sync ]]; then
  [[ $(capture "$(cygpath -w "$work/codex.exe")" --version) == "codex-cli $version" ]] || fail '下载的二进制版本不匹配。'
  # 先在同目录准备已校验文件，再原子替换；占用导致失败时保留原文件。
  stage="$(dirname "$binary")/codex.new.$$.exe"
  cp -- "$work/codex.exe" "$stage"
  daemon_touched=true
  daemon stop
  step '替换 CLI 二进制'
  node -e 'require("fs").renameSync(process.argv[1],process.argv[2])' "$(cygpath -w "$stage")" "$(cygpath -w "$binary")"
  stage=''
fi

step '同步 daemon'
daemon_touched=true
# 首次建立管理包；同步完成后恢复原来的运行/停止状态。
daemon_path=$(field "$info" managedCodexPath)
if [[ ! -f $(cygpath -u "$daemon_path") ]]; then daemon start; fi
if [[ $action == restore ]]; then
  daemon update
else
  daemon update --from-cli --yes
fi
if $was_running; then daemon start; else daemon stop; fi
daemon_touched=false
updated=$(read_daemon)
if [[ $action != restore ]]; then
  [[ $(hash "$binary") == "$(hash "$(cygpath -u "$(field "$updated" managedCodexPath)")")" ]] || fail 'CLI 与 daemon 二进制不一致。'
fi
echo "完成：$action；CLI $version；daemon $(field "$updated" status)"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
