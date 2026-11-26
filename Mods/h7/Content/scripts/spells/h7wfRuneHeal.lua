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

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Rune Heal (click an ally; heals the allies in the first three columns)
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "combatHeal" } -- step number -> cursor
	local AIM = { ["*"] = "creature" } -- target type of the first step (spell targetType)
	if hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local step = #partialTarget + 1
	local cursor = CURSORS[step]
	if cursor == nil then return nil end
	local spell = mechanics:getSpell()
	if step ~= 1 then return nil end
	local aim = AIM[spell:getJsonKey()] or AIM["*"]
	if aim ~= "creature" and aim ~= "location" then return nil end
	local spellName = spell:getNameTextID()
	if aim == "creature" then
		local battle = mechanics:getBattle()
		local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
		local names = { spellName }
		if unit ~= nil then table.insert(names, unit:getCreature():getNameTextID(unit:getCount())) end
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.27" }, replaceStrings = names }, -- Cast %s on %s
			blockedText = { append = { "core.genrltxt.23" } },                  -- Select a target for the spell
			healthGainTextID = "vcmi.battleWindow.healValuePreview"
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

--- Hover estimate: same formula as apply. Every living ally in the caster's first three columns heals X (top creature only, no resurrection; at level 5 extra heals per friendly rune on it),
--- healing is summed. Which stack is clicked does not change the result
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local caster = mechanics:getUnitCaster()
		if caster == nil then return zero end
		local lv = W.levelOf(caster) or 2
		local v = W.SKILL.runeHeal[lv] or W.SKILL.runeHeal[2]
		local side = caster:getSide()
		local total = 0
		for _, u in ipairs(battle:getUnitsIf(function(u) return u:getSide() == side and W.healable(u, false) and inFront(u, side) end)) do
			local times = 1
			if lv >= 5 then times = times + runes(u) end
			local lost = u:getMaxHealth() - u:getFirstHPleft()
			local per = math.floor(v)
			if per > 0 and lost > 0 then total = total + math.min(per * times, lost) end
		end
		return { hpDelta = total, unitsDelta = 0 }
	end)
	if ok and result then return result end
	return zero
end

return Script
