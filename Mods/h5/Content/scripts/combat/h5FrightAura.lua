local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Fright Aura (H5 Nightmare, Executioner)
--- Enemies within range hexes (default 3) of this stack get -morale Morale (default 3); creatures with fixed morale (undead, non-living, mechanical etc.) are unaffected.
--- Recalculated after stacks move, act or die (the hidden area script h5AreaZone on all stacks calls Script.refresh after others act).
--- Effect: a hidden MORALE reduction plus a visible display bonus H5_FRIGHTENED_H5C (value = morale lost).
--- Parameters: range, morale

local EFF = "h5FrightAuraEff"
local SHOW = "H5_FRIGHTENED_H5C"
-- H5 fixed values (the ability parameters range and morale are only for description; all auras share one calculation)
local RANGE, MORALE = 3, 3

local function moraleImmune(u)
	return u:hasBonuses({ type = "UNDEAD" }) or u:hasBonuses({ type = "NON_LIVING" }) or A.has(u, "MECHANICAL")
		or u:hasBonuses({ type = "NO_MORALE" }) or u:isTurret() or u:hasBonuses({ type = "SIEGE_WEAPON" })
end

local function current(u)
	local list = u:getBonuses({ type = "MORALE" }):filter(function(b) return b:getStacking() == EFF end)
	if list:size() == 0 then return 0, list end
	return -list:getBonus(1):getVal(), list
end

function Script.refresh(server, battle)
	local carriers = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and A.ability(u, "h5FrightAura") ~= nil
	end)
	local units = battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() end)
	for _, u in ipairs(units) do
		local want = 0
		if not moraleImmune(u) then
			for _, c in ipairs(carriers) do
				if battle:isHostile(c, u) then
					if A.unitDistance(c, u) <= RANGE then want = math.max(want, MORALE) end
				end
			end
		end
		local have, list = current(u)
		if have ~= want then
			-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
			if list:size() > 0 then Proxy.removeExact(server, battle, u, list) end
			local shows = u:getBonuses({ type = SHOW })
			if shows:size() > 0 then server:removeUnitBonuses(battle, u, shows) end
			if want > 0 then
				local src = u:getCreature():getJsonKey()
				server:addUnitBonus(battle, u, {
					type = "MORALE", val = -want, duration = ENUM.BonusDuration.oneBattle,
					sourceType = ENUM.BonusSource.other, sourceID = src, stacking = EFF, hidden = true
				}, true)
				server:addUnitBonus(battle, u, {
					type = SHOW, val = want, duration = ENUM.BonusDuration.oneBattle,
					sourceType = ENUM.BonusSource.other, sourceID = src, stacking = SHOW
				}, true)
			end
		end
	end
end

function Script:onBattleStart(server, battle, unit) Script.refresh(server, battle) end
function Script:onRoundStart(server, battle, unit) Script.refresh(server, battle) end
function Script:onActionFinished(server, battle, unit) Script.refresh(server, battle) end

function Script:onDeath(server, battle, unit) Script.refresh(server, battle) end

return Script
