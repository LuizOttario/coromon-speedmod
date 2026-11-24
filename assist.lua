---------------------------------------------------------------------------
-- Assistente: dicas automáticas, sem IA e sem internet.
--  * fora da batalha: próximo Titã (nível/tipo), pontos de potencial,
--    golpes melhores para equipar, Coromon machucado
--  * na batalha: melhor golpe contra o inimigo, perigo de tipo, troca
--  * captura nova: avalia o potencial (notificação no topo)
-- Tudo é lido do jogo com pcall; se algo falhar, a dica só não aparece.
---------------------------------------------------------------------------
do
	local function call(obj, method, ...)
		if type(obj) ~= "table" and type(obj) ~= "userdata" then return nil end
		local f = obj[method]
		if type(f) ~= "function" then return nil end
		local ok, r = pcall(f, obj, ...)
		if ok then return r end
		return nil
	end

	local function upper(s) return normalize(tostring(s or "")) end

	local function monUID(m) return call(m, "getUID") end
	local function monName(m)
		local n = call(m, "getDisplayName") or call(m, "getNickname")
		if type(n) ~= "string" or n == "" then
			local d = ASSIST_MON[monUID(m) or ""]
			n = d and d.n or "?"
		end
		return upper(n)
	end
	local function monType(m)
		local t = call(m, "getRandomizablePrimaryType")
		if type(t) == "table" then t = call(t, "getValue") or t.value end
		if type(t) == "string" and ASSIST_TYPE_PT[t] then return t end
		local d = ASSIST_MON[monUID(m) or ""]
		return d and d.t or "normal"
	end
	local function monLevel(m) return tonumber(call(m, "getLevel")) or 0 end
	-- Disco Lunar: poder = base + nível do usuário (skills/ghost/MOON_DISC.lua do jogo)
	local function skillPower(uid, m)
		return ASSIST_SKILL[uid].p + ((uid == "MOON_DISC") and monLevel(m) or 0)
	end
	local function hpFrac(m)
		local h, mx = tonumber(call(m, "getHealth")), tonumber(call(m, "getMaxHealth"))
		if h and mx and mx > 0 then return h / mx end
		return 1
	end
	local function selectedSkills(m)
		local s = call(m, "getSelectedSkillUIDs")
		return type(s) == "table" and s or {}
	end

	local function potentialText(p)
		if not p then return "POT ?" end
		if p >= 21 then return "POT 21/21 PERFEITO" end
		if p >= 17 then return "POT " .. p .. "/21 POTENTE" end
		if p >= 12 then return "POT " .. p .. "/21 BOM" end
		if p >= 7 then return "POT " .. p .. "/21 MEDIO" end
		return "POT " .. p .. "/21 FRACO"
	end
	local function typeMult(atk, def)
		local row = ASSIST_CHART[atk]
		if not row then return 1 end
		if row[def] == true then return 2 end
		if row[def] == false then return 0.5 end
		return 1
	end
	local function typeName(t) return upper(ASSIST_TYPE_PT[t] or t) end

	-- pontuação de um golpe do Coromon m contra um alvo do tipo defType
	local function skillScore(m, skillUID, defType)
		local s = ASSIST_SKILL[skillUID]
		if not s or s.c == "x" or s.p <= 0 then return 0, 1 end
		local d = ASSIST_MON[monUID(m) or ""] or { a = 100, s = 100 }
		local stat = s.c == "p" and d.a or d.s
		local stab = (s.t == monType(m)) and 1.5 or 1
		local mult = defType and typeMult(s.t, defType) or 1
		return skillPower(skillUID, m) * stat / 100 * stab * mult, mult
	end

	local function squad()
		local ok, sq = pcall(function() return playerMonsters:getSquad() end)
		if ok and type(sq) == "table" then return sq end
		return {}
	end

	-- Spinners que mandam o Coromon pro time (todos menos o Insano)
	local function normalSpinners()
		local total = 0
		for _, uid in ipairs({ "SPINNER_REGULAR_1", "SPINNER_REGULAR_2", "SPINNER_REGULAR_3", "SPINNER_REGULAR_4",
			"SPINNER_ELEMENT_NORMAL", "SPINNER_ELEMENT_GHOST", "SPINNER_ELEMENT_ELECTRIC", "SPINNER_ELEMENT_SAND",
			"SPINNER_ELEMENT_FIRE", "SPINNER_ELEMENT_ICE", "SPINNER_ELEMENT_WATER", "SPINNER_SURPRISE",
			"SPINNER_DREAM", "SPINNER_HEAL" }) do
			-- o jogo espera um objeto de item (ele chama _item:getUID())
			local ok, n = pcall(function() return playerInventory:getAmount({ getUID = function() return uid end }) end)
			if ok and tonumber(n) then total = total + tonumber(n) end
		end
		return total
	end
	ASSIST.normalSpinners = normalSpinners

	-----------------------------------------------------------------------
	-- Quiz/perguntas: o jogo marca a resposta certa como "<pergunta>.answers.N.correct".
	-- Embrulhamos a função de textos do jogo (localise) e, quando ela busca o texto
	-- de uma pergunta, procuramos a resposta correta correspondente.
	-----------------------------------------------------------------------
	local quizAnswer, quizUntil = nil, 0
	local origLocalise, wrappedLocalise
	local function findAnswer(key)
		for _, base in ipairs({ key:match("^(.+)%.%d+$") or false, key }) do
			if base then
				for i = 1, 6 do
					local k = base .. ".answers." .. i .. ".correct"
					local ok, txt = pcall(origLocalise, k)
					if ok and type(txt) == "string" and txt:find("%a%a") and txt ~= k and not txt:find("answers", 1, true) then
						return txt
					end
				end
			end
		end
	end
	local function wrapLocalise()
		if type(localise) ~= "function" or localise == wrappedLocalise then return end
		origLocalise = localise
		local inside = false
		-- devolve exatamente o que o original devolveu: o jogo faz table.insert(t, 1, localise(...))
		-- e valores a mais quebram a mochila (itemScreen.lua:462)
		local function quiz(key, ...)
			if not inside and type(key) == "string" and (key:find("%.%d+$") or key:find("question%d+$")) and not key:find("answers", 1, true) then
				inside = true
				local ok, ans = pcall(findAnswer, key)
				inside = false
				if ok and ans then
					quizAnswer, quizUntil = ans, system.getTimer() + 90000
					log("quiz: resposta = " .. ans .. " (" .. key .. ")")
				end
			end
			return ...
		end
		wrappedLocalise = function(key, ...)
			return quiz(key, origLocalise(key, ...))
		end
		localise = wrappedLocalise
		log("textos do jogo embrulhados (ajuda com perguntas)")
	end
	function ASSIST.quizLines()
		pcall(wrapLocalise)
		if ASSIST_ORDERS and quizAnswer and system.getTimer() < quizUntil then
			return { { "PERGUNTA NA TELA!", ORANGE }, { "RESPOSTA: " .. upper(quizAnswer), GREEN } }
		end
	end

	-----------------------------------------------------------------------
	-- Batalha
	-----------------------------------------------------------------------
	local battleDiag = {}
	local function diag(key, msg)
		if not battleDiag[key] then battleDiag[key] = true; log("batalha: " .. msg) end
	end
	-- a figura de batalha guarda o Coromon em .monster e o lado em .team
	local function unwrap(sp)
		if type(sp) == "table" and type(sp.monster) == "table" then return sp.monster end
		return sp
	end
	local function asList(t)
		if type(t) ~= "table" then return {} end
		local out = {}
		for _, v in pairs(t) do out[#out + 1] = v end
		return out
	end
	local foeSprite, mySprite
	local function currentBattleSprites()
		if type(Battle) ~= "table" then diag("noBattle", "global Battle ausente"); return nil end
		local b = call(Battle, "get")
		if not b then return nil end  -- fora da batalha
		local mine = asList(call(b, "getMonsterSpritesInBattle", "player"))
		local enemies = asList(call(b, "getMonsterSpritesInBattle", "enemy"))
		if #mine == 0 or #enemies == 0 then
			-- outro caminho: todos os sprites + getIsEnemy
			local all = asList(call(b, "getMonsterSpritesInBattle"))
			if #all == 0 then all = asList(call(b, "getAllMonsterSprites")) end
			mine, enemies = {}, {}
			for _, sp in ipairs(all) do
				local enemy = call(sp, "getIsEnemy")
				if enemy == nil and type(sp) == "table" then enemy = (sp.team == "enemy") or sp.isEnemy end
				if enemy then enemies[#enemies + 1] = sp else mine[#mine + 1] = sp end
			end
		end
		if #mine == 0 or #enemies == 0 then
			diag("empty", "batalha sem sprites (meus=" .. #mine .. " inimigos=" .. #enemies .. ")")
			return nil
		end
		local anyAlive = false
		foeSprite = enemies[1]  -- o sprite sabe o participante (treinador/selvagem); o Coromon não
		mySprite = mine[1]
		for i, e in ipairs(enemies) do enemies[i] = unwrap(e) end
		for i, m in ipairs(mine) do mine[i] = unwrap(m) end
		for _, e in ipairs(enemies) do
			if call(e, "isAlive") ~= false and call(e, "isFainted") ~= true then anyAlive = true end
		end
		local phase = tostring(call(b, "getPhase"))
		diag("phase" .. phase, "fase=" .. phase .. " visivel=" .. tostring(call(b, "isVisible")))
		if not anyAlive then return nil end
		diag("ok", "batalha lida: meus=" .. #mine .. " inimigos=" .. #enemies)
		return mine, enemies
	end

	local function multText(mult)
		if mult >= 2 then return "SUPER EFETIVO" elseif mult < 1 then return "POUCO EFETIVO" end
		return "NORMAL"
	end

	-- flag global usada pelo speedmod.lua (trava de 1X sempre ativa em batalha)
	do
		local last = 0
		Runtime:addEventListener("enterFrame", function()
			local now = system.getTimer()
			if now - last < 200 then return end
			last = now
			local ok, mine = pcall(currentBattleSprites)
			SPEEDMOD_IN_BATTLE = ok and mine ~= nil or false
		end)
	end

	-- chance de aparecer no mapa: no mato e com a isca (que só atrai famílias que você ainda não tem)
	-- os 3 iniciais têm conquista de captura: se um que falta aparece no mapa, ele vira o alvo
	local STARTERS = { "ICE_BEAR", "FIRE_TURTLE", "WATER_SHARK" }
	function ASSIST.starterHere(mapFile)
		local enc = mapFile and ASSIST_MAPENC and ASSIST_MAPENC[mapFile]
		if not enc then return nil end
		for _, f in ipairs(STARTERS) do
			if enc[f] and not ownedFamilies[f] then return f end
		end
	end
	function ASSIST.encPct(mapFile, fam)
		local enc = mapFile and ASSIST_MAPENC and ASSIST_MAPENC[mapFile]
		if not (enc and fam and enc[fam]) then return nil end
		local tot, totLure = 0, 0
		for f, w in pairs(enc) do
			tot = tot + w
			if not ownedFamilies[f] or f == fam then totLure = totLure + w end
		end
		return math.floor(enc[fam] / tot * 100 + 0.5), math.floor(enc[fam] / math.max(totLure, 0.001) * 100 + 0.5)
	end
	function ASSIST.battleLines()
		local mine, enemies = currentBattleSprites()
		if not mine then return nil end
		local out = {}
		local me = mine[1]
		local foe = enemies[1]
		local foeType, myType = monType(foe), monType(me)
		out[#out + 1] = { "VS " .. monName(foe) .. " NV" .. monLevel(foe) .. " (" .. typeName(foeType) .. ")", WHITE }

		-- Coromon selvagem: vale capturar?
		local foeUID = monUID(foe)
		local foeData = ASSIST_MON[foeUID or ""]
		local foeFam = foeData and foeData.f
		local okT, isTrainer = pcall(function()
			-- como o jogo faz (AIScore.lua:126): Battle:getBattleParticipant(sprite:getTeam())
			local team = call(foeSprite, "getTeam") or "enemy"
			local p = (team ~= nil and call(Battle, "getBattleParticipant", team))
				or call(foeSprite, "getBattleParticipant") or call(foeSprite, "getParticipant")
			-- treinador: botão de fuga vira "forfeit" (bandeira); Titã também não se captura
			local esc = p and call(p, "getPlayerEscapeButtonMode")
			local r = p and (esc == "forfeit" or type(p.showTrainerMonsterIndicator) == "function"
				or type(p.getSpeakerName) == "function" or type(p.isTitan) == "function") or false
			diag("trainer" .. tostring(monUID(foe)), "adversario: time=" .. tostring(team) .. " participante=" .. tostring(p ~= nil)
				.. " fuga=" .. tostring(esc) .. " treinador=" .. tostring(r))
			return r
		end)
		local pot = tonumber(call(foe, "getPotential"))
		-- teste final do Sensei (Spinners do Sensei pegam qualquer um): quem vence o time dele
		local SENSEI_PICK = { ELECTRIC_CERBERUS = "VENCE ATLANTERN (AGUA)", FIRE_MAGMA = "VENCE ARCTUROS (GELO)",
			FIRE_BULL = "VENCE ARCTUROS (GELO)", WATER_SWAMP = "VENCE RUPTIUS (FOGO)" }
		if SENSEI_QUEST and foeFam and not (okT and isTrainer) then
			local why = SENSEI_PICK[foeFam]
			out[#out + 1] = why and { "SENSEI: CAPTURE! " .. why, GREEN } or { "SENSEI: NAO E DOS 3 INDICADOS", ORANGE }
		elseif foeFam and not (okT and isTrainer) then
			local mapFile
			pcall(function() mapFile = worldHelper:getMapFile() end)
			local target = mapFile and (ASSIST.starterHere(mapFile) or (ROUTE_TARGET_FAM and ROUTE_TARGET_FAM[mapFile]))
			if ownedFamilies[foeFam] then
				out[#out + 1] = { "JA TEM ESSA FAMILIA", GREY }
			elseif pot and pot >= 21 then
				out[#out + 1] = { "PERFEITO! CAPTURE", GREEN }
			elseif mapFile and lureDone(mapFile) then
				if target == foeFam then
					out[#out + 1] = { "ALVO DA ROTA! CAPTURE", GREEN }
				elseif target and not ownedFamilies[target] then
					local txt = ROUTE_TARGET and ROUTE_TARGET[mapFile] or ""
					local tname = txt:match(":%s*(%S+)") or target
					out[#out + 1] = { "NAO E O ALVO (" .. upper(tname) .. ")", ORANGE }
				else
					out[#out + 1] = { "PODE CAPTURAR", GREEN }
				end
			elseif mapFile then
				out[#out + 1] = { "NORMAL: SO CAPTURA PERFEITO", ORANGE }
			end
			-- chance de aparecer neste mapa (como a isca: sem as famílias que você já tem)
			local pMapa, pIsca = ASSIST.encPct(mapFile, foeFam)
			if pMapa then out[#out + 1] = { "MATO " .. pMapa .. "% / ISCA " .. pIsca .. "%", WHITE } end
			if foeData.r then
				out[#out + 1] = { foeData.r .. ((foeData.n == foeData.fn) and ", FORMA FINAL (" or (", VIRA " .. upper(foeData.fn) .. " (")) .. foeData.tier .. ")",
					foeData.tier == "FORTE" and GREEN or WHITE }
			end
			if pot then
				out[#out + 1] = { potentialText(pot), pot >= 12 and GREEN or WHITE }
			end
			local traitUID = call(foe, "getTraitUID")
			local tr = traitUID and ASSIST_TRAIT and ASSIST_TRAIT[traitUID]
			if tr then
				local chance = ASSIST_FAMTRAITS and ASSIST_FAMTRAITS[foeFam] and ASSIST_FAMTRAITS[foeFam][traitUID]
				local rar = chance and (chance <= 15 and "RARO" or (chance <= 25 and "INCOMUM" or "COMUM")) or "?"
				local best = ASSIST_FAMBEST and ASSIST_FAMBEST[foeFam]
				local isBest = best == traitUID or (best and ASSIST_TRAIT[best] and ASSIST_TRAIT[best].s <= (tr.s or 2))
				out[#out + 1] = { "TRACO " .. upper(tr.n) .. (chance and (" " .. chance .. "%") or "") .. (isBest and " (MELHOR)" or ""),
					isBest and GREEN or WHITE }
				if not isBest and best and ASSIST_TRAIT[best] then
					out[#out + 1] = { "MELHOR: " .. upper(ASSIST_TRAIT[best].n) .. " " .. ASSIST_FAMTRAITS[foeFam][best] .. "%", ORANGE }
				end
			end
			local catchable = (mapFile and lureDone(mapFile)) or (pot and pot >= 21)
			if catchable and not ownedFamilies[foeFam] then
				if normalSpinners() == 0 then
					out[#out + 1] = { "SEM SPINNER NORMAL! O INSANO NAO VAI PRO TIME", ORANGE }
				end
			end
			if catchable and not ownedFamilies[foeFam] then
				local verdict, col
				local target = mapFile and (ASSIST.starterHere(mapFile) or (ROUTE_TARGET_FAM and ROUTE_TARGET_FAM[mapFile]))
				local _, altFam = routeAlt(mapFile or "", ownedFamilies)
				local isAlt = altFam == foeFam
				if target == foeFam then
					verdict, col = "VALE PEGAR (ALVO)", GREEN
				elseif isAlt and target and ownedFamilies[target] then
					verdict, col = "PEGUE: MELHOR QUE SOBROU", GREEN
				elseif foeData.tier == "FORTE" and (pot or 0) >= 12 then
					verdict, col = "VALE PEGAR", GREEN
				elseif foeData.tier == "FRACO" or (pot or 21) <= 6 then
					verdict, col = "NAO COMPENSA", ORANGE
				else
					verdict, col = "SERVE COMO RESERVA", WHITE
				end
				out[#out + 1] = { verdict, col }
			end
		end

		-- melhor golpe equipado
		local best, bestScore, bestMult = nil, 0, 1
		for _, uid in ipairs(selectedSkills(me)) do
			local sc, mult = skillScore(me, uid, foeType)
			if sc > bestScore then best, bestScore, bestMult = uid, sc, mult end
		end
		-- Dano estimado pela fórmula do jogo (skillMoveUtility.calculateDamageForPower) com os
		-- status reais de batalha, no pior sorteio (x0,85) para não errar a favor no Insano.
		local function estDamage(atkSp, atkMon, atkType, defSp, defType, uid)
			local sk = ASSIST_SKILL[uid]
			if not sk or sk.c == "x" or sk.p <= 0 then return nil end
			local spc = sk.c == "s"
			local atk = tonumber(call(atkSp, "calculateStatInBattle", spc and "specialAttack" or "attack"))
			local def = tonumber(call(defSp, "calculateStatInBattle", spc and "specialDefense" or "defense"))
			local lvl = tonumber(monLevel(atkMon))
			if not (atk and def and lvl) then return nil end
			local dmg = ((2 + 2 * lvl / 5) * skillPower(uid, atkMon) * math.max(1, atk) / math.max(1, def) / 50 + 2) * 0.85
			return dmg * ((sk.t == atkType) and 1.5 or 1) * typeMult(sk.t, defType)
		end
		local foeHP, myHP = tonumber(call(foe, "getHealth")), tonumber(call(me, "getHealth"))
		local myPE, myMaxPE = tonumber(call(me, "getEnergy")), tonumber(call(me, "getMaxEnergy"))
		-- golpes: dano estimado e se dá para pagar
		local kill, bestPay, bestAll
		for _, uid in ipairs(selectedSkills(me)) do
			local okD, d = pcall(estDamage, mySprite, me, myType, foeSprite, foeType, uid)
			local e = ASSIST_SKILL[uid] and ASSIST_SKILL[uid].e or 99
			if okD and d then
				local pay = not myPE or e <= myPE
				if pay and foeHP and d >= foeHP and (not kill or e < kill.e or (e == kill.e and d > kill.d)) then
					kill = { uid = uid, e = e, d = d }
				end
				if pay and (not bestPay or d > bestPay.d) then bestPay = { uid = uid, e = e, d = d } end
				if not bestAll or d > bestAll.d then bestAll = { uid = uid, e = e, d = d } end
			end
		end
		-- o quanto o inimigo bate em mim por turno (melhor golpe dele)
		local foeHit = 0
		for _, uid in ipairs(selectedSkills(foe)) do
			local okD, d = pcall(estDamage, foeSprite, foe, foeType, mySprite, myType, uid)
			if okD and d and d / 0.85 > foeHit then foeHit = d / 0.85 end  -- melhor sorteio dele
		end
		local restPE = myMaxPE and math.floor(myMaxPE / 2) or nil
		if not ASSIST_ORDERS then
			-- modo "só informações": sem dizer qual golpe usar nem quando descansar
			if myPE and bestAll and not bestPay then out[#out + 1] = { "SEM PE PARA ATACAR", ORANGE } end
		elseif kill then
			out[#out + 1] = { "USE " .. upper(ASSIST_SKILL[kill.uid].n) .. " (DERRUBA, " .. kill.e .. " PE)", GREEN }
		elseif myPE and bestAll and not bestPay then
			local risky = myHP and foeHit >= myHP
			out[#out + 1] = { "SEM PE! DESCANSE" .. (restPE and (" (+" .. restPE .. " PE)") or "") .. (risky and " OU TROQUE" or ""),
				ORANGE }
		elseif myPE and bestAll and bestPay and bestAll.uid ~= bestPay.uid and myHP and foeHit < myHP * 0.35
			and bestAll.d >= bestPay.d * 1.5 then
			out[#out + 1] = { "DESCANSE: DEPOIS USE " .. upper(ASSIST_SKILL[bestAll.uid].n), ORANGE }
		elseif bestPay or best then
			local u = (bestPay and bestPay.uid) or best
			out[#out + 1] = { "USE " .. upper(ASSIST_SKILL[u].n) .. (bestMult >= 2 and u == best and " (2X)" or (bestMult < 1 and u == best and " (FRACO)" or "")),
				(bestMult >= 2 and u == best) and GREEN or WHITE }
		end
		if myHP and foeHit >= myHP then
			out[#out + 1] = { "PERIGO: ELE PODE TE DERRUBAR", ORANGE }
		end

		-- perigo e troca
		local danger = typeMult(foeType, myType) >= 2
		local lvlGap = monLevel(foe) - monLevel(me)
		if danger then
			out[#out + 1] = { "CUIDADO: " .. typeName(foeType) .. " TE VENCE", ORANGE }
		end
		if lvlGap >= 4 then
			out[#out + 1] = { "INIMIGO +" .. lvlGap .. " NIVEIS", ORANGE }
		end
		if danger or bestMult < 1 or hpFrac(me) < 0.25 then
			local pick, pickScore = nil, 0
			for _, m in ipairs(squad()) do
				if m ~= me and call(m, "isAlive") ~= false and hpFrac(m) > 0.3
					and typeMult(foeType, monType(m)) < 2 then
					local sc = 0
					for _, uid in ipairs(selectedSkills(m)) do
						sc = math.max(sc, (skillScore(m, uid, foeType)))
					end
					if sc > pickScore then pick, pickScore = m, sc end
				end
			end
			if pick and pickScore > bestScore * 1.2 then
				if ASSIST_ORDERS then out[#out + 1] = { "TROQUE: " .. monName(pick), GREEN } end
			elseif hpFrac(me) < 0.25 then
				out[#out + 1] = { "VIDA BAIXA: CURE/TROQUE", ORANGE }
			end
		end
		return out
	end

	-----------------------------------------------------------------------
	-- Fora da batalha
	-----------------------------------------------------------------------
	local function nextTitan()
		for _, t in ipairs(ASSIST_TITANS or {}) do
			if not achDone(t.ach) then return t end
		end
	end

	local function teamLevel(sq)
		local lv = {}
		for _, m in ipairs(sq) do lv[#lv + 1] = monLevel(m) end
		table.sort(lv, function(a, b) return a > b end)
		local n, sum = math.min(3, #lv), 0
		for i = 1, n do sum = sum + lv[i] end
		return n > 0 and math.floor(sum / n) or 0
	end

	local function hasGoodType(sq, goods)
		for _, m in ipairs(sq) do
			for _, uid in ipairs(selectedSkills(m)) do
				local s = ASSIST_SKILL[uid]
				if s and s.c ~= "x" then
					for _, g in ipairs(goods) do if s.t == g then return true end end
				end
			end
		end
		return false
	end

	-- golpe que vale trocar: aprendível no nível atual, mais forte que o pior golpe de dano equipado
	local function skillUpgrade(m)
		local d = ASSIST_MON[monUID(m) or ""]
		if not d then return nil end
		local list = ASSIST_FAMSKILLS[d.f]
		if not list then return nil end
		local lvl = monLevel(m)
		local sel, selSet = selectedSkills(m), {}
		for _, u in ipairs(sel) do selSet[u] = true end
		local worst, worstScore = nil, math.huge
		for _, u in ipairs(sel) do
			local sc = skillScore(m, u, nil)
			if sc > 0 and sc < worstScore then worst, worstScore = u, sc end
		end
		local best, bestScore = nil, 0
		for _, e in ipairs(list) do
			local u, at = e[1], e[2]
			if at <= lvl and not selSet[u] then
				local sc = skillScore(m, u, nil)
				if sc > bestScore then best, bestScore = u, sc end
			end
		end
		if best and (#sel < 4 or (worst and bestScore > worstScore * 1.15)) then
			return best, (#sel < 4) and nil or worst
		end
	end

	local function potentialAdvice(m)
		local undist = tonumber(call(m, "getAmountOfPotentialStatsUndistributed")) or 0
		if undist <= 0 then return nil end
		-- pelo que a espécie é mais forte (status base da forma final), não pelos golpes ativos
		local cur = ASSIST_MON[monUID(m) or ""] or { a = 1, s = 1 }
		local d = cur
		for _, x in pairs(ASSIST_MON) do
			if x.f == cur.f and x.n == cur.fn then d = x; break end
		end
		-- longo prazo: status da forma final × melhor golpe que a família aprende em cada categoria
		-- (golpe do mesmo tipo vale 1,5x). Ganha o lado que rende mais dano no fim do jogo.
		local best = { p = 0, s = 0 }
		for _, e in ipairs((ASSIST_FAMSKILLS and ASSIST_FAMSKILLS[cur.f]) or {}) do
			local sk = ASSIST_SKILL[e[1]]
			if sk and best[sk.c] then
				local pw = sk.p * ((sk.t == d.t) and 1.5 or 1)
				if pw > best[sk.c] then best[sk.c] = pw end
			end
		end
		local phys, spec = d.a * best.p, d.s * best.s
		-- Garras afiadas: golpes de contato (quase todos os físicos) +15%
		if call(m, "getTraitUID") == "SHARP_CLAWS" then phys = phys * 1.15 end
		if phys == spec then phys, spec = cur.a, cur.s end
		-- o jogo limita 60 pontos por status: cheio, passa para o próximo (velocidade, depois vida)
		local order = (spec > phys) and { { "specialAttack", "ATAQUE ESP." }, { "speed", "VELOCIDADE" }, { "hp", "PV" },
			{ "attack", "ATAQUE" }, { "specialDefense", "DEFESA ESP." }, { "defense", "DEFESA" } }
			or { { "attack", "ATAQUE" }, { "speed", "VELOCIDADE" }, { "hp", "PV" },
			{ "specialAttack", "ATAQUE ESP." }, { "defense", "DEFESA" }, { "specialDefense", "DEFESA ESP." } }
		for _, o in ipairs(order) do
			local used = tonumber(call(m, "getPotentialStat", o[1]))
			if not used or used < 60 then return undist, o[2] end
		end
		return undist, order[1][2]
	end

	-- dicas de troca de golpe de toda a equipe (mostradas com o menu do jogo aberto)
	function ASSIST.skillLines()
		local out = {}
		-- Pedra Maca/Peca bloqueiam golpes de status: avisar se o Coromon tem um ativo
		for _, m in ipairs(squad()) do
			local item = tostring(call(m, "getHoldItemUID") or "")
			if item:find("DISABLE_STATUS_SKILLS", 1, true) then
				for _, u in ipairs(selectedSkills(m)) do
					local sk = ASSIST_SKILL[u]
					if sk and sk.c == "x" then
						out[#out + 1] = { monName(m) .. ": PEDRA BLOQUEIA " .. upper(sk.n), ORANGE }
						break
					end
				end
			end
		end
		for _, m in ipairs(squad()) do
			local new, old = skillUpgrade(m)
			if new then
				out[#out + 1] = { monName(m) .. ": ATIVE " .. upper(ASSIST_SKILL[new].n), { 1, 1, 1 } }
				if old then
					out[#out + 1] = { "  NO LUGAR DE " .. upper(ASSIST_SKILL[old].n), { 0.75, 0.75, 0.8 } }
				end
			end
			if #out >= 6 then break end
		end
		-- pontos de potencial (o menu do jogo esconde a caixa do mapa, onde essa dica fica)
		for _, m in ipairs(squad()) do
			local n, stat = potentialAdvice(m)
			if n and #out < 8 then out[#out + 1] = { monName(m) .. ": " .. n .. " PTS EM " .. stat, { 0.6, 1, 0.6 } } end
		end
		if #out > 0 then table.insert(out, 1, { "ASSISTENTE", { 0.45, 0.75, 1 } }) end
		return out
	end

	-- máquinas que ficam com o Coromon até você andar N passos (Potencializador, Traçoformador...)
	local STEP_MACHINES = {
		{ "potentialRerollWorldEffect", "POTENCIALIZADOR" },
		{ "traitRerollWorldEffect", "TRACOFORMADOR" },
		{ "potentialStatSoftResetWorldEffect", "RESET DE PONTOS" },
		{ "spinnerSwapWorldEffect", "TROCA DE SPINNER" },
	}
	local function stepMachineLines(out)
		local effects = call(playerSettings, "getSaveableBattleEffects")
		local steps = tonumber(call(playerStats, "getSteps"))
		if type(effects) ~= "table" or not steps then return end
		for _, eff in pairs(effects) do
			local cls = type(eff) == "table" and type(eff.classes) == "table" and eff.classes or {}
			if cls.abstractUpgradeMonsterAfterPlayerStepsWorldEffect then
				local label = "MAQUINA"
				for _, sm in ipairs(STEP_MACHINES) do if cls[sm[1]] then label = sm[2] end end
				local m = call(eff, "getMonster")
				local who = m and (" (" .. monName(m) .. ")") or ""
				local left = (tonumber(call(eff, "getTargetPlayerSteps")) or steps) - steps
				if left > 0 then
					out[#out + 1] = { label .. who .. ": FALTAM " .. math.ceil(left) .. " PASSOS", WHITE }
				else
					out[#out + 1] = { label .. who .. ": PRONTO! VA BUSCAR", GREEN }
				end
			end
		end
	end

	function ASSIST.overworldLines()
		local out = {}
		pcall(stepMachineLines, out)
		if normalSpinners() == 0 then
			out[#out + 1] = { "SEM SPINNER NORMAL: COMPRE NA LOJA", ORANGE }
		end
		local sq = squad()
		local t = nextTitan()
		if t and #sq > 0 then
			local lv = teamLevel(sq)
			local goods = {}
			for _, g in ipairs(t.good) do goods[#goods + 1] = typeName(g) end
			if lv < t.lvl - 3 then
				out[#out + 1] = { upper(t.n) .. " NV" .. t.lvl .. ": TREINE (TIME " .. lv .. ")", ORANGE }
			else
				out[#out + 1] = { "PRONTO P/ " .. upper(t.n) .. " (TIME " .. lv .. ")", GREEN }
			end
			if not hasGoodType(sq, t.good) then
				out[#out + 1] = { "FALTA GOLPE " .. table.concat(goods, "/"), ORANGE }
			end
		end
		for _, m in ipairs(sq) do
			local n, stat = potentialAdvice(m)
			if n then
				out[#out + 1] = { monName(m) .. ": " .. n .. " PTS EM " .. stat, GREEN }
				break
			end
		end
		for _, m in ipairs(sq) do
			local new, old = skillUpgrade(m)
			if new then
				local txt = monName(m) .. ": EQUIPE " .. upper(ASSIST_SKILL[new].n)
				if old then txt = txt .. " NO LUGAR DE " .. upper(ASSIST_SKILL[old].n) end
				out[#out + 1] = { txt, WHITE }
				break
			end
		end
		for _, m in ipairs(sq) do
			local f = hpFrac(m)
			if f < 0.4 and call(m, "isAlive") ~= false then
				out[#out + 1] = { "CURE " .. monName(m) .. " (" .. math.floor(f * 100) .. "%)", ORANGE }
				break
			end
		end
		return out
	end

	-----------------------------------------------------------------------
	-- Captura nova: avalia o potencial
	-----------------------------------------------------------------------
	local knownIds, lastCapCheck = nil, 0
	Runtime:addEventListener("enterFrame", function()
		local now = system.getTimer()
		if now - lastCapCheck < 2000 then return end
		lastCapCheck = now
		local ok, list = pcall(function() return playerMonsters:getOwnedMonstersIncludingMonsterGraveyard() end)
		if not ok or type(list) ~= "table" then return end
		local ids = {}
		for _, m in pairs(list) do
			local id = call(m, "getIdentifier")
			if id ~= nil then ids[tostring(id)] = m end
		end
		local newOnes, known = {}, 0
		if knownIds then
			for _ in pairs(knownIds) do known = known + 1 end
			for id, m in pairs(ids) do
				if not knownIds[id] then newOnes[#newOnes + 1] = m end
			end
		end
		-- lista vazia antes (tela de título) ou muitos de uma vez (save carregado): só vira a base
		if knownIds and known > 0 and #newOnes <= 2 then
			for _, m in ipairs(newOnes) do
				if notifyToast then
					local inInsane = false
					local okI, ins = pcall(function() return playerMonsters:getInsaneSpinnerSquad() end)
					if okI and type(ins) == "table" then
						for _, x in pairs(ins) do if x == m then inInsane = true end end
					end
					if inInsane then
						notifyToast("FOI PRO SPINNER INSANO: SO PARA MISSOES, NAO LUTA",
							"CAPTUROU " .. monName(m) .. " NV" .. monLevel(m))
					else
						local p = tonumber(call(m, "getPotential"))
						notifyToast(potentialText(p), "CAPTUROU " .. monName(m) .. " NV" .. monLevel(m))
						local tu = call(m, "getTraitUID")
						local tr = tu and ASSIST_TRAIT and ASSIST_TRAIT[tu]
						if tr then notifyToast(upper(tr.n), "TRACO DO " .. monName(m)) end
					end
				end
			end
		end
		knownIds = ids
	end)
end

---------------------------------------------------------------------------

---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Overlays do jogo que o HUD precisa saber se estão abertos (guarda a hora em que abriu):
--  * popup de Potencial (ao subir de nível, inclusive em batalha): mostra a dica de pontos
--  * TallMonsterButtonOverlay ("Trocar X por:"): esconde a caixa do assistente
---------------------------------------------------------------------------
do
	local HOOKS = {
		{ mod = "classes.interface.battle.AbstractPotentialStatsOverlay", flag = "SPEEDMOD_POTENTIAL_OPEN" },
		{ mod = "classes.interface.overlays.TallMonsterButtonOverlay", flag = "SPEEDMOD_SWAP_OPEN" },
		-- detalhes do golpe (tecla F / segurar no painel de golpes): o assistente tampava o texto
		{ mod = "classes.interface.battle.BattleHeldSkillDetailsPopupBuilder", flag = "SPEEDMOD_SKILLINFO_OPEN", open = "show", close = "hide", ttl = 20000 },
	}
	local lastCheck = 0
	Runtime:addEventListener("enterFrame", function()
		local now = system.getTimer()
		for _, h in ipairs(HOOKS) do
			if _G[h.flag] and now - _G[h.flag] > (h.ttl or 120000) then _G[h.flag] = nil end  -- segurança
		end
		if now - lastCheck < 1000 then return end
		lastCheck = now
		for _, h in ipairs(HOOKS) do
			local m = package.loaded[h.mod]
			if type(m) == "table" and type(m.new) == "function" and m.new ~= h.wrapped then
				local orig = m.new
				h.wrapped = function(...)
					local o = orig(...)
					pcall(function()
						local openK = h.open or "open"
						for _, k in ipairs({ openK, h.close or "close" }) do
							local f = o[k]
							if type(f) == "function" then
								o[k] = function(...)
									_G[h.flag] = (k == openK) and system.getTimer() or nil
									return f(...)
								end
							end
						end
					end)
					return o
				end
				m.new = h.wrapped
				log("overlay observado: " .. h.mod)
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Lembrar o último golpe: o painel de golpes começa no golpe guardado em
-- monsterSprite:getMostRecentBeforeSkillData(). Antes de montar o painel,
-- guardamos ali o último golpe que o Coromon usou.
---------------------------------------------------------------------------
do
	local MOD = "classes.interface.battle.oneStepActionsPanelBuilder"
	local wrappedNew, lastCheck, loggedFocus = nil, 0, false
	local lastSkillByMon = {}
	LEMBRAR_GOLPE = false   -- true liga a memória do último golpe (cursor)
	local guard, guardActed = nil, false
	local GUARD_MS, LEAK_MS = 600, 350
	local DIRS = { up = true, down = true, left = true, right = true, w = true, a = true, s = true, d = true }
	-- tecla nova = você agindo; direções logo no começo são "vazamento" da caminhada
	Runtime:addEventListener("key", function(e)
		if guard and e.phase == "down" then
			local k = tostring(e.keyName)
			if not DIRS[k] or system.getTimer() - guard.t0 > LEAK_MS then guardActed = true end
		end
		-- diagnóstico: teclas com o painel de golpes aberto (até o golpe ser escolhido)
		local p = SPEEDMOD_PANEL_DIAG
		if p and e.phase == "down" and system.getTimer() - p.t0 < 20000 then
			local cur = "?"
			pcall(function() cur = tostring(p.nav:getSelectedIndex()) end)
			log("painel de golpes: tecla " .. tostring(e.keyName) .. " com cursor em " .. cur .. " [" .. SPEEDMOD_INPUT_STATE() .. "] (" ..
				math.floor(system.getTimer() - p.t0) .. " ms)")
		end
		return false
	end)
	Runtime:addEventListener("enterFrame", function()
		local g = guard
		if not g then return end
		if guardActed or system.getTimer() - g.t0 > GUARD_MS then guard = nil; return end
		pcall(function()
			if g.nav:getSelectedIndex() ~= g.idx then g.nav:setSelectedIndex(g.idx, false) end
		end)
	end)
	-- Destrava: com o painel de golpes aberto, se o jogo ficar com a entrada
	-- bloqueada (inputHelper:blockInput sem o unblockInput correspondente) por
	-- mais de 0,8 s, o A/espaço não usa o golpe e só o cursor anda. Desbloqueia.
	local blockedSince, unblocks = nil, 0
	Runtime:addEventListener("enterFrame", function()
		if not (SPEEDMOD_PANEL_OPEN == true and SPEEDMOD_IN_BATTLE == true) then blockedSince = nil; return end
		pcall(function()
			local lvl = inputHelper:getInputLevel()
			if inputHelper:isInputBlocked(lvl) then
				local now = system.getTimer()
				blockedSince = blockedSince or now
				if now - blockedSince > 800 then
					inputHelper:unblockInput()
					blockedSince = nil
					unblocks = unblocks + 1
					log("painel de golpes: entrada estava travada (nivel " .. tostring(lvl) .. "), destravei (" .. unblocks .. "x)")
				end
			else
				blockedSince = nil
			end
		end)
	end)
	SPEEDMOD_INPUT_STATE = function()
		local r = "?"
		pcall(function()
			local lvl = inputHelper:getInputLevel()
			r = "nivel " .. tostring(lvl) .. " bloqueado=" .. tostring(inputHelper:isInputBlocked(lvl))
		end)
		return r
	end
	Runtime:addEventListener("enterFrame", function()
		local now = system.getTimer()
		if now - lastCheck < 1000 then return end
		lastCheck = now
		local m = package.loaded[MOD]
		if type(m) ~= "table" or type(m.new) ~= "function" or m.new == wrappedNew then return end
		local orig = m.new
		wrappedNew = function(self, container, options, ...)
			local panel = orig(self, container, options, ...)
			pcall(function()
				local sp = options and options.monsterSprite
				if not sp or type(panel) ~= "table" then return end
				-- último golpe por Coromon, guardado entre batalhas
				local monKey = "?"
				pcall(function() monKey = tostring(sp.monster:getIdentifier()) end)
				if type(sp.setMostRecentBeforeSkillData) == "function" and not sp._speedmodWrapped then
					sp._speedmodWrapped = true
					local origSet = sp.setMostRecentBeforeSkillData
					sp.setMostRecentBeforeSkillData = function(selfSp, data, ...)
						pcall(function()
							for u, d in pairs(skillDataList or {}) do
								if d == data then lastSkillByMon[monKey] = u; break end
							end
							SPEEDMOD_PANEL_DIAG = nil
							SPEEDMOD_PANEL_OPEN = false
							log("golpe escolhido: " .. tostring(lastSkillByMon[monKey]) .. " (" .. monKey .. ")")
						end)
						return origSet(selfSp, data, ...)
					end
				end
				-- o jogo guarda o último golpe escolhido, mas não usa. Logo depois de abrir,
				-- o painel volta pro golpe 1 sozinho, e direções que "vazam" da caminhada
				-- jogam o cursor pros botões da lateral. Por ~0,6 s mantemos o cursor no
				-- golpe certo (ou no 1), até você apertar algo de propósito.
				local function targetIndex()
					local want = sp:getMostRecentBeforeSkillData()
					if not want and lastSkillByMon[monKey] and skillDataList then want = skillDataList[lastSkillByMon[monKey]] end
					if not want then return 1 end
					for i, u in ipairs(sp.monster:getSelectedSkillUIDs() or {}) do
						if (skillDataList and skillDataList[u] == want) or (type(want) == "table" and want.UID == u) then return i end
					end
					return 1
				end
				local function arm(why)
					local nav = panel:getGamepadNavigation()
					if not (nav and nav.setSelectedIndex and nav.getSelectedIndex) then return end
					local idx = targetIndex()
					pcall(function()
						local uids = {}
						for i, u in ipairs(sp.monster:getSelectedSkillUIDs() or {}) do uids[#uids + 1] = i .. "=" .. tostring(u) end
						local w = sp:getMostRecentBeforeSkillData()
						log("painel de golpes: golpes " .. table.concat(uids, " ") .. " | guardado " ..
							tostring(lastSkillByMon[monKey]) .. " | jogo lembra " .. tostring(w and w.UID or w))
					end)
					-- LEMBRAR_GOLPE desligado: mover o cursor via setSelectedIndex parecia
					-- dessincronizar o foco do painel e o A deixava de usar o golpe.
					local g = { nav = nav, idx = idx, t0 = system.getTimer() }
					if LEMBRAR_GOLPE then guard = g end
					SPEEDMOD_PANEL_DIAG = g
					SPEEDMOD_PANEL_OPEN = true
					guardActed = false
					log("painel de golpes (" .. why .. "): cursor no golpe " .. idx)
				end
				if type(panel.hide) == "function" then
					local origHide = panel.hide
					panel.hide = function(...)
						SPEEDMOD_PANEL_OPEN = false
						return origHide(...)
					end
				end
				if type(panel.show) == "function" then
					local origShow = panel.show
					local function afterShow(...)
						local ok, err = pcall(arm, "show")
						if not ok then log("painel de golpes (show): " .. tostring(err)) end
						return ...  -- mesmos valores que o show original
					end
					panel.show = function(...) return afterShow(origShow(...)) end
				end
				local ok, err = pcall(arm, "novo")
				if not ok then log("painel de golpes: " .. tostring(err)) end
			end)
			return panel
		end
		m.new = wrappedNew
		log("painel de golpes: lembrando o ultimo golpe usado")
	end)
end


---------------------------------------------------------------------------
