local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Settling of the H6 Dynasty Weapon Transfer Life (Sandro's Staff level 5 gives the hero a BATTLE_WIDE COMBAT_EVENT_TRIGGER, carried by stacks of both sides,
--- one per stacking):
---   after a hero's cast (other == nil) hits a living stack, the damage of that hit is worked out (health before - health after in the target's entry),
---   and living stacks of the other side carrying H6DYN_LIFELINK regain val% of it as health (healing only, no resurrection; Ring of Oblivion irrelevant).
---   Only damage to the "other side" counts: the hero's spells hurting its own stacks are not turned into healing.
---   Spells cast by scripts raise no onSpellHit (engine rule), so only spells the hero casts personally count.

local ANIM = "h6dyn/fx/lifedrain_target"

function Script:onSpellHit(server, battle, unit, other, payload)
	if other ~= nil then return end -- Stack casts do not count, only the hero's
	-- The state before the hit is in this stack's own target entry (entry.unitBefore)
	local entry = self:ownEntry(unit, payload)
	if not entry or not entry.unitBefore or not unit then return end
	if not unit:isLiving() then return end
	local dealt = entry.unitBefore:getAvailableHealth() - unit:getAvailableHealth()
	if dealt <= 0 then return end
	local side = unit:getSide()
	local recipients = battle:getUnitsIf(function(u)
		return u:getSide() ~= side and u:isAlive() and u:getBonusesValue({ type = "H6DYN_LIFELINK" }) > 0
	end)
	local animated = false
	for _, r in ipairs(recipients) do
		local amount = math.floor(dealt * r:getBonusesValue({ type = "H6DYN_LIFELINK" }) / 100)
		if amount > 0 and r:getTotalHealth() > r:getAvailableHealth() then
			server:showBattleAnimation(battle, { { unit = r } }, ANIM, "", 1.0, true)
			server:healUnit(battle, r, amount, ENUM.HealLevel.heal, ENUM.HealPower.permanent)
			animated = true
		end
	end
	-- Nothing else changes after the healing, so the deferred animation needs a refresh to play (checklist section 10 animation rules)
	if animated then server:refreshBattleUnits(battle) end
end

return Script
