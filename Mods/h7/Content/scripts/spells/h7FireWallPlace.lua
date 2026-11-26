local Base = require("spells/obstacle")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Obstacle placement of Fire Wall (H7): changes only one thing in the core obstacle effect: H7's vertical 1x5 fire wall often overlaps stacks,
--- and the core version requires every hex to be free to cast; here it can be cast with at least one free hex, skipping hexes occupied by stacks, obstacles or walls.
--- Everything else (shape, animation, trigger spell, duration, Expert stopping trap) as the core obstacle, with the same parameters.

local DIRECTION_METHOD = { TL = "copyToNorthWest", TR = "copyToNorthEast", R = "copyToEast", BR = "copyToSouthEast", BL = "copyToSouthWest", L = "copyToWest" }

local function applyShape(hex, shape)
	local result = hex
	for _, dir in ipairs(shape or {}) do
		local m = DIRECTION_METHOD[dir]
		if m then result = result[m](result) end
	end
	return result
end

local function opts(self, side)
	if side == ENUM.BattleSide.attacker then return self.attacker or {} end
	return self.defender or {}
end

local function clear(battle, hex)
	if hex == nil or not hex:isValid() or not hex:isAvailable() then return false end
	if battle:getUnitByPos(hex, true) ~= nil then return false end
	for _, o in ipairs(battle:getObstaclesOnPos(hex, false)) do
		if o:getObstacleType() ~= ENUM.ObstacleType.moat then return false end
	end
	if battle:hasFortifications() and battle:hexToWallPart(hex) ~= ENUM.WallPart.invalid then return false end
	return true
end

function Script:freeTargets(mechanics, target)
	local battle = mechanics:getBattle()
	local shapes = opts(self, mechanics:getCasterSide()).shape
	if shapes == nil or #shapes == 0 then shapes = { {} } end
	local out = {}
	for _, dest in ipairs(target) do
		if dest.hex and dest.hex:isValid() then
			local ok = true
			for _, shape in ipairs(shapes) do
				if not clear(battle, applyShape(dest.hex, shape)) then ok = false break end
			end
			if ok then out[#out + 1] = dest end
		end
	end
	return out
end

function Script:applicableTarget(mechanics, problem, target)
	if #self:freeTargets(mechanics, target) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	return Base.apply(self, mechanics, server, self:freeTargets(mechanics, target))
end

--- Round 301: newer engines call this every time a target is chosen; returning nil uses the engine's default hint

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Wall of Fire (H7)
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); with clearAffected at this level a blocked hex shows "X cannot be placed here" (181) without an estimate; damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorPlace" } -- step number -> cursor
	local AIM = { ["*"] = "location" } -- target type of the first step (spell targetType)
	local CLEAR = { -- clearAffected of the spell at the current level (none/basic/advanced/expert)
		["heroes-memorial.h7:h7FireWall"] = { true, true, true, true },
	}
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
	local levels = CLEAR[spell:getJsonKey()]
	if step == 1 and levels ~= nil and levels[mechanics:getRangeLevel() + 1] then
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } },        -- Cast %s
			blockedText = { append = { "core.genrltxt.181" }, replaceStrings = { spellName } } -- %s cannot be placed here
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

return Script
