-- Teste do assistente: lua5.1 test/assist_test.lua test/modfull.lua
system = { DocumentsDirectory = 1, pathForFile = function(n) return "test/" .. n end }
local now = 0
system.getTimer = function() return now end
listeners = {}; LISTENERS = listeners
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
TEXTS = {}
display = { contentWidth=453, contentHeight=256,
  newGroup=function() return newObj() end,
  newRect=function(p,x,y,w,h) local o=newObj(); o.parent=p; o.x,o.y,o.w,o.h=x,y,w,h; RECTS[#RECTS+1]=o; return o end,
  getCurrentStage=function() return { setFocus=function() end } end }
audio = { loadSound=function() return {} end, play=function() end }
package.preload["displaylib"] = function() display.timeScale = 1; function display:setTimeScale(s) display.timeScale = s end end
timer = { performWithDelay=function() end, timeScale=1 }; transition = {}; spriteHelper = {}
playerQuests = { isCompleted = function(self, q, ch) return ch == "luxSolisTown.PICK_STARTER" end }
playerSettings = { isLuxLuredMap = function() return true end }
local function mon(uid, lvl, skills, hp, pot, undist, id, enemy)
  return { getUID=function() return uid end, getLevel=function() return lvl end,
    getSelectedSkillUIDs=function() return skills end, getHealth=function() return hp end, getMaxHealth=function() return 100 end,
    getPotential=function() return pot end, getAmountOfPotentialStatsUndistributed=function() return undist end,
    getIdentifier=function() return id end, isAlive=function() return true end, getIsEnemy=function() return enemy end,
    getMonsterData=function() return { getMonsterFamilyUID=function() return uid:gsub("_%d+$","") end } end }
end
local shark = mon("WATER_SHARK_1", 9, {"CHOMP","MIGHTY_ROAR","BUBBLE_BURST"}, 30, 14, 3, 1)
local moffel = mon("SAND_MOLE_1", 8, {"SAND_TOSS"}, 90, 10, 0, 2)
SQUAD = { shark, moffel }
OWNED = { shark, moffel }
INSANE_TEST = { mon("NORMAL_CROW_1", 3, {}, 15, 9, 0, 7), mon("SAND_MOLE_1", 4, {}, 15, 11, 0, 8) }
INSANE_TEST[1].getDisplayName = function() return "Rococo" end
INSANE_TEST[2].getDisplayName = function() return "Tornado" end
playerMonsters = { getSquad=function() return SQUAD end, getOwnedMonstersIncludingMonsterGraveyard=function() return OWNED end,
  getInsaneSpinnerSquad=function() return INSANE_TEST end, hasFullSquad=function() return #SQUAD >= 6 end,
  releaseFromInsaneSpinnerSquad=function(self, m) for i, x in ipairs(INSANE_TEST) do if x == m then table.remove(INSANE_TEST, i) break end end end,
  addToSquad=function(self, m) SQUAD[#SQUAD+1] = m end, addToMonsterStorage=function() end }
local got = { PROGRESS_1_PICK_STARTER = true }
Achievement = setmetatable({}, { __index = function(t, k) return { isAchieved = function() return got[k] or false end } end })
monsterFamilyDataList = setmetatable({}, { __index = function() return { isCatchable = function() return true end } end })
MAP = "amishTown"
worldHelper = { getMapFile = function() return MAP end }
local LANG = { ["x.question3.1"] = "Qual habilidade causa mais dano?", ["x.question3.answers.1.correct"] = "Brasa (40 de poder)", ["x.question3.answers.2.false1"] = "Pancada" }
localise = function(k) return LANG[k] or k end
playerInventory = { getAmount = function(self, item) local u = item:getUID(); return u == "SPINNER_REGULAR_1" and 5 or 0 end }
playerQuests = { isCompleted = function(self, q, ch) return ch == "luxSolisTown.PICK_STARTER" or ch == "luxSolisTown.REPORT_AT_RECEPTION" end,
  getActiveQuests = function() return { { getUID = function() return "MAIN" end }, { getUID = function() return "BEEZEL_BREAKOUT" end } } end,
  getCurrentChapter = function(self, q) return q == "MAIN" and "amishTown.GOTO_ELECTRICTOWN" or "amishTown.DEFEAT_ALL_BEEZELS_4_LEFT" end,
  getQuestDescription = function(self, q, ch) return q == "MAIN" and "O primeiro Tita estara na Ilha Donar." or "Estou procurando por mais 4 Beezels perto de Hayville." end,
  getQuestName = function(self, q) return q == "MAIN" and "Forca-tarefa Tita" or "Fuga de Beezels" end }
assert(loadfile(arg[1]))()
require("displaylib")
local function frames(ms) for i=1,ms/16 do now = now + 16; for _,f in ipairs(listeners.enterFrame) do f({}) end end end

print("== HUD esquerda")
HUD_TEST_LINES = true
for _, l in ipairs(ASSIST_TEST.overworldLines()) do print("  " .. l[1]) end
print("== batalha contra Voltgar-like (eletrico) com Tutubarao em campo")
local foe = mon("ELECTRIC_BEETLE_1", 14, {}, 100, 5, 0, 99, true); foe.getTraitUID = function() return "SUPERSENSORY" end
local spMe, spFoe = { monster = shark, team = "player" }, { monster = foe, team = "enemy" }
Battle = { get=function() return { getMonsterSpritesInBattle=function(self, side) if side == "player" then return { spMe } elseif side == "enemy" then return { spFoe } end return { spMe, spFoe } end } end }
for _, l in ipairs(ASSIST_TEST.battleLines() or {}) do print("  " .. l[1]) end
Battle = nil
print("== quiz")
ASSIST_TEST.quizLines()
localise("x.question3.1")
for _, l in ipairs(ASSIST_TEST.quizLines() or {}) do print("  " .. l[1]) end
print("== captura nova")
frames(2500)
OWNED = { shark, moffel, mon("NORMAL_CYBORG_1", 4, {}, 50, 18, 0, 3) }
frames(2500)
print("toast:", LAST_TOAST and table.concat(LAST_TOAST, " / ") or "nenhum")
local L, R = HUD_DEBUG()
print("== caixa esquerda"); for _, l in ipairs(L or {}) do print("  " .. l[1]) end

print("== F9")
local function key(k) for _,f in ipairs(LISTENERS.key) do f({phase="down", keyName=k}) end end
frames(4000)
print("time agora:", #SQUAD, "spinner insano:", #INSANE_TEST)

print("== PAINEL")
skillDataList = { CHOMP = {}, BUBBLE_BURST = {}, STREAMLINE = {} }
local before = skillDataList.BUBBLE_BURST
local sp = { monster = { getSelectedSkillUIDs = function() return { "CHOMP", "MIGHTY_ROAR", "BUBBLE_BURST", "STREAMLINE" } end },
  getMostRecentBeforeSkillData = function() return before end }
local selected
local NAMES = { "b1", "b2", "b3", "b4", "rest", ["acoes-lateral"] = 6 }
local nav = { setSelectedIndex = function(self, i) selected = NAMES[i] end,
  getSelectedIndex = function() for i, n in ipairs(NAMES) do if n == selected then return i end end return 6 end }
local shown = false
package.loaded["classes.interface.battle.oneStepActionsPanelBuilder"] = { new = function(self, c, o)
  return { getGamepadNavigation = function() return nav end, show = function(self) shown = true end } end }
frames(1500)
local r = package.loaded["classes.interface.battle.oneStepActionsPanelBuilder"]:new({}, { monsterSprite = sp })
selected = "b1"; frames(100)
print("criado (jogo voltou pro 1): foco =", selected)
before = skillDataList.STREAMLINE
r:show(); selected = "acoes-lateral"; frames(100)
print("turno seguinte com direcao vazada: foco =", selected, "show original chamado =", shown)
frames(1000); selected = "b2"; frames(100)
print("depois de 0,6s o jogador manda: foco =", selected)
print("== tela de habilidades (menu do jogo aberto)")
local shark13 = mon("WATER_SHARK_1", 13, {"CHOMP","MIGHTY_ROAR","BUBBLE_BURST","STREAMLINE"}, 100, 14, 0, 1)
SQUAD = { shark13 }
for _, l in ipairs(ASSIST_TEST.skillLines()) do print("  " .. l[1]) end
pauseMenu = { isCreated = function() return true end }
local before = #RECTS
frames(3000)
print("  caixa desenhada no menu:", #RECTS > before)
pauseMenu = { isCreated = function() return false end }
frames(1000)
