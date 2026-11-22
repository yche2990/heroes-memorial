--- Heroes VII creatures and spells (heroes-memorial.h7) batch C: helpers shared by attack abilities (hexes, lines, normal attack damage, school reduction, marks,
--- statuses lasting until the end of the next action, ground fire). Only loaded with require("combat/h7AttackLib"), not registered as a script.
---
--- Function list (L = require("combat/h7AttackLib"))
---   Hexes: L.hexIndex / L.hexDistance / L.unitDistance / L.nearestHex(u, toward) / L.hexTable(battle)
---         L.neighbours(hex), L.reach(battle, unit, maxSteps) (hexes reachable on foot), L.walkTo(server, battle, unit, dest, reached) (walk there step by step)
---         L.syncSprite(server, battle, unit, hex) (make the client image follow after changeUnit changed the position)
---         L.lineIndex(a, b, k)  hex index of step k on the line from a to b (may extend beyond the distance; nil off the board)
---   Stacks: L.damageable(u) (alive, not a ghost, not an arrow tower, not invincible), L.adjacentUnits(battle, unit, pred), L.name(unit)
---   Damage: L.attackDamage(server, attacker, target, pct, ranged)  stack size x random damage x attack/defense modifier (the engine's H3 formula) x pct%
---         L.schoolDamage(target, amount, school)  damage after school reduction; school: fire / dark / light / prime (only the "all magic" reduction)
---         L.hit(server, battle, target, amount, anim, sound)  play the animation (deferred) and deal damage; returns actual damage, deaths
---   Chances: L.boost(unit) (Divination CHANGECHANCE_BOOST), L.roll(server, battle, unit, pct)
---   Marks (hidden bonus H7_ATK_MARK_H7C, kept apart by stacking group): L.markValue / L.setMark / L.clearMark / L.removeByStacking
---   Until the end of the next action: L.addTurnBuff(server, battle, unit, key, list), L.clearTurnBuff(server, battle, unit, key, types)
---   Ground fire: L.burnHexes(server, battle, unit, hexes, spellName, power, turns, anim, appearAnim)
---   Battle log: L.log(server, battle, n, strings, numbers) (texts in the valueDescriptions of H7_ATK_MARK_H7C)

local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local M = {}

M.W = 17
M.MOD = "heroes-memorial.h7"
M.MARK = "H7_ATK_MARK_H7C"

local D = ENUM.BonusDuration

-- ---- Hexes -------------------------------------------------------------------------------------

function M.hexIndex(hex)
	return hex:getX() + hex:getY() * M.W
end

--- Same as the engine's BattleHex::getDistance
function M.hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

function M.unitDistance(a, b)
	local ha, hb = a:getHexes(), b:getHexes()
	local best = 1000
	for i = 1, ha:size() do
		for j = 1, hb:size() do
			local d = M.hexDistance(ha:at(i), hb:at(j))
			if d < best then best = d end
		end
	end
	return best
end

function M.unitHexDistance(u, hex)
	local hs = u:getHexes()
	local best = 1000
	for i = 1, hs:size() do
		local d = M.hexDistance(hs:at(i), hex)
		if d < best then best = d end
	end
	return best
end

--- Round 353d: walking. Stacks walk hex by hex (the client plays the walking animation for each step) instead of teleporting.
local DIRS = { "copyToEast", "copyToWest", "copyToNorthEast", "copyToNorthWest", "copyToSouthEast", "copyToSouthWest" }

function M.neighbours(hex)
	local out = {}
	for _, d in ipairs(DIRS) do
		local ok, h = pcall(function() return hex[d](hex) end)
		if ok and h ~= nil and h:isValid() then out[#out + 1] = h end
	end
	return out
end

local function standable(battle, unit, h)
	if h == nil or not h:isValid() or not h:isAvailable() then return false end
	local ok, res = pcall(function() return battle:isAccessibleForUnit(unit, h) end)
	return ok and res
end

--- Hexes reachable from the stack's current position within maxSteps steps (as the engine: two-hex creatures counted by the head hex, every step must fit).
--- Returns { [hex index] = { hex = hex, steps = steps, prev = previous hex index } }, with steps = 0 at the start
function M.reach(battle, unit, maxSteps)
	local start = unit:getPosition()
	local si = M.hexIndex(start)
	local out = { [si] = { hex = start, steps = 0 } }
	local queue, qi = { start }, 1
	while qi <= #queue do
		local h = queue[qi]
		qi = qi + 1
		local cur = out[M.hexIndex(h)]
		if cur.steps < maxSteps then
			for _, n in ipairs(M.neighbours(h)) do
				local ni = M.hexIndex(n)
				if out[ni] == nil and standable(battle, unit, n) then
					out[ni] = { hex = n, steps = cur.steps + 1, prev = M.hexIndex(h) }
					queue[#queue + 1] = n
				end
			end
		end
	end
	return out
end

--- Walk to dest along the reach route (flyers fly there at once). Falls back to teleporting if no route is found.
function M.walkTo(server, battle, unit, dest, reached)
	local di = M.hexIndex(dest)
	local node = reached and reached[di]
	if node == nil or node.steps == 0 then
		if node == nil then server:moveUnit(battle, unit, dest, true) end
		return
	end
	if unit:hasBonuses({ type = "FLYING" }) then
		server:moveUnit(battle, unit, dest, false)
		return
	end
	local path = {}
	while node ~= nil and node.steps > 0 do
		table.insert(path, 1, node.hex)
		node = reached[node.prev]
	end
	for _, h in ipairs(path) do server:moveUnit(battle, unit, h, false) end
end

--- Round 353d: changing only the position (changeUnit) does not move the client image, so an in-place "teleport" is sent to make it follow (otherwise it looks like it is still at the old position while it is actually at the new one)
function M.syncSprite(server, battle, unit, hex)
	pcall(function() server:moveUnit(battle, unit, hex, true) end)
end

--- Hex of u nearest to toward (a stack)
function M.nearestHex(u, toward)
	local hs = u:getHexes()
	local best, bestHex = 1000, u:getPosition()
	for i = 1, hs:size() do
		local d = M.unitHexDistance(toward, hs:at(i))
		if d < best then best, bestHex = d, hs:at(i) end
	end
	return bestHex
end

function M.hexTable(battle)
	local arr = battle:getAllPossibleHexes()
	local t = {}
	for i = 1, arr:size() do
		local h = arr:at(i)
		t[M.hexIndex(h)] = h
	end
	return t
end

local function toCube(hex)
	local u = hex:getX() + math.floor(hex:getY() / 2)
	local v = hex:getY()
	return u - v, -u, v
end

local function roundCube(x, y, z)
	local rx, ry, rz = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
	local dx, dy, dz = math.abs(rx - x), math.abs(ry - y), math.abs(rz - z)
	if dx > dy and dx > dz then
		rx = -ry - rz
	elseif dy > dz then
		ry = -rx - rz
	else
		rz = -rx - ry
	end
	return rx, ry, rz
end

--- Hex index of step k on the line from a to b (k = 0 is a; k may exceed the distance, extending the line); nil off the board
function M.lineIndex(a, b, k)
	local ax, ay, az = toCube(a)
	local bx, by, bz = toCube(b)
	local n = M.hexDistance(a, b)
	if n == 0 then return nil end
	local t = k / n
	local x = ax + (bx - ax) * t + 1e-6
	local y = ay + (by - ay) * t + 2e-6
	local z = az + (bz - az) * t - 3e-6
	local _, ry, rz = roundCube(x, y, z)
	local v = rz
	local u = -ry
	local col = u - math.floor(v / 2)
	if v < 0 or v > 10 or col < 1 or col > 15 then return nil end
	return col + v * M.W
end

-- ---- Stacks -------------------------------------------------------------------------------------

function M.damageable(u)
	return u ~= nil and u:isAlive() and not u:isGhost() and not u:isTurret() and not u:isInvincible()
end

function M.isWarMachine(u)
	return u:hasBonuses({ type = "SIEGE_WEAPON" })
end

function M.adjacentUnits(battle, unit, pred)
	local out = {}
	local list = battle:getUnitsIf(function(o)
		return o:isAlive() and not o:isGhost() and o:unitID() ~= unit:unitID()
	end)
	for _, o in ipairs(list) do
		if M.unitDistance(unit, o) == 1 and (pred == nil or pred(o)) then table.insert(out, o) end
	end
	return out
end

function M.name(unit)
	return unit:getCreature():getNameTextID(unit:getCount())
end

--- Can shoot: a shooter, not 100% Forgetful
function M.canShoot(unit)
	if not unit:isShooter() then return false end
	local ok, f = pcall(function() return unit:getBonusesValue({ type = "FORGETFULL" }) end)
	if ok and type(f) == "number" and f >= 100 then return false end
	return true
end

--- Enemy adjacent (shooter blocked)
function M.engaged(battle, unit)
	return #M.adjacentUnits(battle, unit, function(o)
		return battle:isHostile(unit, o) and not o:isTurret()
	end) > 0
end

-- ---- Damage -------------------------------------------------------------------------------------

local function rollBase(server, attacker, ranged)
	local count = attacker:getCount()
	local minDamage = attacker:getMinDamage(ranged)
	local maxDamage = math.max(minDamage, attacker:getMaxDamage(ranged))
	local base = 0
	if count <= 10 then
		for _ = 1, count do base = base + server:rngInt(minDamage, maxDamage) end
	else
		for _ = 1, 10 do base = base + server:rngInt(minDamage, maxDamage) end
		base = base * count / 10
	end
	return base
end

--- H7 audit A3: reductions on the target that engine attack damage also applies (armorer / magicShield / petrification of damageCalculator, multiplied together):
--- armor-type all-damage reduction (non-spell sources: Raise Shields, Rune of Balance, Shadow Cloak etc.), shield / air shield depending on range, all-damage reduction from spells such as Petrify.
--- Ranged attacks on targets inside a Mist Veil (H7_FOGSHROUD_H7C) are 0 (as damage/h7FogShroudPatch). Returns a multiplier from 0 to 1.
local function reductionFactor(target, ranged)
	local ok, r = pcall(function()
		if ranged and target:hasBonuses({ type = "H7_FOGSHROUD_H7C" }) then return 0 end
		local armor = target:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll" }):filter(function(b)
			return b:getSource() ~= ENUM.BonusSource.spellEffect
		end):totalValue()
		local shield = target:getBonusesValue({ type = "GENERAL_DAMAGE_REDUCTION", subtype = ranged and "damageTypeRanged" or "damageTypeMelee" }) or 0
		local petrify = target:getBonusesValue({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", sourceType = ENUM.BonusSource.spellEffect }) or 0
		local f = 1
		for _, v in ipairs({ armor, shield, petrify }) do f = f * (100 - math.max(0, math.min(100, v))) / 100 end
		return f
	end)
	if ok and type(r) == "number" then return r end
	return 1
end
M.reductionFactor = reductionFactor

--- Normal attack damage: stack size x random damage x attack/defense modifier (+5% per point of higher attack, at most +300%; -2.5% per point of higher defense, at most -70%) x pct% x target reduction (see above).
--- Luck, Morale and other attack bonuses are not counted. Ranged on targets in a Mist Veil is 0 (returns 0, callers treat it as "cannot hit").
function M.attackDamage(server, attacker, target, pct, ranged)
	local red = reductionFactor(target, ranged)
	if red <= 0 then return 0 end
	local base = rollBase(server, attacker, ranged)
	local diff = attacker:getAttack(ranged) - target:getDefense(ranged)
	local factor
	if diff > 0 then
		factor = 1 + 0.05 * math.min(diff, 60)
	else
		factor = 1 - 0.025 * math.min(-diff, 28)
	end
	return math.max(1, math.floor(base * factor * (pct or 100) / 100 * red))
end

local SCHOOL_SUFFIX = {
	fire = { "fire" }, water = { "water" }, air = { "air" }, earth = { "earth" },
	dark = { "02darkSchool", "darkSchool" }, light = { "01lightSchool", "lightSchool" },
	prime = {}
}

local function subMatches(sub, names)
	sub = sub or ""
	for _, n in ipairs(names) do
		if sub == n or sub:sub(-(#n + 1)) == "." .. n or sub:sub(-(#n + 1)) == ":" .. n then return true end
	end
	return false
end

local function bonusesOf(unit, typeName)
	local ok, list = pcall(function() return unit:getBonuses({ type = typeName }) end)
	if ok and list ~= nil then return list end
	return nil
end

--- School immunity (SPELL_SCHOOL_IMMUNITY for that school or all)
function M.schoolImmune(unit, school)
	local names = SCHOOL_SUFFIX[school] or {}
	local list = bonusesOf(unit, "SPELL_SCHOOL_IMMUNITY")
	if list == nil then return false end
	for i = 1, list:size() do
		local sub = list:getBonus(i):getSubtype()
		if subMatches(sub, names) or subMatches(sub, { "any" }) then return true end
	end
	return false
end

--- H7 audit B8: summed with the engine's stacking rules (within one stacking group only the entry with the largest absolute value counts; entries without a stacking group all add up)
local function stackedSum(list, pred)
	local total, groups = 0, {}
	for i = 1, list:size() do
		local b = list:getBonus(i)
		if pred(b) then
			local v = b:getVal()
			local st = b:getStacking() or ""
			if st == "" then total = total + v
			elseif groups[st] == nil or math.abs(v) > math.abs(groups[st]) then groups[st] = v end
		end
	end
	for _, v in pairs(groups) do total = total + v end
	return total
end

--- School damage: first that school's SPELL_DAMAGE_REDUCTION, then the "all magic" one (same order as the engine's adjustRawDamage); 0 with school immunity
function M.schoolDamage(unit, amount, school)
	if amount <= 0 or unit:isInvincible() then return 0 end
	if M.schoolImmune(unit, school) then return 0 end
	local names = SCHOOL_SUFFIX[school] or {}
	local own, any = 0, 0
	local list = bonusesOf(unit, "SPELL_DAMAGE_REDUCTION")
	if list ~= nil then
		any = stackedSum(list, function(b) return subMatches(b:getSubtype(), { "any" }) end)
		own = stackedSum(list, function(b) return not subMatches(b:getSubtype(), { "any" }) and subMatches(b:getSubtype(), names) end)
	end
	local v = amount * (100 - math.min(100, own)) / 100
	v = v * (100 - math.min(100, any)) / 100
	return math.max(0, math.floor(v))
end

--- Play the animation (deferred, in the same beat as the damage), then deal damage; nothing if amount <= 0 or it cannot hit
function M.hit(server, battle, target, amount, anim, sound)
	if not M.damageable(target) or amount <= 0 then return 0, 0 end
	if anim then
		server:showBattleAnimation(battle, { { unit = target } }, anim, sound or "", 1.0, true)
	end
	return server:damageUnit(battle, target, amount)
end

-- ---- Chances -------------------------------------------------------------------------------------

function M.boost(unit)
	local ok, v = pcall(function() return unit:getBonusesValue({ type = "CHANGECHANCE_BOOST" }) end)
	if ok and type(v) == "number" and v > 0 then return v end
	return 0
end

function M.roll(server, battle, unit, pct)
	if pct >= 100 then return true end
	if pct <= 0 then return false end
	local ok, r = pcall(function() return server:rollCombatAbility(battle, unit, pct) end)
	if ok and type(r) == "boolean" then return r end
	return server:rngInt(1, 100) <= pct
end

-- ---- Marks -------------------------------------------------------------------------------------

local function byStacking(unit, typeName, key)
	return unit:getBonuses({ type = typeName }):filter(function(b) return b:getStacking() == key end)
end
M.byStacking = byStacking

function M.removeByStacking(server, battle, unit, typeName, key)
	local list = byStacking(unit, typeName, key)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

function M.markValue(unit, key)
	local list = byStacking(unit, M.MARK, key)
	if list:size() == 0 then return nil end
	return list:getBonus(1):getVal()
end

function M.clearMark(server, battle, unit, key)
	M.removeByStacking(server, battle, unit, M.MARK, key)
end

--- turns = nil: whole battle; otherwise N rounds (the engine counts down at the start of each round; turns = 1 lasts until the end of this round)
function M.setMark(server, battle, unit, key, val, turns)
	M.clearMark(server, battle, unit, key)
	local d = {
		type = M.MARK, val = val, hidden = true, stacking = key,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey()
	}
	if turns then d.duration = D.nTurns; d.turns = turns else d.duration = D.oneBattle end
	server:addUnitBonus(battle, unit, d, true)
end

-- ---- Until the end of the next action -------------------------------------------------------------------------
--- H7 "until the end of its next turn": the bonus is added for 2 engine rounds as a fallback and removed by the script when the stack's own action ends (waiting does not count).
--- list: list of BonusDescriptors (type, subtype, val, valueType, hidden, icon etc.); stacking set to key for all.

function M.addTurnBuff(server, battle, unit, key, list)
	for _, d in ipairs(list) do
		M.removeByStacking(server, battle, unit, d.type, key)
		local x = {}
		for k, v in pairs(d) do x[k] = v end
		x.stacking = key
		x.duration = D.nTurns
		x.turns = 2
		x.sourceType = ENUM.BonusSource.other
		x.sourceID = unit:getCreature():getJsonKey()
		if x.val == nil then x.val = 0 end
		server:addUnitBonus(battle, unit, x, false)
	end
end

function M.clearTurnBuff(server, battle, unit, key, types)
	for _, t in ipairs(types) do M.removeByStacking(server, battle, unit, t, key) end
end

function M.hasTurnBuff(unit, key, typeName)
	return byStacking(unit, typeName, key):size() > 0
end

--- In onActionFinished, "the stack's own turn has ended" means: it is the actor, and this was not a wait (waits are recorded by onWait as waitKey)
--- Casts that do not use the turn (preparation / charge abilities; H7_AB_USED_H7C stacking h7NoSkipCast added by spells/h7abLib.markNoSkip):
--- the stack can still act after casting, so the cast does not count as a full action. Each script records it in onUnitSpellcast with noteNoSkipCast as its own "wait" mark,
--- and the shared mark is removed in onActionFinished (ownTurnEnded / clearNoSkipCast) (every script's onUnitSpellcast runs before onActionFinished).
M.NOSKIP_TYPE, M.NOSKIP_KEY = "H7_AB_USED_H7C", "h7NoSkipCast"
function M.noSkipCast(unit)
	return byStacking(unit, M.NOSKIP_TYPE, M.NOSKIP_KEY):size() > 0
end
function M.clearNoSkipCast(server, battle, unit)
	M.removeByStacking(server, battle, unit, M.NOSKIP_TYPE, M.NOSKIP_KEY)
end
function M.noteNoSkipCast(server, battle, unit, waitKey)
	if M.noSkipCast(unit) then M.setMark(server, battle, unit, waitKey, 1, 1) end
end

function M.ownTurnEnded(server, battle, unit, other, waitKey)
	if other == nil or other:unitID() ~= unit:unitID() then return false end
	M.clearNoSkipCast(server, battle, unit)
	if M.markValue(unit, waitKey) ~= nil then
		M.clearMark(server, battle, unit, waitKey)
		return false
	end
	return true
end

-- ---- Ground fire (spell obstacles: enemies entering or acting while standing on them take the triggering spell's damage) ---------------------------------

local function spellObj(name)
	local s = nil
	pcall(function() s = LIBRARY:getSpellByName(M.MOD .. ":" .. name) end)
	if s == nil then pcall(function() s = LIBRARY:getSpellByName(name) end) end
	return s
end
M.spellObj = spellObj

--- hexes: list of BattleHex; if a hex already has this spell's fire, it is replaced by the new one (new power and rounds)
function M.burnHexes(server, battle, unit, hexes, spellName, power, turns, anim, appearAnim)
	local spell = spellObj(spellName)
	if spell == nil or power <= 0 then return 0 end
	local placed = 0
	local seen = {}
	for _, h in ipairs(hexes) do
		local idx = M.hexIndex(h)
		if not seen[idx] and h:isAvailable() then
			seen[idx] = true
			for _, o in ipairs(battle:getObstaclesOnPos(h, false) or {}) do
				local s = o:getSpell()
				if s ~= nil and s:getJsonKey() == spell:getJsonKey() then server:removeObstacle(battle, o) end
			end
			server:addObstacle(battle, {
				pos              = h,
				obstacleType     = ENUM.ObstacleType.spellCreated,
				spell            = spell,
				casterSpellPower = power,
				spellLevel       = 0,
				casterSide       = unit:getSide(),
				turnsRemaining   = turns or 2,
				hidden           = false,
				passable         = true,
				nativeVisible    = true,
				trap             = false,
				removeOnTrigger  = false,
				trigger          = M.MOD .. ":" .. spellName,
				appearSound      = "",
				appearAnimation  = appearAnim or anim, -- Round 405: the appearing animation uses 1 frame (the engine queues each hex's appearing animation, so walking 5 hexes would wait for 5 of them; as the Sanctuary Kirin in round 302)
				animation        = anim,
				removalAnimation = "",
				customSize       = { h }
			})
			placed = placed + 1
		end
	end
	return placed
end

-- ---- Battle log ---------------------------------------------------------------------------------

function M.log(server, battle, n, strings, numbers)
	server:appendLog(battle, {
		append = { "core.bonus." .. M.MARK .. ".description." .. n },
		replaceStrings = strings or {},
		replaceNumbers = numbers or {}
	})
end

function M.perish(server, battle, victim, killed)
	local BattleLog = require("battleLog")
	BattleLog.creaturesPerish(server, battle, victim, killed)
end

return M
