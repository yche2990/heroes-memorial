local Base = require("heroes-memorial:spells/h5Summon")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Summon Elemental (H7): two changes on top of heroes-memorial:h5Summon
---   1. Each time one kind is picked at random from ids (H7 template mCreaturePool: Air, Earth, Fire, Water, Light and Dark elementals, this mod's neutral elementals),
---      count = trunc(base + perPower x Magic) (H7 mScalingStruct: 2 + 0.10/0.15/0.20/0.30 x Magic);
---      summoned creatures vanish after battle; can be cast several times, summoning different kinds (H7 has no "one kind only" restriction).
---   2. Expert (with "Prime Understanding III"): summoned stacks get the combat event growScript (h7ElementalGrow), count + grow at the start of every round after.
--- Parameters: as h5Summon, plus grow, growScript, growIcon, growLevel (from which level, default 3)

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local side = mechanics:getCasterSide()
	local idx = (#self.ids > 1) and server:rngInt(1, #self.ids) or 1
	local creature = LIBRARY:getCreatureByName(self.ids[idx])
	if not creature then return end
	local lvl = Lib.level(mechanics)
	for _, dest in ipairs(target) do
		if dest.unit == nil and dest.hex ~= nil then
			local hex = battle:getAvailableHex(creature, side, dest.hex)
			if hex == nil or not hex:isValid() then hex = battle:getAvailableHex(creature, side) end
			local n = self:amountFor(mechanics, creature)
			if n > 0 and hex ~= nil and hex:isValid() then
				local fx = self.fx and (self.fx[idx] or self.fx[1])
				if fx and server:describeChanges() then
					server:showBattleAnimation(battle, { { hex = hex } }, fx, "", 1.0, true)
				end
				local unit = server:addUnit(battle, {
					count = n,
					type = creature,
					side = side,
					position = hex,
					summoned = not self.permanent
				})
				if unit and lvl >= (self.growLevel or 3) and self.growScript and (self.grow or 0) > 0 then
					local d = {
						type       = "COMBAT_EVENT_TRIGGER",
						subtype    = self.growScript,
						val        = self.grow,
						duration   = ENUM.BonusDuration.oneBattle,
						sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(),
						sourceID   = mechanics:getSpell():getJsonKey(),
						stacking   = "h7ElementalGrow"
					}
					if self.growIcon then d.icon = self.growIcon end
					server:addUnitBonus(battle, unit, d, false)
				end
				server:refreshBattleUnits(battle)
			end
		end
	end
end

--- Round 301: newer engines call this every time a target is chosen; returning nil uses the engine's default hint
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
