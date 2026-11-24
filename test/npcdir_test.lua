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
-- self-check: seta ao vivo até os NPCs da etapa (HELP_PREPARATIONS em Alavi)
worldHelper.getMapFile = function() return "iceTown" end
local npcs = { olivia = { tileX = 30, tileY = 20 }, thorbjorn = { tileX = 20, tileY = 10 } }
worldHelper.getSpawnableByName = function(_, n) return npcs[n] end
spawnableHelper = { getPlayerSpawnable = function() return { tileX = 22, tileY = 17 } end }
playerQuests.getActiveQuests = function() return { "MAIN" } end
playerQuests.getCurrentChapter = function() return "iceTown.HELP_PREPARATIONS_3_left" end
playerQuests.getQuestDescription = function() return "Ajude 3 pessoas" end
playerQuests.getQuestName = function() return "Historia" end
assert(loadfile(arg[1]))()
local out = HUD_DEBUG() or {}
local txt = ""
for _, l in ipairs(out) do txt = txt .. l[1] .. "\n" end
print(txt)
assert(txt:find("OLIVIA: 3 SUL, 8 LESTE"), "olivia") ; assert(txt:find("THORBJORN: 7 NORTE"), "thorbjorn")
print("ok")
