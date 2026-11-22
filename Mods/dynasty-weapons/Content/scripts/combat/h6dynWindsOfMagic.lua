--- H6 Dynasty Weapon, Totem of Batu level 5 "Winds of Magic": for the next 3 rounds, whenever the enemy hero casts a spell, a random enemy stack takes
--- that spell's mana cost x mult damage (x10 in H6, x0.5 by the conversion rules).
--- The active ability attaches this script as a battlefield bonus (addInfo.side = casting side), carried by stacks of both sides; handled only once, on the first target the spell hits.
--- other == nil when a hero casts; for positive spells the casting side is the target's side, for negative / damage spells the other side.
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onSpellHit(server, battle, unit, other, payload)
	if other ~= nil then return end
	local first = (payload.targets or {})[1]
	if not first or not first.unit or not unit or first.unit:unitID() ~= unit:unitID() then return end
	local spell = payload.spell
	if not spell or spell:isNeutral() then return end
	local casterSide = spell:isPositive() and unit:getSide() or Lib.opposite(unit:getSide())
	if casterSide == self.side then return end
	local cost = spell:getCost(0)
	local amount = math.floor(cost * (self.mult or 5))
	if amount <= 0 then return end
	-- War machines and summoned creatures are not victims (L1)
	local victims = battle:getUnitsIf(function(x)
		return x:getSide() == casterSide and x:isAlive() and not x:isTurret() and not x:isInvincible() and not Lib.isSiege(x) and not Lib.isSummoned(x)
	end)
	if #victims == 0 then return end
	local v = victims[server:rngInt(1, #victims)]
	Lib.anim(server, battle, v, self.anim)
	local dmg = Lib.damage(server, battle, v, amount)
	if (not dmg or dmg <= 0) and self.anim then server:refreshBattleUnits(battle) end
end

return Script
