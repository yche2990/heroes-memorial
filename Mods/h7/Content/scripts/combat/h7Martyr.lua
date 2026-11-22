local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7SLLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Martyrdom (H7): the spell h7Martyr puts the visible mark H7_MARTYR_H7C on the martyr (value = share %, 3 rounds),
--- and this script (3 rounds) plus Morale +1 on every other stack of the same side.
--- Whenever these allies are attacked (melee, ranged, counterattacks), X% of the hit is taken by the martyr instead (the martyr loses health directly, regardless of Attack and Defense);
--- damage spells actively cast (onSpellHit) are shared too. With several martyrs on the field, the one with the most remaining health is chosen. An invincible martyr does not share.
--- How it works: a temporary reduction before the hit (h7SLLib.preHit); after the hit the original damage is worked out backwards, the martyr loses X%,
--- and the original target is settled at (original damage - what the martyr actually took), refunding or charging the difference. If the martyr has too little health, the rest still falls on the original target.
--- When the martyr dies, h7MartyrEnd removes the Martyrdom effects from all allies.

local TAG = "Martyr"
local LINK = "H7_SHARE_LINK_H7C"
local MARK = "H7_MARTYR_H7C"
local ANIM = "h7/fx/slMartyr"

function Script:martyr(battle, unit)
	local myId = unit:unitID()
	local side = unit:getSide()
	local list = battle:getUnitsIf(function(u)
		return u:unitID() ~= myId and u:getSide() == side and u:isAlive() and not u:isGhost()
			and u:hasBonuses({ type = MARK }) and not u:isInvincible()
	end)
	local best = nil
	for _, u in ipairs(list) do
		if best == nil or u:getAvailableHealth() > best:getAvailableHealth() then best = u end
	end
	return best
end

--- The original target would take full and the martyr shares share%; returns the damage the original target should finally take
function Script:transfer(server, battle, unit, full)
	local m = self:martyr(battle, unit)
	if m == nil or full <= 0 then return full end
	local share = math.min(100, m:getBonusesValue({ type = MARK }))
	local want = math.floor(full * share / 100 + 0.5)
	if want <= 0 then return full end
	L.anim(server, battle, { m }, ANIM, "", 0.85)
	local done, killed = server:damageUnit(battle, m, want)
	server:appendLog(battle, {
		append         = { "core.bonus.H7_SL_LOG_H7C.description.5" },
		replaceStrings = { m:getCreature():getNameTextID(m:getCount()), unit:getCreature():getNameTextID(unit:getCount()) },
		replaceNumbers = { done }
	})
	L.perishLog(server, battle, m, killed)
	return full - done
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if self:martyr(battle, unit) == nil then return end
	L.preHit(server, battle, unit, TAG, LINK)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local dealt, full = L.postHit(server, battle, unit, TAG, LINK, payload, self)
	if dealt == nil then return end
	local want = self:transfer(server, battle, unit, full)
	L.settle(server, battle, unit, dealt, want)
end

function Script:onSpellHit(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local entry = self:ownEntry(unit, payload)
	local before = entry and entry.unitBefore
	if before == nil then return end
	local lost = before:getAvailableHealth() - unit:getAvailableHealth()
	if lost <= 0 then return end
	local want = self:transfer(server, battle, unit, lost)
	if want < lost then
		server:healUnit(battle, unit, lost - want, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
		server:refreshBattleUnits(battle)
	end
end

return Script
