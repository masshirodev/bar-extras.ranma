# AGENTS.md

bar-extras.ranma is a ranma plugin in Lua: `plugin/bar_extras.lua` is all of it, and
its header comment is the reference that `README.md` repeats. ranma's API is
https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit, and an option goes in the README's table.
- Keep to the API of the latest ranma release, which CI loads it into.
- Every module works only while shown: start on `module_shown`, stop on
  `module_hidden` (and on a reload, ask `ranma.module_shown`). A new module
  follows the same `life[name] = { start, stop }` shape.
- Options are `bar_extras.*`: option names take letters, digits and `_` only.
- After a test, check no `playerctl` is left running (`pgrep -x playerctl`):
  stop a test server with `ranma action "quit now"`, not a signal.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server. Test behaviour in a private server
  (its own `RANMA_CONFIG_DIR`, `XDG_RUNTIME_DIR` and tmux socket, with
  `RANMA_SOCKET RANMA RANMA_PANE TMUX` unset), never the one you are typing in.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and fails if it does not.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
