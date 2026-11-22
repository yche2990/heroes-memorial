local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 adjacent-ally auras (Magic Resist Aura, Aura of Bravery, Leadership, Protect Ally)
--- Formerly a JSON aura with BATTLE_WIDE + UNIT_ADJACENT + ["noneOf","OPPOSITE_SIDE"], which in tests reached not a single own stack (H5Force.allyAura was 0,
--- checklist section 10 "friend or foe direction"). Now a script: decides by battle:isHostile (hypnotized stacks count for the controlling side), attaching temporary bonuses to own stacks adjacent to the aura creature and removing them when no longer adjacent.
--- Recalculated at battle start, the start of each round, after the aura creature acts, and when it dies; after other stacks act the battle-wide hidden area script h5AreaZone calls Script.refresh.
--- The same aura does not stack (however many aura creatures are adjacent, only one counts). The aura creature is not affected by its own aura.
--- Kinds are told apart by bonus value (engine Lua cannot read the addInfo table of other stacks' bonuses): 1 Magic Resist Aura, 2 Aura of Bravery, 3 Leadership, 4 Protect Ally

local KINDS = {
	-- Actual effect (hidden) + display bonus (with icon and description, type registered in bonuses.json)
	magicRes = { eff = { type = "MAGIC_RESISTANCE", val = 30 }, show = "H5_AURA_MAGICRES_H5C", showVal = 30 },
	bravery = { eff = { type = "MORALE", val = 1, valueType = "independentMax" }, show = "H5_AURA_BRAVERY_H5C", showVal = 1 },
	commander = { eff = { type = "STACKS_SPEED", val = 10, valueType = "percentToAll" }, show = "H5_AURA_COMMANDER_H5C", showVal = 10 },
	shieldOther = { eff = { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeRanged", val = 50 }, show = "H5_AURA_SHIELD_H5C", showVal = 50 },
}
local ORDER = { "magicRes", "bravery", "commander", "shieldOther" }

local function stackKey(kind) return "h5AllyAura|" .. kind end

local function bearers(battle)
	local out = {}
	local list = battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() end)
	for _, u in ipairs(list) do
		local cl = u:getBonuses({ type = "COMBAT_EVENT_TRIGGER" })
		for i = 1, cl:size() do
			local b = cl:getBonus(i)
			local sub = b:getSubtype() or ""
			if sub == "h5AllyAura" or sub:sub(-11) == ":h5AllyAura" then
				local kind = ORDER[b:getVal()]
				if kind ~= nil and KINDS[kind] then
					out[kind] = out[kind] or {}
					table.insert(out[kind], u)
				end
			end
		end
	end
	return out
end

local function has(u, kind)
	local k = KINDS[kind]
	return u:getBonuses({ type = k.show }):filter(function(b) return b:getStacking() == stackKey(kind) end):size() > 0
end

local function remove(server, battle, u, kind)
	local k = KINDS[kind]
	for _, t in ipairs({ k.eff.type, k.show }) do
		local list = u:getBonuses({ type = t }):filter(function(b) return b:getStacking() == stackKey(kind) end)
		-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
		if list:size() > 0 then Proxy.removeExact(server, battle, u, list) end
	end
end

local function add(server, battle, u, kind, src)
	local k = KINDS[kind]
	local e = {
		type = k.eff.type, val = k.eff.val, duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = stackKey(kind), hidden = true
	}
	if k.eff.subtype then e.subtype = k.eff.subtype end
	if k.eff.valueType then e.valueType = ENUM.BonusValueType[k.eff.valueType] end
	server:addUnitBonus(battle, u, e, true)
	server:addUnitBonus(battle, u, {
		type = k.show, val = k.showVal, duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = stackKey(kind)
	}, true)
end

function Script.refresh(server, battle)
	local by = bearers(battle)
	local units = battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() and not u:isTurret() end)
	for _, kind in ipairs(ORDER) do
		local list = by[kind] or {}
		for _, u in ipairs(units) do
			local src = nil
			for _, c in ipairs(list) do
				if c:unitID() ~= u:unitID() and not battle:isHostile(c, u) and A.unitDistance(c, u) == 1 then
					src = c:getCreature():getJsonKey(); break
				end
			end
			local cur = has(u, kind)
			if src ~= nil and not cur then add(server, battle, u, kind, src)
			elseif src == nil and cur then remove(server, battle, u, kind) end
		end
	end
end

--- Whether any aura stack is on the field (used by h5AreaZone, to avoid going through all stacks every time)
function Script.present(battle)
	local found = battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() and A.ability(u, "h5AllyAura") ~= nil end)
	return #found > 0
end

function Script:onBattleStart(server, battle, unit) Script.refresh(server, battle) end
function Script:onRoundStart(server, battle, unit) Script.refresh(server, battle) end
function Script:onActionFinished(server, battle, unit) Script.refresh(server, battle) end
function Script:onDeath(server, battle, unit) Script.refresh(server, battle) end

return Script
