local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Memorial Shrine: Unstoppable Charge (approximation of the Haven ultimate Unstoppable Charge):
--- retaliation (including pre-emptive retaliation) deals val% of normal damage (175 = +75%). A permanent bonus on the hero, passed to the whole army.
--- Original: the Knight's "Retaliation Strike" damage is tripled (Training's retaliation bonus at most +25% -> +75%).
--- Uses its own stacking group h5UnstoppableCharge, so it and the Warmonger's Fierce Retaliation (h5FierceRetaliation) do not clear each other.

local STACK = "h5UnstoppableCharge"

local function clear(server, battle, unit)
	H5.removeByStacking(server, battle, unit, "PERCENTAGE_DAMAGE_BOOST", STACK)
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	clear(server, battle, unit)
	if not payload.isCounter then return end
	local pct = (self.val or 175) - 100
	if pct <= 0 then return end
	for _, sub in ipairs({ "damageTypeMelee", "damageTypeRanged" }) do
		server:addUnitBonus(battle, unit, {
			type = "PERCENTAGE_DAMAGE_BOOST", subtype = sub, val = pct,
			duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
			stacking = STACK, hidden = true
		}, true)
	end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	clear(server, battle, unit)
end

return Script
