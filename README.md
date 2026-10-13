# bar-extras.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: four bar modules, now playing, network, disk and docker, each costing nothing until you put it in the bar and only working while the bar shows it.

Needs ranma v0.2.3 or newer (`module_shown` / `module_hidden`).

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/plugins/bar-extras.lua`:

```lua
return { "masshirodev/bar-extras.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/bar-extras.ranma ~/.config/ranma/pack/plugins/start/bar-extras.ranma
```

Then place the ones you want:

```lua
ranma.bar { right = { "nowplaying", "net", "disk", "docker", "datetime" } }
```

Add them only once the plugin is installed: a bar naming a module that no installed plugin declares makes every config reload fail.

Needs, per module: `playerctl` (nowplaying), Linux's `/proc` and `/sys` (net), `df` (disk), the docker CLI (docker).

## What it does

```text
bar-extras: four bar modules, each on only where you put it.

  nowplaying  what a media player plays (playerctl, so mpv, Spotify, a
              browser, Jellyfin's players): `▶ Artist – Title`, `‖` when
              paused, nothing with no player. A click plays or pauses.
              bar_extras.player picks players, bar_extras.ignore_player
              leaves some out (an mpv playing a video wallpaper).
  net         the interface the default route goes out of, and its
              traffic each second, from /proc/net/dev: `↓1.2M ↑40K`;
              `net down` (urgent) when it is down. A click names it.
  disk        how full a mount is (`/` by default): `/ 63%`, urgent from
              bar_extras.disk_warn on. Several mounts, space-separated,
              show side by side. A click shows what is free.
  docker      how many containers run: `◆ 6`; nothing when docker does
              not answer. A click opens docker.ranma's screen when that
              plugin is installed.

None of them is placed for you, and none costs anything until it is:
  ranma.bar { right = { "nowplaying", "net", "disk", "docker", "datetime" } }
Each works only while the bar shows it (module_shown / module_hidden):
nowplaying keeps one `playerctl --follow` running then, and stops it when
the module goes off screen; disk and docker run their command every
bar_extras.disk_interval / docker_interval seconds; net reads two files
in /proc every bar_extras.net_interval seconds, with no process at all.

Needs ranma 0.2.3 or newer, the first with module_shown and module_hidden.

ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("The bar",
"Timers and processes", "Hooks").
```

## Modules

| Module | Shows | A click |
| --- | --- | --- |
| `nowplaying` | `▶ Artist – Title`, `‖` paused; nothing with no player | Play / pause |
| `net` | `↓1.2M ↑40K` per second on the default route's interface; `net down` | Names the interface |
| `disk` | `/ 63%` per mount; urgent from `bar_extras.disk_warn` | What is free |
| `docker` | `◆ 6` containers running; nothing when docker does not answer | docker.ranma's screen, when installed |

## Options

In ranma's settings panel under `bar_extras`, or with hako's `opts`, or `ranma.set { bar_extras = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `bar_extras.width` | `32` | The most characters of `Artist – Title` shown. |
| `bar_extras.player` | `""` | playerctl's `--player` list (`mpv,spotify`); empty follows whichever played last. |
| `bar_extras.ignore_player` | `""` | playerctl's `--ignore-player` list: players never shown (an mpv playing a video wallpaper). |
| `bar_extras.net_interface` | `""` | The interface `net` shows; empty is the default route's. |
| `bar_extras.net_interval` | `2` | Seconds between two looks at `/proc/net/dev`. |
| `bar_extras.disk` | `"/"` | The mounts `disk` shows, space-separated. |
| `bar_extras.disk_warn` | `90` | From this percentage on, `disk` is urgent. |
| `bar_extras.disk_interval` | `60` | Seconds between two runs of `df`. |
| `bar_extras.docker_interval` | `10` | Seconds between two runs of `docker ps -q`. |

## Costs

Nothing runs for a module that is not in the bar, or while the bar does not show it (a profile without it, a hidden bar). While shown: `nowplaying` keeps one `playerctl metadata --follow` running, which prints only when something changes, and stops it when the module goes off screen; `net` reads `/proc/net/route` and `/proc/net/dev` in Lua, no process; `disk` and `docker` run `df` and `docker ps -q` on their intervals, through `ranma.spawn`, never two at once.

## Limits

- `net`'s rates use the interval as the time between two samples (Lua's clock counts whole seconds), so a late tick reads a little high.
- A server killed with a signal (not quit or reloaded) leaves its `playerctl` running, as ranma does not get to end its jobs then.

## License

MIT or Apache-2.0, as ranma.
