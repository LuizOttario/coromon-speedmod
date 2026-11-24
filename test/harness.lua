-- Simulação do mod fora do jogo: lua5.1 test/harness.lua test/modfull.lua
system = { DocumentsDirectory = 1, pathForFile = function(n) return "test/" .. n end }
local now = 0
system.getTimer = function() return now end
local listeners = {}
Runtime = { addEventListener = function(self, n, f) listeners[n] = listeners[n] or {}; table.insert(listeners[n], f) end }
RECTS = {}
local function newObj()
  local o = {}
  o.setFillColor=function() end; o.toFront=function() end
  o.addEventListener=function(self,n,f) self["_"..n]=f end
  o.removeSelf=function(self) self.removed=true end
  o.insert=function(self, c) c.parent=self end
  return o
end
display = { contentWidth=453, contentHeight=256,
  newGroup=function() return newObj() end,
  newRect=function(p,x,y,w,h) local o=newObj(); o.parent=p; o.x,o.y,o.w,o.h=x,y,w,h; RECTS[#RECTS+1]=o; return o end,
  getCurrentStage=function() return { setFocus=function() end } end }
audio = { loadSound=function() return {} end, play=function() end }
package.preload["displaylib"] = function() display.timeScale = 1; function display:setTimeScale(s) display.timeScale = s end end
timer = { performWithDelay=function() end, timeScale=1 }; transition = {}; spriteHelper = {}
playerQuests = { isCompleted = function() return false end }
playerSettings = { isLuxLuredMap = function() return false end }
playerMonsters = { getOwnedMonstersIncludingMonsterGraveyard = function() return {} end, getOwnedMonstersExcludingInsaneSpinnerSquad = function() return {} end }
local got = {}
Achievement = setmetatable({}, { __index = function(t, k) return { isAchieved = function() return got[k] or false end } end })
monsterFamilyDataList = setmetatable({}, { __index = function() return { isCatchable = function() return true end } end })
worldHelper = { getMapFile = function() return "amishTown" end }
assert(loadfile(arg[1]))()
require("displaylib")
local function key(k) for _,f in ipairs(listeners.key) do f({phase="down", keyName=k}) end end
local function frames(ms) for i=1,ms/16 do now = now + 16; for _,f in ipairs(listeners.enterFrame) do f({}) end end end

key("home")                               -- aba velocidade
local hit
for _, r in ipairs(RECTS) do if not r.removed and r._touch and r.h == 12 then hit = r end end
assert(hit, "barra nao encontrada")
local trackW = hit.w - 6
local left = hit.x - trackW / 2
hit._touch({ phase = "began", x = left })
for _, f in ipairs({0, 0.25, 0.5, 0.75, 1}) do
  hit._touch({ phase = "moved", x = left + f * trackW })
  print(string.format("barra %.2f -> escala %s", f, tostring(display.timeScale)))
end
hit._touch({ phase = "ended", x = left + 0.3 * trackW })
print("solto em 0.30 -> escala", display.timeScale)
key("3"); print("tecla 3 -> escala", display.timeScale)
key("tab"); key("tab"); frames(3000)        -- missões, rota
got.PROGRESS_1_PICK_STARTER = true; frames(3000)
key("f8"); frames(6000); key("f7"); frames(2000)
-- timer de input vindo do "inputHelper"
local calls = {}
timer.performWithDelay = function(d) calls[#calls+1] = "normal " .. d; return {} end
timer.performWithDelayIgnoringTimescale = function(d) calls[#calls+1] = "real " .. d; return {} end
frames(100)  -- o mod reembrulha o timer novo
local fake = loadstring("\n\nreturn function() local t = timer.performWithDelay(600, function() end); return t end", "@D:/x/inputHelper.lua")()
print("escala antes", display.timeScale); fake()
local fake2 = loadstring("\n\nreturn function() local t = timer.performWithDelay(250, function() end); return t end", "@D:\\a\\coromon\\classes\\interface\\pauseMenu.lua")()
fake2()
local fake3 = loadstring("\n\nreturn function() local t = timer.performWithDelay(500, function() end); return t end", "@D:\\a\\coromon\\classes\\interface\\battle\\x.lua")()
fake3()
timer.performWithDelay(300, function() end)  -- timer comum do jogo
print("chamadas:", table.concat(calls, ", "))
key("home"); key("home"); key("tab")
if not listeners.mouse then print("sem listener de mouse") end
local before = 0
for _, f in ipairs(listeners.mouse) do f({ scrollY = 120, x = 30, y = 120 }) end
for _, f in ipairs(listeners.mouse) do f({ scrollY = 120, x = 90, y = 360 }) end  -- em pixels da janela
print("roda ok")
-- botao de acao: 1x por meio segundo
key("6")  -- (menu fechado: so registra)
print("antes", display.timeScale)
for _, f in ipairs(listeners.key) do f({ phase="down", keyName="escape" }) end
print("botao de acao ->", display.timeScale)
frames(600)
print("depois de 0.6s ->", display.timeScale)
print("ok")
