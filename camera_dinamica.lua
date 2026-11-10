-- camera_dinamica.lua  v0.4
-- Camera ABERTA na defesa/meio e FECHADA (sua Dynamic Wide custom) perto do gol adversario.
-- Parametros (descobertos com o camtune): distancia da camera da Dynamic Wide = 0x14260b8fc
--   (28.70 original; valor alto = camera longe/aberta, valor baixo = perto).
--   Altura da camera da DW = 0x14260b900 (35.44 original; alto = camera la em cima, tipo blimp).
-- Teclas:  F6 = modo (dinamico / forcar FECHADA / forcar ABERTA / desligado)
--          F7 = "estou atacando para a DIREITA"   F8 = "estou atacando para a ESQUERDA"
-- Configuracao: camera_dinamica.ini (na pasta do Sider); Shift+R recarrega.
local m = {}
m.version = "1.2.1"

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
    near_start = 45,           -- a partir de quantos metros do gol comeca a fechar
    near_end = 16,             -- a partir de quantos metros esta totalmente fechada
    def_start = 35,            -- na propria defesa: a partir de quantos metros do SEU gol comeca a fechar
    def_end = 17,              -- ...e fecha ao maximo (a grande area tem 16,5 m)
    def_strength = 0.6,        -- 0..1: quanto fecha na propria area (1 = igual ao ataque, 0 = nao fecha)
    side_start = 12,           -- bola a partir de quantos metros do centro (eixo z) comeca a abrir extra
    side_end = 28,             -- ...e abre o maximo (campo tem +-34 m de largura)
    side_dist = 10,            -- distancia extra na lateral
    side_height = 25,          -- altura extra na lateral
    side_top = 1.0,            -- ganho na lateral de CIMA (z negativo, onde o campo some)
    side_bottom = 0.3,         -- ganho na lateral de BAIXO
    smooth = 0.05,             -- 0..1, suavizacao por frame (menor = mais lento)
    dist_open = 40.0,   dist_close = 28.698,
    lat_open = 21.921,  lat_close = 21.921,
    angle_open = 0.20,  angle_close = 0.20,
    height_open = 90.0, height_close = 35.442,
}
local cfg_order = { "enabled", "debug", "first_half_dir", "near_start", "near_end",
    "def_start", "def_end", "def_strength", "side_start", "side_end", "side_dist", "side_height", "side_top", "side_bottom", "smooth",
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
    { "suavizacao (menor = mais lento)", "smooth",       0.01, 0.01, 1  },
    { "ligado (1) / desligado (0)",      "enabled",      1,    0,   1   },
}
local sel = 1
local frame_no = 0
local overlay_seen = -100

-- ===== leitura de memoria =====
local base
local function valid(p) return p and p > 0x10000 and p < 0x7fffffffffff end
local function u64(a) return memory.unpack("i64", memory.read(a, 8)) end
local function rf(a) return memory.unpack("f", memory.read(a, 4)) end
local function wf(a, v) memory.write(a, memory.pack("f", v)) end
local function finite(v) return v == v and v > -1e6 and v < 1e6 end

-- ===== estado =====
local mode = 0                 -- 0 dinamico, 1 forcar FECHADA, 2 forcar ABERTA, 3 desligado
local mode_names = { [0] = "dinamico", "forcar FECHADA", "forcar ABERTA", "desligado" }
local t_smooth = 0             -- 0 = aberta, 1 = fechada
local side_smooth = 0          -- abertura extra perto das laterais (0..1)
local calib = nil              -- { gk=indice, s0=sinal do goleiro, dir0=direcao, cur=sinal atual }
local pending_auto = false
local last_info = "aguardando partida"
local dbg = { d = 0, t = 0, dir = 0, bx = 0, bz = 0 }
local was_writing = false

local ball_node = nil          -- indice do no que tem a bola (varia entre partida e treino)
-- so le objetos da mesma area de memoria dos jogadores (evita ler enderecos nao mapeados)
local function in_pool(g, node)
    local p0 = u64(g + PL_NODE * 0x28 + 0x20)
    return valid(p0) and node > p0 - 0x800000 and node < p0 + 0x800000
end

local function read_node_ball(g, n)
    local node = u64(g + n * 0x28 + 0x20)
    if not valid(node) or not in_pool(g, node) then return nil end
    local a = node + BALL_POS
    local x, y, z = rf(a), rf(a + 4), rf(a + 8)
    if not (finite(x) and finite(y) and finite(z)) then return nil end
    if x == 0 and y == 0 and z == 0 then return nil end
    if math.abs(x) > 75 or math.abs(z) > 50 or y < -2 or y > 40 then return nil end
    return x, y, z
end

-- a bola e replicada em varios nos vizinhos: so aceita se o no seguinte tiver os MESMOS valores
local function read_ball_checked(g, n)
    local x, y, z = read_node_ball(g, n)
    if not x then return nil end
    local x2, y2, z2 = read_node_ball(g, n + 1)
    if x2 == x and y2 == y and z2 == z then return x, y, z end
    return nil
end

local miss_frames = 0
local function dump_nodes(g)   -- diagnostico (1x): o que ha nos nos de G, para mapear o Master League
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
local function get_ball(g)
    if ball_node then
        local x, y, z = read_ball_checked(g, ball_node)
        if x then return x, y, z end
        ball_node = nil
    end
    -- 1) faixa onde ja foi validado (partida normal e treino); 2) depois, faixa mais larga para baixo
    for n = 0xe3, BALL_NODE_MAX do
        local x, y, z = read_ball_checked(g, n)
        if x then
            ball_node = n
            log(string.format("camera_dinamica: bola encontrada no no 0x%x", n))
            return x, y, z
        end
    end
    -- faixa larga (so para modos desconhecidos, ex. Master League): um candidato so vale
    -- depois de se MOVER varias vezes; dado parado nunca e bola
    if cand then
        local x, y, z = read_ball_checked(g, cand.n)
        if not x then
            cand = nil
        else
            if math.abs(x - cand.x) > 0.05 or math.abs(z - cand.z) > 0.05 then cand.moves = cand.moves + 1 end
            cand.x, cand.z = x, z
            if cand.moves >= 8 then
                ball_node = cand.n
                log(string.format("camera_dinamica: bola encontrada no no 0x%x (faixa ampla, confirmada por movimento)", cand.n))
                cand = nil
                return x, y, z
            end
        end
        return nil
    end
    for n = 0xe2, BALL_NODE_MIN, -1 do
        local x, y, z = read_ball_checked(g, n)
        if x then cand = { n = n, x = x, z = z, moves = 0 }; break end
    end
    return nil
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

local function apply(t, extra)  -- t: 0 = aberta, 1 = fechada; extra[nome] soma ao valor
    for _, p in ipairs(PARAMS) do
        local a, b = cfg[p[3]], cfg[p[4]]
        if math.abs(a - b) > 1e-6 then wf(p[2], a + (b - a) * t + ((extra and extra[p[1]]) or 0)) end
    end
    was_writing = true
end

local function restore_close()
    -- volta ao ajuste "fechado" (= sua Dynamic Wide normal)
    for _, p in ipairs(PARAMS) do
        local a, b = cfg[p[3]], cfg[p[4]]
        if math.abs(a - b) > 1e-6 then wf(p[2], b) end
    end
    was_writing = false
end

function m.set_teams(ctx, home, away)
    calib = nil
    pending_auto = true
    t_smooth = 0
    last_info = "partida carregando"
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
    elseif vkey == 0x76 or vkey == 0x77 then   -- F7 direita / F8 esquerda
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
    local g = u64(base + G_OFF)
    if not valid(g) then
        last_info = "sem partida"
        return
    end
    local bx, by, bz = get_ball(g)
    if not bx then
        last_info = "bola nao encontrada"
        miss_frames = miss_frames + 1
        if miss_frames == 240 then dump_nodes(g) end
        return
    end
    miss_frames = 0
    if pending_auto and not calib then
        if calibrate(g, cfg.first_half_dir, "auto") then pending_auto = false end
    end

    local dir = attack_dir(g)
    dbg.bx, dbg.bz = bx, bz
    if dir then
        dbg.dir = dir
        dbg.d = HALF_LEN - dir * bx          -- distancia (em x) ate a linha de fundo adversaria
    end
    local target
    if mode == 1 then target = 1
    elseif mode == 2 then target = 0
    else
        local span = cfg.near_start - cfg.near_end
        if span < 1 then span = 1 end
        local dspan = cfg.def_start - cfg.def_end
        if dspan < 1 then dspan = 1 end
        if dir then
            -- assimetrico: ataque fecha por completo; a propria area fecha so ate def_strength
            local d_own = HALF_LEN + dir * bx
            local t_att = smoothstep((cfg.near_start - dbg.d) / span)
            local t_def = cfg.def_strength * smoothstep((cfg.def_start - d_own) / dspan)
            target = (t_att > t_def) and t_att or t_def
        else
            -- sem saber o lado: simetrico (fecha perto de qualquer um dos dois gols)
            local d = HALF_LEN - math.abs(bx)
            target = smoothstep((cfg.near_start - d) / span)
            last_info = "ok (simetrico: sem calibracao do lado)"
        end
    end
    -- previa: enquanto edita uma linha ABERTA/FECHADA no overlay, mostra aquela vista
    local sm = cfg.smooth
    if overlay_active() and EDIT[sel][6] then
        target = (EDIT[sel][6] == "c") and 1 or 0
        if sm < 0.15 then sm = 0.15 end
        last_info = "PREVIA: " .. ((EDIT[sel][6] == "c") and "vista FECHADA" or "vista ABERTA")
    end
    t_smooth = t_smooth + (target - t_smooth) * sm
    if cfg.debug == 1 and frame_no % 20 == 0 then
        log(string.format("cd: bola x=%.1f y=%.1f z=%.1f | dir=%s d_adv=%.1f | alvo=%.2f t=%.2f | modo=%d",
            bx, by, bz, tostring(dir), dbg.d, target, t_smooth, mode))
    end
    dbg.t = t_smooth
    -- abre mais quando a bola esta perto de uma lateral (para o outro lado do campo nao sumir)
    local side_t = 0
    if bz then
        local span2 = cfg.side_end - cfg.side_start
        if span2 < 1 then span2 = 1 end
        local gain = (bz < 0) and cfg.side_top or cfg.side_bottom
        side_t = gain * smoothstep((math.abs(bz) - cfg.side_start) / span2)
    end
    side_smooth = side_smooth + (side_t - side_smooth) * sm
    local k = side_smooth * (1 - t_smooth)
    apply(t_smooth, { dist = cfg.side_dist * k, altura = cfg.side_height * k })
    if dir and not (overlay_active() and EDIT[sel][6]) then last_info = "ok" end
end

function m.overlay_on(ctx)
    overlay_seen = frame_no
    local lines = {}
    for i, it in ipairs(EDIT) do
        lines[#lines + 1] = string.format("%s %-33s %8.3f", (i == sel) and "--->" or "    ", it[1], cfg[it[2]])
    end
    return string.format(
        "camera_dinamica %s | modo: %s | %s\nbola x=%.1f z=%.1f | ataque dir=%d | dist. gol=%.1f | fechamento=%.2f\n[F6] modo  [F7] ataco p/ DIREITA  [F8] ataco p/ ESQUERDA   |   PgUp/PgDn escolhe, Delete diminui, Insert aumenta (salva sozinho)\n%s",
        m.version, mode_names[mode], last_info, dbg.bx, dbg.bz or 0, dbg.dir, dbg.d, dbg.t, table.concat(lines, "\n"))
end

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
