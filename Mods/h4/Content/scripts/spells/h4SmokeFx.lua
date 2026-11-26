--- Heroes IV Memorial: Smoke (H4): smoke on the target hex and the ring around it for turns rounds;
--- shots whose line crosses smoke (the shooter's and target's hexes included) deal half damage, settled in the tick of combat/h4Proc.
local Base = require("spells/spellEffect")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local DIRS = { "copyToNorthWest", "copyToNorthEast", "copyToEast", "copyToSouthEast", "copyToSouthWest", "copyToWest" }

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local center = target[1] and target[1].hex
	if center == nil or not center:isValid() then return end
	local hexes = { center }
	for _, d in ipairs(DIRS) do
		local h = center[d](center)
		if h:isValid() and h:getX() > 0 and h:getX() < 16 then table.insert(hexes, h) end
	end
	-- During the AI simulation no obstacle is placed and no settling script attached (such commands are not allowed in the simulation, round 587)
	if not server:describeChanges() then return end
	for _, h in ipairs(hexes) do
		server:addObstacle(battle, {
			pos = h, obstacleType = ENUM.ObstacleType.spellCreated, spell = mechanics:getSpell(),
			casterSpellPower = 0, spellLevel = mechanics:getEffectLevel(), casterSide = mechanics:getCasterSide(),
			turnsRemaining = self.turns or 3, hidden = false, passable = true, nativeVisible = true,
			trap = false, removeOnTrigger = false, trigger = "", appearSound = "",
			appearAnimation = self.animation or "SP04_", animation = self.animation or "SP04_", removalAnimation = "h4/fx/blank",   -- The engine plays the fade animation reversed; leaving it empty would play the appearing animation backwards, so a blank animation is used to vanish at once (round 587)
			customSize = {},
		})
	end
	local any = battle:getUnitsIf(function(u)
		return u:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b) return b:getStacking() == "h4ProcTick" end):size() > 0
	end)
	if #any == 0 then
		server:addBattleBonus(battle, {
			type = "COMBAT_EVENT_TRIGGER", subtype = "h4Proc", val = 0, hidden = true, addInfo = { mode = "tick" },
			duration = "ONE_BATTLE", sourceType = "OTHER", stacking = "h4ProcTick"
		})
	end
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Mist Bottle, Smoke (H4)
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
