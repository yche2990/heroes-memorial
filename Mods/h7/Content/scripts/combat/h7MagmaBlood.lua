local Base = require("combat/combatScript")
local Imm = require("heroes-memorial.h7:combat/h7ImmuneLib")
local A = require("heroes-memorial.h7:combat/h7AuraLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Magma Blood (Fire Giant, Fire Titan)
--- Cannot be targeted by negative Fire spells (statuses) (same method as the Fire immunity of h7Immunity);
--- one Fire spell's damage kills at most one creature (original H7EffectSpecialLimitKills, mKillLimit = 1):
---   after the hit, if the health lost exceeds what the top creature had left, the excess is restored (resurrecting if needed), so the stack loses only one creature.
--- Limitation: only actively cast Fire spells count (the engine only sends onSpellHit for those); scripted damage such as Fire Breath or Fire Shield cannot be caught.
--- With the Ring of Oblivion in play there is no resurrection, only the top creature is healed (as hota ringOfOblivionPatch).

local KEY = "h7Imm|fire"

local function ensure(server, battle, unit)
	if not unit:isAlive() or unit:isGhost() then return end
	Imm.ensure(server, battle, unit, KEY, Imm.debuffs("fire"))
end

function Script:onBattleStart(server, battle, unit) ensure(server, battle, unit) end
function Script:onRoundStart(server, battle, unit) ensure(server, battle, unit) end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other ~= nil and other:unitID() == unit:unitID() then ensure(server, battle, unit) end
end

local function reviveHeal(unit, amount)
	local ok, ring = pcall(function() return unit:hasBonuses({ type = "HOTA_RING_OF_OBLIVION" }) end)
	if ok and ring then
		if not unit:isAlive() then return 0, ENUM.HealLevel.heal end
		return math.min(amount, unit:getMaxHealth() - unit:getFirstHPleft()), ENUM.HealLevel.heal
	end
	return amount, ENUM.HealLevel.resurrect
end

function Script:onSpellHit(server, battle, unit, other, payload)
	local spell = payload.spell
	if spell == nil or unit:isGhost() then return end
	if not Imm.inSchool(spell, "fire") then return end

	if unit:isAlive() and Imm.shouldStrip(spell, "fire") and Imm.stripSpell(server, battle, unit, spell) > 0 then
		server:refreshBattleUnits(battle)
	end

	if not spell:isDamage() then return end
	local entry = self:ownEntry(unit, payload)
	local before = entry and entry.unitBefore
	if before == nil then return end
	local hpBefore = before:getAvailableHealth()
	local count = before:getCount()
	if count <= 1 then return end
	local maxHp = before:getMaxHealth()
	local top = hpBefore - (count - 1) * maxHp
	local now = unit:isAlive() and unit:getAvailableHealth() or 0
	local lost = hpBefore - now
	if lost <= top then return end
	local amt, lvl = reviveHeal(unit, lost - top)
	if amt <= 0 then return end
	local healed = server:healUnit(battle, unit, amt, lvl, ENUM.HealPower.permanent)
	server:refreshBattleUnits(battle)
	A.log(server, battle, 6, { A.name(unit) }, { healed or amt })
end

return Script
