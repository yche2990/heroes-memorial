--- Erratic Storm (H7): places a passable storm area within radius hexes of the target hex (spell obstacle, lasting turns rounds).
--- The rules are done by the damage patch damage/h7AirStorm:
---   stacks shooting while standing in the storm area get Attack -X;
---   shots whose line (shooter to target, the target's hex included) crosses the storm area deal only 10% damage.
--- In addition every stack on the field gets the hidden mark H7_AIRSTORM_H7C (value = X, only the largest per group, lasting turns rounds),
--- which the damage patch checks first, so battles without a storm cost no extra time.
--- Parameters:
---   radius            radius of the storm area (hexes)
---   turns             rounds
---   base, perPower    Attack reduction X = trunc(base + perPower x SP), 4 numbers by none/basic/advanced/expert
---   animation, sound  looping animation of the storm area (drawn from the bottom-left corner of the anchor hex), sound on appearing
local Base = require("spells/spellEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Air = require("heroes-memorial.h7:spells/h7AirLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local MARK = "H7_AIRSTORM_H7C"

local function centerOf(target)
	for _, dest in ipairs(target) do
		if dest.hex and dest.hex:isValid() then return dest.hex end
		if dest.unit then return dest.unit:getPosition() end
	end
	return nil
end

function Script:applicableGeneral(mechanics, problem)
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	local c = centerOf(target)
	if c == nil or not c:isValid() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local c = centerOf(spellTarget)
	if c == nil or not c:isValid() then return hexes end
	for _, h in ipairs(Air.hexesAround(c, self.radius or 2)) do hexes:insert(h) end
	return hexes
end

--- The animation is drawn from the bottom-left corner of the anchor hex toward the upper right: the anchor is two hexes down-left of the center and one more to the left (ground center in the image at (110, height-105))
local function anchorOf(c)
	local a = c:copyToSouthWest()
	if a:isValid() then a = a:copyToSouthWest() end
	if a:isValid() then a = a:copyToWest() end
	if a:isValid() then return a end
	return c
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local c = centerOf(target)
	if c == nil or not c:isValid() then return end
	local spell = mechanics:getSpell()
	local sp, lvl = Lib.power(mechanics), Lib.level(mechanics)
	local x = math.max(0, math.floor(Lib.value(self.base, self.perPower, lvl, sp)))
	local turns = self.turns or 3

	local anchor = anchorOf(c)
	server:addObstacle(battle, {
		pos              = anchor,
		obstacleType     = ENUM.ObstacleType.spellCreated,
		spell            = spell,
		casterSpellPower = sp,
		spellLevel       = lvl,
		casterSide       = mechanics:getCasterSide(),
		turnsRemaining   = turns,
		hidden           = false,
		passable         = true,
		nativeVisible    = true,
		trap             = false,
		removeOnTrigger  = false,
		appearSound      = self.sound or "",
		-- Round 416: the engine never draws obstacles with an empty appearing animation; animation itself is a one-time "growing from nothing" animation,
		-- so appearing uses the growing part (<animation>_in), the persistent image loops the last frames of full growth (<animation>_loop), and the fade is left empty = appearing played backwards (shrinking)
		appearAnimation  = (self.animation and self.animation ~= "") and (self.animation .. "_in") or "",
		animation        = (self.animation and self.animation ~= "") and (self.animation .. "_loop") or "",
		customSize       = Air.hexesAround(c, self.radius or 2)
	})

	-- H7 audit B4: X is added as a battle-wide bonus (stacks entering later inherit it too), with the storm's anchor hex in the stacking group, and the damage patch takes X from the storm the shooter stands in;
	-- battle-wide bonuses cannot be added in the AI simulation, so there it is still added to the stacks present at that moment as before
	if server:describeChanges() then
		server:addBattleBonus(battle, {
			type       = MARK,
			val        = x,
			duration   = "ONE_BATTLE",
			sourceType = "OTHER",
			sourceID   = "h7AirStorm",
			stacking   = "h7AirStorm@" .. tostring(anchor:getX() + anchor:getY() * 17),
			hidden     = true
		})
		server:refreshBattleUnits(battle)
		return
	end
	local units = battle:getUnitsIf(function(u) return u:isAlive() end)
	for _, u in ipairs(units) do
		server:addUnitBonus(battle, u, {
			type       = MARK,
			val        = x,
			duration   = "N_TURNS",
			turns      = turns,
			sourceType = "OTHER",
			sourceID   = "h7AirStorm",
			stacking   = "h7AirStorm",
			hidden     = true
		}, false)
	end
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Weird Storm (H7)
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorPlace" } -- step number -> cursor
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
