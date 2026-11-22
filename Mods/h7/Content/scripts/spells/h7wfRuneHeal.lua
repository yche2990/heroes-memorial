local Base = require("spells/unitEffect")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Rune Healing (Runestone, round 428): cast by clicking any friendly stack (active casts cannot use no-target spells, checklist section 10),
--- heals all living allies (undead, constructs and war machines excluded) in its side's first three columns (the three columns after the edge column on its side), X each (W.SKILL.runeHeal).
--- Level 5: one more healing for each friendly rune on the target (spell effects of the Highlands rune school runeHighlands: Highlands runes and H7 memorial runes both count).
--- The AI simulation follows the actual healing (healing is already a value the AI understands).

local function inFront(u, side)
	local hs = u:getHexes()
	for i = 1, hs:size() do
		local x = hs:at(i):getX()
		if side == ENUM.BattleSide.attacker then
			if x >= 1 and x <= 3 then return true end
		elseif x >= 13 and x <= 15 then return true end
	end
	return false
end

local function runes(u)
	local seen, n = {}, 0
	local list = u:getBonuses({ sourceType = ENUM.BonusSource.spellEffect })
	for i = 1, list:size() do
		local id = tostring(list:getBonus(i):getSourceID())
		if not seen[id] then
			seen[id] = true
			local ok, sp = pcall(function() return LIBRARY:getSpellByName(id) end)
			if ok and sp ~= nil and sp:isPositive() then
				local okL, schools = pcall(function() return sp:getSchools() end)
				if okL and schools then
					for _, s in ipairs(schools) do
						local k = (type(s) == "string") and s or (s.getJsonKey and s:getJsonKey()) or tostring(s)
						if k:sub(-13) == "runeHighlands" then n = n + 1; break end
					end
				end
			end
		end
	end
	return n
end

function Script:isValidTarget(mechanics, unit)
	return unit ~= nil and unit:isAlive() and not unit:isGhost()
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local lv = W.levelOf(caster) or 2
	local v = W.SKILL.runeHeal[lv] or W.SKILL.runeHeal[2]
	local side = caster:getSide()
	local list = battle:getUnitsIf(function(u) return u:getSide() == side and W.healable(u, false) and inFront(u, side) end)
	local shown = {}
	for _, u in ipairs(list) do
		local times = 1
		if lv >= 5 then times = times + runes(u) end
		local total = 0
		for _ = 1, times do total = total + W.heal(server, battle, u, v) end
		if total > 0 then
			shown[#shown + 1] = { unit = u }
			W.log(server, battle, 8, { W.name(u) }, { total })
		end
	end
	if #shown > 0 and server:describeChanges() then
		server:showBattleAnimation(battle, shown, "h7/fx/h7wfRuneHeal", "", 1.0, true)
		server:refreshBattleUnits(battle)
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
