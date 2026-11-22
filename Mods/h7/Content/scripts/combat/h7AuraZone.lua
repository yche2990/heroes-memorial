local Base = require("combat/combatScript")
local A = require("heroes-memorial.h7:combat/h7AuraLib")
local Imm = require("heroes-memorial.h7:combat/h7ImmuneLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 creatures: hidden battle-wide script (creatures with adjacent auras pass it BATTLE_WIDE to every stack; one copy per stacking group).
--- Handles:
---   after any stack's action (hero casts included, possibly a teleport), adjacent ally auras are recalculated (h7AuraLib.refresh);
---     the Soul Fire bonus lasts until the end of that stack's own next action, and is removed then if it is no longer next to a Fire Spirit;
---   Raise Shields: after a stack protected by Raise Shields is hit in melee or ranged, the adjacent Legionnaire takes the same amount of damage (original: the ally takes only 25%, the Legionnaire another 25%);
---   Pure Aura fallback: after a sheltered stack is hit by an actively cast negative spell (including statuses attached to damage spells), the statuses that spell left are removed (damage still counts).

local SHIELD_ANIM = "h7/fx/h7Shielding"
local PURITY_ANIM = "h7/fx/h7Purity"

function Script:onActionFinished(server, battle, unit, other, payload)
	if other ~= nil and other:unitID() ~= unit:unitID() then return end
	if other ~= nil then A.actorDone(server, battle, unit) end
	A.refresh(server, battle)
end

--- Raise Shields: damage passed to the adjacent Legionnaire
function Script:onAfterAttacked(server, battle, unit, other, payload)
	if A.auraValue(unit, "h7SHIELDING") == nil then return end
	local entry = self:ownEntry(unit, payload)
	if entry == nil or (entry.damage or 0) <= 0 then return end
	local guard = nil
	local list = battle:getUnitsIf(function(u)
		return A.real(u) and u:unitID() ~= unit:unitID() and A.ability(u, "h7SHIELDING") ~= nil
	end)
	for _, g in ipairs(list) do
		if not battle:isHostile(g, unit) and A.unitDistance(g, unit) == 1 and not g:isInvincible() then
			guard = g; break
		end
	end
	if guard == nil then return end
	local amount = entry.damage
	server:showBattleAnimation(battle, { { unit = guard } }, SHIELD_ANIM, "", 1.0, true)
	local dealt = server:damageUnit(battle, guard, amount)
	A.log(server, battle, 2, { A.name(guard), A.name(unit) }, { dealt or amount })
end

--- Pure Aura fallback
function Script:onSpellHit(server, battle, unit, other, payload)
	local spell = payload.spell
	if spell == nil or not unit:isAlive() then return end
	if A.auraValue(unit, "h7AuraOfPurity") == nil then return end
	-- Blocks statuses only: the damage of damage spells still counts, only the attached statuses are removed
	if not Imm.shouldStrip(spell, "any") then return end
	if Imm.stripSpell(server, battle, unit, spell) > 0 then
		server:showBattleAnimation(battle, { { unit = unit } }, PURITY_ANIM, "", 1.0, true)
		server:refreshBattleUnits(battle)
		A.log(server, battle, 3, { A.name(unit) }, {})
	end
end

return Script
