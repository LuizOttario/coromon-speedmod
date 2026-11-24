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
playerQuests = { isCompleted = function() return true end }  -- história toda feita (pós-jogo)
playerSettings = { isLuxLuredMap = function() return false end }
playerMonsters = { getOwnedMonstersIncludingMonsterGraveyard = function() return {} end, getOwnedMonstersExcludingInsaneSpinnerSquad = function() return {} end }
local got = setmetatable({ SPEND_LESS_THAN_50_GOLD_IN_SHOP = false }, { __index = function() return true end })
Achievement = setmetatable({}, { __index = function(t, k) return { isAchieved = function() return got[k] or false end } end })
monsterFamilyDataList = setmetatable({}, { __index = function() return { isCatchable = function() return true end } end })
worldHelper = { getMapFile = function() return "amishTown" end }
-- self-check: contador de vasos plantados por cidade
worldHelper.getMapFile = function() return "desertTown" end
FruitGrowingPotList = nil
playerWorldData = { getProperty = function(_, k) return k:find("desertTown_hiddenItem_") and k:find("_1") and true or nil end, resolveConsistentSavePropertiesFromSpawnableOrProperty = function(_, id)
  return { spawnedFruitData = (id:find("31_9") or id:find("58_32")) and {} or nil } end }
playerQuests.getActiveQuests = function() return {} end
playerStats = playerStats or {}; playerStats.getAmountOfHiddenItemsFound = function() return 56 end
assert(loadfile(arg[1]))()
local txt = ""
for _, l in ipairs(HUD_DEBUG() or {}) do txt = txt .. l[1] .. "\n" end
print(txt); assert(txt:find("PLATINA: FALTAM 1"), "platina"); assert(txt:find("PROXIMA:"), "proxima"); print("ok")
