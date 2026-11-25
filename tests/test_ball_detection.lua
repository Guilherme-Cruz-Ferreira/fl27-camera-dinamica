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

-- H) suavizacao de 2a ordem (smoothdamp)
local function run(fps, secs, target, tt, vmax)
  local st, cur, dt, out, prevc, maxstep = { v = 0 }, 0, 1 / fps, {}, 0, 0
  for i = 1, math.floor(secs * fps) do
    cur = T.smoothdamp(cur, target, st, tt, vmax, dt)
    out[i] = cur
    if math.abs(cur - prevc) > maxstep then maxstep = math.abs(cur - prevc) end
    prevc = cur
  end
  return out, maxstep
end
local o60, ms60 = run(60, 4, 1, 1.3, 1.0)
local mono, over = true, false
for i = 2, #o60 do if o60[i] < o60[i - 1] - 1e-9 then mono = false end if o60[i] > 1 + 1e-6 then over = true end end
check("H nunca recua e nunca ultrapassa o alvo", mono and not over)
check("H arranque suave: 1o quadro mexe < 0,5% do curso", o60[1] < 0.005, string.format("%.5f", o60[1]))
check("H assenta (>98%) em 4 s", o60[#o60] > 0.98, string.format("%.4f", o60[#o60]))
local o30 = run(30, 4, 1, 1.3, 1.0); local o120 = run(120, 4, 1, 1.3, 1.0)
check("H mesmo resultado a 30/60/120 FPS (valor em t=1 s)", math.abs(o30[30] - o60[60]) < 0.02 and math.abs(o120[120] - o60[60]) < 0.02,
      string.format("30fps=%.3f 60fps=%.3f 120fps=%.3f", o30[30], o60[60], o120[120]))
local oj = run(60, 3, 1, 1.3, 1.0)
local fastest = 0; for i = 2, #oj do local sp = (oj[i] - oj[i - 1]) * 60; if sp > fastest then fastest = sp end end
check("H velocidade maxima respeitada (<= 1,15 curso/s)", fastest <= 1.15, string.format("pico %.2f curso/s", fastest))
local oslow = run(60, 3, 1, 1.3, 0.5)
local f2 = 0; for i = 2, #oslow do local sp = (oslow[i] - oslow[i - 1]) * 60; if sp > f2 then f2 = sp end end
check("H max_speed 0,5 limita ainda mais", f2 <= 0.6, string.format("pico %.2f curso/s", f2))
-- alvo se movendo (bola cruzando de uma lateral para o meio): sem saltos entre quadros
local st, cur, worst, prevc = { v = 0 }, 0, 0, 0
for i = 1, 240 do local tg = (i < 60) and 1 or 0; cur = T.smoothdamp(cur, tg, st, 1.3, 1.0, 1 / 60); if math.abs(cur - prevc) > worst then worst = math.abs(cur - prevc) end prevc = cur end
check("H inversao brusca do alvo: maior passo por quadro < 2% do curso", worst < 0.02, string.format("%.4f", worst))

-- H2) FPS medido pelo relogio de parede (os.time simulado)
local fake = 1000; local real_time = os.time; os.time = function() return fake end
for sec = 1, 8 do for f = 1, 60 do T.frame_dt() end fake = fake + 1 end
local dt60 = T.frame_dt()
check("H2 mede ~60 FPS", math.abs(1 / dt60 - 60) < 6, string.format("%.1f fps", 1 / dt60))
for sec = 1, 10 do for f = 1, 30 do T.frame_dt() end fake = fake + 1 end
local dt30 = T.frame_dt()
check("H2 acompanha queda para ~30 FPS", math.abs(1 / dt30 - 30) < 4, string.format("%.1f fps", 1 / dt30))
os.time = real_time

-- R) ramp (perfil trapezoidal planejado)
local function runramp(fps, secs, tgt_fn, vmax, tt)
  local st = { cur = 0, v = 0 }; local dt = 1 / fps; local out, vel = {}, {}
  for i = 1, math.floor(secs * fps) do T.ramp(st, tgt_fn((i - 1) * dt), vmax, tt, dt); out[i] = st.cur; vel[i] = st.v end
  return out, vel
end
local r, v = runramp(60, 8, function() return 45 end, 18, 0.9)
local over, vmaxobs, amaxobs, signs = false, 0, 0, 0
for i = 1, #r do if r[i] > 45 + 1e-9 then over = true end if math.abs(v[i]) > vmaxobs then vmaxobs = math.abs(v[i]) end
  if i > 1 then local ac = math.abs(v[i] - v[i - 1]) * 60; if ac > amaxobs then amaxobs = ac end end end
check("R nao ultrapassa o alvo", not over)
check("R chega ao alvo e para (final exato, v=0)", math.abs(r[#r] - 45) < 1e-6 and v[#v] == 0, string.format("final=%.4f v=%.4f", r[#r], v[#v]))
check("R respeita a velocidade maxima (18)", vmaxobs <= 18 + 1e-6, string.format("pico %.2f", vmaxobs))
check("R aceleracao <= a_max (20/s2) com folga de 25%", amaxobs <= 25, string.format("pico %.1f/s2", amaxobs))
local last = 0; for i = 1, #r do if v[i] > 0.5 then last = i end end
check("R chega devagar: velocidade <= 1.5 u/s no ultimo 0,5 s antes de parar", (function() for i = math.max(1, #r - 30), #r do if math.abs(v[i]) > 1.5 then return false end end return true end)())
-- sem oscilacao: velocidade nunca troca de sinal numa subida simples
local flips = 0; for i = 2, #v do if v[i] * v[i - 1] < 0 then flips = flips + 1 end end
check("R subida simples nao oscila (0 trocas de sentido)", flips == 0, flips .. " trocas")
-- inversao no meio do caminho
local r2, v2 = runramp(60, 8, function(t) return (t < 1.2) and 45 or 0 end, 18, 0.9)
local worst = 0; for i = 2, #v2 do local ac = math.abs(v2[i] - v2[i - 1]) * 60; if ac > worst then worst = ac end end
check("R inversao do alvo no meio: aceleracao sempre <= 25/s2 (sem tranco)", worst <= 25, string.format("pico %.1f/s2", worst))
check("R inversao: termina no novo alvo (0)", math.abs(r2[#r2]) < 1e-6)
-- mesmo resultado em 30/60/120 FPS
local p30 = runramp(30, 3, function() return 45 end, 18, 0.9); local p60 = runramp(60, 3, function() return 45 end, 18, 0.9); local p120 = runramp(120, 3, function() return 45 end, 18, 0.9)
check("R igual em 30/60/120 FPS (posicao em t=1,5 s)", math.abs(p30[45] - p60[90]) < 1.5 and math.abs(p120[180] - p60[90]) < 1.5, string.format("%.1f %.1f %.1f", p30[45], p60[90], p120[180]))
-- ruido pequeno no alvo nao faz a camera 'nervosa'
local r3 = runramp(60, 6, function(t) return 20 + ((math.floor(t / 0.4) % 2 == 0) and 2 or -2) end, 18, 0.9)
local tvn = 0; for i = 2, #r3 do tvn = tvn + math.abs(r3[i] - r3[i - 1]) end
check("R ruido de +-2 no alvo: movimento total proximo do necessario (<= 30)", tvn <= 30, string.format("%.1f (necessario ~20)", tvn))

-- K) 2.1: depois de set_teams o modulo espera ~2,5 s (150 quadros) sem tocar na memoria da partida
reset(); fresh(); ball(0xee, 0xef, 10, 0.11, -20)
local d0 = (string.unpack("<f", memory.read(0x14260b8fc, 4)))
for i = 1, 149 do m.display_frame({}) end
local d1 = (string.unpack("<f", memory.read(0x14260b8fc, 4)))
check("K espera 150 quadros apos set_teams sem escrever na camera", d0 == d1, string.format("%s -> %s", tostring(d0), tostring(d1)))

-- J) traco F10 (depois da espera do carregamento)
reset(); fresh(); ball(0xee, 0xef, 10, 0.11, -20)
for i = 1, 150 do m.display_frame({}) end
for i = 1, 120 do m.display_frame({}) end
m.key_down({ sider_dir = arg[2] .. "/" }, 0x79)
local fh = io.open(arg[2] .. "/\\camera_dinamica_trace.csv", "r")
local nl = 0; local header2 = ""
if fh then for l in fh:lines() do nl = nl + 1; if nl == 2 then header2 = l end end fh:close() end
check("J F10 grava o traco (120 quadros + 2 cabecalhos)", nl == 122, nl .. " linhas; cab: " .. header2:sub(1, 40))

-- I) display_frame roda sem erro nos cenarios (smoke) e escreve valores finitos na camera
reset(); fresh(); ball(0xee, 0xef, 40, 0.11, 0)
local okrun, err = pcall(function() for i = 1, 400 do m.display_frame({}) end end)
local dist = (string.unpack("<f", memory.read(0x14260b8fc, 4)))
check("I display_frame 400 quadros sem erro", okrun, tostring(err))
check("I camera perto do gol foi para a vista fechada (dist ~ dist_close)", dist > 20 and dist < 30, string.format("dist=%.2f", dist))
print(string.format("\n%d OK, %d falhas", ok, fail))
print("log do modulo:"); for _, l in ipairs(logs) do print("   " .. l) end
