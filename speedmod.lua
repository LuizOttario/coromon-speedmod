-- Coromon Speed Mod
-- Home abre/fecha o menu de velocidade (1x 2x 5x 10x 20x 100x).
-- Dentro do menu: clique com o mouse ou aperte 1-6.
--
-- Como funciona: o jogo já tem um sistema interno de escala de tempo
-- (display:setTimeScale), que controla timers, transições, sprites, texto e
-- movimento. O mod embrulha essa função e multiplica o valor que o próprio
-- jogo pede pelo multiplicador escolhido.

local SPEEDS = { 1, 2, 5, 10, 20, 100 }  -- 500x trava; 200x anda igual ao 100x (limite por frame)
local TOGGLE_KEYS = { home = true }

-- Log de diagnóstico: Documents/speedmod.log na pasta de dados do jogo.
local logLines = 0
local function log(msg)
	print("SpeedMod: " .. tostring(msg))
	if logLines > 300 then return end
	logLines = logLines + 1
	pcall(function()
		local path = system.pathForFile("speedmod.log", system.DocumentsDirectory)
		local f = io.open(path, logLines == 1 and "w" or "a")
		if f then f:write(os.date("%H:%M:%S "), tostring(msg), "\n"); f:close() end
	end)
end

local mult = 1          -- multiplicador escolhido pelo jogador

-- Velocidade salva entre sessões (Documents/speedmod_config.txt)
local CONFIG_FILE = "speedmod_config.txt"
local function loadSavedSpeed()
	local v
	pcall(function()
		local f = io.open(system.pathForFile(CONFIG_FILE, system.DocumentsDirectory), "r")
		if f then v = tonumber(f:read("*l")); f:close() end
	end)
	if v and v >= 1 and v <= 100 then return v end
	return 1
end
local function saveSpeed(v)
	pcall(function()
		local f = io.open(system.pathForFile(CONFIG_FILE, system.DocumentsDirectory), "w")
		if f then f:write(tostring(v), "\n"); f:close() end
	end)
end
mult = loadSavedSpeed()
if mult ~= 1 then log("velocidade salva: " .. tostring(mult) .. "x") end

-- Enquanto o menu de pausa do jogo está aberto, roda em 1x (menus acelerados
-- "clicam sozinhos"). A velocidade escolhida volta ao fechar o menu.
local suspended = false
local function effMult() return suspended and 1 or mult end
local base = 1          -- escala que o jogo pediu por último
local origSetTimeScale  -- display.setTimeScale original
local wrapped = false

-- Timers de input (ex.: "segurar botão" de 600ms nas habilidades) precisam
-- correr em tempo real; senão, acelerado, todo clique vira "segurar" e a
-- habilidade não é usada. Compensamos só o multiplicador do mod nos timers
-- criados pelo inputHelper. A função de repetição de tecla (definida na linha
-- 716) já compensa a escala sozinha, então fica de fora.
local timerWrapped = nil
-- Timers de menus/navegação rodam em tempo real (bloqueios anti-clique-duplo,
-- cursores, popups). Acelerá-los faz o menu "clicar sozinho" acima de ~3.6x.
local REALTIME_PATHS = { "inputHelper", "\\interface\\", "/interface/", "\\convenience\\", "/convenience/",
	"\\navigation\\", "/navigation/", "handCursor", "confirmPopup", "pauseMenu", "worldInterface",
	"cutsceneUtility", "UIButton" }
local BATTLE_UI = { "\\interface\\battle\\", "/interface/battle/" }
-- popups de conquista animam com transição (acelerada) e somem por timer: com o timer em
-- tempo real e a transição a 100x, o jogo caiu em AchievementAchievedPopup.lua:39 (2026-11-19)
local SCALED_POPUPS = { "AchievedPopup", "CreditsOverlay" }  -- AchievedPopup cobre conquista, marco e marco de skin (caiu em MonsterSpriteSkinMilestoneAchievedPopup:48 em 2026-11-21)
local function isRealtimeSource(src)
	for _, p in ipairs(BATTLE_UI) do
		if src:find(p, 1, true) then return false end
	end
	for _, p in ipairs(SCALED_POPUPS) do
		if src:find(p, 1, true) then return false end
	end
	for _, p in ipairs(REALTIME_PATHS) do
		if src:find(p, 1, true) then return true end
	end
	return false
end
local REPEAT_FN_LINE = 716
local function wrapTimer()
	if type(timer) ~= "table" or type(timer.performWithDelay) ~= "function" then return end
	if timer.performWithDelay == timerWrapped then return end
	if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then
		if timerWrapped == nil then log("debug.getinfo indisponível; timers de input não compensados") end
		timerWrapped = false
		return
	end
	local orig = timer.performWithDelay
	local timerLib = timer
	local inputLogs = 0
	timerWrapped = function(delay, ...)
		if effMult() ~= 1 and type(delay) == "number" then
			local info = debug.getinfo(2, "S")
			if info and info.source and isRealtimeSource(info.source)
				and not (info.source:find("inputHelper", 1, true) and info.linedefined == REPEAT_FN_LINE) then
				-- tempo real: o jogo tem um timer que ignora a escala de tempo
				local realFn = timerLib.performWithDelayIgnoringTimescale
				if inputLogs < 15 then
					inputLogs = inputLogs + 1
					log("timer em tempo real: " .. tostring(delay) .. "ms linha " .. tostring(info.linedefined)
						.. " vel " .. tostring(mult) .. " escala " .. tostring(timerLib.timeScale)
						.. (realFn and " (tempo real)" or " (compensado)"))
				end
				if type(realFn) == "function" then
					return realFn(delay, ...)
				end
				delay = delay * effMult()
			end
		end
		return orig(delay, ...)
	end
	timer.performWithDelay = timerWrapped
	log("timer.performWithDelay embrulhado (input em tempo real)")
end

-- A função original mexe em timer/transition/spriteHelper; esses globais só
-- existem depois que o jogo termina de carregar as bibliotecas.
local function gameReady()
	return type(timer) == "table" and type(transition) == "table" and type(spriteHelper) == "table"
end

-- transition.number(de, até, tempo, easing, aCadaPasso): os popups de conquista/marco
-- mudam a largura do nome a cada passo; se o popup some antes (acontece acelerado),
-- o passo lê .width de um texto apagado e o jogo fecha (MonsterSpriteSkinMilestoneAchievedPopup:48,
-- caiu 2x em 2026-11-21 colhendo cogumelos). Erro num passo da animação vira só log.
local numberWrapped
local function wrapTransitionNumber()
	if type(transition) ~= "table" or type(transition.number) ~= "function" or transition.number == numberWrapped then return end
	local orig = transition.number
	numberWrapped = function(a, b, t, easing, step, ...)
		if type(step) == "function" then
			local inner = step
			step = function(...)
				local r = { pcall(inner, ...) }
				if not r[1] then log("passo de animacao ignorado: " .. tostring(r[2])); return end
				return unpack(r, 2, table.maxn(r))
			end
		end
		return orig(a, b, t, easing, step, ...)
	end
	transition.number = numberWrapped
	log("transition.number protegido")
end

local function applyScale()
	if origSetTimeScale and gameReady() then
		pcall(wrapTimer)
		pcall(wrapTransitionNumber)
		local ok, err = pcall(origSetTimeScale, display, base * effMult())
		if not ok then log("erro ao aplicar escala: " .. tostring(err)) end
	end
end

local function tryWrap()
	if wrapped then return true end
	if type(display) == "table" and type(display.setTimeScale) == "function" then
		origSetTimeScale = display.setTimeScale
		display.setTimeScale = function(self, scale)
			base = tonumber(scale) or 1
			return origSetTimeScale(self, base * effMult())
		end
		wrapped = true
		log("setTimeScale encontrado e embrulhado")
		return true
	end
	return false
end

-- A biblioteca que define display.setTimeScale é carregada pelo main original
-- via require. Observamos os requires até ela aparecer e depois desfazemos o hook.
-- O mesmo hook liga debugSettings.UI.skipSplashScreen (opção de depuração do jogo,
-- desligada na versão normal) para pular as logos de abertura (indie.io e TRAGsoft).
local realRequire = require
local splashSkipped = false
require = function(name, ...)
	local a = realRequire(name, ...)
	if name == "classes.configs.debugSettings" and not splashSkipped then
		splashSkipped = true
		pcall(function()
			local ds = type(a) == "table" and a.UI and a or debugSettings
			ds.UI.skipSplashScreen = true
			log("abertura pulada (skipSplashScreen)")
		end)
	end
	if tryWrap() and splashSkipped and require ~= realRequire then
		require = realRequire
	end
	return a
end


-- Duas fontes de "1x temporário": menu de pausa aberto, e logo depois de
-- apertar um botão de ação (o menu que abre faz a animação em velocidade normal
-- e o mesmo aperto não "vaza" para dentro dele).
local pausedFlag, holdUntil = false, 0
local function refreshSuspended()
	-- SPEEDMOD_PANEL_OPEN (assist.lua): painel de golpes aberto = 1X, senão o jogo
	-- confunde um toque com "segurar" (detalhes) e o golpe não sai
	local v = pausedFlag or (system.getTimer() < holdUntil) or (SPEEDMOD_PANEL_OPEN == true and SPEEDMOD_IN_BATTLE == true)
	if v ~= suspended then
		suspended = v
		applyScale()
	end
end
local function setSuspended(v)
	pausedFlag = v and true or false
	refreshSuspended()
end
local MOVE_KEYS = { up = true, down = true, left = true, right = true, w = true, a = true, s = true, d = true,
	home = true, f7 = true, f8 = true, f9 = true }
-- Andando (direção apertada ou analógico inclinado) não há trava: assim o botão
-- de correr (B / Shift) acelera na hora. Ao começar a andar, a trava é cancelada.
local DIR_KEYS = { up = true, down = true, left = true, right = true, w = true, a = true, s = true, d = true }
local dirDown, axisDir = {}, {}
-- Cada direção vale por no máximo 3 s desde que foi apertada: se um "soltar" se
-- perder, o mod não fica achando para sempre que você está andando.
local DIR_TTL = 3000
local function inBattle() return SPEEDMOD_IN_BATTLE == true end
local function moving()
	if inBattle() then return false end   -- em batalha a trava sempre vale
	local now = system.getTimer()
	for k, t in pairs(dirDown) do
		if now - t < DIR_TTL then return true end
		dirDown[k] = nil
	end
	for k, t in pairs(axisDir) do
		if now - t < DIR_TTL then return true end
		axisDir[k] = nil
	end
	return false
end
local function cancelHold()
	if holdUntil > 0 and not inBattle() then holdUntil = 0; refreshSuspended() end
end
Runtime:addEventListener("key", function(e)
	local k = tostring(e.keyName)
	if DIR_KEYS[k] then
		if e.phase == "down" then dirDown[k] = system.getTimer(); cancelHold() else dirDown[k] = nil end
	-- em batalha: 1X só ENQUANTO o botão está apertado (+150 ms). O jogo decide
	-- "tocou" x "segurou" (segurar = ver detalhes, não usa o golpe) pelo tempo
	-- do jogo; acelerado, um toque normal virava "segurou" e o ataque não saía.
	elseif inBattle() and mult ~= 1 and not MOVE_KEYS[k] then
		if e.phase == "down" then
			holdUntil = system.getTimer() + 3000   -- segurando (limite de segurança)
		else
			holdUntil = system.getTimer() + 150
		end
		refreshSuspended()
	elseif e.phase == "down" and mult ~= 1 and not MOVE_KEYS[k] and not moving() then
		holdUntil = system.getTimer() + 500
		refreshSuspended()
	end
	return false
end)
-- só o analógico de movimento conta (gatilhos ficam em -1 parados e travariam "andando")
local STICK_AXES = { leftX = true, leftY = true, x = true, y = true }
Runtime:addEventListener("axis", function(e)
	local at = tostring(e.axis and e.axis.type)
	if not STICK_AXES[at] then return false end
	local id = tostring(e.device and e.device.descriptor) .. ":" .. at
	local on = math.abs(tonumber(e.normalizedValue) or 0) > 0.5
	if on and not axisDir[id] then cancelHold() end
	if on then axisDir[id] = axisDir[id] or system.getTimer() else axisDir[id] = nil end
	return false
end)
Runtime:addEventListener("enterFrame", function()
	refreshSuspended()
end)

-- Erro que derrubaria o jogo: grava mensagem e pilha no log (sem o limite de 300
-- linhas) e deixa o jogo tratar como sempre (mostra a tela de erro).
Runtime:addEventListener("unhandledError", function(e)
	pcall(function()
		local f = io.open(system.pathForFile("speedmod.log", system.DocumentsDirectory), "a")
		if f then
			f:write(os.date("%H:%M:%S"), " ERRO DO JOGO: ", tostring(e.errorMessage), "\n",
				tostring(e.stackTrace), "\n")
			f:close()
		end
	end)
	return false
end)

