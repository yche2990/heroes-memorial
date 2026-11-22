local Base = require("combat/combatScript")
local L = require("heroes-memorial.h4:combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Heroes IV Memorial: chance-based abilities after attacks (Stun, Fear, Freeze, Swallow) and Giant Slayer.
--- Chances read Deduction (CHANGECHANCE_BOOST, via h7StatusLib.roll).
---
--- Parameters (addInfo of COMBAT_EVENT_TRIGGER):
---   mode   "incap" makes the target unable to act; "swallow" swallow; "slayer" giant slayer
---   val    trigger chance (%)
---   incap: turns = number of the target's own turns it lasts (default 1); show = display bonus type; log = battle log number; fx = hit animation (H4 effect of the same name);
---          mind = true: stacks immune to mind spells are unaffected (fear); school: school immunity (e.g. water);
---          tint: tint spell cast after freezing (Ice Demon: heroes-memorial.h4:h4FrozenTint, the stack turns ice blue, removed by tick when the freeze ends);
---          melee / ranged = false: melee / shooting does not trigger; counter = false: retaliation does not trigger
---   swallow: amount = percentage of the target's count swallowed (at least 1)
---   slayer: minLevel = minimum target level; attack = Attack bonus
---   spellHit / bolt / randomCurse: see the "casting after attacks" section below
---   poison: the target is poisoned for left rounds (default 15), taking 1/4 of this hit's damage at the start of each round; a poisoned stack is not poisoned again until the poison wears off (as in Heroes IV)
---   block: when attacked in melee or at range, blocks with val% chance (this hit's damage -100%), playing fx above itself (Heroes IV block effect) and writing battle log line log (Minotaur, round 585)
---   noRetal: the target cannot retaliate against its active attacks (Bone Dragon's Fear; the knockback is done by heroes-memorial.h4:h47Shove)
---   berserk: Berserk (the same stack also carries the engine's CPU_CONTROLLED: on its turn it attacks an enemy in reach automatically, never allies, and cannot wait);
---          the engine leaves it standing when no enemy is in reach, so this script adds the charge: at the start of each round, a berserk stack that cannot reach any enemy this round
---          first walks toward the nearest enemy (only if it still cannot reach after walking, so it never moves twice in a round; at least 1 hex, at most its speed)
---   schoolWard: at battle start the stack gets val% less damage from spells of school (source other, not counted as the creature's own school resistance)
---   tick: one copy on the whole battlefield (attached by the script itself), settles poison
---   potionFx (potions): plays effect fx on the stack at battle start
---   quickness (Potion of Quickness): one extra attack in round 1 (ADDITIONAL_ATTACK at battle start, removed at the start of round 2)
---   immortal (Potion of Immortality): the first friendly stack wiped out is fully revived at once, once per battle; afterwards all friendly stacks get the mark h4PotImmortalSpent
---   divineGuard: on the holder's stacks for the expansion divine artifacts (Crown of the Supreme One and others); at battle start one divineWatch goes on the whole battlefield (recording the holder's side and own schools)
---   divineWatch: after a hero's (not a creature's) spell hits stacks, if it belongs to none of the schools and was cast by the holder's side's hero
---          (beneficial spell on own stacks, harmful spell on enemy stacks), every friendly stack loses val% (default 20) of its current total health.
---          Spells that are neither beneficial nor harmful, and spells that hit no stack (summons, obstacles), cannot be traced to their caster and cause no backlash.
---   negateFirstStrike: Negate First Strike (Pikeman, Air Elemental, Dragon Golem, Goblin Knight; round 588). The engine decides "the target retaliates first" before the attack and scripts cannot change the order,
---          so the result is reproduced: damage taken from the first-strike retaliation is healed at once (resurrection counts as permanent), and after its own hit, if the opponent is still alive and able to act, the damage is dealt again by the opponent's remaining count
---          so it is as if the opponent retaliated after the attack as usual.
--- Unable to act: NOT_ACTIVE + NO_RETALIATION (as h7StatusLib.incapacitate); for 2 rounds after it ends it cannot be incapacitated again.

local D = ENUM.BonusDuration
local BLOCK = "h4BlockHit"   -- Damage reduction mark of this blocked hit
local LOG = "core.bonus.H4_LOG_H4C.description."

local function log(server, battle, n, strings, numbers)
	if not server:describeChanges() then return end
	server:appendLog(battle, { append = { LOG .. n }, replaceStrings = strings or {}, replaceNumbers = numbers or {} })
end

local function primary(unit, other, payload)
	for i, entry in ipairs(payload.targets or {}) do
		if entry.unit ~= nil and ((other ~= nil and entry.unit:unitID() == other:unitID()) or (other == nil and i == 1)) then
			return entry
		end
	end
	return nil
end

function Script:onBattleStart(server, battle, unit, other, payload)
	if self.mode == "potionFx" and unit:isAlive() and not unit:isTurret() then
		server:showBattleAnimation(battle, { { unit = unit } }, self.fx, "", 1.0, true)
		server:refreshBattleUnits(battle)
		return
	end
	if self.mode == "quickness" and unit:isAlive() then
		server:addUnitBonus(battle, unit, {
			type = "ADDITIONAL_ATTACK", val = 1, hidden = false, duration = "ONE_BATTLE",
			sourceType = "OTHER", stacking = "h4PotQuick"
		}, false)
		return
	end
	if self.mode == "schoolWard" and unit:isAlive() then
		-- School resistance (death ward of Crusaders and Monks, life ward of Demons, round 587): attached only at battle start with source other,
		-- so the Tears of Ashan Light/Dark Magic skills do not treat them as light/dark creatures because of a "creature's own school reduction"
		server:addUnitBonus(battle, unit, {
			type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool." .. self.school, val = self.val or 50, hidden = true,
			duration = "ONE_BATTLE", sourceType = "OTHER", stacking = "h4SchoolWard" .. self.school
		}, false)
		return
	end
	if self.mode == "incap" then L.ensureTracker(server, battle, unit) end
	if self.mode == "berserk" and unit:isAlive() then self:berserkAdvance(server, battle, unit) end
	if self.mode == "divineGuard" then self:divineGuard(server, battle, unit) end
	if self.mode == "massCaster" and unit:isAlive() then
		-- Count reaching weeks weeks of growth: the mass version of the spell this battle
		local need = (unit:getCreature():getGrowth() or 0) * (self.weeks or 5)
		if need > 0 and unit:getCount() >= need then
			for _, sp in ipairs(self.spells or {}) do
				server:addUnitBonus(battle, unit, {
					type = "SPELLCASTER", subtype = "spell." .. sp, val = 2, hidden = true,
					duration = "ONE_BATTLE", sourceType = "OTHER", stacking = "h4Mass" .. sp
				}, false)
			end
		end
	end
end

--- Chance: base chance x (100 + Deduction CHANGECHANCE_BOOST)%, capped at 100 (Deduction 20/50/100, as its PERCENT_TO_ALL for SPELL_AFTER_ATTACK)
local function roll(server, battle, unit, pct)
	pct = math.min(100, math.floor((pct or 0) * (100 + L.boost(unit)) / 100 + 0.5))
	return L.roll(server, battle, unit, pct)
end

function Script:allowed(payload)
	if payload.isCounter and self.counter == false then return false end
	if payload.ranged then return self.ranged ~= false end
	return self.melee ~= false
end

function Script:incap(server, battle, unit, t, payload)
	-- Mind immunity: as the target conditions of the original mind spells; undead, non-living, mechanical units and war machines are unaffected too (round 587)
	if self.mind then
		for _, ty in ipairs({ "MIND_IMMUNITY", "UNDEAD", "NON_LIVING", "MECHANICAL", "SIEGE_WEAPON" }) do
			if t:hasBonuses({ type = ty }) then return end
		end
	end
	if self.show == "H4_FEAR_H4C" and t:hasBonuses({ type = "H4_FEAR_IMMUNE_H4C" }) then return end
	if self.school and L.schoolImmune(t, self.school) then return end
	if L.markValue(t, "h7IncapImmune") ~= nil then return end
	if t:hasBonuses({ type = "NOT_ACTIVE" }) then return end
	if not roll(server, battle, unit, self.val or 0) then return end
	L.ensureTracker(server, battle, unit)
	local turns = L.turnsFor(t, self.turns or 1, payload.isCounter)
	local key = unit:getCreature():getJsonKey()
	for _, typeName in ipairs({ "NOT_ACTIVE", "NO_RETALIATION" }) do
		server:addUnitBonus(battle, t, {
			type = typeName, val = 0, hidden = true, duration = D.nTurns, turns = turns,
			sourceType = ENUM.BonusSource.other, sourceID = key, stacking = "h7Incap"
		}, false)
	end
	L.setShow(server, battle, t, self.show or "H4_STUN_H4C", turns, turns, "h7Incap", key, 0)
	L.setMark(server, battle, t, "h7IncapImmune", 1, turns + 2)
	server:showBattleAnimation(battle, { { unit = t } }, self.fx or "h7/fx/h7Incap", self.sound or "PARALYZE", 1.0, true)
	server:refreshBattleUnits(battle)
	if self.tint then
		local sp = nil
		pcall(function() sp = LIBRARY:getSpellByName(self.tint) end)
		if sp ~= nil then
			server:castSpell(battle, unit, sp, { t }, 0)
			Script.ensureTick(server, battle, unit)
		end
	end
	log(server, battle, self.log or 1, { L.name(unit), L.name(t) }, {})
end

function Script:swallow(server, battle, unit, t)
	if not roll(server, battle, unit, self.val or 0) then return end
	local n = math.floor(t:getCount() * (self.amount or 0) / 100)
	n = math.min(math.max(1, n), t:getCount())
	server:showBattleAnimation(battle, { { unit = t } }, "h4/fx/devour", "SLAYER", 1.0, true)
	local name = L.name(unit)
	local _, killed = server:damageUnit(battle, t, n * t:getMaxHealth())
	if killed and killed > 0 then log(server, battle, 4, { name, t:getCreature():getNameTextID(killed) }, { killed }) end
end

-- ---- Poison (Heroes IV poison attack) ----
local POISON = "H4_POISON_H4C"
local function poisoned(t)
	local list = t:getBonuses({ type = POISON }):filter(function(b) return b:getStacking() == "h4Poison" end)
	if list:size() == 0 then return nil end
	return list:getBonus(1):getVal()
end

local function ensureTick(server, battle, unit)
	local has = unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b) return b:getStacking() == "h4ProcTick" end)
	if has:size() > 0 then return end
	server:addBattleBonus(battle, {
		type = "COMBAT_EVENT_TRIGGER", subtype = "h4Proc", val = 0, hidden = true, addInfo = { mode = "tick" },
		duration = "ONE_BATTLE", sourceType = "OTHER", stacking = "h4ProcTick"
	})
end

Script.ensureTick = function(server, battle, unit) ensureTick(server, battle, unit) end

function Script:poison(server, battle, unit, t, damage)
	if t:hasBonuses({ type = "UNDEAD" }) or t:hasBonuses({ type = "NON_LIVING" }) or t:hasBonuses({ type = "MECHANICAL" }) then return end
	if t:getBonusesValue({ type = "LEVEL_SPELL_IMMUNITY" }) >= 5 then return end
	if poisoned(t) ~= nil then return end
	if not roll(server, battle, unit, self.val or 100) then return end
	local amount = math.max(1, math.floor(damage / 4))
	server:showBattleAnimation(battle, { { unit = t } }, "h4/fx/poison", "", 1.0, true)
	L.setShow(server, battle, t, POISON, amount, nil, "h4Poison", unit:getCreature():getJsonKey())
	L.setMark(server, battle, t, "h4Poison:left", self.turns or 15, nil)
	server:refreshBattleUnits(battle)
	ensureTick(server, battle, unit)
	log(server, battle, 5, { L.name(t) }, { amount })
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if self.mode == "quickness" then
		L.removeByStacking(server, battle, unit, "ADDITIONAL_ATTACK", "h4PotQuick")
		return
	end
	if self.mode == "berserk" then
		if unit:isAlive() and not unit:hasBonuses({ type = "NOT_ACTIVE" }) then self:berserkAdvance(server, battle, unit) end
		return
	end
	if self.mode ~= "tick" or not unit:isAlive() then return end
	-- Freeze tint: once the freeze (NOT_ACTIVE of h7Incap) has ended, the tint spell's effect is removed and the stack's colour returns
	if unit:getBonuses({ type = "STACKS_SPEED" }):filter(function(b) return b:getStacking() == "h4FrozenTint" end):size() > 0
		and unit:getBonuses({ type = "NOT_ACTIVE" }):filter(function(b) return b:getStacking() == "h7Incap" end):size() == 0 then
		L.removeByStacking(server, battle, unit, "STACKS_SPEED", "h4FrozenTint")
		server:refreshBattleUnits(battle)
	end
	local amount = poisoned(unit)
	if amount == nil then return end
	local left = (L.markValue(unit, "h4Poison:left") or 1) - 1
	if not unit:isInvincible() then
		server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7WitherTick", "", 1.0, true)
		local dealt, killed = server:damageUnit(battle, unit, amount)
		log(server, battle, 6, { L.name(unit) }, { dealt or amount })
		require("battleLog").creaturesPerish(server, battle, unit, killed)
	end
	if left > 0 and unit:isAlive() then
		L.setMark(server, battle, unit, "h4Poison:left", left, nil)
	else
		L.removeByStacking(server, battle, unit, POISON, "h4Poison")
		L.clearMark(server, battle, unit, "h4Poison:left")
	end
end


-- ---- Potion of Immortality: the first friendly stack wiped out is fully revived at once, once per battle (summons and clones excepted) ----
function Script:onDeath(server, battle, unit, other, payload)
	if self.mode ~= "immortal" then return end
	if unit:isAlive() or unit:isClone() or unit:copy():isSummoned() or unit:isTurret() then return end
	if L.markValue(unit, "h4PotImmortalSpent") ~= nil then return end
	-- Ring of Oblivion (hota.artifacts): stacks of the side wearing the ring cannot be revived (round 587)
	local okRing, ring = pcall(function() return unit:hasBonuses({ type = "HOTA_RING_OF_OBLIVION" }) end)
	if okRing and ring then return end
	local side = unit:getSide()
	local mine = battle:getUnitsIf(function(u) return u:getSide() == side end)
	for _, u in ipairs(mine) do L.setMark(server, battle, u, "h4PotImmortalSpent", 1, nil) end
	server:showBattleAnimation(battle, { { unit = unit } }, "h4/fx/precognition_potion", "RESURECT", 0.5, true)
	local n = unit:getBaseAmount()
	local _, raised = server:healUnit(battle, unit, n * unit:getMaxHealth(), ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	server:refreshBattleUnits(battle)
	if raised and raised > 0 then
		server:appendLog(battle, {
			append = { raised == 1 and "core.genrltxt.117" or "core.genrltxt.116" },
			replaceStrings = { unit:getCreature():getNameTextID(raised) },
			replaceNumbers = { raised }
		})
	end
end

-- ---- Martyr (protected stack): attack damage it takes is transferred to the martyr (val = martyr's id + 1) ----
function Script:onAfterAttacked(server, battle, unit, other, payload)
	if self.mode == "negateFirstStrike" then
		self:nfsAbsorb(server, battle, unit, other, payload)
		return
	end
	if self.mode == "block" then
		L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_REDUCTION", BLOCK)
		return
	end
	if self.mode ~= "martyrProt" then return end
	local entry = self:ownEntry(unit, payload)
	local dmg = entry and entry.damage or 0
	if dmg <= 0 then return end
	local id = (self.val or 0) - 1
	local m = battle:getUnitsIf(function(x) return x:isAlive() and x:unitID() == id end)[1]
	if m == nil or m:getSide() ~= unit:getSide() then return end
	server:healUnit(battle, unit, dmg, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	server:showBattleAnimation(battle, { { unit = m } }, "h4/fx/martyr_client", "", 1.0, true)
	local dealt = server:damageUnit(battle, m, dmg)
	server:refreshBattleUnits(battle)
	log(server, battle, 8, { L.name(m), L.name(unit) }, { dealt or dmg })
end

-- ---- Spell shackles: damage (val) on every cast ----
function Script:onUnitSpellcast(server, battle, unit, other, payload)
	if self.mode ~= "shackle" or not unit:isAlive() then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h4/fx/spell_shackle", "", 1.0, true)
	local dealt = server:damageUnit(battle, unit, self.val or 0)
	log(server, battle, 9, { L.name(unit) }, { dealt or self.val or 0 })
end

-- ---- Smoke: shots whose line crosses a smoke hex deal half damage to the target ----
local function axial(x, y) return x + math.floor(y / 2), y end
local function lineCells(ax, ay, bx, by)
	local q1, r1 = axial(ax, ay)
	local q2, r2 = axial(bx, by)
	local dq, dr = q2 - q1, r2 - r1
	local n
	if (dq >= 0 and dr >= 0) or (dq < 0 and dr < 0) then n = math.max(math.abs(dq), math.abs(dr)) else n = math.abs(dq) + math.abs(dr) end
	local cells = {}
	for i = 0, n do
		local t = (n == 0) and 0 or i / n
		local q = q1 + dq * t + 1e-6
		local r = r1 + dr * t + 1e-6
		local s = r - q  -- Third coordinate: distance = max(|dq|, |dr|, |dr - dq|)
		local rq, rr, rs = math.floor(q + 0.5), math.floor(r + 0.5), math.floor(s + 0.5)
		local eq, er, es = math.abs(rq - q), math.abs(rr - r), math.abs(rs - s)
		if eq > er and eq > es then rq = rr - rs elseif er > es then rr = rs + rq end
		local y = rr
		table.insert(cells, (rq - math.floor(y / 2)) * 100 + y)
	end
	return cells
end

local SMOKE_HIT = "h4SmokeHit"
function Script:smokeCheck(server, battle, unit, payload)
	local smoke = {}
	local found = false
	for _, o in ipairs(battle:getAllObstacles() or {}) do
		local sp = o:getSpell()
		if sp ~= nil then
			local k = sp:getJsonKey() or ""
			if k == "h4Smoke" or k:sub(-8) == ":h4Smoke" then
				local p = o:getPosition(); smoke[p:getX() * 100 + p:getY()] = true; found = true
			end
		end
	end
	if not found then return end
	local entry = payload.targets and payload.targets[1]
	local t = entry and entry.unit
	if t == nil then return end
	local a, b = unit:getPosition(), t:getPosition()
	for _, c in ipairs(lineCells(a:getX(), a:getY(), b:getX(), b:getY())) do
		if smoke[c] then
			server:addUnitBonus(battle, t, {
				type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeRanged", val = 50, hidden = true,
				duration = D.nTurns, turns = 1, sourceType = ENUM.BonusSource.other, sourceID = "h4Smoke", stacking = SMOKE_HIT
			}, false)
			return
		end
	end
end

-- ---- Berserk: charge toward the nearest enemy when none is in reach ----
local DIRS = { "copyToNorthWest", "copyToNorthEast", "copyToEast", "copyToSouthEast", "copyToSouthWest", "copyToWest" }

local function hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then return math.max(math.abs(dx), math.abs(dy)) end
	return math.abs(dx) + math.abs(dy)
end

local function distTo(pos, foe)
	local best = 1000
	local hs = foe:getHexes()
	for i = 1, hs:size() do
		local d = hexDistance(pos, hs:at(i))
		if d < best then best = d end
	end
	return best
end

-- Edge columns (0 and 16) and steps across the wall do not count; engine query errors also count as unable to move
local function canStep(battle, unit, from, to)
	local ok, r = pcall(function()
		return battle:isAccessibleForUnit(unit, to) and not battle:hasPenaltyOnLine(from, to, true, false)
	end)
	return ok and r == true
end

function Script:berserkAdvance(server, battle, unit)
	local foes = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isTurret() and battle:isHostile(unit, u)
	end)
	if #foes == 0 then return end
	-- Entangled stacks do not move; those that can still shoot (Frenzied Gnasher and others) stay and shoot (round 587)
	if unit:hasBonuses({ type = "BIND_EFFECT" }) then return end
	if unit:hasBonuses({ type = "SHOOTER" }) then return end
	local pos = unit:getPosition()
	local target, best = nil, 1000
	for _, f in ipairs(foes) do
		local d = distTo(pos, f)
		if d < best then best, target = d, f end
	end
	if target == nil or best <= 1 then return end
	local speed = unit:getBonusesValue({ type = "STACKS_SPEED" })
	local need = best - 1
	if need <= speed then return end
	-- First charge need - speed hexes, so the remaining distance is exactly what it can walk this round up to the enemy (round 587: it used to subtract 1 more and only moved 1 hex per round when close)
	local limit = math.min(speed, need - speed)
	-- Among hexes reachable within limit steps (breadth first, around stacks and obstacles), pick the one nearest to the target
	local function key(h) return h:getX() * 100 + h:getY() end
	local seen = { [key(pos)] = true }
	local parent = {}
	local frontier = { pos }
	local cur, curD, moved = pos, best, 0
	for step = 1, limit do
		local nextF = {}
		for _, h0 in ipairs(frontier) do
			for _, dir in ipairs(DIRS) do
				local h = h0[dir](h0)
				if h:isValid() and h:getX() > 0 and h:getX() < 16 and not seen[key(h)] and canStep(battle, unit, h0, h) then
					seen[key(h)] = true
					parent[key(h)] = h0
					table.insert(nextF, h)
					local d = distTo(h, target)
					if d < curD then cur, curD, moved = h, d, step end
				end
			end
		end
		frontier = nextF
		if #frontier == 0 then break end
	end
	if moved == 0 then return end
	-- Move hex by hex (one move to a far end point made the client slide straight through stacks and obstacles, round 587)
	local path = {}
	local h = cur
	while h ~= nil and key(h) ~= key(pos) do table.insert(path, 1, h) h = parent[key(h)] end
	for _, step in ipairs(path) do server:moveUnit(battle, unit, step, false) end
end


-- ---- Negate First Strike ----
local NFS = "h4NegFS"
local function firstStriker(u)
	return u ~= nil and u:hasBonuses({ type = "FIRST_STRIKE" })
end
function Script:nfsClear(server, battle, unit)
	for _, k in ipairs({ ":main", ":dmg", ":cnt", ":id" }) do
		if L.markValue(unit, NFS .. k) ~= nil then L.clearMark(server, battle, unit, NFS .. k) end
	end
end
function Script:nfsAbsorb(server, battle, unit, other, payload)
	-- Hit by a retaliation before acting itself = the opponent's first strike
	if not payload.isCounter or L.markValue(unit, NFS .. ":main") ~= nil then return end
	if other == nil or not battle:isHostile(unit, other) or not firstStriker(other) then return end
	local dmg = 0
	for _, e in ipairs(payload.targets or {}) do
		if e.unit ~= nil and e.unit:unitID() == unit:unitID() then dmg = e.damage or 0 end
	end
	if dmg <= 0 then return end
	server:healUnit(battle, unit, dmg, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	server:refreshBattleUnits(battle)
	L.setMark(server, battle, unit, NFS .. ":dmg", dmg, 1)
	L.setMark(server, battle, unit, NFS .. ":cnt", math.max(1, other:getCount()), 1)
	L.setMark(server, battle, unit, NFS .. ":id", other:unitID() + 1, 1)
	log(server, battle, 14, { L.name(unit), L.name(other) }, {})
end
function Script:nfsRetaliate(server, battle, unit, payload)
	local dmg = L.markValue(unit, NFS .. ":dmg")
	if dmg == nil then return end
	local cnt, id = L.markValue(unit, NFS .. ":cnt") or 1, (L.markValue(unit, NFS .. ":id") or 0) - 1
	L.clearMark(server, battle, unit, NFS .. ":dmg")
	local s = battle:getUnitsIf(function(x) return x:isAlive() and x:unitID() == id end)[1]
	if s == nil or s:hasBonuses({ type = "NOT_ACTIVE" }) or not unit:isAlive() or unit:isInvincible() then return end
	local d = math.floor(dmg * s:getCount() / cnt)
	if d <= 0 then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h4/fx/blank", "", 1.0, false)
	server:damageUnit(battle, unit, d)
end

-- ---- The target cannot retaliate against active attacks (Bone Dragon) ----
local NORET = "h4NoRetal"
function Script:onActionFinished(server, battle, unit, other, payload)
	if self.mode == "negateFirstStrike" then
		if other ~= nil and other:unitID() == unit:unitID() then self:nfsClear(server, battle, unit) end
		return
	end
	if self.mode ~= "noRetal" then return end
	if other == nil or other:unitID() ~= unit:unitID() then return end
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() end)) do
		L.removeByStacking(server, battle, u, "NO_RETALIATION", NORET)
	end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if self.mode == "negateFirstStrike" then
		if not payload.isCounter and (payload.attackIndex or 0) == 0 then self:nfsRetaliate(server, battle, unit, payload) end
		return
	end
	if self.mode == "tick" then
		for _, e in ipairs(payload.targets or {}) do
			if e.unit then L.removeByStacking(server, battle, e.unit, "GENERAL_DAMAGE_REDUCTION", SMOKE_HIT) end
		end
		return
	end
	if self.mode == "coward" then
		L.removeByStacking(server, battle, unit, "GENERAL_ATTACK_REDUCTION", "h4Coward")
		return
	end
	if self.mode == "poison" then
		if not unit:isAlive() or payload.isCounter == true and self.counter == false then return end
		local e = primary(unit, other, payload)
		if e ~= nil and (e.damage or 0) > 0 and L.canHit(battle, unit, e.unit) then self:poison(server, battle, unit, e.unit, e.damage) end
		return
	end
	local hit = { incap = true, swallow = true, spellHit = true, bolt = true, randomCurse = true }
	if not hit[self.mode] then return end
	if not unit:isAlive() or not self:allowed(payload) then return end
	local entry = primary(unit, other, payload)
	if entry == nil then return end
	local t = entry.unit
	if t == nil or not t:isAlive() then return end
	if self.mode == "spellHit" or self.mode == "bolt" or self.mode == "randomCurse" then
		-- As SPELL_AFTER_ATTACK: cast while the target is alive, no damage required
		if self.mode == "spellHit" then self:spellHit(server, battle, unit, t)
		elseif self.mode == "bolt" then self:bolt(server, battle, unit, t)
		else self:randomCurse(server, battle, unit, t) end
		return
	end
	if (entry.damage or 0) <= 0 then return end
	if not L.canHit(battle, unit, t) then return end
	if self.mode == "incap" then self:incap(server, battle, unit, t, payload) else self:swallow(server, battle, unit, t) end
end

-- ---- Casting after attacks (as the engine's SPELL_AFTER_ATTACK, but with Heroes IV effects) ----
--- spellHit: spell = original spell (effect, immunity and every mod's changes to it as the original); level = spell level (default 2); turns = duration (default the creature's CREATURE_ENCHANT_POWER, otherwise 3);
---           fx = hit effect; sound; log = battle log number (%s attacker, %s target)
--- bolt: Thunderbird lightning, damage = count x SPECIFIC_SPELL_POWER(spell), adjusted by spell's resistance and immunity; fx effect
--- randomCurse: the Evil Eye's random negative spell (same list and duration as h7MagicTouch), playing the Heroes IV effect of the same name
local function spellObj(name)
	local sp = nil
	pcall(function() sp = LIBRARY:getSpellByName(name) end)
	if sp == nil then pcall(function() sp = LIBRARY:getSpellByName("core:" .. name) end) end
	return sp
end

local function fromSpell(b, name)
	local id = b:getSourceID() or ""
	return id == name or id == "core:" .. name
end

local function hasSpellEffect(t, name)
	return t:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b) return fromSpell(b, name) end):size() > 0
end

local function enchantTurns(unit)
	local v = unit:getBonusesValue({ type = "CREATURE_ENCHANT_POWER" })
	if v == nil or v <= 0 then return 3 end
	return v
end

--- Magic resistance: as the engine's CStack::magicResistance, own resistance multiplied with adjacent allies' resistance aura (SPELL_RESISTANCE_AURA, the largest)
local function magicResistance(battle, t)
	local mr = math.max(0, math.min(100, t:getBonusesValue({ type = "MAGIC_RESISTANCE" }) or 0))
	local aura = 0
	local around = t:getSurroundingHexes()
	for _, u in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and u:unitID() ~= t:unitID() and not battle:isHostile(u, t) end)) do
		local a = u:getBonusesValue({ type = "SPELL_RESISTANCE_AURA" }) or 0
		if a > aura then
			local hexes = u:getHexes()
			for i = 1, hexes:size() do
				if around:contains(hexes:at(i)) then aura = a break end
			end
		end
	end
	aura = math.min(100, aura)
	return 100 - math.floor((100 - mr) * (100 - aura) / 100)
end

local function resisted(server, battle, t)
	local mr = magicResistance(battle, t)
	return mr > 0 and server:rngInt(1, 100) <= mr
end

function Script:spellHit(server, battle, unit, t)
	local sp = spellObj(self.spell)
	if sp == nil then return end
	if not roll(server, battle, unit, self.val or 100) then return end
	if sp:isNegative() and resisted(server, battle, t) then return end
	local had = hasSpellEffect(t, self.spell)
	server:applySpellEffects(battle, unit, sp, { t }, self.level or 2, self.turns or enchantTurns(unit), false)
	if not had and not hasSpellEffect(t, self.spell) then return end   -- Immunity (the original spell's own immunity rules)
	server:showBattleAnimation(battle, { { unit = t } }, self.fx or "", self.sound or "", 1.0, true)
	server:refreshBattleUnits(battle)
	log(server, battle, self.log or 12, { L.name(unit), L.name(t), sp:getNameTextID() }, {})
end

function Script:bolt(server, battle, unit, t)
	local sp = spellObj(self.spell or "thunderbolt")
	if sp == nil then return end
	if t:hasAbsoluteImmunity(sp) or L.spellImmune(t, self.spell or "thunderbolt") then return end
	-- Level immunity (lightning level 2), immunity to all negative spells and magic resistance also follow the spell (round 587)
	if (t:getBonusesValue({ type = "LEVEL_SPELL_IMMUNITY" }) or 0) >= (self.level or 2) then return end
	if t:hasBonuses({ type = "NEGATIVE_EFFECTS_IMMUNITY" }) then return end
	if not roll(server, battle, unit, self.val or 0) then return end
	if resisted(server, battle, t) then return end
	local power = unit:getBonusesValue({ type = "SPECIFIC_SPELL_POWER", subtype = self.spell or "thunderbolt" }) or 0
	local damage = sp:adjustDamage(battle, unit, t, unit:getCount() * power)
	if damage <= 0 then return end
	server:showBattleAnimation(battle, { { unit = t } }, self.fx or "", self.sound or "LIGHTBLT", 1.0, true)
	local dealt, killed = server:damageUnit(battle, t, damage)
	require("battleLog").spellDamage(server, battle, sp, t, dealt, killed)
end

local CURSE_FX = { misfortune = "h4/fx/misfortune", curse = "h4/fx/curse", forgetfulness = "h4/fx/forgetfulness",
	sorrow = "h4/fx/sorrow", slow = "h4/fx/slow", weakness = "h4/fx/weakness" }
function Script:randomCurse(server, battle, unit, t)
	if not L.canHit(battle, unit, t) or L.schoolImmune(t, "none") then return end
	if resisted(server, battle, t) then return end
	local cands = {}
	for _, d in ipairs(L.DEBUFFS) do
		local sp = spellObj(d.spell)
		if sp ~= nil and not L.spellImmune(t, d.spell) and not t:hasAbsoluteImmunity(sp) then table.insert(cands, d) end
	end
	if #cands == 0 then return end
	-- Tried one by one in random order, the first that really takes effect counts: the original spell's own target conditions (e.g. Forgetfulness only works on shooters)
	-- cannot be read in Lua, and a trigger must not be wasted on a spell that has no effect on the target
	for i = #cands, 2, -1 do
		local j = server:rngInt(1, i)
		cands[i], cands[j] = cands[j], cands[i]
	end
	local old = t:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		for _, d in ipairs(L.DEBUFFS) do if fromSpell(b, d.spell) then return true end end
		return false
	end)
	if old:size() > 0 then server:removeUnitBonuses(battle, t, old) end
	local pick, sp = nil, nil
	for _, d in ipairs(cands) do
		local s = spellObj(d.spell)
		server:applySpellEffects(battle, unit, s, { t }, 2, d.turns, false)
		if hasSpellEffect(t, d.spell) then pick, sp = d, s break end
	end
	if pick == nil then return end
	server:showBattleAnimation(battle, { { unit = t } }, CURSE_FX[pick.spell] or pick.anim, pick.sound, 1.0, true)
	server:refreshBattleUnits(battle)
	log(server, battle, 12, { L.name(unit), L.name(t), sp:getNameTextID() }, {})
end

-- Giant Slayer: checks the opponent's level before the exchange; if high enough, temporary Attack is added and removed when the exchange ends (after 1 round at the latest)
local SLAY = "h4GiantSlayer"
function Script:slay(server, battle, unit, foe)
	L.removeByStacking(server, battle, unit, "PRIMARY_SKILL", SLAY)
	if foe == nil or not battle:isHostile(unit, foe) then return end
	if foe:getCreature():getLevel() < (self.minLevel or 7) then return end
	server:addUnitBonus(battle, unit, {
		type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = self.attack or 20, hidden = true,
		duration = D.nTurns, turns = 1, sourceType = ENUM.BonusSource.other,
		sourceID = unit:getCreature():getJsonKey(), stacking = SLAY
	}, true)
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if self.mode == "negateFirstStrike" then
		if not payload.isCounter then L.setMark(server, battle, unit, NFS .. ":main", 1, 1) end
		return
	end
	if self.mode == "tick" then
		if payload.ranged and not payload.isCounter then self:smokeCheck(server, battle, unit, payload) end
		return
	end
	if self.mode == "coward" then
		if payload.isCounter or not unit:isAlive() then return end
		local e = primary(unit, other, payload)
		local t = (e and e.unit) or other
		L.removeByStacking(server, battle, unit, "GENERAL_ATTACK_REDUCTION", "h4Coward")
		if t ~= nil and t:getAvailableHealth() > unit:getAvailableHealth() then
			server:addUnitBonus(battle, unit, {
				type = "GENERAL_ATTACK_REDUCTION", val = 100, hidden = true, duration = D.nTurns, turns = 1,
				sourceType = ENUM.BonusSource.other, sourceID = "h4Cowardice", stacking = "h4Coward"
			}, false)
			log(server, battle, 10, { L.name(unit) }, {})
		end
		return
	end
	if self.mode == "noRetal" then
		if payload.isCounter or payload.ranged or not unit:isAlive() then return end
		local e = primary(unit, other, payload)
		local t = (e and e.unit) or other
		if t == nil or not t:isAlive() or not battle:isHostile(unit, t) then return end
		if t:hasBonuses({ type = "H4_FEAR_IMMUNE_H4C" }) then return end
		L.removeByStacking(server, battle, t, "NO_RETALIATION", NORET)
		server:addUnitBonus(battle, t, {
			type = "NO_RETALIATION", val = 0, hidden = true, duration = D.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), stacking = NORET
		}, false)
		return
	end
	if self.mode ~= "slayer" then return end
	local entry = primary(unit, other, payload)
	self:slay(server, battle, unit, entry and entry.unit or other)
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if self.mode == "block" then
		L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_REDUCTION", BLOCK)
		if not unit:isAlive() or other == nil or not battle:isHostile(unit, other) then return end
		if not roll(server, battle, unit, self.val or 30) then return end
		server:addUnitBonus(battle, unit, {
			type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 100, hidden = true,
			duration = D.nTurns, turns = 1, sourceType = ENUM.BonusSource.other, sourceID = "h4Block", stacking = BLOCK
		}, false)
		server:showBattleAnimation(battle, { { unit = unit } }, self.fx or "h4/fx/block", self.sound or "", 1.0, true)
		log(server, battle, self.log or 13, { L.name(unit) }, {})
		return
	end
	if self.mode ~= "slayer" then return end
	self:slay(server, battle, unit, other)
end

-- ---- Expansion divine artifacts: only own-school spells allowed (backlash) ----
function Script:divineGuard(server, battle, unit)
	local side = tostring(unit:getSide())
	local tag = "h4DivineWatch" .. side
	local has = unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b) return b:getStacking() == tag end)
	if has:size() > 0 then return end
	server:addBattleBonus(battle, {
		type = "COMBAT_EVENT_TRIGGER", subtype = "h4Proc", val = self.val or 20, hidden = true,
		addInfo = { mode = "divineWatch", side = side, schools = self.schools or {} },
		duration = "ONE_BATTLE", sourceType = "OTHER", stacking = tag
	})
end

local function schoolKey(name)
	name = tostring(name or "")
	name = string.gsub(name, "^.*:", "")
	name = string.gsub(name, "^spellSchool%.", "")
	return name
end

function Script:onSpellHit(server, battle, unit, other, payload)
	if self.mode ~= "divineWatch" then return end
	if other ~= nil then return end -- Creature casts are ignored
	local spell = payload.spell
	if spell == nil then return end
	local first = (payload.targets or {})[1]
	if first == nil or first.unit == nil or first.unit:unitID() ~= unit:unitID() then return end -- Each cast counts only once
	local allowed = {}
	for _, s in ipairs(self.schools or {}) do allowed[schoolKey(s)] = true end
	for _, sc in ipairs(spell:getSchools() or {}) do
		if allowed[schoolKey(sc:getJsonKey())] then return end
	end
	local hitSide = tostring(unit:getSide())
	local mine
	if spell:isPositive() then mine = (hitSide == self.side)
	elseif spell:isNegative() then mine = (hitSide ~= self.side)
	else return end
	if not mine then return end
	local pct = self.val or 20
	local victims = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isTurret() and tostring(u:getSide()) == self.side
	end)
	local fx = {}
	for _, u in ipairs(victims) do table.insert(fx, { unit = u }) end
	if #fx == 0 then return end
	server:showBattleAnimation(battle, fx, "h4/fx/spell_shackle", "", 1.0, true)
	for _, u in ipairs(victims) do
		local dmg = math.floor(u:getAvailableHealth() * pct / 100)
		if dmg > 0 then server:damageUnit(battle, u, dmg) end
	end
	log(server, battle, 11, {}, { pct })
end

return Script
