---------------------------------------------------------------------------
-- Painel fixo (sempre visível) no canto superior esquerdo:
-- mapa atual, Isca Lux livre/usada, alvo da rota e a próxima missão.
-- F7 esconde/mostra.
---------------------------------------------------------------------------
do
	local hud, hudVisible, lastSig, lastCheck = nil, true, nil, -10000
	local MAX = 30
	local lastDiag
	local lastPaused

	local function currentStory()
		for _, it in ipairs(MISSION_DATA or {}) do
			if it.st and not it.side and not storyDone(it) then return it.st end
		end
	end

	-- missões ativas, direto do Diário do jogo (texto já com o progresso)
	local function questUID(q)
		if type(q) == "string" then return q end
		if type(q) == "table" then
			local ok, u = pcall(function() return q:getUID() end)
			if ok and type(u) == "string" then return u end
			return q.UID or q.uid or q.questUID
		end
	end
	local function questInfo(uid)
		local ok, ch = pcall(function() return playerQuests:getCurrentChapter(uid) end)
		if not ok or type(ch) ~= "string" then return nil end
		local okD, desc = pcall(function() return playerQuests:getQuestDescription(uid, ch) end)
		local okN, name = pcall(function() return playerQuests:getQuestName(uid) end)
		local short = ch:match("([^.]+)$") or ch
		local hint = QUEST_HINT and (QUEST_HINT[uid .. "|" .. short] or QUEST_HINT[uid .. "|" .. ch]
			or QUEST_HINT[uid .. "|*"])
		local npcs = QUEST_NPC and (QUEST_NPC[uid .. "|" .. short] or QUEST_NPC[uid .. "|" .. ch])
		return {
			uid = uid,
			chapter = ch,
			name = okN and type(name) == "string" and name or uid,
			desc = okD and type(desc) == "string" and desc or "",
			hint = hint,
			npcs = npcs,
		}
	end
	local function activeQuests()
		local ok, list = pcall(function() return playerQuests:getActiveQuests() end)
		local out = {}
		if ok and type(list) == "table" then
			for _, q in pairs(list) do
				local uid = questUID(q)
				if uid then
					local info = questInfo(uid)
					if info then out[#out + 1] = info end
				end
			end
		end
		return out
	end
	local SIDE_COLOR = { 0.85, 0.85, 0.9 }
	local questDiagDone = false
	local function questDiag()
		if questDiagDone then return end
		questDiagDone = true
		pcall(function()
			local f = playerQuests.isCompleted
			local i, state = 1, nil
			while true do
				local n, v = debug.getupvalue(f, i)
				if not n then break end
				if n == "stateByQuestByChapter" then state = v end
				i = i + 1
			end
			for _, q in ipairs({ "PROLOGUE", "MAIN" }) do
				local parts = {}
				for k, v in pairs(state and state[q] or {}) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
				log("estado " .. q .. ": " .. table.concat(parts, " "))
			end
			log("PROLOGUE completo=" .. tostring(playerQuests:isCompleted("PROLOGUE"))
				.. " repel=" .. tostring(playerQuests:isCompleted("PROLOGUE", "luxSolisTown.OBTAIN_REPEL_MODULE")))
		end)
	end

	local function questLines(out, mapName)
		questDiag()
		local quests = activeQuests()
		if #quests == 0 then return false end
		local main, sides = nil, {}
		for _, q in ipairs(quests) do
			if q.uid == "MAIN" or q.uid == "PROLOGUE" then main = q else sides[#sides + 1] = q end
		end
		if main then
			for i, l in ipairs(wrap("HISTORIA: " .. main.desc, MAX)) do
				if i <= 2 then out[#out + 1] = { l, STORY_COLOR } end
			end
			if main.hint then
				for i, l in ipairs(wrap("  " .. main.hint, MAX)) do
					if i <= 2 then out[#out + 1] = { l, GREY } end
				end
			end
		end
		-- secundárias: primeiro as que acontecem no mapa atual
		local mn = mapName and normalize(mapName) or ""
		table.sort(sides, function(a, b)
			local ah = a.hint and mn ~= "" and normalize(a.hint):find(mn, 1, true) and 1 or 0
			local bh = b.hint and mn ~= "" and normalize(b.hint):find(mn, 1, true) and 1 or 0
			return ah > bh
		end)
		for i, q in ipairs(sides) do
			if i > 1 then
				out[#out + 1] = { "+" .. (#sides - 1) .. " MISSOES NO DIARIO", GREY }
				break
			end
			out[#out + 1] = { "MISSAO: " .. q.name, WHITE }
			for j, l in ipairs(wrap(q.desc, MAX)) do
				if j <= 2 then out[#out + 1] = { l, SIDE_COLOR } end
			end
			if q.hint then
				for j, l in ipairs(wrap("  " .. q.hint, MAX)) do
					if j <= 2 then out[#out + 1] = { l, GREY } end
				end
			end
		end
		return true
	end

	local function nextMission()
		local allFamDone = achDone("CATCH_ALL_MONSTER_FAMILIES")
		local n, cur, step, optStep = 0, nil, nil, nil
		for _, it in ipairs(MISSION_DATA or {}) do
			if it.m then
				if cur then break end
				n = n + 1
				if not achDone(it.ach) then cur = n .. ". " .. it.m end
			elseif it.h and cur then
				break
			elseif it.s and cur and not step then
				if not (it.allfam and it.fam and not familyCatchable(it.fam)) then
					local hasCheck = it.ch or it.q or it.lure or it.fam or it.ach
					if not hasCheck or not itemDone(it, allFamDone) then
						-- passos "(opcional)" só aparecem se não sobrar nenhum obrigatório
						if it.s:find("^%(opcional%)") then
							optStep = optStep or it.s
						else
							step = it.s
						end
					end
				end
			end
		end
		return cur, step or optStep
	end

	local MAXR = 26  -- largura do quadro do assistente
	local function addWrapped(out, l, maxLines, width)
		for i, w in ipairs(wrap(l[1], width or MAX)) do
			if i <= (maxLines or 2) then out[#out + 1] = { w, l[2] } end
		end
	end

	-- área (cidade) do mapa atual; mapas internos sem cidade no nome mantêm a última
	local AREA_RULES = {
		{ "luxSolis", "PARQUE" }, { "amish", "PARQUE" }, { "harbor", "PARQUE" }, { "homeTown", "PARQUE" },
		{ "library", "PARQUE" }, { "electric", "ILHA DONAR" }, { "powerTower", "ILHA DONAR" },
		{ "ghost", "PAWBURY" }, { "swamp", "PAWBURY" }, { "templeDungeon", "PAWBURY" }, { "mansion", "PAWBURY" },
		{ "mescher", "PAWBURY" }, { "desert", "DARUDIC" }, { "oasis", "DARUDIC" }, { "pyramid", "DARUDIC" },
		{ "palace", "DARUDIC" }, { "barracks", "DARUDIC" }, { "fire", "VLAMMA" }, { "volcano", "VLAMMA" },
		{ "dojo", "VLAMMA" }, { "ice", "ALAVI" }, { "frozen", "ALAVI" }, { "water", "IXQUN" },
	}
	local AREA_TITLE = { PARQUE = "HAYVILLE E PARQUE", ["ILHA DONAR"] = "ILHA DONAR", PAWBURY = "PAWBURY",
		DARUDIC = "DARUDIC", VLAMMA = "VLAMMA", ALAVI = "ALAVI", IXQUN = "IXQUN" }
	local lastArea = "PARQUE"
	local function areaOf(mf)
		for _, r in ipairs(AREA_RULES) do
			if mf:find(r[1], 1, true) then lastArea = r[2]; return r[2] end
		end
		return lastArea
	end

	-- próxima conquista pendente dentro da área (pelo cabeçalho da lista)
	-- nome do lugar sem "(parte N)": "Pantano Encharcado (parte 2)" -> "PANTANO ENCHARCADO"
	local function placeBase(v) return normalize((v:gsub("%s*%b()", ""))) end
	local function currentPlace(mapFile)
		local name, best = MAP_NAMES and MAP_NAMES[mapFile], 0
		if not name and MAP_NAMES then
			for k, v in pairs(MAP_NAMES) do
				if mapFile:find(k, 1, true) and #k > best then name, best = v, #k end
			end
		end
		return name and placeBase(name)
	end
	-- o texto cita um lugar? só vale se for o mapa atual (sem lugar citado: vale em toda a área)
	local function placeOK(text, here)
		if not (MAP_NAMES and here and text) then return true end
		local t, cited = normalize(text), false
		for _, v in pairs(MAP_NAMES) do
			local b = placeBase(v)
			if #b > 3 and t:find(b, 1, true) then
				if b == here then return true end
				cited = true
			end
		end
		return not cited
	end
	-- próxima conquista da área que dá para fazer NESTE mapa; conta as que são em outro mapa
	local function areaAchievement(area, mapFile)
		local allFamDone = achDone("CATCH_ALL_MONSTER_FAMILIES")
		local here = mapFile and currentPlace(mapFile)
		local inArea, cur, step, optStep, elsewhere = false, nil, nil, nil, 0
		local function finish()
			if not cur then return nil end
			local txt = step or optStep or cur.t
			if placeOK(txt, here) then return txt end
			elsewhere = elsewhere + 1
			cur, step, optStep = nil, nil, nil
		end
		for _, it in ipairs(MISSION_DATA or {}) do
			if it.h then
				if inArea then local r = finish(); if r then return r, elsewhere end end
				inArea = it.h:find(area, 1, true) == 1
			elseif inArea and it.m then
				local r = finish(); if r then return r, elsewhere end
				-- need: só depois de um capítulo da história (ex.: ter o Tremor)
				if not achDone(it.ach) and not (it.need and not chapterDone(it.need)) then cur = it end
			elseif inArea and it.s and cur and not step then
				local hasCheck = it.ch or it.q or it.lure or it.fam or it.ach
				if not hasCheck or not itemDone(it, allFamDone) then
					if it.s:find("^%(opcional%)") then optStep = optStep or it.s else step = it.s end
				end
			end
		end
		local r = finish()
		return r, elsewhere
	end

	-- dica extra só quando é útil (onde achar/capturar); listas "Onde: ..." de NPCs confundem
	local function extraHint(q)
		local h = q.hint
		if not h or h == "" or h:lower():find("^onde:") then return nil end
		return h
	end
	-- o que fazer AGORA: o texto do passo atual do jogo + dica extra
	local function questHint(q)
		local d, h = q.desc or "", extraHint(q)
		if d == "" then return h end
		if h then return d .. " - " .. h end
		return d
	end
	local curCh = 0  -- capítulo do último mapa conhecido
	local LEFT_MAX = 11
	local inBattleHud = false  -- em batalha o jogo mostra o ícone de clima no canto de cima à esquerda
	local inMescher = false   -- Reino de Mescher: o jogo mostra os frascos de almas no canto de cima à esquerda
	local function soulsLeft()
		local n
		pcall(function()
			local t = worldHelper:getSpawnablesByInstanceOf("mescherRealmLightSoul")
			if type(t) == "table" then n = #t end
		end)
		return n
	end
	-- direção ao vivo do jogador até um NPC da etapa que esteja neste mapa
	local function tileOf(o)
		local x, y
		pcall(function() x, y = o:getTileX(), o:getTileY() end)
		if not x then x, y = o.tileX, o.tileY end
		return tonumber(x), tonumber(y)
	end
	local function npcLines(out, q)
		if not (q and q.npcs) then return end
		local pl
		pcall(function() pl = spawnableHelper:getPlayerSpawnable() end)
		if not pl then return end
		local px, py = tileOf(pl)  -- ("a and f()" perderia o segundo valor)
		if not (px and py) then return end
		for _, nm in ipairs(q.npcs) do
			local sp
			pcall(function() sp = worldHelper:getSpawnableByName(nm) end)
			local nx, ny
			if sp then nx, ny = tileOf(sp) end
			if nx and ny and #out < LEFT_MAX then
				local dx, dy = nx - px, ny - py
				local t = {}
				if dy < -1 then t[#t + 1] = (-dy) .. " NORTE" elseif dy > 1 then t[#t + 1] = dy .. " SUL" end
				if dx > 1 then t[#t + 1] = dx .. " LESTE" elseif dx < -1 then t[#t + 1] = (-dx) .. " OESTE" end
				local who = nm:gsub("Festival$", ""):upper()
				out[#out + 1] = { "  -> " .. who .. ": " .. (#t > 0 and table.concat(t, ", ") or "AQUI DO LADO"), GREEN }
			end
		end
	end
	local potsLogged = false
	local function stepLines(out, mapFile)
		local area = areaOf(mapFile)
		out[#out + 1] = { "PASSO A PASSO - " .. (AREA_TITLE[area] or area), ORANGE }
		local n = 0
		local function addStep(text, hint, color)
			local lines = {}
			for i, l in ipairs(wrap((n + 1) .. ". " .. text, MAX)) do
				if i <= 4 then lines[#lines + 1] = { l, color or WHITE } end
			end
			if hint then
				for i, l in ipairs(wrap("   " .. hint, MAX)) do
					if i <= 3 then lines[#lines + 1] = { l, GREY } end
				end
			end
			-- passo que não cabe inteiro fica de fora (antes saía cortado no meio)
			if #out + #lines > LEFT_MAX then return end
			n = n + 1
			for _, l in ipairs(lines) do out[#out + 1] = l end
		end
		local quests = activeQuests()
		local main
		local others, moreHere, later = 0, 0, 0
		curCh = (MAP_CH and MAP_CH[mapFile]) or curCh
		-- história primeiro: é o que sempre importa (antes ficava por último e sumia no corte de linhas)
		for _, q in ipairs(quests) do
			if q.uid == "MAIN" or q.uid == "PROLOGUE" then main = q end
		end
		local ach, achElsewhere = areaAchievement(area, mapFile)
		local sideHere = false
		for _, q in ipairs(quests) do
			if q ~= main and QUEST_AREA and QUEST_AREA[q.uid] == area
				and not (QUEST_NEED_CH and QUEST_NEED_CH[q.uid] and QUEST_NEED_CH[q.uid] > curCh) then sideHere = true end
		end
		if inMescher then
			local left = soulsLeft()
			if left and left > 0 then out[#out + 1] = { "ALMAS NESTE MAPA: FALTAM " .. left, GREEN } end
		end
		SENSEI_QUEST = main ~= nil and main.chapter == "fireTown.SENSEI_STRATEGIC_BATTLE"
		if main then
			local label = (not sideHere and not ach) and "CIDADE CONCLUIDA! PROXIMO: " or "HISTORIA: "
			addStep(label .. main.desc, extraHint(main), STORY_COLOR)
			npcLines(out, main)
		end
		-- missões secundárias desta cidade (pós-jogo não mostra)
		for _, q in ipairs(main and quests or {}) do
			if q == main then
			elseif QUEST_NEED_CH and QUEST_NEED_CH[q.uid] and QUEST_NEED_CH[q.uid] > curCh then
				later = later + 1   -- pede Coromon de um lugar que você ainda não alcançou
			elseif QUEST_AREA and QUEST_AREA[q.uid] == area then
				if n < 3 then
					local left = q.chapter and q.chapter:match("_(%d+)_LEFT$")
					addStep(normalize(q.name) .. (left and (" (FALTAM " .. left .. ")") or ""), questHint(q))
					npcLines(out, q)
				else
					moreHere = moreHere + 1
				end
			else
				others = others + 1
			end
		end
		-- conquista desta cidade (só se for neste mapa)
		if ach then addStep("CONQUISTA: " .. ach, nil, { 0.95, 0.75, 0.3 }) end
		-- história acabou: rumo à platina (quantas faltam e a próxima da lista, em qualquer lugar)
		if not main then
			local pend, first, tip = 0, nil, nil
			for _, it in ipairs(MISSION_DATA or {}) do
				if it.m and it.ach and not achDone(it.ach) then
					pend = pend + 1
					if not first and not (it.need and not chapterDone(it.need)) then first, tip = it.m, it.t end
				end
			end
			if pend > 0 then
				addStep("PLATINA: FALTAM " .. pend .. " CONQUISTAS", nil, ORANGE)
				if first and not ach then addStep("PROXIMA: " .. normalize(first) .. (tip and (" - " .. tip) or ""), nil, { 0.95, 0.75, 0.3 }) end
			else
				addStep("PLATINA: TODAS AS CONQUISTAS FEITAS!", nil, GREEN)
			end
		end
		-- conquista "plante em todos os vasos": o jogo exige TODOS com fruta ao mesmo tempo
		pcall(function()
			if achDone("PLANT_FRUITS_IN_ALL_POTS") or type(FruitGrowingPotList) ~= "table" then return end
			local here, hereN, tot, totN = 0, 0, 0, 0
			local missing, byName, emptyIds = {}, {}, {}
			for _, id in ipairs(FruitGrowingPotList) do
				local folder = tostring(id):match("^([^/]+)/") or ""
				local okP, props = pcall(function() return playerWorldData:resolveConsistentSavePropertiesFromSpawnableOrProperty(id) end)
				local planted = okP and type(props) == "table" and props.spawnedFruitData ~= nil
				totN = totN + 1
				if planted then tot = tot + 1 end
				if not planted then emptyIds[#emptyIds + 1] = tostring(id):gsub("_fruitGrowingPot", "") end
				if areaOf(folder) == area then
					hereN = hereN + 1
					if planted then
						here = here + 1
					else
						-- "ghostTown/houseSabrina_fruitGrowingPot_4_7" -> "CASA SABRINA"; mapa da cidade -> "RUA"
						local sub = tostring(id):match("/([%w]+)_fruitGrowingPot") or "?"
						local nm = (sub == folder) and "RUA" or (sub:gsub("^house(%u)", "CASA %1"):gsub("_.*", "")):upper()
						if not byName[nm] then byName[nm] = { n = nm, c = 0 }; missing[#missing + 1] = byName[nm] end
						byName[nm].c = byName[nm].c + 1
					end
				end
			end
			-- mesma regra do jogo (playerStats: todos os vasos com fruta). Recupera a conquista se o jogo
			-- caiu no popup antes de salvar (2026-11-19)
			if tot == totN and totN > 0 then
				pcall(function() Achievement.PLANT_FRUITS_IN_ALL_POTS:achieveAndShowIndicator() end)
				log("vasos: todos plantados, conquista PLANT_FRUITS_IN_ALL_POTS marcada")
			end
			if hereN > 0 and #out < LEFT_MAX then
				local faltaAqui, faltaTot = hereN - here, totN - tot
				out[#out + 1] = { (faltaAqui > 0 and ("VASOS: FALTAM " .. faltaAqui .. " AQUI") or "VASOS: TODOS PLANTADOS AQUI")
					.. " (" .. faltaTot .. " NO TOTAL)", GREY }
			end
			if potsLogged ~= tot then  -- registra de novo sempre que planta/colhe (para conferir pelo log)
				potsLogged = tot
				-- arquivo próprio (o speedmod.log para de gravar depois de 300 linhas)
				pcall(function()
					local f = io.open(system.pathForFile("speedmod_vasos.txt", system.DocumentsDirectory), "w")
					if f then
						f:write(os.date("%H:%M:%S"), " plantados ", tot, "/", totN, "\nvazios:\n", table.concat(emptyIds, "\n"), "\n")
						f:close()
					end
				end)
			end
		end)
		if moreHere > 0 then out[#out + 1] = { "+" .. moreHere .. " MISSOES AQUI (VEJA O DIARIO)", GREY } end
		if (achElsewhere or 0) > 0 then out[#out + 1] = { "+" .. achElsewhere .. " CONQUISTAS EM OUTROS MAPAS DAQUI", GREY } end
		if others > 0 then out[#out + 1] = { "+" .. others .. " MISSOES EM OUTRAS CIDADES", GREY } end
		if later > 0 then out[#out + 1] = { "+" .. later .. " MISSOES PARA DEPOIS", GREY } end
	end

	local function buildLines()
		-- na batalha: só as dicas de batalha
		local battleRight
		local okB, battle = pcall(ASSIST.battleLines)
		if okB and battle and #battle > 0 then
			battleRight = { { "ASSISTENTE", ORANGE } }
			local okQ, quiz = pcall(ASSIST.quizLines)
			if okQ and quiz then for _, l in ipairs(quiz) do addWrapped(battleRight, l, 3, MAXR) end end
			for _, l in ipairs(battle) do addWrapped(battleRight, l, 2, MAXR) end
		elseif not okB then
			log("assistente batalha: " .. tostring(battle))
		end
		local mapFile
		pcall(function() mapFile = worldHelper:getMapFile() end)
		if type(mapFile) ~= "string" then return nil end
		inMescher = mapFile:find("_mescherRealm$") ~= nil
		refreshOwnedFamilies()
		local out = {}
		local usedNow = lureDone(mapFile)
		local diagKey = mapFile .. tostring(usedNow)
		if diagKey ~= lastDiag then
			lastDiag = diagKey
			log("mapa " .. mapFile .. " isca usada=" .. tostring(usedNow))
		end
		local name = MAP_NAMES and MAP_NAMES[mapFile]
		local target = ROUTE_TARGET and ROUTE_TARGET[mapFile]
		inBattleHud = battleRight ~= nil
		if target and (not usedNow or battleRight) then
			local fam = ROUTE_TARGET_FAM and ROUTE_TARGET_FAM[mapFile]
			local txt = target
			if fam and ownedFamilies[fam] then
				local alt, altFam = routeAlt(mapFile, ownedFamilies)
				txt = alt and ("MELHOR: " .. alt) or (not usedNow and "NADA NOVO AQUI" or nil)
				fam = altFam
			end
			local st = ASSIST.starterHere(mapFile)
			if st then
				fam = st
				local d = ASSIST_MON[st .. "_1"]
				txt = "INICIAL: " .. ((d and d.n or st):upper()) .. " 0% (CONQUISTA)"
			end
			-- % ao vivo: com a isca (só famílias que você ainda não tem), não a do mato
			local _, pIsca = ASSIST.encPct(mapFile, fam)
			if txt and pIsca then txt = txt:gsub("%d+%%", "ISCA " .. pIsca .. "%%", 1) end
			if txt then
				out[#out + 1] = { (usedNow and "ALVO DA ISCA: " or "ISCA LIVRE AQUI: ") .. normalize(txt), GREEN }
			end
		end
		local right = {}
		local okQ, quiz = pcall(ASSIST.quizLines)
		if okQ and quiz then
			right[1] = { "ASSISTENTE", ORANGE }
			for _, l in ipairs(quiz) do addWrapped(right, l, 3, MAXR) end
		end
		if battleRight then
			return out, battleRight
		end
		local okA, tips = pcall(ASSIST.overworldLines)
		if okA and tips and #tips > 0 then
			if #right == 0 then right[1] = { "ASSISTENTE", ORANGE } end
			for i, l in ipairs(tips) do
				if i <= 4 then addWrapped(right, l, 2, MAXR) end
			end
		elseif not okA then
			log("assistente: " .. tostring(tips))
		end
		local okS, err = pcall(stepLines, out, mapFile)
		if not okS then log("passo a passo: " .. tostring(err)) end
		-- menos poluição: no máximo LEFT_MAX linhas à esquerda (corta do fim: os "+N MISSOES" saem antes do texto)
		while #out > LEFT_MAX do table.remove(out) end
		return out, right
	end

	-- desenha uma caixa de texto; anchorRight = encostada na borda direita
	local function box(group, lines, px, x, y, anchorRight, border)
		if not lines or #lines == 0 then return end
		local widest = 0
		for _, l in ipairs(lines) do widest = math.max(widest, #normalize(l[1])) end
		local w, h = (widest * 4 + 5) * px, (#lines * 7 + 3) * px
		local left = anchorRight and (x - w) or x
		if border then
			rect(group, left + w / 2, y + h / 2, w + 2 * px, h + 2 * px, border[1], border[2], border[3], 0.8)
		end
		rect(group, left + w / 2, y + h / 2, w, h, 0, 0, 0, 0.6)
		for i, l in ipairs(lines) do
			drawText(group, l[1], left + 3 * px, y + 2 * px + (i - 1) * 7 * px, px, l[2][1], l[2][2], l[2][3])
		end
	end

	local pauseBox, pauseSig, pauseCheck = nil, nil, 0
	local iaLastState = nil
	HUD_DEBUG = function() return buildLines() end
	local function draw(leftLines, rightLines)
		if hud then pcall(function() hud:removeSelf() end); hud = nil end
		if not hudVisible then return end
		local px = math.max(1, select(2, screen()) / (inBattleHud and 560 or 500))  -- fonte menor (cabe 11 linhas)
		local sw, sh, _, _, ox, oy = screen()
		hud = display.newGroup()
		-- esquerda: mapa, isca, missão
		box(hud, leftLines, px, ox + 2 * px + (inBattleHud and math.floor(sw * 0.055) or 0), oy + 2 * px + (inMescher and math.floor(sh * 0.1) or 0), false, nil)
		-- direita: assistente (caixa com borda azul, abaixo dos ícones do canto)
		-- assistente: fonte menor (tamanho fracionado) e mais alto, acima dos botões da direita
		local pxr = math.max(1, select(2, screen()) / 480)
		box(hud, rightLines, pxr, ox + sw - 2 * pxr, oy + math.floor(sh * 0.16), true, { 0.3, 0.6, 1 })
	end

	Runtime:addEventListener("enterFrame", function()
		local now = system.getTimer()
		if now - lastCheck > 1500 then
			lastCheck = now
			local ok, leftLines, rightLines = pcall(buildLines)
			if not ok then leftLines, rightLines = nil, nil end
			-- IA ao vivo: salva o estado pro script ia_assistente.py e mostra a resposta dele
			pcall(function()
				local st = {}
				for _, l in ipairs(leftLines or {}) do st[#st + 1] = "MISSAO " .. l[1] end
				for _, l in ipairs(rightLines or {}) do st[#st + 1] = "ASSIST " .. l[1] end
				local s = table.concat(st, "\n")
				if s ~= iaLastState then
					iaLastState = s
					local f = io.open(system.pathForFile("speedmod_estado.txt", system.DocumentsDirectory), "w")
					if f then f:write(s, "\n"); f:close() end
				end
				local f = io.open(system.pathForFile("speedmod_ia.txt", system.DocumentsDirectory), "r")
				if f then
					local ia = {}
					for l in f:lines() do if #ia < 3 and l ~= "" then ia[#ia + 1] = { l:upper(), { 0.6, 1, 0.6 } } end end
					f:close()
					if #ia > 0 then
						rightLines = rightLines or { { "ASSISTENTE", { 1, 0.7, 0.2 } } }
						for _, l in ipairs(ia) do rightLines[#rightLines + 1] = l end
					end
				end
			end)
			local sig = tostring(hudVisible)
			for _, l in ipairs(leftLines or {}) do sig = sig .. "|" .. l[1] end
			sig = sig .. "#"
			for _, l in ipairs(rightLines or {}) do sig = sig .. "|" .. l[1] end
			if sig ~= lastSig then
				lastSig = sig
				local okD, err = pcall(draw, leftLines, rightLines)
				if not okD then log("hud: " .. tostring(err)) end
			end
		end
		if hud then
			-- some quando o menu de pausa/loja do jogo está aberto
			local paused = false
			if type(pauseMenu) == "table" and type(pauseMenu.isCreated) == "function" then
				local okP, r = pcall(pauseMenu.isCreated, pauseMenu)
				paused = okP and r and true or false
			end
			if paused ~= lastPaused then
				lastPaused = paused
				local lvl
				pcall(function() lvl = inputHelper:getInputLevel() end)
				log("menu do jogo aberto=" .. tostring(paused) .. " nivel de input=" .. tostring(lvl))
			end
			pcall(setSuspended, paused)
			if paused and menu then pcall(closeMenu) end
			if menu then paused = true end
			if SPEEDMOD_SWAP_OPEN then paused = true end  -- tela de troca aberta: some
			if SPEEDMOD_POTENTIAL_OPEN then paused = true end  -- popup de Potencial: só a caixinha de pontos
			if SPEEDMOD_SKILLINFO_OPEN then paused = true end  -- detalhes do golpe abertos: some
			hud.isVisible = not paused
			hud.alpha = paused and 0 or 1
			if not paused and hud.toFront then hud:toFront() end
		end
		-- menu do jogo aberto: caixinha só com a troca de golpes sugerida
		local gamePaused = (lastPaused or SPEEDMOD_POTENTIAL_OPEN ~= nil) and not menu
		if gamePaused then
			if now - pauseCheck > 1000 then
				pauseCheck = now
				local ok, lines = pcall(function() return ASSIST.skillLines() end)
				if not ok then lines = nil end
				local sig = ""
				for _, l in ipairs(lines or {}) do sig = sig .. "|" .. l[1] end
				if sig ~= pauseSig then
					pauseSig = sig
					if pauseBox then pcall(function() pauseBox:removeSelf() end); pauseBox = nil end
					if hudVisible and lines and #lines > 0 then
						pcall(function()
							local px = math.max(1, math.floor(select(2, screen()) / 360))  -- fonte menor
							local sw, sh, _, _, ox, oy = screen()
							pauseBox = display.newGroup()
							box(pauseBox, lines, px, ox + sw - 2 * px, oy + math.floor(sh * 0.075), true, { 0.3, 0.6, 1 })
						end)
					end
				end
			end
			if pauseBox and pauseBox.toFront then pauseBox:toFront() end
		elseif pauseBox then
			pcall(function() pauseBox:removeSelf() end)
			pauseBox, pauseSig = nil, nil
		end
	end)

	Runtime:addEventListener("key", function(e)
		if e.keyName == "f7" and e.phase == "down" then
			hudVisible = not hudVisible
			lastCheck, lastSig = -10000, nil
			return true
		end
	end)
end
