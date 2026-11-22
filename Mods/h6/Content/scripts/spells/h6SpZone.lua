--- H6 memorial hero spells, batch 3: places an obstacle or zone on the battlefield (Ice Wall, Wall of Rock, Frozen Ground, Blizzard, Poison Cloud).
--- The active part is one obstacle covering all zone hexes (one per hex before round 416); zones that settle every round or have visible strips to remove on expiry get one battlefield-level event h6SpZoneTick (one per cast).
--- Parameters: mode (disc / wall / rocks / idol (center hex only)), single (only one may exist), radius, turns (4 numbers, -1 = until the battle ends), passable, hidden, trap,
---       animation, appear, removal (persistent / appearing / fading animations),
---       fx (round 416: { D, E, group } persistent strip parameters, see h6SpLib.zoneFxList; with fx the appearing and fading animations play separately on the center hex),
---       tick (nil or { who, hostileOnly, base, per (4 numbers), school, status, animation, sound, now (also settles once at cast time) })
--- 2026-11-08 (AI skill fixes, review A2):
---   * transformTarget: the first entry is still the clicked hex (apply reads target[1].hex), followed by the stacks the zone will affect,
---     so the engine (getAffectedStacks) and the AI (BattleAI choosing where to drop location spells) can count the affected stacks; the neutral Ice Wall and Wall of Rock add nothing.
---   * AI simulation (Proxy.trial): no obstacle is placed and no settlement trigger added; the equivalent change the AI understands for one round of settlement is reported (see Script:trial), then return.
---   Real casting (describeChanges true) is unchanged.
--- Review C1: single (statue) is now one per side on the field: only that side's own existing one is dismantled (see zoneSides).
local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script
local BLANK = "h5/fx/fx_blank"

local function blocked(battle, h)
	return battle:getUnitByPos(h, true) ~= nil or #(battle:getObstaclesOnPos(h, false) or {}) > 0
end

function Script:applicableGeneral(mechanics, problem) return true end

function Script:applicableTarget(mechanics, problem, target)
	local dest = target[1]
	if dest == nil or dest.hex == nil or not dest.hex:isValid() or not dest.hex:isAvailable()
	   or (not self.passable and blocked(mechanics:getBattle(), dest.hex)) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local dest = spellTarget[1]
	if dest and dest.hex and dest.hex:isValid() then
		for _, h in ipairs(S.zoneHexes(mechanics:getBattle(), self.mode, dest.hex, self.radius, mechanics:getCasterSide())) do hexes:insert(h) end
	end
	return hexes
end

--- Stacks the zone will affect (only for transformTarget and the simulation; real settlement is still done obstacle by obstacle by h6SpLib.zoneTick, with the same rules):
---   With tick: tick.aura > 0 (statue) uses the aura rings around the center, otherwise the zone hexes; who = "adjacent" counts stacks touching the zone, otherwise stacks standing in it;
---     hostileOnly counts enemies only; with a bonus but no damage or status (statue, Shadow Veil) only the casting side's stacks count;
---   ground traps without tick (Frozen Ground trap): non-flying enemies within 2 hexes of the zone (that may walk in);
---   the rest (pure obstacles like Ice Wall and Wall of Rock): empty.
function Script:affected(mechanics, center)
	local battle = mechanics:getBattle()
	local side = mechanics:getCasterSide()
	local t = self.tick
	local out = {}
	if t == nil then
		if not self.trap then return out end
		local r = (self.radius or 1) + 2
		for _, u in ipairs(battle:getUnitsIf(function(x) return L.real(x) and x:getSide() ~= side and not x:hasBonuses({ type = "FLYING" }) end)) do
			if Proxy.unitDistance(u, center) <= r then out[#out + 1] = u end
		end
		return out
	end
	local hexes
	if (t.aura or 0) > 0 then hexes = S.zoneHexes(battle, "disc", center, t.aura, side)
	else hexes = S.zoneHexes(battle, self.mode, center, self.radius, side) end
	local buffOnly = t.bonus ~= nil and (t.base == nil and t.per == nil and t.status == nil)
	for _, u in ipairs(battle:getUnitsIf(function(x) return L.real(x) end)) do
		local mine = u:getSide() == side
		if not (t.hostileOnly and mine) and not ((t.alliedOnly or buffOnly) and not mine) then
			local ok = false
			for _, h in ipairs(hexes) do
				if t.who == "adjacent" then
					local uh = u:getHexes()
					for i = 1, uh:size() do if L.hexDistance(uh:at(i), h) == 1 then ok = true; break end end
				elseif u:coversPos(h) then ok = true end
				if ok then break end
			end
			if ok then out[#out + 1] = u end
		end
	end
	return out
end

--- Review A2: the target hex comes first, followed by the stacks that will be affected. Harmful spells list enemies (Poison Cloud hits friend and foe, so own stacks in the zone are listed too,
--- and the AI treats them as a downside when choosing the spot); beneficial spells list the casting side's stacks; neutral spells (Ice Wall, Wall of Rock) return as is, and the AI uses the engine's neutral location spell method
function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local aim = aimPoint[1]
	if aim == nil or aim.hex == nil or not aim.hex:isValid() then return spellTarget end
	if not mechanics:isPositive() and not mechanics:isNegative() then return spellTarget end
	local positive = mechanics:isPositive()
	local side = mechanics:getCasterSide()
	local list = { { hex = aim.hex } }
	for _, u in ipairs(self:affected(mechanics, aim.hex)) do
		-- Beneficial spells list only the casting side's stacks (enemies hit by the Storm Spirit's Chain Lightning are not listed: when choosing where to drop a beneficial spell, the AI counts listed enemies as a downside)
		if not positive or u:getSide() == side then list[#list + 1] = { unit = u, hex = u:getPosition() } end
	end
	return list
end

--- AI simulation: report the equivalent change the AI understands for one round of settlement (only called during Proxy.trial)
---   Damage (Blizzard, Poison Cloud, Storm Spirit's Chain Lightning): stacks in the zone that will be hit get one round's worth of Proxy.damage, adjusted like this spell's damage;
---     Poison Cloud hits friend and foe, so own stacks in the zone are charged as well (which keeps the AI from casting it on its own troops); Chain Lightning's first jump picks a random enemy in the zone, so it is averaged;
---   Status (Chilled): enemies in the zone count as 1 round of control at severity 0.25;
---   Buffs (Earth Spirit damage reduction, Storm Spirit Speed +2, Shadow Veil ranged / melee reduction): the casting side's stacks in the zone get the same native bonus (which the engine understands),
---     for the zone's duration in rounds (stacks standing in it get it again every round; zones lasting until battle end count as 3 rounds);
---   Frozen Ground (ground trap): enemies that may walk in count as 1 round of control at severity 0.25 x a half chance.
function Script:trial(mechanics, server, battle, center, side, covered)
	local t = self.tick
	local units = {}
	-- Round 420: when a one-per-side zone (statue) is recast, stacks the old one already covered add no new value, otherwise the AI would recast it in place every round;
	-- recasting removes the old one, so stacks covered by the old one but not the new one lose the effect; nothing is reported if the new one does not cover more stacks than are lost
	local inNew, lost = {}, 0
	for _, u in ipairs(self:affected(mechanics, center)) do
		inNew[u:unitID()] = true
		if not (covered and covered[u:unitID()]) then units[#units + 1] = u end
	end
	if covered then
		for id in pairs(covered) do if not inNew[id] then lost = lost + 1 end end
		if #units <= lost then units = {} end
	end
	if t == nil then
		if self.trap then
			for _, u in ipairs(units) do Proxy.damage(server, battle, u, u:getAvailableHealth() * Proxy.controlRatio(1, 0.25) * 0.5) end
		end
		return
	end
	local turns = S.pick(mechanics, self.turns)
	if turns <= 0 then turns = 3 end
	if t.bonus then
		for _, u in ipairs(units) do
			if u:getSide() == side then
				for _, b in ipairs(t.bonus) do
					local v = b.val
					if type(v) == "table" then v = S.pick(mechanics, v) end
					Proxy.buff(server, battle, u, { type = b.type, subtype = b.subtype, val = v or 0, turns = turns })
				end
			end
		end
	end
	local amount = math.floor(S.value(mechanics, t.base, t.per))
	local foes = {}
	for _, u in ipairs(units) do if u:getSide() ~= side then foes[#foes + 1] = u end end
	if amount > 0 then
		if t.chain then
			for _, u in ipairs(foes) do Proxy.damage(server, battle, u, S.spellDamage(mechanics, u, amount, t.school) / #foes) end
		else
			for _, u in ipairs(units) do
				if not (t.alliedOnly and u:getSide() ~= side) then Proxy.damage(server, battle, u, S.spellDamage(mechanics, u, amount, t.school)) end
			end
		end
	end
	if t.status then
		for _, u in ipairs(foes) do
			if u:isAlive() then Proxy.damage(server, battle, u, u:getAvailableHealth() * Proxy.controlRatio(1, 0.25)) end
		end
	end
end

--- Review C1: which side placed the same-named zone anchored at centerIdx. At cast time the spell name, casting side and center hex are written into the stacking group of the settlement trigger
--- ("h6SpZone:<spell>:<side>:<center>:<random>", a battlefield-level bonus inherited by every stack); it is looked up here on a living stack.
--- Returns { [side] = true }; zones cast before round 420 (without these in the stacking group) cannot be found and an empty table is returned
local function zoneSides(battle, key, centerIdx)
	local prefix = "h6SpZone:" .. key .. ":"
	local sides, scanned = {}, false
	battle:getUnitsIf(function(u)      -- The predicate is called for every stack, so the first living stack is scanned through a side effect
		if not scanned and u:isAlive() then
			scanned = true
			local list = u:getBonuses({ type = "COMBAT_EVENT_TRIGGER" })
			for i = 1, list:size() do
				local st = list:getBonus(i):getStacking() or ""
				if st:sub(1, #prefix) == prefix then
					local sd, c = st:sub(#prefix + 1):match("^(%d+):(%d+):")
					if sd and tonumber(c) == centerIdx then sides[tonumber(sd)] = true end
				end
			end
		end
		return false
	end)
	return sides
end

--- Center hexes carrying visible strips: one group per rock for Wall of Rock, otherwise only the center hex
function Script:fxCenters(battle, center, side)
	if self.fx and self.fx.group then return S.zoneHexes(battle, self.mode, center, self.radius, side) end
	return { center }
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local dest = target[1]
	if dest == nil or dest.hex == nil then return end
	local center = dest.hex
	local spell = mechanics:getSpell()
	local side = mechanics:getCasterSide()
	local turns = S.pick(mechanics, self.turns)
	if turns == 0 then turns = 1 end
	local fx = self.fx
	-- Review A2: in the AI simulation no obstacle is placed and no trigger added; the equivalent change of one round of settlement is reported, then return.
	-- The neutral Ice Wall and Wall of Rock do not go here (the AI already casts them; their simulation stays as before)
	if Proxy.trial(server) and (mechanics:isPositive() or mechanics:isNegative()) then
		local covered = nil
		if self.single then
			covered = {}
			local key = spell:getJsonKey()
			for _, o in ipairs(battle:getAllObstacles() or {}) do
				local s2 = o:getSpell()
				if s2 ~= nil and s2:getJsonKey() == key and zoneSides(battle, key, L.hexIndex(o:getPosition()))[side] then
					for _, u in ipairs(self:affected(mechanics, o:getPosition())) do covered[u:unitID()] = true end
				end
			end
		end
		self:trial(mechanics, server, battle, center, side, covered)
		return
	end
	if self.single then                       -- Only one may exist per side: first dismantle the side's existing one (the active obstacle's position is the old center hex)
		local key = spell:getJsonKey()
		for _, o in ipairs(battle:getAllObstacles() or {}) do
			local s2 = o:getSpell()
			if s2 ~= nil and s2:getJsonKey() == key then
				-- Review C1: the enemy's one stays; when the side cannot be told (old saves) it is dismantled as before
				local sides = zoneSides(battle, key, L.hexIndex(o:getPosition()))
				if next(sides) == nil or sides[side] then
					if fx then S.zoneFxClear(server, battle, self:fxCenters(battle, o:getPosition(), side), fx, self.removal, o:getPosition()) end
					server:removeObstacle(battle, o)
				end
			end
		end
	end
	local cells = {}
	for _, h in ipairs(S.zoneHexes(battle, self.mode, center, self.radius, side)) do
		if self.passable or not blocked(battle, h) then cells[#cells + 1] = h end
	end
	if #cells == 0 then return end
	-- Round 416: the engine queues obstacles one by one, each waiting for the previous appearing animation, and fades play backwards and block what follows, so:
	-- the appearing animation plays separately on the center hex (waiting until done); the visible persistent image is a group of inactive strips (h6SpLib.zoneFxPlace);
	-- only 1 obstacle is active, covering all zone hexes, with a blank 1-frame (invisible) appearance and persistent image. On expiry zoneTick removes the strips and plays the fading animation.
	if fx then
		if self.appear and self.appear ~= "" and server:describeChanges() then
			server:showBattleAnimation(battle, { { hex = center } }, self.appear, "", 1.0)
		end
		local centers = {}
		for _, c in ipairs(self:fxCenters(battle, center, side)) do
			for _, h in ipairs(cells) do if L.hexIndex(h) == L.hexIndex(c) then centers[#centers + 1] = c; break end end
		end
		S.zoneFxPlace(server, battle, centers, fx, self.animation, side, self.passable, self.hidden)
	end
	server:addObstacle(battle, {
		pos = center, obstacleType = ENUM.ObstacleType.spellCreated, spell = spell,
		casterSpellPower = S.power(mechanics), spellLevel = mechanics:getEffectLevel(), casterSide = side,
		turnsRemaining = turns, hidden = self.hidden or false, passable = self.passable or false, nativeVisible = false,
		trap = self.trap or false, removeOnTrigger = false, trigger = "",
		appearSound = "", appearAnimation = fx and BLANK or (self.appear or BLANK),
		animation = fx and BLANK or (self.animation or BLANK),
		removalAnimation = fx and "" or (self.removal or ""),
		customSize = cells,
	})
	local t = self.tick
	if (t or fx) and server:describeChanges() then
		-- Review A1: level is the casting level written when zoneTick adds bonuses (the schema of h6SpZoneTick allows extra fields)
		local info = { spell = spell:getJsonKey(), side = side, mode = self.mode, center = L.hexIndex(center), radius = self.radius or 1,
			level = mechanics:getEffectLevel() }
		if fx then
			local cs = {}
			for _, c in ipairs(self:fxCenters(battle, center, side)) do cs[#cs + 1] = L.hexIndex(c) end
			info.fx = { D = fx.D, E = fx.E, removal = self.removal, centers = cs }
		end
		if t then
			info.who = t.who or "inside"; info.hostileOnly = t.hostileOnly or false; info.amount = math.floor(S.value(mechanics, t.base, t.per))
			info.school = t.school; info.status = t.status; info.animation = t.animation; info.sound = t.sound
			info.aura = t.aura; info.alliedOnly = t.alliedOnly; info.chain = t.chain
			if t.bonus then
				info.bonus = {}
				for _, b in ipairs(t.bonus) do
					local v = b.val
					if type(v) == "table" then v = S.pick(mechanics, v) end
					info.bonus[#info.bonus + 1] = { type = b.type, subtype = b.subtype, val = v }
				end
			end
			if t.now then S.zoneTick(server, battle, info) end
		else
			info.fxOnly = true
		end
		server:addBattleBonus(battle, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6SpZoneTick", val = 0, duration = "ONE_BATTLE",
			-- Review C1: the stacking group carries the spell name, casting side and center hex (zoneSides uses them to tell whose statue it is), still ending in a random number, one per cast
			sourceType = "OTHER", stacking = "h6SpZone:" .. spell:getJsonKey() .. ":" .. tostring(math.floor(side)) .. ":" .. tostring(math.floor(L.hexIndex(center)))
				.. ":" .. tostring(server:rngInt(1, 999999999)), hidden = true, addInfo = info })
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

return Script
