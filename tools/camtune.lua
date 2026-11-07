-- camtune.lua v0.1: sintonizador ao vivo dos parametros da camera (Dynamic Wide custom e fan view).
-- Abra o overlay (Espaco), va ate a pagina "camtune.lua" (1 / ` trocam de modulo).
--   PageUp / PageDown : escolhe o parametro     Delete / Insert : diminui / aumenta
--   Home : restaura TODOS os valores originais   End : escreve os valores atuais no log
local m = {}
m.version = "0.1"
local P = {
  { "DW angulo (camera.lua)",        0x1425985a4, 0.05 },
  { "DW 21.92  (rsp+38)",            0x14260b8f8, 0.5  },
  { "DW 28.70  (base xmm0)",         0x14260b8fc, 0.5  },
  { "DW 35.44  (xmm0 - xmm3)",       0x14260b900, 0.5  },
  { "DW 0.070  (mult xmm6)",         0x14260b8dc, 0.01 },
  { "DW 0.380  (add xmm6)",          0x14260b8e0, 0.02 },
  { "DW 8.268",                      0x14260b8f4, 0.5  },
  { "DW 1.667",                      0x14260b8f0, 0.1  },
  { "fanview zoom",                  0x14260b7d8, 0.5  },
  { "fanview altura",                0x14260b7dc, 0.02 },
  { "fanview angulo",                0x14260b7f4, 0.05 },
}
local sel = 1
local frame_no, overlay_seen = 0, -100
local orig = {}
local function rf(a) return memory.unpack("f", memory.read(a, 4)) end
local function wf(a, v) memory.write(a, memory.pack("f", v)) end

function m.key_down(ctx, vkey)
    if frame_no - overlay_seen > 3 then return end
    local p = P[sel]
    if vkey == 0x21 and sel > 1 then sel = sel - 1          -- PageUp
    elseif vkey == 0x22 and sel < #P then sel = sel + 1     -- PageDown
    elseif vkey == 0x2e then wf(p[2], rf(p[2]) - p[3])      -- Delete
    elseif vkey == 0x2d then wf(p[2], rf(p[2]) + p[3])      -- Insert
    elseif vkey == 0x24 then                                -- Home
        for i, q in ipairs(P) do if orig[i] then wf(q[2], orig[i]) end end
        log("camtune: valores originais restaurados")
    elseif vkey == 0x23 then                                -- End
        for _, q in ipairs(P) do log(string.format("camtune: %-26s %s = %.4f", q[1], memory.hex(q[2]), rf(q[2]))) end
    end
end

function m.display_frame(ctx) frame_no = frame_no + 1 end

function m.overlay_on(ctx)
    overlay_seen = frame_no
    if not orig[1] then for i, q in ipairs(P) do orig[i] = rf(q[2]) end end
    local lines = {}
    for i, q in ipairs(P) do
        lines[#lines + 1] = string.format("%s %-26s %9.3f  (orig %.3f)", (i == sel) and "--->" or "    ", q[1], rf(q[2]), orig[i])
    end
    return "camtune " .. m.version .. "   PgUp/PgDn escolhe   Delete diminui   Insert aumenta   Home restaura   End log\n" .. table.concat(lines, "\n")
end

function m.init(ctx)
    for i, q in ipairs(P) do orig[i] = rf(q[2]) end
    ctx.register("key_down", m.key_down)
    ctx.register("display_frame", m.display_frame)
    ctx.register("overlay_on", m.overlay_on)
end
return m
