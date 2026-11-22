local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Stranglehold (Kraken)
---
--- When attacking or counterattacking a single-hex enemy (H7 medium size), the target is held and cannot move (BIND_EFFECT, remembering the Kraken's id):
---   the engine releases it automatically when the Kraken dies or they are no longer adjacent (as Treant Entangle);
---   released at the Kraken's next action (H7: until the start of the Kraken's next turn). Here it is removed when its next action ends;
---   during its own action the other stack cannot move anyway, so the effect is the same.
--- Added during its own action with stacking h7StrangleNew:<id>, changed to h7Strangle:<id> when the action ends; added directly as the latter on counterattacks.

local function key(unit, fresh)
	return (fresh and "h7StrangleNew:" or "h7Strangle:") .. tostring(unit:unitID())
end

function Script:bind(server, battle, unit, t, fresh)
	server:addUnitBonus(battle, t, {
		type = "BIND_EFFECT", val = 0, addInfo = unit:unitID(),
		duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
		stacking = key(unit, fresh),
		icon = "h7/abilities/h7Stranglehold",
		description = "@core.bonus.H7_STATE_H7C.description.22"
	}, false)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or other == nil then return end
	local entry = self:ownEntry(other, payload)
	if entry == nil or not L.canHit(battle, unit, other) then return end
	if other:getHexes():size() > 1 then return end
	if not L.adjacent(unit, other) then return end
	L.removeByStacking(server, battle, other, "BIND_EFFECT", key(unit, true))
	L.removeByStacking(server, battle, other, "BIND_EFFECT", key(unit, false))
	self:bind(server, battle, unit, other, not payload.isCounter)
	server:showBattleAnimation(battle, { { unit = other } }, "h7/fx/h7Entangle", "BIND", 1.0, true)
	server:refreshBattleUnits(battle)
	L.log(server, battle, 9, { L.name(other) }, {})
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	local oldKey, newKey = key(unit, false), key(unit, true)
	local bound = battle:getUnitsIf(function(u) return u:isAlive() and u:hasBonuses({ type = "BIND_EFFECT" }) end)
	for _, u in ipairs(bound) do
		L.removeByStacking(server, battle, u, "BIND_EFFECT", oldKey)
		local fresh = u:getBonuses({ type = "BIND_EFFECT" }):filter(function(b) return b:getStacking() == newKey end)
		if fresh:size() > 0 then
			Proxy.removeExact(server, battle, u, fresh)
			if unit:isAlive() then self:bind(server, battle, unit, u, false) end
		end
	end
end

return Script
