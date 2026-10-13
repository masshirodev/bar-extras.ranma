-- bar-extras: four bar modules, each on only where you put it.
--
--   nowplaying  what a media player plays (playerctl, so mpv, Spotify, a
--               browser, Jellyfin's players): `▶ Artist – Title`, `‖` when
--               paused, nothing with no player. A click plays or pauses.
--               bar_extras.player picks players, bar_extras.ignore_player
--               leaves some out (an mpv playing a video wallpaper).
--   net         the interface the default route goes out of, and its
--               traffic each second, from /proc/net/dev: `↓1.2M ↑40K`;
--               `net down` (urgent) when it is down. A click names it.
--   disk        how full a mount is (`/` by default): `/ 63%`, urgent from
--               bar_extras.disk_warn on. Several mounts, space-separated,
--               show side by side. A click shows what is free.
--   docker      how many containers run: `◆ 6`; nothing when docker does
--               not answer. A click opens docker.ranma's screen when that
--               plugin is installed.
--
-- None of them is placed for you, and none costs anything until it is:
--   ranma.bar { right = { "nowplaying", "net", "disk", "docker", "datetime" } }
-- Each works only while the bar shows it (module_shown / module_hidden):
-- nowplaying keeps one `playerctl --follow` running then, and stops it when
-- the module goes off screen; disk and docker run their command every
-- bar_extras.disk_interval / docker_interval seconds; net reads two files
-- in /proc every bar_extras.net_interval seconds, with no process at all.
--
-- Needs ranma 0.2.3 or newer, the first with module_shown and module_hidden.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("The bar",
-- "Timers and processes", "Hooks").

ranma.option("bar_extras.width", {
  type = "int", min = 10, max = 80, default = 32,
  name = "Now playing width", desc = "The most characters of `Artist – Title` the bar shows.",
})
ranma.option("bar_extras.player", {
  type = "string", default = "",
  name = "Player", desc = "playerctl's --player list (mpv,spotify); empty follows whichever played last.",
})
ranma.option("bar_extras.ignore_player", {
  type = "string", default = "",
  name = "Ignore players", desc = "playerctl's --ignore-player list: players never shown (a video wallpaper's mpv).",
})
ranma.option("bar_extras.net_interface", {
  type = "string", default = "",
  name = "Interface", desc = "The network interface net shows; empty is the one the default route goes out of.",
})
ranma.option("bar_extras.net_interval", {
  type = "int", min = 1, max = 60, default = 2, slider = false,
  name = "Net interval", desc = "Seconds between two looks at /proc/net/dev.",
})
ranma.option("bar_extras.disk", {
  type = "string", default = "/",
  name = "Mounts", desc = "The mounts disk shows, space-separated.",
})
ranma.option("bar_extras.disk_warn", {
  type = "int", min = 50, max = 100, default = 90,
  name = "Disk warning", desc = "From this percentage on, disk is drawn urgent.",
})
ranma.option("bar_extras.disk_interval", {
  type = "int", min = 10, max = 3600, default = 60, slider = false,
  name = "Disk interval", desc = "Seconds between two runs of df.",
})
ranma.option("bar_extras.docker_interval", {
  type = "int", min = 2, max = 600, default = 10, slider = false,
  name = "Docker interval", desc = "Seconds between two runs of docker ps.",
})

local shown = {}   -- module name -> true while on screen

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

local function cut(s, n)
  local len = utf8.len(s)
  if not len then return s:sub(1, n) end
  if len <= n then return s end
  return s:sub(1, utf8.offset(s, n) - 1) .. "…"
end

-- Each module: start() when it comes on screen, stop() when it goes.
local life = {}

ranma.on("module_shown", function(ev)
  local l = life[ev.name]
  if l and not shown[ev.name] then
    shown[ev.name] = true
    l.start()
  end
end)
ranma.on("module_hidden", function(ev)
  local l = life[ev.name]
  if l and shown[ev.name] then
    shown[ev.name] = nil
    l.stop()
  end
end)
-- After a reload the modules may already be on screen, and nothing says so.
ranma.defer(0, function()
  for name, l in pairs(life) do
    if ranma.module_shown(name) and not shown[name] then
      shown[name] = true
      l.start()
    end
  end
end)

-- A command every `interval` seconds while shown, its output handed to take().
local function polled(name, interval_key, cmd, take)
  local timer, job, busy = nil, nil, false
  local function run()
    if busy then return end
    busy = true
    job = ranma.spawn(cmd(), {
      timeout = 15,
      on_exit = function(r)
        busy = false
        job = nil
        take(r)
        ranma.refresh_module(name)
      end,
    })
  end
  life[name] = {
    start = function()
      run()
      timer = ranma.every(ranma.get(interval_key) * 1000, run)
    end,
    stop = function()
      if timer then ranma.cancel(timer) end
      timer = nil
    end,
  }
end

-- nowplaying -------------------------------------------------------------------

local playing = nil   -- { status, artist, title }
local follower = nil

local SEP = "\31"

local function player_args(...)
  local out = { "playerctl" }
  local p = ranma.get("bar_extras.player")
  if p ~= "" then
    out[#out + 1] = "--player"
    out[#out + 1] = p
  end
  local ignore = ranma.get("bar_extras.ignore_player")
  if ignore ~= "" then
    out[#out + 1] = "--ignore-player"
    out[#out + 1] = ignore
  end
  for _, a in ipairs({ ... }) do out[#out + 1] = a end
  return out
end

local function take_line(line)
  local status, artist, title = line:match("^(.-)" .. SEP .. "(.-)" .. SEP .. "(.*)$")
  if not status or status == "" or status == "Stopped" then
    playing = nil
  else
    playing = { status = status, artist = artist, title = title }
  end
  ranma.refresh_module("nowplaying")
end

life.nowplaying = {
  start = function()
    if follower then return end
    -- One process for as long as the module shows: playerctl prints a line
    -- whenever the player, the track or the status changes.
    follower = ranma.spawn(player_args("metadata", "--follow", "--format",
      "{{status}}" .. SEP .. "{{artist}}" .. SEP .. "{{title}}"), {
      on_line = take_line,
      on_exit = function()
        follower = nil
        playing = nil
        ranma.refresh_module("nowplaying")
      end,
    })
  end,
  stop = function()
    if follower then ranma.kill(follower) end
    follower = nil
  end,
}

ranma.module("nowplaying", {
  render = function()
    if not playing then return nil end
    local what = playing.title ~= "" and playing.title or "?"
    if playing.artist ~= "" then what = playing.artist .. " – " .. what end
    what = cut(what, ranma.get("bar_extras.width"))
    if playing.status == "Paused" then return { text = "‖ " .. what, style = "dim" } end
    return { text = "▶ " .. what, style = "normal" }
  end,
  on_click = function()
    ranma.spawn(player_args("play-pause"), { timeout = 5 })
  end,
})

-- net ----------------------------------------------------------------------------

local net = { iface = nil, rx = nil, tx = nil, down = 0, up = 0, state = nil, ready = false }

local function default_iface()
  local text = read("/proc/net/route") or ""
  for line in text:gmatch("[^\n]+") do
    local iface, dest = line:match("^(%S+)%s+(%x+)")
    if dest == "00000000" then return iface end
  end
end

local function rate(bytes)
  if bytes >= 1024 * 1024 * 1024 then return ("%.1fG"):format(bytes / 1024 ^ 3) end
  if bytes >= 1024 * 1024 then return ("%.1fM"):format(bytes / 1024 ^ 2) end
  if bytes >= 1024 then return ("%.0fK"):format(bytes / 1024) end
  return ("%dB"):format(math.floor(bytes))
end

local function net_sample()
  local want = ranma.get("bar_extras.net_interface")
  local iface = want ~= "" and want or default_iface()
  if not iface then
    net.state = "none"
    return
  end
  if iface ~= net.iface then
    net.iface, net.rx, net.tx, net.ready = iface, nil, nil, false
  end
  local oper = (read("/sys/class/net/" .. iface .. "/operstate") or ""):gsub("%s+", "")
  local dev = read("/proc/net/dev") or ""
  local rx, tx = dev:match("\n%s*" .. iface:gsub("%p", "%%%0") .. ":%s*(%d+)%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)")
  if not rx or oper == "down" then
    net.state = "down"
    return
  end
  rx, tx = tonumber(rx), tonumber(tx)
  -- Lua's clock counts whole seconds; the timer's period is the better dt.
  if net.rx then
    local dt = ranma.get("bar_extras.net_interval")
    net.down, net.up = math.max(0, rx - net.rx) / dt, math.max(0, tx - net.tx) / dt
    net.ready = true
  end
  net.rx, net.tx = rx, tx
  net.state = "up"
end

local net_timer = nil
life.net = {
  start = function()
    net_sample()
    net_timer = ranma.every(ranma.get("bar_extras.net_interval") * 1000, function()
      net_sample()
      ranma.refresh_module("net")
    end)
  end,
  stop = function()
    if net_timer then ranma.cancel(net_timer) end
    net_timer = nil
    net.rx, net.tx, net.ready = nil, nil, false
  end,
}

ranma.module("net", {
  render = function()
    if net.state == "down" then return { text = "net down", style = "urgent" } end
    if net.state ~= "up" then return nil end
    if not net.ready then return { text = "↓— ↑—", style = "dim" } end
    return "↓" .. rate(net.down) .. " ↑" .. rate(net.up)
  end,
  on_click = function()
    ranma.toast("net: " .. (net.iface or "no interface") .. (net.state == "down" and " is down" or ""))
  end,
})

-- disk ---------------------------------------------------------------------------

local disks = {}   -- in the order of bar_extras.disk: { mount, pct, avail }

local function mounts()
  local out = {}
  for m in ranma.get("bar_extras.disk"):gmatch("%S+") do out[#out + 1] = m end
  return out
end

polled("disk", "bar_extras.disk_interval", function()
  local cmd = { "df", "-P", "-k" }
  for _, m in ipairs(mounts()) do cmd[#cmd + 1] = m end
  return cmd
end, function(r)
  disks = {}
  local list = mounts()
  local i = 0
  for line in (r.stdout or ""):gmatch("[^\n]+") do
    local avail, pct = line:match("^%S+%s+%d+%s+%d+%s+(%d+)%s+(%d+)%%")
    if avail then
      i = i + 1
      disks[#disks + 1] = { mount = list[i] or "?", pct = tonumber(pct), avail = tonumber(avail) * 1024 }
    end
  end
end)

ranma.module("disk", {
  render = function()
    if #disks == 0 then return nil end
    local parts, urgent = {}, false
    for _, d in ipairs(disks) do
      parts[#parts + 1] = d.mount .. " " .. d.pct .. "%"
      if d.pct >= ranma.get("bar_extras.disk_warn") then urgent = true end
    end
    return { text = table.concat(parts, "  "), style = urgent and "urgent" or "normal" }
  end,
  on_click = function()
    local parts = {}
    for _, d in ipairs(disks) do parts[#parts + 1] = d.mount .. ": " .. rate(d.avail) .. " free" end
    ranma.toast("disk: " .. table.concat(parts, ", "))
  end,
})

-- docker -------------------------------------------------------------------------

local containers = nil   -- how many run, or nil when docker did not answer

polled("docker", "bar_extras.docker_interval", function()
  return { "docker", "ps", "-q" }
end, function(r)
  if r.error or r.code ~= 0 then
    containers = nil
    return
  end
  local n = 0
  for _ in (r.stdout or ""):gmatch("[^\n]+") do n = n + 1 end
  containers = n
end)

ranma.module("docker", {
  render = function()
    if not containers then return nil end
    return { text = "◆ " .. containers, style = containers > 0 and "normal" or "dim" }
  end,
  on_click = function()
    -- docker.ranma declares this option: it is installed.
    if pcall(ranma.get, "docker.refresh") then return ranma.emit("docker_open") end
    ranma.toast("docker: " .. tostring(containers or 0) .. " running (docker.ranma shows them on a click)")
  end,
})
