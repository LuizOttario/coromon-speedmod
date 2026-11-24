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
timer = { performWithDelay=function() end, timeScale=1 }; transition = { number = function(a, b, t, e, step) STEP = step; return "handle" end }; spriteHelper = {}
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
-- aplicar escala liga as proteções (precisa de velocidade != 1? não: só gameReady)
display:setTimeScale(1)
for _ = 1, 3 do for _, f in ipairs(listeners.enterFrame or {}) do f({}) end end
local h = transition.number(0, 1, 100, nil, function(_, v) local t = nil; return t.width * v end)
assert(h == "handle", "retorno do transition")
STEP(nil, 0.5)  -- não pode estourar
transition.number(0, 1, 100, nil, function(_, v) return v * 2 end)
assert(STEP(nil, 3) == 6, "valor preservado")
print("ok")
