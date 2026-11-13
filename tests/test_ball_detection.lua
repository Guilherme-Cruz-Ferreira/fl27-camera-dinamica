-- simula a memoria do jogo e testa a deteccao da bola do camera_dinamica
local _open = io.open; io.open = function(p, mode) return _open(p, mode and mode:gsub("t", "") or nil) end   -- "wt" so existe no Windows
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
local logs = {}
log = function(s) logs[#logs + 1] = s end
local G, P0 = 0x30000000, 0x20000000
local function setq(a, v) memory.write(a, string.pack("<i8", v)) end
local function setf(a, v) memory.write(a, string.pack("<f", v)) end
local function node_ptr(n) return 0x20100000 + n * 0x2000 end
local function reset()
  bytes = {}
  setq(0x140000000 + 0x36f3dc8, G)
  for i = 0, 21 do setq(G + (0xf3 + i) * 0x28 + 0x20, P0 + i * 0x3f40) end
  for n = 0x90, 0xf2 do setq(G + n * 0x28 + 0x20, node_ptr(n)) end
end
local function ball(n1, n2, x, y, z) for n = n1, n2 do local a = node_ptr(n) + 0xa80; setf(a, x); setf(a + 4, y); setf(a + 8, z) end end
local m = dofile(arg[1])
m.init({ sider_dir = arg[2] .. "/", register = function() end })
local T = m._teste
local ok, fail = 0, 0
local function check(name, cond, extra) if cond then ok = ok + 1 else fail = fail + 1 end print((cond and "OK   " or "FALHA") .. " " .. name .. (extra and ("  -> " .. extra) or "")) end
local function near(a, b) return a and math.abs(a - b) < 0.01 end
local function fresh() m.set_teams({}, 1, 2) end

-- A) partida: grupo "falso" em 0xe3..0xe5 e bola de verdade em 0xee..0xef
reset(); fresh(); ball(0xe3, 0xe5, 26.72, 0.11, -26.14); ball(0xe8, 0xe8, 23.28, 0, 0.52); ball(0xec, 0xec, 2.5, 0, -3.16); ball(0xee, 0xef, 20.82, 0.11, -22.7)
local x = T.get_ball(G); local st, nd = T.estado()
check("A partida: usa o grupo de no mais alto (0xee), nao o 0xe3", near(x, 20.82) and nd == 0xee, string.format("x=%s no=0x%x", tostring(x), nd or 0))

-- B) liga: bola guardada fora do campo (z=100) -> 'fora', sem erro; depois volta
reset(); fresh(); ball(0xec, 0xec, 7.49, 0, -0.18); ball(0xed, 0xef, 0, 0.11, 100)
x = T.get_ball(G); st, nd = T.estado()
check("B liga: bola guardada (z=100) = 'fora de jogo', nao segue o no 0xec", x == nil and st == "fora", "estado=" .. tostring(st))
ball(0xed, 0xef, 10, 0.11, 5); x = T.get_ball(G); st = T.estado()
check("B liga: bola volta ao jogo", near(x, 10) and st == "ok", "x=" .. tostring(x))
ball(0xed, 0xef, 0, 0.11, 100); x = T.get_ball(G)
check("B liga: ao sair de jogo, segura a ultima posicao (x=10)", near(x, 10) and T.estado() == "fora")

-- C) treino: bola replicada em 0xe3..0xec, nos de cima zerados
reset(); fresh(); ball(0xe3, 0xec, -9.43, 1.74, -6.46)
x = T.get_ball(G); st, nd = T.estado()
check("C treino: acha a bola no grupo 0xe3..0xec", near(x, -9.43) and st == "ok", string.format("no=0x%x", nd or 0))

-- D) so um par solto na faixa ampla (0xd9,0xda), se movendo -> NAO pode virar bola
reset(); fresh(); local got = nil
for i = 1, 40 do ball(0xd9, 0xda, -53.4 + i * 0.2, 0.11, 7.5); got = got or T.get_ball(G) end
check("D par solto em 0xd9/0xda nunca vira bola", got == nil, "estado=" .. tostring((T.estado())))

-- E) faixa ampla com grupo de 3 que se move -> aceito depois de confirmar movimento
reset(); fresh(); got = nil; local frames = 0
for i = 1, 40 do ball(0xd5, 0xd7, 5 + i * 0.3, 0.11, 2); local v = T.get_ball(G); if v and not got then got = v; frames = i end end
check("E grupo de 3 em faixa ampla e aceito so apos se mover", got ~= nil and frames >= 8, "aceito no quadro " .. frames)

-- F) grupo de 3 PARADO na faixa ampla -> nunca aceito
reset(); fresh(); got = nil
for i = 1, 60 do ball(0xd5, 0xd7, 5, 0.11, 2); got = got or T.get_ball(G) end
check("F grupo parado na faixa ampla nunca vira bola", got == nil)

-- G) troca de no no meio da partida (0xe3 primeiro, depois aparece 0xee): corrige em ate 60 quadros
reset(); fresh(); ball(0xe3, 0xe5, 1, 0.11, 1); x = T.get_ball(G)
ball(0xee, 0xef, 30, 0.11, 3); local sw = nil
for i = 1, 70 do local v = T.get_ball(G); if near(v, 30) and not sw then sw = i end end
check("G passa para o no mais alto quando ele aparece", sw ~= nil and sw <= 61, "no quadro " .. tostring(sw))

-- H) suavizacao por tempo
local a60, a30, a120 = T.alpha(0.02, 1 / 60), T.alpha(0.02, 1 / 30), T.alpha(0.02, 1 / 120)
check("H alpha: 60 fps = valor do ini", near(a60, 0.02), string.format("%.4f", a60))
check("H alpha: 2 quadros de 60 fps = 1 quadro de 30 fps", near(1 - (1 - a60) ^ 2, a30), string.format("30fps=%.4f", a30))
check("H alpha: 2 quadros de 120 fps = 1 quadro de 60 fps", near(1 - (1 - a120) ^ 2, a60), string.format("120fps=%.4f", a120))

-- I) display_frame roda sem erro nos cenarios (smoke) e escreve valores finitos na camera
reset(); fresh(); ball(0xee, 0xef, 40, 0.11, 0)
local okrun, err = pcall(function() for i = 1, 400 do m.display_frame({}) end end)
local dist = (string.unpack("<f", memory.read(0x14260b8fc, 4)))
check("I display_frame 400 quadros sem erro", okrun, tostring(err))
check("I camera perto do gol foi para a vista fechada (dist ~ dist_close)", dist > 20 and dist < 30, string.format("dist=%.2f", dist))
print(string.format("\n%d OK, %d falhas", ok, fail))
print("log do modulo:"); for _, l in ipairs(logs) do print("   " .. l) end
