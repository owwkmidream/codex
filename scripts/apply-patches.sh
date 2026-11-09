#!/usr/bin/env bash
# 在独立上游 checkout 中应用功能提交；失败时保留现场并写明具体功能。
set -euo pipefail

repo="$(cd "$1" && pwd)"
patch="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
baseline="$3"
report="$(mkdir -p "$4" && cd "$4" && pwd)"
series="$(dirname "$patch")/series/$baseline"
output="${GITHUB_OUTPUT:-/dev/null}"
git -C "$repo" config user.name 'Codex patches'
git -C "$repo" config user.email 'patches@localhost'

fetch_baseline() {
  if ! git -C "$repo" rev-parse --verify "$baseline^{commit}" >/dev/null 2>&1; then
    git -C "$repo" fetch --depth=1 origin "refs/tags/$baseline:refs/tags/$baseline"
  fi
}

failed() {
  local feature="$1"
  {
    printf '### 失败功能\n\n%s\n\n' "$feature"
    printf '### 应用日志\n\n'
    cat "$report/apply.log"
    printf '\n### 冲突内容\n\n'
    git -C "$repo" diff --diff-filter=U
  } > "$report/conflict.log"
  git -C "$repo" diff --name-only --diff-filter=U > "$report/conflict-files.txt"
  printf 'applied=false\nstrategy=%s\n' "$strategy" >> "$output"
  printf '补丁失败：%s\n' "$feature"
}

shopt -s nullglob
patches=("$series"/*.patch)
if ((${#patches[@]})); then
  strategy='git am --3way'
  fetch_baseline
  # 后续功能可能修改前面功能新增的代码，先重建基线链以提供完整的三方合并原像。
  if [[ "$(git -C "$repo" rev-parse HEAD)" != "$(git -C "$repo" rev-parse "$baseline^{commit}")" ]]; then
    base_worktree="$(mktemp -d)"
    trap 'git -C "$repo" worktree remove --force "$base_worktree"' EXIT
    git -C "$repo" worktree add --detach "$base_worktree" "$baseline"
    for mail in "${patches[@]}"; do
      if ! git -C "$base_worktree" -c core.hooksPath=/dev/null am --committer-date-is-author-date "$mail" > "$report/apply.log" 2>&1; then
        failed "基线重建：$(basename "$mail")"
        exit 0
      fi
    done
    git -C "$base_worktree" branch -f "patch-base/$baseline" HEAD
  fi
  for mail in "${patches[@]}"; do
    printf '应用功能：%s\n' "$(basename "$mail")"
    if ! git -C "$repo" -c core.hooksPath=/dev/null am --3way --committer-date-is-author-date "$mail" > "$report/apply.log" 2>&1; then
      failed "$(basename "$mail")"
      exit 0
    fi
  done
else
  # 历史版本只有合并补丁，仍支持精确应用和基线三方合并。
  strategy='git apply'
  if git -C "$repo" apply --check "$patch" > "$report/apply.log" 2>&1; then
    git -C "$repo" apply --index "$patch"
  else
    strategy='git apply --3way'
    fetch_baseline
    if ! git -C "$repo" apply --3way "$patch" > "$report/apply.log" 2>&1; then
      failed "$(basename "$patch")"
      exit 0
    fi
  fi
  # 使用基线日期，重复构建同一份源码得到相同的构建标识。
  stamp="$(git -C "$repo" show -s --format=%aI HEAD)"
  GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" \
    git -C "$repo" -c core.hooksPath=/dev/null commit -m "Apply $baseline patches"
fi
printf 'applied=true\nstrategy=%s\n' "$strategy" >> "$output"
