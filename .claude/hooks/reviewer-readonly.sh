#!/usr/bin/env bash
# PreToolUse hook for the pr-reviewer subagent (Issue #7).
# Reads the hook JSON on stdin and exits 2 (block) unless the Bash command is a
# single read-only git/gh command from the allow list below.
# Order: unconditional blocks first (chaining, redirection, substitution,
# newline, any other shell metacharacter, file output options), then the allow list.
set -u
# Fail closed: any exit other than 0 (allow) or 2 (block), e.g. a script error,
# becomes a block. Claude Code only treats exit 2 as a block.
trap 'rc=$?; [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || exit 2' EXIT

block() {
  echo "reviewer-readonly: blocked ($1). pr-reviewer may only run single read-only git/gh commands." >&2
  exit 2
}

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || block "unreadable hook input"
[ -n "$cmd" ] || block "empty command"

case "$cmd" in
  *$'\n'* | *$'\r'*) block "newline" ;;
  *';'* | *'|'* | *'&'*) block "command chaining" ;;
  *'>'* | *'<'*) block "redirection" ;;
  *'$('* | *'`'*) block "command substitution" ;;
esac

# Quotes, backslashes, $, braces and globs let the shell turn a word into a
# different one (e.g. '--output=x' or --out""put=x), so the word checks below
# would not see it. Only plain characters are allowed.
case "$cmd" in
  *[!A-Za-z0-9\ ._/:=@,+%^~-]*) block "shell metacharacter" ;;
esac

read -r -a words <<< "$cmd"
[ "${#words[@]}" -gt 0 ] || block "empty command"

for w in "${words[@]}"; do
  case "$w" in
    --output* | -o*) block "file output option $w" ;;
    --web) block "opens a browser: $w" ;;
  esac
done

prog=${words[0]}
sub=${words[1]:-}
action=${words[2]:-}

# git -C is allowed only for a worktree under .claude/worktrees, and the read-only
# list below still applies to the subcommand that follows it.
if [ "$prog" = git ] && [ "$sub" = -C ]; then
  dir=${words[2]:-}
  case "$dir" in
    *..*) block "parent path in git -C: $dir" ;;
    .claude/worktrees/?* | */.claude/worktrees/?*) ;;
    *) block "git -C outside .claude/worktrees: $dir" ;;
  esac
  sub=${words[3]:-}
fi

case "$prog" in
  git)
    case "$sub" in
      diff | log | show | status | rev-parse | ls-files | merge-base | blame) exit 0 ;;
    esac
    ;;
  gh)
    for w in "${words[@]}"; do
      [ "$w" != "-w" ] || block "opens a browser: $w"
    done
    case "$sub $action" in
      "pr view" | "pr diff" | "pr checks" | "pr list" | \
      "issue view" | "issue list" | \
      "run view" | "run list") exit 0 ;;
    esac
    ;;
esac

block "not on the allow list: $prog $sub"
