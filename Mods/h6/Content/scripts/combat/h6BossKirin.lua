local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Enraged Kirin (H6 boss): Riptide: the hexes marked last round (spells/h6Riptide records them on the Kirin) erupt in water columns at the start of this round;
--- stacks standing on them (friend or foe) take per Water damage (scaled by Water and all-spell reduction). Parameters: per, animation, sound

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() then return end
	local v = L.markValue(unit, "h6Riptide")
	if not v then return end
	L.clearMark(server, battle, unit, "h6Riptide")
	local h = L.hexTable(battle)[v - 1]
	local u = h and battle:getUnitByPos(h, true)
	if u and L.real(u) and not u:isInvincible() then
		local dealt, killed = L.hit(server, battle, u, math.floor((self.per or 350) * (100 - L.schoolReduction(u, "water")) / 100), self.animation, self.sound)
		L.log(server, battle, "H6_RIPTIDE_H6C", 1, { L.name(u) }, { dealt or 0, killed or 0 })
	elseif h and self.animation and server:describeChanges() then
		server:showBattleAnimation(battle, { { hex = h } }, self.animation, self.sound or "", 1.0, false)
	end
end

return Script
