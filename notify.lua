---------------------------------------------------------------------------
-- Notificação de missão concluída (estilo troféu), no topo central da tela,
-- com um som curto gerado pelo próprio mod. F8 mostra uma notificação de teste.
---------------------------------------------------------------------------
do
	local SOUND_FILE = "speedmod_trofeu.wav"
	local soundHandle, soundTried = nil, false

	local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
	local function u32(v) return u16(v % 65536) .. u16(math.floor(v / 65536)) end

	-- Dois tons curtos com decaimento suave (som próprio do mod).
	local function writeChime(path)
		local rate, dur = 22050, 1.0
		local n = math.floor(rate * dur)
		local notes = { { f = 1046.5, t = 0 }, { f = 1568.0, t = 0.11 } }
		local out, twoPi = {}, 2 * math.pi
		for i = 0, n - 1 do
			local t, v = i / rate, 0
			for _, nt in ipairs(notes) do
				local dt = t - nt.t
				if dt >= 0 then
					local env = math.exp(-dt * 5) * math.min(1, dt * 300)
					v = v + env * (math.sin(twoPi * nt.f * dt) * 0.7 + math.sin(twoPi * nt.f * 2 * dt) * 0.12)
				end
			end
			local smp = math.floor(math.max(-1, math.min(1, v * 0.32)) * 32767)
			if smp < 0 then smp = smp + 65536 end
			out[#out + 1] = u16(smp)
		end
		local data = table.concat(out)
		local f = io.open(path, "wb")
		if not f then return false end
		f:write("RIFF", u32(36 + #data), "WAVEfmt ", u32(16), u16(1), u16(1), u32(rate), u32(rate * 2),
			u16(2), u16(16), "data", u32(#data), data)
		f:close()
		return true
	end

	local function playChime()
		if not soundTried then
			soundTried = true
			local ok, err = pcall(function()
				if type(audio) ~= "table" then error("sem audio") end
				local path = system.pathForFile(SOUND_FILE, system.DocumentsDirectory)
				local f = io.open(path, "rb")
				if f then f:close() else writeChime(path) end
				soundHandle = audio.loadSound(SOUND_FILE, system.DocumentsDirectory)
			end)
			if not ok then log("som da notificacao: " .. tostring(err)) end
		end
		if soundHandle then pcall(audio.play, soundHandle) end
	end

	-- título "N. Nome" de cada conquista, na ordem das missões
	local missionTitle = {}
	do
		local n = 0
		for _, it in ipairs(MISSION_DATA or {}) do
			if it.m then
				n = n + 1
				missionTitle[it.ach] = n .. ". " .. it.m
			end
		end
	end

	local TROPHY = {
		"1111111",
		"1011101",
		"0111110",
		"0011100",
		"0001000",
		"0011100",
		"0111110",
	}

	local queue, current = {}, nil
	local SHOW_IN, SHOW_HOLD, SHOW_OUT = 250, 4200, 300

	local function buildToast(title, header)
		local px = math.max(1, math.floor(select(2, screen()) / 256))
		local w, _, cx, _, _, oy = screen()
		local g = display.newGroup()
		local text2 = normalize(title)
		local maxChars = 44
		if #text2 > maxChars then text2 = text2:sub(1, maxChars - 1) .. "." end
		header = normalize(header or "MISSAO CONCLUIDA")
		local tw = math.max(#header, #text2) * 4 * px
		local bw, bh = tw + 26 * px, 20 * px
		local top = oy + 4 * px
		rect(g, cx, top + bh / 2, bw + 2 * px, bh + 2 * px, 0.25, 0.27, 0.32, 0.95)
		rect(g, cx, top + bh / 2, bw, bh, 0.07, 0.07, 0.09, 0.95)
		local left = cx - bw / 2
		-- troféu dourado
		local tpx = 2 * px
		local ix, iy = left + 4 * px, top + (bh - 7 * tpx) / 2
		for r, row in ipairs(TROPHY) do
			for c = 1, #row do
				if row:sub(c, c) == "1" then
					rect(g, ix + (c - 0.5) * tpx, iy + (r - 0.5) * tpx, tpx, tpx, 0.98, 0.78, 0.2, 1)
				end
			end
		end
		local tx = left + 21 * px
		drawText(g, header, tx, top + 4 * px, px, 0.7, 0.7, 0.75)
		drawText(g, text2, tx, top + 11 * px, px, 1, 1, 1)
		g.y = -(bh + 8 * px)
		return g, bh + 8 * px
	end

	local function showNext()
		local item = table.remove(queue, 1)
		if not item then return end
		local ok, g, h = pcall(buildToast, item[1], item[2])
		if not ok then log("notificacao: " .. tostring(g)); return end
		current = { g = g, h = h, t0 = system.getTimer() }
		playChime()
	end

	local function notifyMission(title, header)
		queue[#queue + 1] = { title, header }
		if not current then showNext() end
	end

	notifyToast = notifyMission

	Runtime:addEventListener("enterFrame", function()
		if not current then return end
		local e = system.getTimer() - current.t0
		local g, h = current.g, current.h
		if e < SHOW_IN then
			g.y = -h * (1 - e / SHOW_IN)
		elseif e < SHOW_IN + SHOW_HOLD then
			g.y = 0
		elseif e < SHOW_IN + SHOW_HOLD + SHOW_OUT then
			g.y = -h * ((e - SHOW_IN - SHOW_HOLD) / SHOW_OUT)
		else
			pcall(function() g:removeSelf() end)
			current = nil
			showNext()
			return
		end
		if g.toFront then g:toFront() end
	end)

	-- Verifica as conquistas a cada 2 s (tempo real). A primeira leitura que
	-- funcionar vira a base; daí em diante, cada conquista nova gera notificação.
	local known, lastPoll = nil, 0
	local function readAchievements()
		local st = {}
		for _, uid in ipairs(PLATINUM_ACHS or {}) do
			local a = Achievement and Achievement[uid]
			if not a then error("conquista " .. uid .. " nao existe") end
			st[uid] = a:isAchieved() and true or false
		end
		return st
	end
	Runtime:addEventListener("enterFrame", function()
		local now = system.getTimer()
		if now - lastPoll < 2000 then return end
		lastPoll = now
		local ok, st = pcall(readAchievements)
		if not ok then return end
		if known then
			for _, uid in ipairs(PLATINUM_ACHS) do
				if st[uid] and not known[uid] then
					notifyMission(missionTitle[uid] or uid)
				end
			end
		end
		known = st
	end)

	Runtime:addEventListener("key", function(e)
		if e.keyName == "f8" and e.phase == "down" then
			notifyMission("1. A AVENTURA ESPERA! (TESTE)")
			return true
		end
	end)
end
