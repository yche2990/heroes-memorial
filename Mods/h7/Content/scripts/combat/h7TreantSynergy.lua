local Base = require("combat/combatScript")
local A = require("heroes-memorial.h7:combat/h7AuraLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Treant Synergy (Dryad, Oak Dryad)
--- Itself and adjacent allies Defense +val (original +5, scaled to +9 by level 2 Attack/Defense); the aura is handled by combat/h7AuraLib.
--- When the Dryad's own action ends, adjacent friendly Treants and Ancient Treants regain heal x number of Dryads health (original 1 x count, still 1 after scaling by level 2 health).
--- Normal healing (no resurrection, as the original TAG_HEAL). Parameter: heal (health restored per Dryad)

local HEAL_ANIM = "h7/fx/h7TreantHeal"
local TREANTS = { h7SylvanTreant = true, h7SylvanAncientTreant = true }

local function isTreant(u)
	local k = u:getCreature():getJsonKey()
	local short = string.match(k, "([^:]+)$") or k
	return TREANTS[short] == true
end

--- Shared by Dryad, Oak Dryad and Gift of Life: heal qualifying adjacent allies
function Script.healAdjacent(server, battle, unit, amount, pick)
	if amount <= 0 then return end
	local list = battle:getUnitsIf(function(u)
		return A.real(u) and u:unitID() ~= unit:unitID() and not battle:isHostile(unit, u) and pick(u)
			and A.unitDistance(unit, u) == 1
	end)
	for _, u in ipairs(list) do
		if u:getFirstHPleft() < u:getMaxHealth() then
			server:showBattleAnimation(battle, { { unit = u } }, HEAL_ANIM, "", 1.0, true)
			local healed = server:healUnit(battle, u, amount, ENUM.HealLevel.heal, ENUM.HealPower.permanent)
			server:refreshBattleUnits(battle)
			A.log(server, battle, 4, { A.name(unit), A.name(u) }, { healed or amount })
		end
	end
end

function Script:onBattleStart(server, battle, unit) A.refresh(server, battle) end
function Script:onRoundStart(server, battle, unit) A.refresh(server, battle) end
function Script:onDeath(server, battle, unit) A.refresh(server, battle) end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() or not unit:isAlive() then return end
	Script.healAdjacent(server, battle, unit, (self.heal or 1) * unit:getCount(), isTreant)
end

return Script
