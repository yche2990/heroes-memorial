--- H6 Memorial Sanctum: shared helpers for the active abilities of might classes (round 418). Not registered as a script; loaded with require("lib/h6MmLib").
---   M.attack(mechanics)          Attack of the casting hero (the "scaling bonus" of original might abilities is based on Attack)
---   M.value(mechanics, arr)      tier value x 0.25 + tier value x 0.025 x Attack (arr holds 4 tier values: none, basic, advanced, expert)
---   M.heroSkill(u, key)          the stack's Attack / Defense from the hero's primary skills (0 if unreadable)
---   M.addOther(server, battle, u, d, turns)   add a bonus whose source is not a spell (cannot be dispelled); turns = nil means the whole battle
---   M.receptive(mechanics, u)    might abilities are not magic: only invincibility counts (negative effects)
local S = require("lib/h6SpLib")
local M = {}

local function prim(hero, key)
	if hero == nil then return 0 end
	local ok, v = pcall(function() return hero:getPrimarySkill(ENUM.PrimarySkill[key]) end)
	if ok and type(v) == "number" then return v end
	ok, v = pcall(function() return hero:getPrimarySkill(key) end)
	if ok and type(v) == "number" then return v end
	return 0
end

function M.heroPrim(mechanics, key)
	local h = nil
	pcall(function() h = mechanics:getHeroCaster() end)
	return math.max(0, prim(h, key))
end

function M.attack(mechanics) return M.heroPrim(mechanics, "attack") end

function M.value(mechanics, arr)
	local v = S.pick(mechanics, arr)
	return v * 0.25 + v * 0.025 * M.attack(mechanics)
end

function M.heroSkill(u, key)
	local ok, v = pcall(function()
		return u:getBonusesValue({ type = "PRIMARY_SKILL", subtype = "primarySkill." .. key, sourceType = ENUM.BonusSource.heroBaseSkill })
	end)
	if ok and type(v) == "number" then return v end
	return 0
end

function M.addOther(server, battle, u, d, turns)
	d.sourceType = d.sourceType or ENUM.BonusSource.other
	d.sourceID = d.sourceID or u:getCreature():getJsonKey()
	d.valueType = d.valueType or ENUM.BonusValueType.additiveValue
	if d.duration == nil then
		if turns then d.duration = ENUM.BonusDuration.nTurns; d.turns = turns else d.duration = ENUM.BonusDuration.oneBattle end
	end
	server:addUnitBonus(battle, u, d, true)
end

function M.receptive(mechanics, u)
	if u:isInvincible() and mechanics:isNegative() then return false end
	return true
end

--- Real stacks on the battlefield (alive, present, not arrow towers or war machines)
function M.real(u)
	if u == nil or not u:isAlive() or u:isGhost() or u:isTurret() then return false end
	return not u:hasBonuses({ type = "SIEGE_WEAPON" })
end

--- Anathema (stacking h6MmAnathema): whether a stack has it, remove it (after Moment of Judgment hits)
M.ANATHEMA = "h6MmAnathema"
function M.cursed(u)
	return u ~= nil and u:getBonuses({ type = "H6_MM_ANATHEMA_H6C" }):filter(function(b) return b:getStacking() == M.ANATHEMA end):size() > 0
end
function M.clearAnathema(server, battle, u)
	local Proxy = require("lib/kadAiProxy")
	for _, t in ipairs({ "GENERAL_DAMAGE_PREMY", "PRIMARY_SKILL", "MORALE", "LUCK", "H6_MM_ANATHEMA_H6C" }) do
		local list = u:getBonuses({ type = t }):filter(function(b) return b:getStacking() == M.ANATHEMA end)
		if list:size() > 0 then Proxy.removeExact(server, battle, u, list) end
	end
end

return M
