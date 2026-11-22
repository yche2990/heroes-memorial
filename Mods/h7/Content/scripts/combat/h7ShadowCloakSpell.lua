local Base = require("heroes-memorial.h7:combat/h47ShadowCloak")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Spell version of Shadow Cloak (H7): three changes to the pack's Shadow Cloak (h47ShadowCloak, copied unchanged into this mod):
---   1. Layers are not given at battle start but when the spell h7ShadowCloak is cast (mark, value = layers, lasting 3 rounds like this script);
---   2. after each layer is used, the remaining layer mark only lasts until this script expires (the original keeps it all battle); when the layers run out it is removed together with this script;
---   3. a miss plays the H7 Shadow Cloak effect.
--- The miss works as in the original script: a hidden mark and 100% damage reduction before the hit, the reduction removed and the hit's damage restored after it; spell damage is not blocked, clones are not protected.
---
--- Parameters (as h47ShadowCloak):
---   mark  name of the layer marker bonus (visible)
---   flag  name of the hidden mark bonus (this hit missed); value description 1 is the battle log

local KEY = "h7ShadowCloakSpell"
local ANIM = "h7/fx/slShadowCloakHit"
local SOUND = "h7/spell_shadow_cloak_tick.ogg"

local function ownTriggers(unit)
	return unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b)
		return string.find(tostring(b:getSubtype() or ""), KEY, 1, true) ~= nil
	end)
end

function Script:turnsLeft(unit)
	local list = ownTriggers(unit)
	local t = 0
	for i = 1, list:size() do
		local r = list:getBonus(i):getTurnsRemain()
		if r > t then t = r end
	end
	return t
end

--- No layers at battle start (given only when the spell is cast)
function Script:onBattleStart(server, battle, unit, other, payload)
end

function Script:setCharges(server, battle, unit, n)
	local _, marks = self:charges(unit)
	if marks:size() > 0 then server:removeUnitBonuses(battle, unit, marks) end
	local turns = self:turnsLeft(unit)
	if n <= 0 or turns <= 0 then
		local list = ownTriggers(unit)
		if list:size() > 0 then server:removeUnitBonuses(battle, unit, list) end
		return
	end
	server:addUnitBonus(battle, unit, {
		type        = self.mark,
		val         = n,
		duration    = ENUM.BonusDuration.nTurns,
		turns       = turns,
		sourceType  = ENUM.BonusSource.other,
		sourceID    = unit:getCreature():getJsonKey()
	}, true)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not self:clearDodge(server, battle, unit) then return end
	if not unit:isAlive() then return end

	local entry = self:ownEntry(unit, payload)
	local damage = entry and entry.damage or 0
	if damage > 0 then
		server:healUnit(battle, unit, damage, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	end

	local left = self:charges(unit) - 1
	self:setCharges(server, battle, unit, left)

	server:showBattleAnimation(battle, { { unit = unit } }, ANIM, SOUND, 0.85, true) server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append         = { "core.bonus." .. self.flag .. ".description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
		replaceNumbers = { math.max(left, 0) }
	})
end

return Script
