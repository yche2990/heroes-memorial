local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Damage over time of Withering Breath (hidden battle-wide bonus, see spells/h6Wither): at the start of each round, stacks carrying H6_WITHER_H6C
--- take Dark damage of "breath damage x current percentage" (scaled by Dark reduction), then the percentage goes up by 1, up to max.
--- The cap is read from the hidden mark h6WitherMax on the target (written at cast time by spells/h6Wither from the spell parameter dotMax; review B10, 2026-11-08,
--- this used to read its own parameter max, so the value was written in two places). Without a mark (old saves) the parameter max is used, otherwise 20.
--- Parameters: max (fallback for old saves, no longer set in creature configs), animation, sound

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() then return end
	local list = unit:getBonuses({ type = "H6_WITHER_H6C" })
	if list:size() == 0 then return end
	local base = 0
	for i = 1, list:size() do base = math.max(base, list:getBonus(i):getVal()) end
	local pct = L.markValue(unit, "h6WitherPct") or 15
	local amount = math.floor(base * pct / 100 * (100 - L.schoolReduction(unit, "02darkSchool")) / 100)
	if pct < (L.markValue(unit, "h6WitherMax") or self.max or 20) then L.setMark(server, battle, unit, "h6WitherPct", pct + 1) end
	if amount <= 0 then return end
	local dealt, killed = L.hit(server, battle, unit, amount, self.animation, self.sound)
	L.log(server, battle, "H6_WITHER_H6C", 1, { L.name(unit) }, { dealt or 0, killed or 0 })
end

return Script
