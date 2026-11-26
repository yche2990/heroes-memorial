local Base = require("spells/damage")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Sunburst (H7): beams shoot from the chosen hex in six directions (eight on H7's square grid, only six on hexes);
--- each beam hits the first enemy it meets (allies do not block beams); obstacles and walls block beams; an enemy on the center hex is hit too (only once).
--- Damage = base[mastery] + perPower[mastery] x Spell Power (average of the H7 random range), then through the engine's spell damage adjustments.
--- Expert (with Light Understanding III): enemies hit lose trunc(debuffPer x Spell Power) Attack and Defense for debuffTurns rounds.
---
--- Parameters:
---   base, perPower   damage
---   debuffPer        4 numbers, Attack/Defense reduction per point of Spell Power per level (0 = none)
---   debuffTurns      rounds of the Attack/Defense reduction

local DIRS = { "copyToNorthWest", "copyToNorthEast", "copyToEast", "copyToSouthEast", "copyToSouthWest", "copyToWest" }

local function centerOf(aimPoint, spellTarget)
	local d = aimPoint[1] or spellTarget[1]
	if d == nil then return nil end
	if d.hex and d.hex:isValid() then return d.hex end
	if d.unit then return d.unit:getPosition() end
	return nil
end

function Script:isEnemy(mechanics, unit)
	return unit:getSide() ~= mechanics:getCasterSide()
end

--- Per beam: returns the hexes the beam passes and the stack it hits (may be nil)
function Script:beam(mechanics, center, dir)
	local battle = mechanics:getBattle()
	local path = {}
	local prev = center
	local h = center[dir](center)
	while h ~= nil and h:isAvailable() do -- Round 401: edge column hexes are isValid but cannot be used to check blocking (hasPenaltyOnLine fails)
		if #battle:getObstaclesOnPos(h, true) > 0 then break end
		if prev:isAvailable() and battle:hasPenaltyOnLine(prev, h, true, false) then break end -- Round 401: when the aiming point is in the edge column, prev cannot be used to check blocking
		path[#path + 1] = h
		local u = battle:getUnitByPos(h, true)
		if u ~= nil and self:isEnemy(mechanics, u) and self:isValidTarget(mechanics, u) then
			return path, u
		end
		prev = h
		h = h[dir](h)
	end
	return path, nil
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local center = centerOf(aimPoint, spellTarget)
	if center == nil then return {} end
	local battle = mechanics:getBattle()
	local seen, result = {}, {}
	local function add(u)
		if u and not seen[u:unitID()] then
			seen[u:unitID()] = true
			result[#result + 1] = { unit = u, hex = u:getPosition() }
		end
	end
	local c = battle:getUnitByPos(center, true)
	if c ~= nil and self:isEnemy(mechanics, c) and self:isValidTarget(mechanics, c) then add(c) end
	for _, dir in ipairs(DIRS) do
		local _, u = self:beam(mechanics, center, dir)
		add(u)
	end
	return result
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local center = centerOf({}, spellTarget)
	if center == nil then return hexes end
	hexes:insert(center)
	for _, dir in ipairs(DIRS) do
		local path = self:beam(mechanics, center, dir)
		for _, h in ipairs(path) do hexes:insert(h) end
	end
	return hexes
end

function Script:damageForTarget(targetIndex, mechanics, unit)
	local raw = Lib.value(self.base, self.perPower, Lib.level(mechanics), Lib.power(mechanics)) * Lib.casterDamageFactor(mechanics)
	return Lib.adjust(mechanics, unit, raw)
end

function Script:apply(mechanics, server, target)
	Base.apply(self, mechanics, server, target)
	local lvl = Lib.level(mechanics)
	local per = self.debuffPer and (self.debuffPer[lvl + 1] or 0) or 0
	if per <= 0 then return end
	local amount = math.floor(per * Lib.power(mechanics))
	if amount <= 0 then return end
	local battle = mechanics:getBattle()
	local key = mechanics:getSpell():getJsonKey()
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			for _, sk in ipairs({ "primarySkill.attack", "primarySkill.defence" }) do
				server:addUnitBonus(battle, unit, {
					type = "PRIMARY_SKILL", subtype = sk, val = -amount,
					duration = ENUM.BonusDuration.nTurns, turns = self.debuffTurns or 3,
					sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(), sourceID = key
				}, false)
			end
		end
	end
end

--- Newer engines call this every time a target is chosen (logging an error if missing); returning nil uses the engine's default hint

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Sunburst (H7): beams in six directions
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorRay" } -- step number -> cursor
	local AIM = { ["*"] = "location" } -- target type of the first step (spell targetType)
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

return Script
