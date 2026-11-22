local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Intercept (ported from King's Bounty, Age of Wonders and Disciples: Age of Wonders "zone of control", Disciples III "interception", King's Bounty 2 "attack of opportunity")
---
--- When an enemy starts moving from a hex adjacent to the interceptor (walking, flying, teleporting, charging into an attack and returning after an attack all count), the interceptor
--- hits it once before it sets off: damage = normal attack damage x pct% (stack size x random damage x attack/defense modifier, without Luck, Morale or other bonuses),
--- and cannot be counterattacked. Each interceptor intercepts only once per round; several adjacent interceptors each strike separately.
--- Interception never kills a whole stack: at most down to 1 health on the last creature (a stack dying before its move starts makes the engine's "walk over and attack"
--- report a "cannot attack" error). No interception during tactics deployment; interceptors that cannot act (paralyzed, petrified etc.) do not intercept.
---
--- How it works: the interceptor carries two bonuses, both using this script:
---   1. The interceptor's own (visible, role = "carrier"): value = pct, stacking "kadInterceptor". Used only as a marker;
---      this script does nothing when role is not "zone".
---   2. The battle-wide one (hidden, role = "zone", "propagator": "BATTLE_WIDE"): every stack on the battlefield inherits a copy,
---      so this script's onBeforeMove runs whenever any stack moves (the engine only sends move events to the mover's own bonuses).
---      It looks for stacks that are adjacent to the mover, hostile, carry the intercept marker and have not intercepted this round, and lets them strike.
---   Several interceptors from the same mod pass down the same bonus (the engine deduplicates); scripts from different mods have different full names and each run once:
---   the first run handles all adjacent interceptors and marks them "intercepted this round", later runs see the mark and skip,
---   so each interceptor strikes at most once per move and per round.
---   "Intercepted this round" = a hidden LUCK 0 bonus on the interceptor, stacking "kadInterceptStruck", lasting 1 round (removed at the start of the next round).
---
--- Parameters (addInfo):
---   role   "carrier" (the interceptor's own visible bonus) or "zone" (the hidden battle-wide bonus)
--- The interception damage percentage is the value of the interceptor's visible bonus (val, standard 50).

local CARRIER = "kadInterceptor"
local STRUCK = "kadInterceptStruck"

local function hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

--- Shortest distance between two stacks (over every hex they occupy)
local function unitDistance(a, b)
	local ha, hb = a:getHexes(), b:getHexes()
	local best = 1000
	for i = 1, ha:size() do
		for j = 1, hb:size() do
			best = math.min(best, hexDistance(ha:at(i), hb:at(j)))
		end
	end
	return best
end

--- Interceptor's damage percentage (value of the visible bonus, largest of several); 0 if it is not an interceptor
local function interceptPct(unit)
	local best = 0
	local list = unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" })
	for i = 1, list:size() do
		local b = list:getBonus(i)
		if b:getStacking() == CARRIER then best = math.max(best, b:getVal()) end
	end
	return best
end

local function hasStruck(unit)
	local list = unit:getBonuses({ type = "LUCK" })
	for i = 1, list:size() do
		if list:getBonus(i):getStacking() == STRUCK then return true end
	end
	return false
end

--- Normal attack damage x pct% (same method as Sticky Tongue oeTongue, melee values)
function Script:damage(server, attacker, target, pct)
	local count = attacker:getCount()
	local minDamage = attacker:getMinDamage(false)
	local maxDamage = math.max(minDamage, attacker:getMaxDamage(false))
	local base = 0
	if count <= 10 then
		for _ = 1, count do base = base + server:rngInt(minDamage, maxDamage) end
	else
		for _ = 1, 10 do base = base + server:rngInt(minDamage, maxDamage) end
		base = base * count / 10
	end
	local diff = attacker:getAttack(false) - target:getDefense(false)
	local factor
	if diff > 0 then
		factor = 1 + 0.05 * math.min(diff, 60)
	else
		factor = 1 - 0.025 * math.min(-diff, 28)
	end
	return math.max(1, math.floor(base * factor * pct / 100))
end

function Script:onBeforeMove(server, battle, unit, other, payload)
	if self.role ~= "zone" then return end
	if battle:getTacticDistance() > 0 then return end
	if not unit:isAlive() or unit:isTurret() or unit:isInvincible() then return end -- Round 192: skip invincible stacks

	local side = unit:getSide()
	local carriers = battle:getUnitsIf(function(u)
		return battle:isHostile(u, unit) and u:isAlive() and not u:isGhost() and not u:isTurret()
			and interceptPct(u) > 0
	end)
	if #carriers == 0 then return end
	table.sort(carriers, function(a, b) return a:unitID() < b:unitID() end)

	for _, carrier in ipairs(carriers) do
		if not unit:isAlive() then return end
		if unit:getAvailableHealth() <= 1 then return end
		if not hasStruck(carrier) and not carrier:hasBonuses({ type = "NOT_ACTIVE" })
			and unitDistance(carrier, unit) == 1 then
			-- Mark first, so other copies running during the same move skip
			server:addUnitBonus(battle, carrier, {
				type       = "LUCK",
				val        = 0,
				duration   = ENUM.BonusDuration.nTurns,
				turns      = 1,
				sourceType = ENUM.BonusSource.creatureAbility,
				sourceID   = carrier:getCreature():getJsonKey(),
				stacking   = STRUCK,
				hidden     = true
			}, true)

			local amount = self:damage(server, carrier, unit, interceptPct(carrier))
			amount = math.min(amount, unit:getAvailableHealth() - 1)
			if amount > 0 then
				server:showBattleAnimation(battle, { { unit = unit } }, "kad/fx/fx_kadIntercept", "", 1.0, true)
				local dealt, killed = server:damageUnit(battle, unit, amount)
				-- "%s deals %d damage"
				server:appendLog(battle, {
					append         = { "core.genrltxt.376" },
					replaceStrings = { carrier:getCreature():getNameTextID(carrier:getCount()) },
					replaceNumbers = { dealt }
				})
				BattleLog.creaturesPerish(server, battle, unit, killed)
			end
		end
	end
end

return Script
