#!/usr/bin/env bash
# Dependency-free assert helpers. Source this in tests/test_*.sh.
_t_pass=0; _t_fail=0
assert_eq() { # actual expected msg
  if [ "$1" = "$2" ]; then _t_pass=$((_t_pass+1)); else
    _t_fail=$((_t_fail+1)); printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$3" "$2" "$1"; fi
}
assert_contains() { # haystack needle msg
  case "$1" in *"$2"*) _t_pass=$((_t_pass+1)) ;;
  *) _t_fail=$((_t_fail+1)); printf 'FAIL: %s (missing: %s)\n' "$3" "$2" ;; esac
}
assert_nonzero() { # cmd... (expects nonzero exit)
  if "$@" >/dev/null 2>&1; then _t_fail=$((_t_fail+1)); printf 'FAIL: expected nonzero: %s\n' "$*"
  else _t_pass=$((_t_pass+1)); fi
}
t_summary() { printf 'pass=%d fail=%d\n' "$_t_pass" "$_t_fail"; [ "$_t_fail" -eq 0 ]; }
