--- Sunburst (H6): places a star on the target hex and sends rays in 8 directions (the 6 neighbour directions plus straight up and down) to the edge of the battlefield;
--- every enemy on the rays (the one on the target hex included) takes base + per x Spell Power Light damage. Parameters: base, per (4 numbers), animation, sound
local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:applicableGeneral(mechanics, problem) return true end
function Script:applicableTarget(mechanics, problem, target)
	for _, d in ipairs(target) do if d.hex and d.hex:isValid() then return true end end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

--- Enemies the rays will hit (same method as apply; only for transformTarget, apply computes it on its own as before)
local function rayVictims(battle, c, side)
	local hexes = L.hexTable(battle)
	local hit, out = {}, {}
	local function take(h)
		local u = battle:getUnitByPos(h, true)
		if u and L.real(u) and u:getSide() ~= side and not hit[u:unitID()] then hit[u:unitID()] = true; out[#out + 1] = u end
	end
	take(c)
	local dirs = {}
	for _, h in pairs(hexes) do if L.hexDistance(h, c) == 1 then dirs[#dirs + 1] = h end end
	for _, dy in ipairs({ -2, 2 }) do
		for _, h in pairs(hexes) do
			if h:getX() == c:getX() and h:getY() == c:getY() + dy then dirs[#dirs + 1] = h end
		end
	end
	for _, n in ipairs(dirs) do
		for k = 1, 30 do
			local idx = L.lineIndex(c, n, k)
			local h = idx and hexes[idx]
			if h == nil then break end
			take(h)
		end
	end
	return out
end

--- 2026-11-08 (AI skill fixes, review A2): the target hex comes first (apply takes the first valid hex as the star's position), followed by the enemies on the rays,
--- so that the engine and the AI (BattleAI choosing where to drop location spells) can count the affected stacks; it used to return only hexes, so the AI dropped every spot as "hits no enemy"
--- and the simulation branch in apply below was never reached
function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local aim = aimPoint[1]
	if aim == nil or aim.hex == nil or not aim.hex:isValid() then return spellTarget end
	local list = { { hex = aim.hex } }
	for _, u in ipairs(rayVictims(mechanics:getBattle(), aim.hex, mechanics:getCasterSide())) do
		list[#list + 1] = { unit = u, hex = u:getPosition() }
	end
	return list
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local c = nil
	for _, d in ipairs(target) do if d.hex and d.hex:isValid() then c = d.hex; break end end
	if c == nil then return end
	local side = mechanics:getCasterSide()
	local hexes = L.hexTable(battle)
	local hit = {}
	local function take(h)
		local u = battle:getUnitByPos(h, true)
		if u and L.real(u) and u:getSide() ~= side then hit[u:unitID()] = u end
	end
	take(c)
	local dirs = {}
	for _, h in pairs(hexes) do if L.hexDistance(h, c) == 1 then dirs[#dirs + 1] = h end end
	-- Straight up and down: hexes in the same column two rows apart (the "diagonal" directions of a hex grid)
	for _, dy in ipairs({ -2, 2 }) do
		for _, h in pairs(hexes) do
			if h:getX() == c:getX() and h:getY() == c:getY() + dy then dirs[#dirs + 1] = h end
		end
	end
	for _, n in ipairs(dirs) do
		for k = 1, 30 do
			local idx = L.lineIndex(c, n, k)
			local h = idx and hexes[idx]
			if h == nil then break end
			take(h)
		end
	end
	local raw = S.value(mechanics, self.base, self.per)
	for _, u in pairs(hit) do
		local d = S.spellDamage(mechanics, u, raw, "01lightSchool")
		if Proxy.trial(server) then Proxy.damage(server, battle, u, d, {}) else L.hit(server, battle, u, d, self.animation, self.sound) end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

return Script
