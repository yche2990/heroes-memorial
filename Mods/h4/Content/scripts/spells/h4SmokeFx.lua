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

return Script
