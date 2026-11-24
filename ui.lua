---------------------------------------------------------------------------
-- Interface (abas VELOCIDADE e MISSOES)
-- Este build da engine não tem newText nem newRoundedRect: tudo é desenhado
-- com display.newRect e uma fonte pixelada 3x5 própria.
---------------------------------------------------------------------------
local menu, badge
local notifyToast   -- definido em notify.lua: notifyToast(texto, cabecalho)
local ASSIST = {}   -- preenchido em assist.lua
local currentTab = "speed"      -- "speed" ou "missions"
local missionScroll = nil       -- linha do topo na aba de missões (nil = ir para a próxima pendente)
local pageGroup                 -- conteúdo da aba atual (recriado ao trocar/rolar)

local function num(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "number" and v > 0 then return v end
	end
end

local function screen()
	local d = display
	local w = num(d.actualContentWidth, d.viewableContentWidth, d.contentWidth) or 480
	local h = num(d.actualContentHeight, d.viewableContentHeight, d.contentHeight) or 270
	local cx = num(d.contentCenterX) or w / 2
	local cy = num(d.contentCenterY) or h / 2
	local ox = type(d.screenOriginX) == "number" and d.screenOriginX or (cx - w / 2)
	local oy = type(d.screenOriginY) == "number" and d.screenOriginY or (cy - h / 2)
	return w, h, cx, cy, ox, oy
end

-- Tamanho do "pixel" da fonte/menu em relação à tela (antes era h/120 com mínimo 2).
local UI_SCALE = 1 / 256
local function pixelSize()
	local _, h = screen()
	return math.max(1, math.floor(h * UI_SCALE))
end

---------------------------------------------------------------------------
-- Fonte 3x5
---------------------------------------------------------------------------
local GLYPHS = {
	A = "010101111101101", B = "110101110101110", C = "011100100100011", D = "110101101101110",
	E = "111100110100111", F = "111100110100100", G = "011100101101011", H = "101101111101101",
	I = "111010010010111", J = "001001001101010", K = "101101110101101", L = "100100100100111",
	M = "101111111101101", N = "110101101101101", O = "010101101101010", P = "110101110100100",
	Q = "010101101110011", R = "110101110101101", S = "011100010001110", T = "111010010010010",
	U = "101101101101111", V = "101101101101010", W = "101101111111101", X = "101101010101101",
	Y = "101101010010010", Z = "111001010100111",
	["0"] = "111101101101111", ["1"] = "010110010010111", ["2"] = "111001111100111",
	["3"] = "111001111001111", ["4"] = "101101111001001", ["5"] = "111100111001111",
	["6"] = "111100111101111", ["7"] = "111001001001001", ["8"] = "111101111101111",
	["9"] = "111101111001111",
	["."] = "000000000000010", [","] = "000000000010100", [":"] = "000010000010000",
	[";"] = "000010000010100", ["!"] = "010010010000010", ["?"] = "110001010000010",
	["("] = "001010010010001", [")"] = "100010010010100", ["%"] = "101001010100101",
	["/"] = "001001010100100", ["-"] = "000000111000000", ["+"] = "000010111010000",
	[">"] = "100010001010100", ["<"] = "001010100010001", ["'"] = "010010000000000",
	["&"] = "010101010101011", ["*"] = "000101010101000", ["["] = "110100100100110",
	["]"] = "011001001001011", ["="] = "000111000111000", ["^"] = "010101000000000",
	["_"] = "000000000000111", ['"'] = "101101000000000", [" "] = "000000000000000",
}

local ACCENTS = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["é"] = "e", ["ê"] = "e",
	["è"] = "e", ["í"] = "i", ["ï"] = "i", ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o",
	["ø"] = "o", ["ú"] = "u", ["ü"] = "u", ["ç"] = "c", ["ñ"] = "n",
	["Á"] = "A", ["À"] = "A", ["Â"] = "A", ["Ã"] = "A", ["É"] = "E", ["Ê"] = "E", ["Í"] = "I",
	["Ó"] = "O", ["Ô"] = "O", ["Õ"] = "O", ["Ú"] = "U", ["Ç"] = "C", ["Ø"] = "O",
}

local function normalize(s)
	s = tostring(s or "")
	s = s:gsub("[\195][\128-\191]", function(c) return ACCENTS[c] or "?" end)
	s = s:gsub("<[^>]*>", "")               -- tags de cor do jogo
	s = s:gsub("[\128-\255]", "")           -- qualquer outro byte fora do ASCII
	return s:upper()
end

local function rect(parent, x, y, w, h, r, g, b, a)
	local o = display.newRect(parent, x, y, w, h)
	o:setFillColor(r or 1, g or 1, b or 1, a or 1)
	return o
end

-- Desenha texto com o canto superior esquerdo em (x, y). Junta pixels vizinhos
-- de uma mesma linha num retângulo só para economizar objetos.
local function drawText(parent, str, x, y, px, r, g, b)
	str = normalize(str)
	for i = 1, #str do
		local glyph = GLYPHS[str:sub(i, i)] or GLYPHS["?"]
		local gx = x + (i - 1) * 4 * px
		for row = 0, 4 do
			local col = 0
			while col < 3 do
				if glyph:sub(row * 3 + col + 1, row * 3 + col + 1) == "1" then
					local run = 1
					while col + run < 3 and glyph:sub(row * 3 + col + run + 1, row * 3 + col + run + 1) == "1" do
						run = run + 1
					end
					rect(parent, gx + (col + run / 2) * px, y + (row + 0.5) * px, run * px, px, r, g, b)
					col = col + run
				else
					col = col + 1
				end
			end
		end
	end
	return #str * 4 * px - px
end

local function textWidth(str, px) return #normalize(str) * 4 * px - px end

local function drawTextCentered(parent, str, cx, cy, px, r, g, b)
	return drawText(parent, str, cx - textWidth(str, px) / 2, cy - 2.5 * px, px, r, g, b)
end

local function wrap(str, maxChars)
	str = normalize(str)
	local lines, line = {}, ""
	for word in str:gmatch("%S+") do
		while #word > maxChars do
			if #line > 0 then lines[#lines + 1] = line; line = "" end
			lines[#lines + 1] = word:sub(1, maxChars)
			word = word:sub(maxChars + 1)
		end
		if #line == 0 then
			line = word
		elseif #line + 1 + #word <= maxChars then
			line = line .. " " .. word
		else
			lines[#lines + 1] = line
			line = word
		end
	end
	if #line > 0 then lines[#lines + 1] = line end
	if #lines == 0 then lines[1] = "" end
	return lines
end

local ORANGE = { 0.95, 0.65, 0.1 }
local GREEN = { 0.45, 0.85, 0.45 }
local GREY = { 0.6, 0.6, 0.65 }
local WHITE = { 1, 1, 1 }

local function button(parent, cx, cy, w, h, label, px, active, onClick)
	local bg = rect(parent, cx, cy, w, h, 1, 1, 1, 0.12)
	if active then bg:setFillColor(ORANGE[1], ORANGE[2], ORANGE[3], 1) end
	local c = active and { 0, 0, 0 } or WHITE
	drawTextCentered(parent, label, cx, cy, px, c[1], c[2], c[3])
	bg:addEventListener("touch", function(e)
		if e.phase == "ended" then onClick() end
		return true
	end)
	bg:addEventListener("tap", function() return true end)
	return bg
end

---------------------------------------------------------------------------
-- Indicador ">>5x" no canto
---------------------------------------------------------------------------
local MAX_SPEED = 100
local function fmtSpeed(v)
	if v < 10 then
		local t = string.format("%.1f", v):gsub("%.0$", "")
		return t
	end
	return tostring(math.floor(v + 0.5))
end
-- escala logarítmica: metade da barra = 10X, mais precisão nas velocidades baixas
local function speedToFrac(v) return math.log(math.max(1, v)) / math.log(MAX_SPEED) end
local function fracToSpeed(f)
	f = math.max(0, math.min(1, f))
	local v = MAX_SPEED ^ f
	if v < 10 then v = math.floor(v * 10 + 0.5) / 10 else v = math.floor(v + 0.5) end
	return math.max(1, math.min(MAX_SPEED, v))
end
local function stepSpeed(v, dir)
	local step = v < 5 and 0.5 or (v < 10 and 1 or (v < 30 and 5 or (v < 100 and 10 or 100)))
	if dir < 0 and v <= 5 and v > 1 then step = 0.5 end
	local n = v + dir * step
	n = math.floor(n / step + 0.5) * step
	return math.max(1, math.min(MAX_SPEED, n))
end

local function updateBadge()
	if badge then badge:removeSelf(); badge = nil end
	if mult == 1 then return end
	-- canto inferior esquerdo: longe dos nomes/vida dos Coromons na batalha
	local px = math.max(1, math.floor(select(2, screen()) / 200))
	local _, h, _, _, ox, oy = screen()
	local label = ">>" .. fmtSpeed(mult) .. "X"
	local bw, bh = (#label * 4 + 3) * px, 9 * px
	local bx, by = ox + bw / 2 + 2 * px, oy + h - bh / 2 - 2 * px
	badge = display.newGroup()
	rect(badge, bx, by, bw, bh, 0, 0, 0, 0.65)
	drawTextCentered(badge, label, bx, by, px, 1, 0.85, 0.2)
	badge:toFront()
end

local renderPage, openMenu -- definidas mais abaixo

local function setSpeedValue(v, rerender)
	mult = v
	saveSpeed(v)
	tryWrap()
	applyScale()
	updateBadge()
	if rerender and menu and currentTab == "speed" then renderPage() end
end

local function setSpeed(index)
	local s = SPEEDS[index]
	if not s then return end
	setSpeedValue(s, true)
end

---------------------------------------------------------------------------
-- Checagens das missões (todas protegidas com pcall)
---------------------------------------------------------------------------
local loggedErrors = {}
local function safe(tag, f)
	local ok, r = pcall(f)
	if not ok then
		local key = tag .. tostring(r)
		if not loggedErrors[key] then loggedErrors[key] = true; log("missao " .. tag .. ": " .. tostring(r)) end
		return false
	end
	return r and true or false
end

local ownedFamilies = {}
-- Família de um Coromon, tentando vários caminhos da API do jogo.
local function familyOf(m)
	local ok, fam = pcall(function() return m:getMonsterData():getMonsterFamilyUID() end)
	if ok and type(fam) == "string" then return fam end
	ok, fam = pcall(function() return m:getMonsterFamilyData():getUID() end)
	if ok and type(fam) == "string" then return fam end
	local uid
	pcall(function() uid = m:getUID() end)
	if type(uid) ~= "string" then uid = type(m) == "table" and (m.UID or m.uid) or nil end
	if type(uid) == "string" then
		ok, fam = pcall(function() return monsterDataList[uid]:getMonsterFamilyUID() end)
		if ok and type(fam) == "string" then return fam end
		return (uid:gsub("_%d+$", ""))
	end
	return nil
end

local famDiagCount = -1
local function refreshOwnedFamilies()
	ownedFamilies = {}
	safe("familias", function()
		local list = playerMonsters:getOwnedMonstersExcludingInsaneSpinnerSquad()  -- mesma lista que o jogo usa na isca e no bloqueio de família repetida
		local n, found = 0, 0
		for _, m in pairs(list or {}) do
			n = n + 1
			local fam = familyOf(m)
			if fam then
				if not ownedFamilies[fam] then found = found + 1 end
				ownedFamilies[fam] = true
			end
		end
		if n ~= famDiagCount then
			famDiagCount = n
			-- onde está cada Coromon (para o log)
			for _, where in ipairs({ "getSquad", "getMonsterStorage", "getInsaneSpinnerSquad", "getMonsterGraveyard" }) do
				local okW, l = pcall(function() return playerMonsters[where](playerMonsters) end)
				local names = {}
				if okW and type(l) == "table" then
					for _, m in pairs(l) do
						local okN, nm = pcall(function() return m:getDisplayName() end)
						names[#names + 1] = okN and tostring(nm) or "?"
						if where == "getSquad" then  -- espécie, traço e potencial (para conferir o melhor traço)
							pcall(function()
								names[#names] = names[#names] .. " [" .. tostring(m:getUID()) .. " " .. tostring(m:getTraitUID())
									.. " pot " .. tostring(m:getPotential()) .. " nv " .. tostring(m:getLevel())
									.. " golpes " .. table.concat(m:getSelectedSkillUIDs() or {}, "/")
									.. " pontos PE" .. m:getPotentialStat("sp") .. " PV" .. m:getPotentialStat("hp")
									.. " AT" .. m:getPotentialStat("attack") .. " ATE" .. m:getPotentialStat("specialAttack")
									.. " DF" .. m:getPotentialStat("defense") .. " DFE" .. m:getPotentialStat("specialDefense")
									.. " VEL" .. m:getPotentialStat("speed")
									.. " sobra " .. tostring(m:getAmountOfPotentialStatsUndistributed())
									.. " item " .. tostring(m:getHoldItemUID()) .. "]"
							end)
						end
					end
				end
				log("  " .. where .. ": " .. table.concat(names, ", "))
			end
			-- itens de segurar na mochila (para indicar qual vai em cada Coromon)
			pcall(function()
				local inv, list = playerInventory:getItems(), {}
				for k, v in pairs(inv or {}) do
					local uid = type(k) == "string" and k or (type(v) == "table" and (v.UID or (v.getUID and v:getUID()))) or tostring(k)
					local amt = type(v) == "number" and v or (type(v) == "table" and (v.amount or v.count)) or "?"
					if tostring(uid):find("HOLD_") then list[#list + 1] = tostring(uid) .. "x" .. tostring(amt) end
				end
				log("  itens de segurar: " .. table.concat(list, ", "))
			end)
			local names = {}
			for f in pairs(ownedFamilies) do names[#names + 1] = f end
			log("capturados: " .. n .. " coromons, familias: " .. table.concat(names, ","))
		end
		return true
	end)
end

local function chapterDone(uid)
	return safe("cap", function()
		return playerQuests:isCompleted("MAIN", uid) or playerQuests:isCompleted("PROLOGUE", uid)
	end)
end

local function storyDone(it)
	return safe("historia", function() return playerQuests:isCompleted(it.q, it.ch) end)
end
local STORY_COLOR = { 0.55, 0.85, 1 }

local function achDone(uid)
	return safe("conq", function()
		local a = Achievement and Achievement[uid]
		return a and a:isAchieved()
	end)
end

local function lureDone(map)
	return safe("lure", function() return playerSettings:isLuxLuredMap(map) end)
end

local function familyCatchable(fam)
	local ok, r = pcall(function()
		local d = monsterFamilyDataList and monsterFamilyDataList[fam]
		if not d then return true end
		return d:isCatchable()
	end)
	if not ok then return true end
	return r ~= false
end

local function itemDone(it, allFamDone)
	if it.info or it.h then return nil end
	if it.ach and achDone(it.ach) then return true end
	if it.ch and chapterDone(it.ch) then return true end
	if it.q and safe("quest", function() return playerQuests:isCompleted(it.q) end) then return true end
	if it.lure and lureDone(it.lure) then return true end
	if it.fam and (ownedFamilies[it.fam] or (it.allfam and allFamDone)) then return true end
	return false
end

-- Monta a lista de linhas para desenhar: {text, color, done(true/false/nil), first}
local platText = "?"
-- Cada missão {m=titulo, t=descricao, ach=conquista} vem seguida das subpartes {s=texto, checagens}.
-- Missão concluída mostra só o título; pendente mostra descrição e subpartes.
local routeText = "?"
local function buildMissionLines(maxChars, data)
	data = data or MISSION_DATA
	local isRoute = data ~= MISSION_DATA
	local stepTotal, stepDone = 0, 0
	refreshOwnedFamilies()
	local allFamDone = achDone("CATCH_ALL_MONSTER_FAMILIES")
	local lines, firstPending = {}, nil
	local total, done, number = 0, 0, 0
	local missionDone, missionEntry, subTotal, subDone = false, nil, 0, 0

	local function closeMission()
		if missionEntry and subTotal > 0 and not missionDone then
			missionEntry.text = missionEntry.text .. " (" .. subDone .. "/" .. subTotal .. ")"
		end
		missionEntry, subTotal, subDone = nil, 0, 0
	end
	local function add(text, color, indent, first)
		local wrapped = wrap(text, maxChars - #indent)
		for i, l in ipairs(wrapped) do
			lines[#lines + 1] = { text = (i == 1 and first or indent) .. l, color = color }
		end
		return lines[#lines - #wrapped + 1]
	end

	for _, it in ipairs(data or {}) do
		if it.h then
			closeMission()
			for _, l in ipairs(wrap(it.h, maxChars)) do
				lines[#lines + 1] = { text = l, color = ORANGE, header = true }
			end
		elseif it.m then
			closeMission()
			number = number + 1
			total = total + 1
			missionDone = achDone(it.ach)
			if missionDone then done = done + 1 end
			local prefix = (missionDone and "[X] " or "[ ] ") .. number .. ". "
			missionEntry = add(prefix .. it.m, missionDone and GREEN or (firstPending and WHITE or ORANGE), "    ", "")
			if not missionDone then
				if not firstPending then firstPending = #lines end
				if it.t and it.t ~= "" then add(it.t, GREY, "    ", "    ") end
			end
		elseif it.s then
			if not (it.allfam and it.fam and not familyCatchable(it.fam)) then
				local hasCheck = it.ch or it.q or it.lure or it.fam or it.ach
				local st = nil
				if hasCheck then st = itemDone(it, allFamDone) end
				if hasCheck then
					subTotal = subTotal + 1
					if st then subDone = subDone + 1 end
					stepTotal = stepTotal + 1
					if st then stepDone = stepDone + 1 end
				end
				if not missionDone then
					local mark = st == nil and "  - " or (st and "  [X] " or "  [ ] ")
					local color = st and GREEN or (st == nil and GREY or WHITE)
					local isFirst = isRoute and st == false and not firstPending
					local e = add(it.s, isFirst and ORANGE or color, string.rep(" ", #mark), mark)
					if isFirst then firstPending = #lines end
				end
			end
		elseif it.st then
			closeMission()
			missionDone = false
			local st = storyDone(it)
			local col = st and GREEN or (it.side and GREY or STORY_COLOR)
			local e = add(it.st, col, "    ", st and "[X] " or "[ ] ")
			if not st and not it.side and not firstPending then
				firstPending = #lines - #wrap(it.st, maxChars - 4) + 1
			end
		elseif it.info then
			closeMission()
			add(it.t, GREY, "  ", "* ")
		end
	end
	closeMission()
	if isRoute then
		routeText = stepDone .. "/" .. stepTotal
	else
		platText = done .. "/" .. total
	end
	return lines, firstPending, done, total
end

local function currentMapInfo()
	local mapFile
	pcall(function() mapFile = worldHelper:getMapFile() end)
	if type(mapFile) ~= "string" then return nil end
	local name = (MAP_NAMES and MAP_NAMES[mapFile]) or mapFile
	local used = lureDone(mapFile)
	return name, used, mapFile
end

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------
local menuBounds
local lastRefresh, lastSignature = 0, nil
local function closeMenu()
	menuBounds = nil
	if menu then
		menu:removeSelf()
		menu, pageGroup = nil, nil
	end
end

local layout = {}

local function renderSpeedPage(g)
	local px, cx, top = layout.px, layout.cx, layout.contentTop
	local rowH, gap = 9 * px, 2 * px
	local w = math.min(layout.panelW - 8 * px, 60 * px)
	for i, s in ipairs(SPEEDS) do
		local y = top + 4 * px + (i - 1) * (rowH + gap) + rowH / 2
		button(g, cx, y, w, rowH, i .. "   " .. s .. "X", px, s == mult, function() setSpeed(i) end)
	end
	-- barra deslizante (tipo volume)
	local sy = top + 4 * px + #SPEEDS * (rowH + gap) + 10 * px
	local trackW = w - 20 * px
	local left = cx - trackW / 2
	local dyn
	local function drawDyn()
		if dyn then dyn:removeSelf() end
		dyn = display.newGroup()
		g:insert(dyn)
		local frac = speedToFrac(mult)
		drawTextCentered(dyn, "PERSONALIZADO: " .. fmtSpeed(mult) .. "X", cx, sy - 7 * px, px, 1, 0.85, 0.2)
		if frac > 0 then
			rect(dyn, left + trackW * frac / 2, sy, trackW * frac, 3 * px, ORANGE[1], ORANGE[2], ORANGE[3], 1)
		end
		rect(dyn, left + trackW * frac, sy, 3 * px, 8 * px, 1, 1, 1, 1)
	end
	rect(g, cx, sy, trackW, 3 * px, 1, 1, 1, 0.2)
	drawDyn()
	local hit = rect(g, cx, sy, trackW + 6 * px, 12 * px, 1, 1, 1, 0.01)
	hit:addEventListener("touch", function(e)
		local stage = display.getCurrentStage and display.getCurrentStage()
		if e.phase == "began" and stage then stage:setFocus(hit) end
		if type(e.x) == "number" then
			local v = fracToSpeed((e.x - left) / trackW)
			if v ~= mult then
				setSpeedValue(v, false)
				pcall(drawDyn)
			end
		end
		if (e.phase == "ended" or e.phase == "cancelled") then
			if stage then stage:setFocus(nil) end
			renderPage()
		end
		return true
	end)
	hit:addEventListener("tap", function() return true end)
	button(g, left - 6 * px, sy, 8 * px, 8 * px, "-", px, false, function() setSpeedValue(stepSpeed(mult, -1), true) end)
	button(g, left + trackW + 6 * px, sy, 8 * px, 8 * px, "+", px, false, function() setSpeedValue(stepSpeed(mult, 1), true) end)
	drawTextCentered(g, "1-" .. #SPEEDS .. ", CLIQUE OU ARRASTE", cx, layout.contentBottom - 4 * px, px, GREY[1], GREY[2], GREY[3])
end

-- Aba ASSIST: modo do assistente. "Só informações" esconde as ordens (USE X, DESCANSE,
-- resposta de quiz); "Dicas completas" mostra tudo. Salvo em Documents/speedmod_assist.txt.
local ASSIST_MODE_FILE = "speedmod_assist.txt"
pcall(function()
	local f = io.open(system.pathForFile(ASSIST_MODE_FILE, system.DocumentsDirectory), "r")
	ASSIST_ORDERS = f and f:read("*l") == "dicas" or false
	if f then f:close() end
end)
local function setAssistOrders(v)
	ASSIST_ORDERS = v
	pcall(function()
		local f = io.open(system.pathForFile(ASSIST_MODE_FILE, system.DocumentsDirectory), "w")
		if f then f:write(v and "dicas" or "info", "\n"); f:close() end
	end)
	log("assistente: " .. (v and "dicas completas" or "so informacoes"))
	renderPage()
end
-- Eventos especiais: o jogo só põe as orelhas de coelho (Hayville) e a roupa de Papai Noel
-- (Lux Solis) na Páscoa e no Natal, pela data do PC (specialEventHelper). Ligado aqui, o jogo
-- acha que é o evento. Vale ao entrar num mapa. Salvo em Documents/speedmod_eventos.txt.
local EVENTS_FILE = "speedmod_eventos.txt"
EVENTS = { easter = false, christmas = false }
pcall(function()
	local f = io.open(system.pathForFile(EVENTS_FILE, system.DocumentsDirectory), "r")
	if f then
		local l = f:read("*l") or ""; f:close()
		EVENTS.easter = l:find("pascoa", 1, true) ~= nil
		EVENTS.christmas = l:find("natal", 1, true) ~= nil
	end
end)
local function setEvent(name, v)
	EVENTS[name] = v
	pcall(function()
		local f = io.open(system.pathForFile(EVENTS_FILE, system.DocumentsDirectory), "w")
		if f then f:write((EVENTS.easter and "pascoa " or "") .. (EVENTS.christmas and "natal" or ""), "\n"); f:close() end
	end)
	log("evento " .. name .. ": " .. tostring(v))
	renderPage()
end
do
	local wrapped = false
	Runtime:addEventListener("enterFrame", function()
		if wrapped or type(specialEventHelper) ~= "table" or type(specialEventHelper.isEaster) ~= "function" then return end
		wrapped = true
		local origE, origC = specialEventHelper.isEaster, specialEventHelper.isChristmas
		specialEventHelper.isEaster = function(...) return EVENTS.easter or origE(...) end
		specialEventHelper.isChristmas = function(...) return EVENTS.christmas or origC(...) end
	end)
end

local function renderAssistPage(g)
	local px, cx, top = layout.px, layout.cx, layout.contentTop
	local rowH, gap = 9 * px, 2 * px
	local w = math.min(layout.panelW - 8 * px, 70 * px)
	button(g, cx, top + 4 * px + rowH / 2, w, rowH, "1   SO INFORMACOES", px, not ASSIST_ORDERS, function() setAssistOrders(false) end)
	button(g, cx, top + 4 * px + rowH + gap + rowH / 2, w, rowH, "2   DICAS COMPLETAS", px, ASSIST_ORDERS, function() setAssistOrders(true) end)
	button(g, cx, top + 4 * px + 2 * (rowH + gap) + rowH / 2, w, rowH, "3   PASCOA " .. (EVENTS.easter and "LIGADA" or "DESLIGADA"), px, EVENTS.easter, function() setEvent("easter", not EVENTS.easter) end)
	button(g, cx, top + 4 * px + 3 * (rowH + gap) + rowH / 2, w, rowH, "4   NATAL " .. (EVENTS.christmas and "LIGADO" or "DESLIGADO"), px, EVENTS.christmas, function() setEvent("christmas", not EVENTS.christmas) end)
	local y = top + 4 * px + 4 * (rowH + gap) + 6 * px
	if EVENTS.easter or EVENTS.christmas then
		drawTextCentered(g, "EVENTO VALE AO ENTRAR NO MAPA", cx, y, px, GREEN[1], GREEN[2], GREEN[3]); y = y + 8 * px
	end
	for _, l in ipairs(ASSIST_ORDERS and { "MOSTRA QUAL GOLPE USAR,", "QUANDO DESCANSAR E A", "RESPOSTA DOS QUIZ." }
		or { "SO DADOS: TIPO, VIDA, PE,", "PERIGO E CAPTURA. QUEM", "DECIDE O GOLPE E VOCE." }) do
		drawTextCentered(g, l, cx, y, px, GREY[1], GREY[2], GREY[3]); y = y + 8 * px
	end
end

local function renderMissionsPage(g)
	local px, cx = layout.px, layout.cx
	local left = layout.panelLeft + 4 * px
	local lineH = 7 * px
	local listTop = layout.contentTop + 2 * px
	local listBottom = layout.contentBottom - 25 * px
	local visible = math.max(3, math.floor((listBottom - listTop) / lineH))
	local maxChars = math.floor((layout.panelW - 20 * px) / (4 * px))

	local lines, firstPending, done, total = buildMissionLines(maxChars, currentTab == "route" and ROUTE_DATA or MISSION_DATA)
	layout.missionLineCount = #lines
	layout.missionVisible = visible
	if missionScroll == nil then
		missionScroll = math.max(1, (firstPending or 1) - 3)
	end
	missionScroll = math.max(1, math.min(missionScroll, math.max(1, #lines - visible + 1)))

	for i = 0, visible - 1 do
		local l = lines[missionScroll + i]
		if not l then break end
		drawText(g, l.text, left, listTop + i * lineH, px, l.color[1], l.color[2], l.color[3])
	end

	-- barra de rolagem
	local trackX = layout.panelLeft + layout.panelW - 5 * px
	local trackH = listBottom - listTop
	rect(g, trackX, listTop + trackH / 2, px, trackH, 1, 1, 1, 0.15)
	if #lines > visible then
		local thumbH = math.max(4 * px, trackH * visible / #lines)
		local frac = (missionScroll - 1) / math.max(1, #lines - visible)
		rect(g, trackX, listTop + thumbH / 2 + frac * (trackH - thumbH), px * 2, thumbH, ORANGE[1], ORANGE[2], ORANGE[3], 1)
	end

	-- rodapé: botões e mapa atual
	local by = layout.contentBottom - 18 * px
	local bw = 22 * px
	button(g, cx - bw * 1.6, by, bw, 8 * px, "SUBIR", px, false, function()
		missionScroll = missionScroll - (visible - 2); renderPage()
	end)
	button(g, cx, by, bw + 8 * px, 8 * px, "PROXIMA", px, true, function()
		missionScroll = nil; renderPage()
	end)
	button(g, cx + bw * 1.6, by, bw, 8 * px, "DESCER", px, false, function()
		missionScroll = missionScroll + (visible - 2); renderPage()
	end)

	local maxStatus = math.floor((layout.panelW - 8 * px) / (4 * px))
	drawText(g, normalize(currentTab == "route" and ("ROTA " .. routeText .. " MAPAS") or ("PLATINA " .. platText)), left, layout.contentBottom - 12 * px, px, ORANGE[1], ORANGE[2], ORANGE[3])
	local name, used, mapFile = currentMapInfo()
	if name and MAP_NAMES and MAP_NAMES[mapFile] then
		local status = name .. " - ISCA " .. (used and "USADA" or "LIVRE")
		drawText(g, normalize(status):sub(1, maxStatus), left, layout.contentBottom - 6 * px, px,
			GREY[1], GREY[2], GREY[3])
	end
end

renderPage = function()
	if not menu then return end
	if pageGroup then pageGroup:removeSelf() end
	pageGroup = display.newGroup()
	menu:insert(pageGroup)
	local ok, err = pcall(function()
		if currentTab == "speed" then renderSpeedPage(pageGroup)
		elseif currentTab == "assist" then renderAssistPage(pageGroup)
		else renderMissionsPage(pageGroup) end
	end)
	if not ok then log("erro ao desenhar aba: " .. tostring(err)) end
end

local function switchTab(tab)
	if currentTab ~= tab then missionScroll = nil end
	currentTab = tab
	if menu then
		closeMenu()
		openMenu()
	end
end

openMenu = function()
	if menu then return end
	lastSignature = nil
	local px = pixelSize()
	local sw, sh, cx, cy = screen()
	menu = display.newGroup()

	-- Painel no meio do lado esquerdo; o resto da tela continua jogável.
	local _, _, _, _, ox = screen()
	local listTab = (currentTab == "missions" or currentTab == "route")
	local panelW = listTab and math.floor(sw * 0.31) or 110 * px
	local panelH = listTab and math.floor(sh * 0.58) or (16 * px + #SPEEDS * 11 * px + 34 * px)
	local panelLeft, panelTop = ox + 4 * px, cy - panelH / 2
	cx = panelLeft + panelW / 2
	rect(menu, cx, cy, panelW + 2 * px, panelH + 2 * px, ORANGE[1], ORANGE[2], ORANGE[3], 1)
	local panel = rect(menu, cx, cy, panelW, panelH, 0.08, 0.09, 0.14, 0.9)
	panel:addEventListener("touch", function() return true end)
	panel:addEventListener("tap", function() return true end)
	menuBounds = { panelLeft - px, panelTop - px, panelLeft + panelW + px, panelTop + panelH + px }

	-- abas
	local tabW = 25 * px
	for i, t in ipairs({ { "speed", "VELOC" }, { "missions", "MISSOES" }, { "route", "ROTA" }, { "assist", "ASSIST" } }) do
		button(menu, cx + (i - 2.5) * (tabW + px), panelTop + 6 * px, tabW, 8 * px, t[2], px,
			currentTab == t[1], function() switchTab(t[1]) end)
	end

	layout = {
		px = px, cx = cx, panelW = panelW, panelLeft = panelLeft,
		contentTop = panelTop + 12 * px, contentBottom = panelTop + panelH - 2 * px,
	}
	renderPage()
	menu:toFront()
end

local function toggleMenu()
	if menu then closeMenu() else openMenu() end
end

local function scrollMissions(delta)
	if menu and (currentTab == "missions" or currentTab == "route") then
		missionScroll = (missionScroll or 1) + delta
		renderPage()
	end
end

-- Mantém o mod por cima de tudo que o jogo desenhar depois.
local function missionSignature()
	refreshOwnedFamilies()
	local allFamDone = achDone("CATCH_ALL_MONSTER_FAMILIES")
	local parts = {}
	for _, it in ipairs(MISSION_DATA or {}) do
		local st
		if it.m then st = achDone(it.ach) elseif it.s then st = itemDone(it, allFamDone) end
		parts[#parts + 1] = st and "1" or "0"
	end
	local name, used = currentMapInfo()
	return table.concat(parts) .. tostring(name) .. tostring(used)
end

local savedApplied = (mult == 1)
Runtime:addEventListener("enterFrame", function()
	if not savedApplied and gameReady() and origSetTimeScale then
		savedApplied = true
		applyScale()
		pcall(updateBadge)
	end
end)

Runtime:addEventListener("enterFrame", function()
	-- o jogo pode recriar o timer; sem a compensação o clique vira "segurar" e o golpe não sai
	if mult ~= 1 and type(timer) == "table" and timerWrapped and timer.performWithDelay ~= timerWrapped then
		timerWrapped = nil
		pcall(wrapTimer)
	end
	if menu and (currentTab == "missions" or currentTab == "route") then
		local now = system.getTimer()
		if now - lastRefresh > 1500 then
			lastRefresh = now
			local ok, sig = pcall(missionSignature)
			if ok and sig ~= lastSignature then
				if lastSignature ~= nil then renderPage() end
				lastSignature = sig
			end
		end
	end
	if menu and menu.toFront then menu:toFront() end
	if badge and badge.toFront then badge:toFront() end
end)

-- Roda do mouse rola a lista de missões.
local wheelLogs = 0
local function inBounds(x, y)
	local b = menuBounds
	if not b or type(x) ~= "number" or type(y) ~= "number" then return true end
	if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then return true end
	-- alguns builds mandam a posição em pixels da janela: converte para o conteúdo
	local sx = tonumber(display.contentScaleX) or 1
	local sy = tonumber(display.contentScaleY) or 1
	local ox = tonumber(display.screenOriginX) or 0
	local oy = tonumber(display.screenOriginY) or 0
	local cx, cy = x * sx + ox, y * sy + oy
	return cx >= b[1] and cx <= b[3] and cy >= b[2] and cy <= b[4]
end

-- Roda do mouse rola a lista de missões/rota.
Runtime:addEventListener("mouse", function(e)
	local dy = tonumber(e.scrollY) or 0
	if dy == 0 and e.type == "scroll" then dy = tonumber(e.deltaY) or 0 end
	if dy == 0 then return false end
	if wheelLogs < 5 then
		wheelLogs = wheelLogs + 1
		log("roda do mouse: dy=" .. tostring(dy) .. " x=" .. tostring(e.x) .. " y=" .. tostring(e.y)
			.. " menu=" .. tostring(menu ~= nil) .. " aba=" .. tostring(currentTab))
	end
	if menu and (currentTab == "missions" or currentTab == "route") then
		pcall(scrollMissions, dy > 0 and 3 or -3)
		return true
	end
	return false
end)

local numberKeys = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8,
	numPad1 = 1, numPad2 = 2, numPad3 = 3, numPad4 = 4, numPad5 = 5, numPad6 = 6, numPad7 = 7, numPad8 = 8 }
local menuKeys = { tab = true, pageUp = true, pageDown = true }

local keyLogs = 0
Runtime:addEventListener("key", function(e)
	if keyLogs < 20 then
		keyLogs = keyLogs + 1
		log("tecla " .. tostring(e.keyName) .. " " .. tostring(e.phase))
	end
	local k = e.keyName
	local isToggle = TOGGLE_KEYS[k]
	-- teclas 1-6 mudam a velocidade direto, sem abrir o menu (fora da aba ASSIST, onde 1/2 trocam o modo)
	local speedKey = numberKeys[k] and SPEEDS[numberKeys[k]] and not (menu and currentTab ~= "speed")
	local mine = isToggle or speedKey or (menu ~= nil and (numberKeys[k] or menuKeys[k]))
	if e.phase ~= "down" then return mine and true or false end

	if isToggle then
		local ok, err = pcall(toggleMenu)
		if not ok then
			log("erro no menu: " .. tostring(err))
			pcall(closeMenu)
		end
		return true
	end
	if not menu then
		if speedKey then pcall(setSpeed, numberKeys[k]); return true end
		return false
	end
	if k == "tab" then
		local nextTab = { speed = "missions", missions = "route", route = "assist", assist = "speed" }
		pcall(switchTab, nextTab[currentTab] or "speed")
		return true
	end
	if k == "pageDown" then pcall(scrollMissions, (layout.missionVisible or 10) - 2); return true end
	if k == "pageUp" then pcall(scrollMissions, -((layout.missionVisible or 10) - 2)); return true end
	if numberKeys[k] and currentTab == "assist" and e.phase == "down" and numberKeys[k] <= 2 then
		pcall(setAssistOrders, numberKeys[k] == 2)
		return true
	end
	if numberKeys[k] and currentTab == "assist" and e.phase == "down" and (numberKeys[k] == 3 or numberKeys[k] == 4) then
		local name = numberKeys[k] == 3 and "easter" or "christmas"
		pcall(setEvent, name, not EVENTS[name])
		return true
	end
	if numberKeys[k] and currentTab == "speed" then
		local ok, err = pcall(setSpeed, numberKeys[k])
		if not ok then log("erro ao mudar velocidade: " .. tostring(err)) end
		return true
	end
	return false
end)

log("SpeedMod: carregado (Home abre o menu)")
do
	local have = {}
	for _, k in ipairs({ "newRect", "newGroup", "newText", "newRoundedRect" }) do
		have[#have + 1] = k .. "=" .. type(display[k])
	end
	log("display: " .. table.concat(have, " ") .. " missoes=" .. tostring(MISSION_DATA and #MISSION_DATA))
end
