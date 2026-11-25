-- camera_dinamica.lua  v2.1
-- Camera ABERTA na defesa/meio e FECHADA (sua Dynamic Wide custom) perto do gol adversario.
-- Parametros (descobertos com o camtune): distancia da camera da Dynamic Wide = 0x14260b8fc
--   (28.70 original; valor alto = camera longe/aberta, valor baixo = perto).
--   Altura da camera da DW = 0x14260b900 (35.44 original; alto = camera la em cima, tipo blimp).
-- Teclas:  F6 = modo (dinamico / forcar FECHADA / forcar ABERTA / desligado)
--          F7 = "estou atacando para a DIREITA"   F8 = "estou atacando para a ESQUERDA"
--          (F6/F7/F8 so com a pagina camera_dinamica aberta no overlay: outros modulos usam as mesmas teclas)
-- Padrao (2.1): o perfil recomendado, testado em partidas (aberta e alta no meio, nao fecha na defesa,
--          lateral discreta so no lado de cima).
-- Configuracao: camera_dinamica.ini (na pasta do Sider); Shift+R recarrega.
local m = {}
m.version = "2.1"

-- ===== enderecos (FL27, exe sem ASLR; validados em 2026-11-06) =====
local G_OFF     = 0x36f3dc8   -- ponteiro do gerenciador da partida
local BALL_NODE_MIN = 0xa0    -- nos de G (+0x20) que podem conter a bola em +0xa80 (varia entre partida normal,
local BALL_NODE_MAX = 0xf1    -- treino e Master League: procura o primeiro grupo valido nessa faixa)
local BALL_POS  = 0xa80       -- posicao (x,y,z) dentro do objeto da bola
local PL_NODE   = 0xf3        -- nos dos jogadores (+0x20 = objeto)
local NPL       = 21
local PL_POS    = 0x2ef8      -- posicao (x,y,z) dentro do objeto do jogador
local HALF_LEN  = 52.5        -- meio comprimento do campo (m)

-- parametros que a transicao mexe: { nome, endereco, chave_aberta, chave_fechada }
local PARAMS = {
    { "dist",   0x14260b8fc, "dist_open",   "dist_close"   },   -- distancia da camera (principal)
    { "lateral",0x14260b8f8, "lat_open",    "lat_close"    },   -- 21.92: deslocamento lateral/altura
    { "angulo", 0x1425985a4, "angle_open",  "angle_close"  },   -- angulo da DW (camera.lua)
    { "altura", 0x14260b900, "height_open",  "height_close"  },   -- 35.44: ALTURA da camera
}

-- ===== configuracao =====
local cfg = {
    enabled = 1,
    debug = 0,                 -- 1: grava posicao da bola e decisao no sider.log (diagnostico)
    first_half_dir = 1,        -- +1: ataca para a direita (x+) no 1o tempo, -1: esquerda
    near_start = 23,           -- a partir de quantos metros do gol comeca a fechar
    near_end = 5,             -- a partir de quantos metros esta totalmente fechada
    def_start = 35,            -- na propria defesa: a partir de quantos metros do SEU gol comeca a fechar
    def_end = 17,              -- ...e fecha ao maximo (a grande area tem 16,5 m)
    def_strength = 0,        -- 0..1: quanto fecha na propria area (1 = igual ao ataque, 0 = nao fecha)
    side_start = 12,           -- bola a partir de quantos metros do centro (eixo z) comeca a abrir extra
    side_end = 28,             -- ...e abre o maximo (campo tem +-34 m de largura)
    side_dist = 10,            -- distancia extra na lateral
    side_height = 5,          -- altura extra na lateral
    side_top = 1.0,            -- ganho na lateral de CIMA (z negativo, onde o campo some)
    side_bottom = 0,         -- ganho na lateral de BAIXO
    side_angle = 0,            -- angulo (inclinacao) extra na lateral (como o fan view: inclina em vez de so se afastar)
    side_lat = 0,              -- parametro 'lateral' extra na lateral
    follow = 0.6,              -- segundos: a camera decide pelo 'lugar da jogada' (bola filtrada), nao pela bola instantanea
    transition = 0.9,          -- segundos para a camera atingir a velocidade de cruzeiro (maior = arranque/freada mais suaves)
    min_time = 2.5,            -- tempo minimo (s) para percorrer TODO o curso abrir<->fechar (limite de velocidade fisico)
    side_in_close = 0.35,      -- 0..1: quanto do extra da lateral continua na vista FECHADA (0 = nenhum)
    max_speed = 1.0,           -- (obsoleto desde a 2.0)
    smooth = 0.05,             -- (obsoleto desde a 1.5; mantido para nao quebrar o .ini)
    dist_open = 60.0,   dist_close = 25.5,
    lat_open = 21.921,  lat_close = 21.921,
    angle_open = 0.20,  angle_close = 0.20,
    height_open = 30.0, height_close = 34.0,
}
local cfg_order = { "enabled", "debug", "first_half_dir", "near_start", "near_end",
    "def_start", "def_end", "def_strength", "side_start", "side_end", "side_dist", "side_height", "side_top", "side_bottom", "side_angle", "side_lat", "follow", "transition", "min_time", "side_in_close", "max_speed", "smooth",
    "dist_open", "dist_close", "lat_open", "lat_close", "angle_open", "angle_close",
    "height_open", "height_close" }

local function load_ini(ctx)
    local path = ctx.sider_dir .. "\\camera_dinamica.ini"
    local f = io.open(path, "r")
    if not f then
        local w = io.open(path, "wt")
        if w then
            w:write("# camera_dinamica.lua " .. m.version .. "\n")
            w:write("# *_open = camera aberta (defesa/meio), *_close = camera fechada (perto do gol adversario)\n\n")
            for _, k in ipairs(cfg_order) do w:write(string.format("%s = %s\n", k, tostring(cfg[k]))) end
            w:close()
        end
        return
    end
    f:close()
    for line in io.lines(path) do
        local name, value = string.match(line, "^([%w_]+)%s*=%s*([-%w%d.]+)")
        if name and cfg[name] ~= nil and tonumber(value) then
            cfg[name] = tonumber(value)
        end
    end
end

local function save_ini(ctx)
    local f = io.open(ctx.sider_dir .. "\\camera_dinamica.ini", "wt")
    if not f then log("camera_dinamica: PROBLEMA ao salvar camera_dinamica.ini"); return end
    f:write("# camera_dinamica.lua " .. m.version .. " (salvo pelo overlay)\n")
    f:write("# *_open = camera aberta (meio), *_close = camera fechada (areas). dist = distancia, height = altura.\n\n")
    for _, k in ipairs(cfg_order) do f:write(string.format("%s = %s\n", k, tostring(cfg[k]))) end
    f:close()
end

-- itens editaveis no overlay: { rotulo, chave, passo, minimo, maximo }
local EDIT = {
    { "fechamento na SUA area (0..1)",   "def_strength", 0.1,  0,   1   },
    { "defesa: comeca a fechar (m)",     "def_start",    1,    10,  60  },
    { "defesa: fechado ao maximo (m)",   "def_end",      1,    5,   40  },
    { "ataque: comeca a fechar (m)",     "near_start",   1,    10,  70  },
    { "ataque: fechado ao maximo (m)",   "near_end",     1,    5,   50  },
    { "ABERTA: distancia",               "dist_open",    1,    5,   150, "o" },
    { "ABERTA: altura",                  "height_open",  2,    5,   200, "o" },
    { "FECHADA: distancia",              "dist_close",   0.5,  -5,  150, "c" },
    { "FECHADA: altura",                 "height_close", 0.5,  2,   200, "c" },
    { "lateral: comeca a abrir (m do centro)", "side_start", 1, 0, 34 },
    { "lateral: abre o maximo (m)",      "side_end",     1,    5,   40  },
    { "lateral: distancia extra",        "side_dist",    1,    0,   80  },
    { "lateral: altura extra",           "side_height",  2,    0,   150 },
    { "lateral de CIMA (ganho 0..1)",    "side_top",     0.1,  0,   2   },
    { "lateral de BAIXO (ganho 0..1)",   "side_bottom",  0.1,  0,   2   },
    { "lateral: angulo extra",           "side_angle",   0.05, -2,  2   },
    { "lateral: 'lateral' extra",        "side_lat",     1,    -40, 60  },
    { "ABERTA: angulo",                  "angle_open",   0.05, -2,  2,  "o" },
    { "FECHADA: angulo",                 "angle_close",  0.05, -2,  2,  "c" },
    { "ABERTA: lateral",                 "lat_open",     1,    -10, 80, "o" },
    { "FECHADA: lateral",                "lat_close",    1,    -10, 80, "c" },
    { "arranque/freada: segundos (maior = mais suave)", "transition", 0.1, 0.2, 6  },
    { "seguir a jogada: segundos (maior = menos nervoso)", "follow", 0.1, 0, 3 },
    { "tempo minimo abrir<->fechar (s)", "min_time",     0.25, 0.5, 10 },
    { "lateral que sobra na vista FECHADA (0..1)", "side_in_close", 0.05, 0, 1 },
    { "ligado (1) / desligado (0)",      "enabled",      1,    0,   1   },
}
local sel = 1
local frame_no = 0
local overlay_seen = -100

-- ===== leitura de memoria =====
local base
local function valid(p) return p and p > 0x10000 and p < 0x7fffffffffff end
-- Leitura SEGURA: o jogo pode ter liberado/movido objetos enquanto a partida carrega; ler um ponteiro velho gerava uma
-- violacao de acesso dentro do gancho (Wine: "KiUserCallbackDispatcher ignoring exception") e o jogo travava em laco.
-- IsBadReadPtr trata a excecao por dentro e devolve 1 se o trecho nao pode ser lido; nesse caso devolvemos 0.
-- (o Sider nao tem pcall: usa-se o ffi global, como os outros modulos)
local bad_read = nil
if ffi then
    ffi.cdef[[int IsBadReadPtr(const void* lp, unsigned long long ucb);]]
    bad_read = function(a, n) return ffi.C.IsBadReadPtr(ffi.cast("const void*", a), n) ~= 0 end
end
local function readable(a, n)
    if not a then return false end
    if type(a) ~= "number" then              -- base do exe chega como ponteiro (cdata): converte para numero
        if not ffi then return true end
        a = tonumber(ffi.cast("intptr_t", a))
        if not a then return false end
    end
    if a < 0x10000 or a > 0x7fffffffffff then return false end
    if bad_read then return not bad_read(a, n) end
    return true
end
local function u64(a)
    if not readable(a, 8) then return 0 end
    return memory.unpack("i64", memory.read(a, 8))
end
local function rf(a)
    if not readable(a, 4) then return 0/0 end
    return memory.unpack("f", memory.read(a, 4))
end
local function wf(a, v) memory.write(a, memory.pack("f", v)) end
local function finite(v) return type(v) == "number" and v == v and v > -1e6 and v < 1e6 end

-- ===== estado =====
local mode = 0                 -- 0 dinamico, 1 forcar FECHADA, 2 forcar ABERTA, 3 desligado
local mode_names = { [0] = "dinamico", "forcar FECHADA", "forcar ABERTA", "desligado" }
local t_smooth = 0             -- 0 = aberta, 1 = fechada
local side_smooth = 0          -- abertura extra perto das laterais (0..1)
local play_x, play_z = nil, nil      -- 'lugar da jogada': bola filtrada
local calib = nil              -- { gk=indice, s0=sinal do goleiro, dir0=direcao, cur=sinal atual }
local pending_auto = false
local last_info = "aguardando partida"
local dbg = { d = 0, t = 0, dir = 0, bx = 0, bz = 0 }
local was_writing = false

-- ===== bola =====
-- A posicao da bola fica em +0xa80 de varios objetos apontados pelos nos de G, sempre REPLICADA em nos vizinhos.
-- Os objetos "de bola" ficam nos nos mais altos (0xed..0xf0 em partida); copias em objetos de jogador ficam abaixo.
-- Regra: entre os grupos de nos vizinhos com valores identicos, vale o de no mais alto. Se esse grupo estiver
-- guardado fora do campo (replay/pausa: z=100), a bola esta "fora de jogo" (nao e erro).
local ball_node = nil          -- no atual da bola
local last_logged_node = nil
local ball_state = "procurando"   -- "ok" | "fora" (guardada fora do campo) | "procurando"
local NODE_MAIN_MIN = 0xe3     -- faixa validada (partida, treino, liga)

local function in_pool(g, node)   -- aceita qualquer ponteiro plausivel (alinhado, na faixa de usuario).
    -- Antes exigia estar a 8 MB do bloco dos jogadores, mas com outros mods (handball, BG Gameplay, goalnets) o jogo
    -- aloca a bola em outra area da memoria (ex.: 0x1e2d5080 contra jogadores em 0x352ff90). Valores lixo sao
    -- descartados por finite()/on_pitch() e pela exigencia de grupo de nos vizinhos com valores identicos.
    return valid(node) and node % 8 == 0
end

local function node_xyz(g, n)
    local node = u64(g + n * 0x28 + 0x20)
    if not valid(node) or not in_pool(g, node) then return nil end
    local a = node + BALL_POS
    local x, y, z = rf(a), rf(a + 4), rf(a + 8)
    if not (finite(x) and finite(y) and finite(z)) then return nil end
    if x == 0 and y == 0 and z == 0 then return nil end
    return x, y, z
end
local function on_pitch(x, y, z) return math.abs(x) <= 62 and math.abs(z) <= 44 and y > -1 and y < 40 end
local function parked(x, y, z)    -- bola guardada fora do campo pelo jogo
    return y > -1 and y < 3 and (math.abs(z) >= 80 or math.abs(x) >= 80) and math.abs(x) < 500 and math.abs(z) < 500
end

-- tamanho do grupo de nos vizinhos (n, n+1, ...) com exatamente os mesmos valores
local function run_len(g, n, x, y, z)
    local len = 1
    while len < 12 do
        local x2, y2, z2 = node_xyz(g, n + len)
        if x2 ~= x or y2 ~= y or z2 ~= z then break end
        len = len + 1
    end
    return len
end

-- procura de cima para baixo o primeiro grupo valido; devolve no, x, y, z
local function scan(g, lo, hi, minlen)
    local n = hi
    while n >= lo do
        local x, y, z = node_xyz(g, n)
        if x and (on_pitch(x, y, z) or parked(x, y, z)) then
            local start = n            -- desce ate o comeco do grupo
            while start > lo do
                local x2, y2, z2 = node_xyz(g, start - 1)
                if x2 ~= x or y2 ~= y or z2 ~= z then break end
                start = start - 1
            end
            if n - start + 1 >= minlen then return start, x, y, z end
            n = start - 1
        else
            n = n - 1
        end
    end
    return nil
end

local miss_frames = 0
local dumped = false
local function dump_nodes(g)   -- diagnostico (so com debug = 1, uma vez por partida)
    log("camera_dinamica: DIAGNOSTICO bola nao encontrada; nos de G (indice ptr x y z):")
    for n = 0x90, 0xf6 do
        local node = u64(g + n * 0x28 + 0x20)
        if valid(node) and in_pool(g, node) then
            local x, y, z = rf(node + BALL_POS), rf(node + BALL_POS + 4), rf(node + BALL_POS + 8)
            log(string.format("  no 0x%x ptr=%s  %.2f %.2f %.2f", n, memory.hex(node), x, y, z))
        end
    end
end

local cand = nil
local last_ball = nil            -- ultima posicao valida {x,y,z}
local lost_frames = 0
local HOLD_FRAMES = 180          -- segura a ultima posicao por ~3 s (gol, reposicao, replay)
local rescan_in = 0

local function set_node(n, how)
    ball_node = n
    if n ~= last_logged_node then
        log(string.format("camera_dinamica: bola no no 0x%x%s", n, how or ""))
        last_logged_node = n
    end
end

-- devolve x, y, z da bola EM JOGO, ou nil (ball_state diz se esta "fora" ou "procurando")
local function get_ball_raw(g)
    rescan_in = rescan_in - 1
    if ball_node and rescan_in > 0 then
        local x, y, z = node_xyz(g, ball_node)
        if x and run_len(g, ball_node, x, y, z) >= 2 then
            if on_pitch(x, y, z) then ball_state = "ok"; return x, y, z end
            if parked(x, y, z) then ball_state = "fora"; return nil end
        end
    end
    -- (re)procura: faixa validada primeiro, grupo de no mais alto
    rescan_in = 60
    local n, x, y, z = scan(g, NODE_MAIN_MIN, BALL_NODE_MAX, 2)
    if n then
        cand = nil
        set_node(n)
        if on_pitch(x, y, z) then ball_state = "ok"; return x, y, z end
        ball_state = "fora"; return nil
    end
    ball_node = nil
    ball_state = "procurando"
    -- faixa larga (modos desconhecidos): exige grupo de 3+ nos E que o valor se mova varias vezes
    rescan_in = 0
    if cand then
        local cx, cy, cz = node_xyz(g, cand.n)
        if not cx or not on_pitch(cx, cy, cz) or run_len(g, cand.n, cx, cy, cz) < 3 then
            cand = nil
        else
            if math.abs(cx - cand.x) > 0.05 or math.abs(cz - cand.z) > 0.05 then cand.moves = cand.moves + 1 end
            cand.x, cand.z = cx, cz
            if cand.moves >= 8 then
                set_node(cand.n, " (faixa ampla, confirmada por movimento)")
                cand = nil; rescan_in = 60; ball_state = "ok"
                return cx, cy, cz
            end
        end
        return nil
    end
    local wn, wx, wy, wz = scan(g, BALL_NODE_MIN, NODE_MAIN_MIN - 1, 3)
    if wn and on_pitch(wx, wy, wz) then cand = { n = wn, x = wx, z = wz, moves = 0 } end
    return nil
end

local function get_ball(g)
    local x, y, z = get_ball_raw(g)
    if x then
        if lost_frames >= 10 and cfg.debug == 1 then
            log(string.format("camera_dinamica: bola de volta apos %d frames (x=%.1f z=%.1f)", lost_frames, x, z))
        end
        lost_frames = 0
        last_ball = { x, y, z }
        return x, y, z
    end
    lost_frames = lost_frames + 1
    if lost_frames == 10 and cfg.debug == 1 then
        log("camera_dinamica: sem bola em jogo (" .. ball_state .. ")")
    end
    if last_ball and lost_frames <= HOLD_FRAMES then
        return last_ball[1], last_ball[2], last_ball[3]   -- mantem o ultimo valor, sem "piscar"
    end
    return nil
end

-- ===== tempo real e suavizacao =====
-- FPS medido pelo relogio de PAREDE (os.time muda a cada segundo real). os.clock NAO serve: mede tempo de CPU do
-- processo inteiro (todas as threads), que no jogo anda 3-5x mais rapido que o tempo real.
local wt_last, wt_frames, fps_est, wt_valid = nil, 0, 60, false
local function frame_dt()
    local now = os.time()
    wt_frames = wt_frames + 1
    if wt_last == nil then
        wt_last, wt_frames = now, 0
    elseif now ~= wt_last then
        local secs = now - wt_last
        if wt_valid and secs >= 1 and secs <= 3 and wt_frames > 0 then
            local f = wt_frames / secs
            if f < 10 then f = 10 elseif f > 300 then f = 300 end
            fps_est = fps_est + (f - fps_est) * 0.5
        end
        wt_valid = true            -- a primeira janela (parcial) nao vale
        wt_last, wt_frames = now, 0
    end
    return 1 / fps_est
end

-- suavizacao de 2a ordem (criticamente amortecida, estilo "SmoothDamp"): comeca e termina suave,
-- com velocidade maxima. st = { v = velocidade }.
local function smoothdamp(cur, target, st, smooth_time, max_speed, dt)
    if smooth_time < 0.05 then smooth_time = 0.05 end
    local omega = 2 / smooth_time
    local x = omega * dt
    local e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
    local change = cur - target
    local max_change = max_speed * smooth_time
    if change > max_change then change = max_change elseif change < -max_change then change = -max_change end
    local tgt2 = cur - change
    local tmp = (st.v + omega * change) * dt
    st.v = (st.v - omega * tmp) * e
    local out = tgt2 + (change + tmp) * e
    if (target - cur > 0) == (out > target) then out = target; st.v = (out - target) / dt end
    return out
end

local function player_x(g, i)
    local p = u64(g + (PL_NODE + i) * 0x28 + 0x20)
    if not valid(p) then return nil end
    local x = rf(p + PL_POS)
    if not finite(x) or math.abs(x) > 70 then return nil end
    return x
end

local function calibrate(g, dir0, why)
    -- procura um goleiro: jogador com |x| > 43 (no saque inicial ficam a ~50 m)
    local best, bestx = nil, 0
    for i = 0, NPL - 1 do
        local x = player_x(g, i)
        if x and math.abs(x) > 43 and math.abs(x) > math.abs(bestx) then best, bestx = i, x end
    end
    if not best then return false end
    calib = { gk = best, s0 = (bestx > 0) and 1 or -1, dir0 = dir0, cur = (bestx > 0) and 1 or -1 }
    log(string.format("camera_dinamica: calibrado (%s): goleiro=obj %d x=%.1f, ataque dir=%d", why, best, bestx, dir0))
    return true
end

local function attack_dir(g)
    if not calib then return nil end
    local x = player_x(g, calib.gk)
    if x and math.abs(x) > 30 then calib.cur = (x > 0) and 1 or -1 end
    return calib.dir0 * calib.s0 * calib.cur
end

local function smoothstep(u)
    if u < 0 then u = 0 elseif u > 1 then u = 1 end
    return u * u * (3 - 2 * u)
end

-- Perfil trapezoidal PLANEJADO: acelera com a_max ate a velocidade de cruzeiro, segue, e FREIA a tempo
-- (v <= sqrt(2*a*distancia_restante)) para chegar ao alvo com velocidade ~0: sem estouro e sem parada seca.
-- Alvo mudando no meio do caminho (inversao): a velocidade so pode mudar a_max por segundo, entao nunca ha tranco.
-- st = { cur, v }; vmax em unidades/s; tt = segundos para atingir a velocidade de cruzeiro (a_max = vmax/tt).
local function ramp(st, target, vmax, tt, dt)
    local amax = vmax / math.max(tt, 0.05)
    local e = target - st.cur
    local ae = math.abs(e)
    -- ae/tt: perto do alvo a velocidade e proporcional ao que falta (aproximacao suave, sem perseguir ruido pequeno);
    -- piso de 2% de vmax para a cauda terminar em tempo finito, sem salto
    local vdes = math.min(vmax, math.sqrt(2 * amax * ae), math.max(ae / math.max(tt, 0.05), 0.02 * vmax), ae / dt)
    if e < 0 then vdes = -vdes end
    local dv = vdes - st.v
    local lim = amax * dt
    if dv > lim then dv = lim elseif dv < -lim then dv = -lim end
    st.v = st.v + dv
    local step = st.v * dt
    if ae <= math.abs(step) and step * e >= 0 then
        st.cur = target; st.v = 0
    else
        st.cur = st.cur + step
    end
    return st.cur
end

-- ===== vista-alvo por parametro e saida suavizada =====
-- Para cada parametro (distancia, altura...): alvo = mistura de DUAS vistas que ja incluem a lateral:
--   aberta(s) = aberta + extra*s            fechada(s) = fechada + extra*side_in_close*s
--   alvo = aberta(s) + (fechada(s) - aberta(s)) * c        (c = fechamento 0..1, s = lateral 0..1)
-- e a saida anda com 'ramp' (perfil trapezoidal planejado) com LIMITE DE VELOCIDADE em unidades do proprio parametro
-- (curso total / min_time), para a camera nunca "pular" mesmo que a bola va longe de repente.
local P_ST = {}      -- estado por parametro: { cur, v }
local function side_of(p)
    if p[1] == "dist" then return cfg.side_dist elseif p[1] == "altura" then return cfg.side_height end
    if p[1] == "angulo" then return cfg.side_angle elseif p[1] == "lateral" then return cfg.side_lat end
    return 0
end
local function param_target(p, c, sd)
    local o, cl, so = cfg[p[3]], cfg[p[4]], side_of(p)
    local open_t = o + so * sd
    local close_t = cl + so * cfg.side_in_close * sd
    return open_t + (close_t - open_t) * c
end
local function param_range(p)
    local o, cl, so = cfg[p[3]], cfg[p[4]], side_of(p)
    local r = math.max(math.abs(o + so - cl), math.abs(o - cl), math.abs(so), 1)
    return r
end
local function drive(c, sd, dt, tt, min_time)
    for _, p in ipairs(PARAMS) do
        local o, cl = cfg[p[3]], cfg[p[4]]
        if math.abs(o - cl) > 1e-6 or side_of(p) ~= 0 then
            local tgt = param_target(p, c, sd)
            local st = P_ST[p[1]]
            if not st then st = { cur = tgt, v = 0 }; P_ST[p[1]] = st end
            ramp(st, tgt, param_range(p) / min_time, tt, dt)
            wf(p[2], st.cur)
        end
    end
    was_writing = true
end

local function restore_close()
    -- volta ao ajuste "fechado" (= sua Dynamic Wide normal)
    for _, p in ipairs(PARAMS) do
        local o, cl = cfg[p[3]], cfg[p[4]]
        if math.abs(o - cl) > 1e-6 or side_of(p) ~= 0 then wf(p[2], cl) end
    end
    P_ST = {}
    was_writing = false
end

-- ===== traco (diagnostico): guarda os ultimos ~15 s; F10 salva em camera_dinamica_trace.csv =====
local TR_N = 900
local TR = { t = {}, bx = {}, bz = {}, px = {}, pz = {}, c = {}, sd = {}, d = {}, h = {} }
local tr_i, tr_count = 0, 0
local function tr_push(bx, bz, px, pz, c, sd)
    tr_i = tr_i % TR_N + 1
    tr_count = math.min(tr_count + 1, TR_N)
    TR.t[tr_i] = frame_no; TR.bx[tr_i] = bx; TR.bz[tr_i] = bz; TR.px[tr_i] = px; TR.pz[tr_i] = pz
    TR.c[tr_i] = c; TR.sd[tr_i] = sd
    TR.d[tr_i] = P_ST.dist and P_ST.dist.cur or 0; TR.h[tr_i] = P_ST.altura and P_ST.altura.cur or 0
end
local function dump_trace(ctx)
    local f = io.open(ctx.sider_dir .. "\\camera_dinamica_trace.csv", "wt")
    if not f then log("camera_dinamica: nao consegui gravar camera_dinamica_trace.csv"); return end
    f:write(string.format("# camera_dinamica %s fps=%.1f follow=%.2f transition=%.2f min_time=%.2f side_in_close=%.2f\n", m.version, fps_est, cfg.follow, cfg.transition, cfg.min_time, cfg.side_in_close))
    f:write("quadro,bola_x,bola_z,jogada_x,jogada_z,fechamento,lateral,dist,altura\n")
    local first = (tr_count == TR_N) and (tr_i % TR_N + 1) or 1
    for k = 0, tr_count - 1 do
        local i = (first + k - 1) % TR_N + 1
        f:write(string.format("%d,%.2f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f\n", TR.t[i], TR.bx[i], TR.bz[i], TR.px[i], TR.pz[i], TR.c[i], TR.sd[i], TR.d[i], TR.h[i]))
    end
    f:close()
    log(string.format("camera_dinamica: TRACO salvo (%d quadros) em camera_dinamica_trace.csv", tr_count))
    last_info = "traco salvo (F10)"
end

local warmup = 0
function m.set_teams(ctx, home, away)
    calib = nil
    pending_auto = true
    t_smooth = 0
    side_smooth = 0
    P_ST = {}
    play_x, play_z = nil, nil
    last_ball = nil
    lost_frames = 0
    dumped = false
    ball_node = nil
    cand = nil
    last_info = "partida carregando"
    warmup = 150           -- ~2,5 s sem tocar na memoria da partida enquanto ela carrega
end

local function overlay_active() return frame_no - overlay_seen <= 3 end

function m.key_down(ctx, vkey)
    if overlay_active() and (vkey == 0x21 or vkey == 0x22 or vkey == 0x2e or vkey == 0x2d) then
        local it = EDIT[sel]
        if vkey == 0x21 and sel > 1 then sel = sel - 1
        elseif vkey == 0x22 and sel < #EDIT then sel = sel + 1
        elseif vkey == 0x2e or vkey == 0x2d then
            local v = cfg[it[2]] + ((vkey == 0x2d) and it[3] or -it[3])
            if v < it[4] then v = it[4] elseif v > it[5] then v = it[5] end
            cfg[it[2]] = math.floor(v * 1000 + 0.5) / 1000
            save_ini(ctx)
        end
        return
    end
    if vkey == 0x75 then          -- F6 (so com a pagina do camera_dinamica aberta: o Fox Locomotion tambem usa F6)
        if not overlay_active() then return end
        mode = (mode + 1) % 4
        if mode == 3 and was_writing then restore_close() end
        log("camera_dinamica: modo " .. mode_names[mode])
    elseif vkey == 0x79 then       -- F10: salva o traco dos ultimos ~15 s (use logo depois de ver um tranco)
        dump_trace(ctx)
    elseif (vkey == 0x76 or vkey == 0x77) and overlay_active() then   -- F7 direita / F8 esquerda (só com a página aberta: F7/F8 também são do TFSE)
        local g = u64(base + G_OFF)
        if valid(g) then
            local dir0 = (vkey == 0x76) and 1 or -1
            if calibrate(g, dir0, "tecla") then pending_auto = false end
        end
    end
end

function m.display_frame(ctx)
    frame_no = frame_no + 1
    if mode == 3 or cfg.enabled == 0 then return end
    if warmup > 0 then warmup = warmup - 1; last_info = "partida carregando"; return end
    local g = u64(base + G_OFF)
    if not valid(g) then
        last_info = "sem partida"
        return
    end
    local dt = frame_dt()
    local bx, by, bz = get_ball(g)
    if not bx then
        if ball_state == "fora" then
            last_info = "bola fora de jogo (replay/pausa)"
        else
            last_info = "bola nao encontrada"
            miss_frames = miss_frames + 1
            if miss_frames == 240 and cfg.debug == 1 and not dumped then dumped = true; dump_nodes(g) end
        end
        if was_writing and last_ball then   -- ja houve bola nesta partida: relaxa para a vista aberta
            drive(0, 0, dt, cfg.transition, cfg.min_time)
            dbg.t = 0
        end
        return
    end
    miss_frames = 0
    if pending_auto and not calib then
        if calibrate(g, cfg.first_half_dir, "auto") then pending_auto = false end
    end

    -- 1) "lugar da jogada": a bola filtrada. Passes longos e rebotes nao fazem a camera bombear.
    if play_x == nil then
        play_x, play_z = bx, bz
    else
        local a = 1 - math.exp(-dt / math.max(cfg.follow, 0.02))
        play_x = play_x + (bx - play_x) * a
        play_z = play_z + (bz - play_z) * a
    end

    -- 2) fechamento c (0 = vista aberta, 1 = fechada) pela posicao da jogada ao longo do campo
    local dir = attack_dir(g)
    dbg.bx, dbg.bz = bx, bz
    local d_att
    if dir then
        dbg.dir = dir
        d_att = HALF_LEN - dir * play_x       -- distancia (em x) ate a linha de fundo adversaria
    else
        d_att = HALF_LEN - math.abs(play_x)
    end
    dbg.d = d_att
    local c
    if mode == 1 then c = 1
    elseif mode == 2 then c = 0
    else
        local span = math.max(cfg.near_start - cfg.near_end, 1)
        local dspan = math.max(cfg.def_start - cfg.def_end, 1)
        c = smoothstep((cfg.near_start - d_att) / span)
        if dir then
            local d_own = HALF_LEN + dir * play_x
            local c_def = cfg.def_strength * smoothstep((cfg.def_start - d_own) / dspan)
            if c_def > c then c = c_def end
        else
            last_info = "ok (simetrico: sem calibracao do lado)"
        end
    end

    -- 3) lateral sd (0..1) pela largura: o outro lado do campo nao pode sumir quando a jogada esta numa lateral
    local span2 = math.max(cfg.side_end - cfg.side_start, 1)
    local gain = (play_z < 0) and cfg.side_top or cfg.side_bottom
    local sd = gain * smoothstep((math.abs(play_z) - cfg.side_start) / span2)

    -- previa: enquanto edita uma linha ABERTA/FECHADA no overlay, mostra aquela vista (rapido)
    local tt, mtime = cfg.transition, cfg.min_time
    if overlay_active() and EDIT[sel][6] then
        c = (EDIT[sel][6] == "c") and 1 or 0
        sd = 0
        tt, mtime = math.min(tt, 0.3), math.min(mtime, 0.8)
        last_info = "PREVIA: " .. ((EDIT[sel][6] == "c") and "vista FECHADA" or "vista ABERTA")
    end

    drive(c, sd, dt, tt, mtime)
    dbg.t = c
    tr_push(bx, bz, play_x, play_z, c, sd)
    if cfg.debug == 1 and frame_no % 20 == 0 then
        log(string.format("cd: bola x=%.1f z=%.1f | jogada x=%.1f z=%.1f | dir=%s d_adv=%.1f | c=%.2f sd=%.2f | modo=%d",
            bx, bz, play_x, play_z, tostring(dir), d_att, c, sd, mode))
    end
    if dir and not (overlay_active() and EDIT[sel][6]) then last_info = "ok" end
end

function m.overlay_on(ctx)
    overlay_seen = frame_no
    local lines = {}
    for i, it in ipairs(EDIT) do
        lines[#lines + 1] = string.format("%s %-33s %8.3f", (i == sel) and "--->" or "    ", it[1], cfg[it[2]])
    end
    return string.format(
        "camera_dinamica %s | modo: %s | %s\nbola x=%.1f z=%.1f | ataque dir=%d | dist. gol=%.1f | fechamento=%.2f | %.0f fps\n[F6] modo  [F7] ataco p/ DIREITA  [F8] ataco p/ ESQUERDA  [F10] salva traco (use logo apos ver um tranco)\nPgUp/PgDn escolhe, Delete diminui, Insert aumenta (salva sozinho)\n%s",
        m.version, mode_names[mode], last_info, dbg.bx, dbg.bz or 0, dbg.dir, dbg.d, dbg.t, fps_est, table.concat(lines, "\n"))
end

m._teste = { ramp = ramp, get_ball = function(g) return get_ball(g) end, estado = function() return ball_state, ball_node end, smoothdamp = smoothdamp, frame_dt = frame_dt, set_fps = function(f) fps_est = f end }

function m.init(ctx)
    base = memory.get_process_info().base
    load_ini(ctx)
    local z = rf(PARAMS[1][2])
    if not finite(z) then error("camera_dinamica: parametro da camera ilegivel") end
    log(string.format("camera_dinamica %s: dist DW=%.3f | enabled=%d", m.version, z, cfg.enabled))
    ctx.register("set_teams", m.set_teams)
    ctx.register("key_down", m.key_down)
    ctx.register("display_frame", m.display_frame)
    ctx.register("overlay_on", m.overlay_on)
end

return m
