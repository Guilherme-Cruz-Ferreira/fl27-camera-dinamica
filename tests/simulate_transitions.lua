-- simula.lua: leva a bola por trajetos tipicos e mede o quao rapido/brusca a camera muda.
-- Uso: texlua simula.lua <modulo.lua> <pasta_tmp> [rotulo]
local _open = io.open; io.open = function(p, mode) return _open(p, mode and mode:gsub("t", "") or nil) end
local bytes = {}
local fm = { i64 = "<i8", f = "<f", i32 = "<i4" }
memory = {
  read = function(a, n) local t = {} for i = 0, n - 1 do t[#t + 1] = string.char(bytes[a + i] or 0) end return table.concat(t) end,
  write = function(a, s) for i = 1, #s do bytes[a + i - 1] = s:byte(i) end end,
  unpack = function(f, s) return (string.unpack(fm[f], s)) end,
  pack = function(f, v) return string.pack(fm[f], v) end,
  hex = function(v) return string.format("0x%x", v) end,
  get_process_info = function() return { base = 0x140000000 } end,
}
log = function() end
local G, P0 = 0x30000000, 0x20000000
local function setq(a, v) memory.write(a, string.pack("<i8", v)) end
local function setf(a, v) memory.write(a, string.pack("<f", v)) end
local function getf(a) return (string.unpack("<f", memory.read(a, 4))) end
local function node_ptr(n) return 0x20100000 + n * 0x2000 end
local function player_ptr(i) return P0 + i * 0x3f40 end
local function reset()
  bytes = {}
  setq(0x140000000 + 0x36f3dc8, G)
  for i = 0, 21 do setq(G + (0xf3 + i) * 0x28 + 0x20, player_ptr(i)) end
  for n = 0x90, 0xf2 do setq(G + n * 0x28 + 0x20, node_ptr(n)) end
  setf(player_ptr(9) + 0x2ef8, 47.0)      -- goleiro em x=+47 => ataque para +x
end
local function ball(x, z, y) for n = 0xed, 0xef do local a = node_ptr(n) + 0xa80; setf(a, x); setf(a + 4, y or 0.11); setf(a + 8, z) end end

local path, tmp, label = arg[1], arg[2], arg[3] or arg[1]
-- ini com os valores do usuario
local f = _open(tmp .. "/\\camera_dinamica.ini", "w")
f:write([[enabled = 1
near_start = 23
near_end = 5
def_start = 35
def_end = 17
def_strength = 0.5
side_start = 12
side_end = 28
side_dist = 15
side_height = 25
side_top = 1
side_bottom = 0.3
dist_open = 30
dist_close = 25.5
height_open = 54
height_close = 34
]]); f:close()
local fake = 5000; os.time = function() return fake end
local m = dofile(path)
local DIST, ALT = 0x14260b8fc, 0x14260b900

-- trajetorias: lista de waypoints {segundos, x, z}; interpolacao linear
local scen = {
  { nome = "lateral de CIMA (meio) -> area de ataque", w = { { 0, 0, -30 }, { 1.0, 0, -30 }, { 2.5, 38, -3 }, { 5.5, 38, -3 } } },
  { nome = "area de ataque -> lateral de CIMA (meio)", w = { { 0, 38, -3 }, { 1.0, 38, -3 }, { 2.5, 0, -30 }, { 5.5, 0, -30 } } },
  { nome = "lateral de CIMA -> lateral de BAIXO (cruzada no meio)", w = { { 0, 0, -30 }, { 1.0, 0, -30 }, { 2.2, 0, 30 }, { 5.0, 0, 30 } } },
  { nome = "bola longa: propria area -> area de ataque (1,0 s)", w = { { 0, -40, 0 }, { 1.0, -40, 0 }, { 2.0, 40, 0 }, { 5.0, 40, 0 } } },
  { nome = "ataque pela lateral: meio-lateral CIMA -> escanteio de ataque", w = { { 0, 5, -30 }, { 1.0, 5, -30 }, { 3.0, 45, -30 }, { 6.0, 45, -30 } } },
  { nome = "bola vai e volta na fronteira da area (x oscila 28-38)", w = (function() local t = {}; for i = 0, 20 do t[#t + 1] = { i * 0.4, (i % 2 == 0) and 28 or 38, 0 } end return t end)() },
}
local function pos(w, t)
  for i = 1, #w - 1 do
    if t <= w[i + 1][1] then
      local a, b = w[i], w[i + 1]; local u = (t - a[1]) / (b[1] - a[1]); if u < 0 then u = 0 end
      return a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u
    end
  end
  local l = w[#w]; return l[2], l[3]
end
print(string.format("== %s", label))
print(string.format("%-62s %8s %8s %9s %9s %7s", "cenario", "v.dist", "v.alt", "acel.alt", "var.total", "tempo"))
local worst = { 0, 0, 0 }
for _, sc in ipairs(scen) do
  reset(); m.init({ sider_dir = tmp .. "/", register = function() end }); m.set_teams({}, 1, 2)
  local dur = sc.w[#sc.w][1] + 1.0
  local fps = 60; local n = math.floor(dur * fps)
  local x0, z0 = pos(sc.w, 0); ball(x0, z0)
  for i = 1, 240 do m.display_frame({}); if i % 60 == 0 then fake = fake + 1 end end   -- assenta na posicao inicial (4 s)
  local d, a = {}, {}
  for i = 1, n do
    local t = (i - 1) / fps; local x, z = pos(sc.w, t); ball(x, z)
    m.display_frame({}); if i % 60 == 0 then fake = fake + 1 end
    d[i], a[i] = getf(DIST), getf(ALT)
  end
  local vd, va, ac, tv = 0, 0, 0, 0
  for i = 2, n do
    local sd = math.abs(d[i] - d[i - 1]) * fps; local sa = math.abs(a[i] - a[i - 1]) * fps
    if sd > vd then vd = sd end; if sa > va then va = sa end
    tv = tv + math.abs(a[i] - a[i - 1])
    if i > 2 then local ca = math.abs((a[i] - a[i - 1]) - (a[i - 1] - a[i - 2])) * fps * fps; if ca > ac then ac = ca end end
  end
  if os.getenv("SIM_DUMP") and tostring(_) == os.getenv("SIM_DUMP") then for i = 1, n, 4 do local t = (i - 1) / fps; local x, z = pos(sc.w, t); print(string.format("   t=%4.2f  bola z=%6.1f  altura=%6.2f  vel=%6.1f/s", t, z, a[i], i > 1 and (a[i] - a[i - 1]) * fps or 0)) end end
  print(string.format("%-62s %6.1f/s %6.1f/s %8.0f/s2 %8.1f %6.1fs", sc.nome, vd, va, ac, tv, dur))
  if vd > worst[1] then worst[1] = vd end; if va > worst[2] then worst[2] = va end
end
print(string.format("PIOR velocidade: dist %.1f/s | altura %.1f/s", worst[1], worst[2]))
