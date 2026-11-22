local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Knockback / pull (H4-H7 mechanic port, round 126; animations added in round 129)
---
--- Knockback (mode = "push"): after a melee attack the target is pushed range hexes (default 1) away from the attacker.
--- Pull (mode = "pull"): after a shot the target is pulled toward the shooter, at most range hexes (default 2), stopping one hex short of the shooter.
---
--- Pushing/pulling happens only after the whole action (counterattacks and double attacks included): the attack only puts a hidden mark on the target, which is handled when the action ends,
--- so the pushed stack does not counterattack from a distance and the second strike does not miss.
--- It cannot be moved when a stack or obstacle is behind it, at the edge of the battlefield, or when it would cross a wall; war machines, arrow towers and stacks immune to charge (CHARGE_IMMUNITY) are not affected.
---
--- Parameters:
---   val    trigger chance (%), default 100
---   mode   "push" or "pull"
---   range  maximum hexes moved
---   fx, sound  animation and sound played where the target lands (default the Earthquake dust C05SPW, ERTHQUAK; fx "" plays no animation). Added in round 585 so the Heroes IV Bone Dragon can use the H4 fear effect
---   immune  optional list of bonus type names: targets with any of them are not pushed or pulled (added in round 587, so the Heroes IV Bone Dragon's fear knockback does not push stacks immune to fear or mind spells)
---   mark   name of this mod's hidden mark bonus (each mod uses a different name, e.g. "H47_SHOVE_MOONSPIRE")
---          Value descriptions 1 and 2 of the mark are battle log texts (knockback, pull)

local DIRS = { "copyToNorthWest", "copyToNorthEast", "copyToEast", "copyToSouthEast", "copyToSouthWest", "copyToWest" }

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

local function toList(arr)
	local list = {}
	for i = 1, arr:size() do list[#list + 1] = arr:at(i) end
	return list
end

local function minDistance(hexesA, hexesB)
	local best = 1000
	for _, a in ipairs(hexesA) do
		for _, b in ipairs(hexesB) do
			local d = hexDistance(a, b)
			if d < best then best = d end
		end
	end
	return best
end

local function shift(hexes, dir)
	local out = {}
	for i, h in ipairs(hexes) do
		local n = h[dir](h)
		if not n:isValid() or not n:isAvailable() then return nil end
		out[i] = n
	end
	return out
end

local function immovable(u)
	if u:isTurret() then return true end
	if u:hasBonuses({ type = "SIEGE_WEAPON" }) then return true end
	if u:hasBonuses({ type = "CHARGE_IMMUNITY" }) then return true end
	return false
end

--- Position of the stack after one step from pos in direction dir; nil if it cannot move
local function step(battle, unit, pos, hexes, dir)
	local newPos = pos[dir](pos)
	if not newPos:isValid() or not newPos:isAvailable() then return nil end
	local newHexes = shift(hexes, dir)
	if newHexes == nil then return nil end
	if not battle:isAccessibleForUnit(unit, newPos) then return nil end
	if battle:hasPenaltyOnLine(pos, newPos, true, false) then return nil end
	return newPos, newHexes
end

local function tagOf(unit)
	return unit:unitID() + 1
end

local function ownMarks(self, u, tag)
	return u:getBonuses({ type = self.mark }):filter(function(b)
		return b:getVal() == tag
	end)
end

local function clearMarks(self, server, battle, tag)
	local marked = battle:getUnitsIf(function(u)
		return u:hasBonuses({ type = self.mark })
	end)
	for _, u in ipairs(marked) do
		local list = ownMarks(self, u, tag)
		if list:size() > 0 then server:removeUnitBonuses(battle, u, list) end
	end
end

function Script:wantsAttack(payload)
	if payload.isCounter then return false end
	if self.mode == "pull" then return payload.ranged == true end
	return not payload.ranged
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not self:wantsAttack(payload) then return end
	if not unit:isAlive() then return end

	local tag = tagOf(unit)
	if (payload.attackIndex or 0) == 0 then
		clearMarks(self, server, battle, tag)
	end

	local target = other
	if target == nil and payload.targets and payload.targets[1] then target = payload.targets[1].unit end
	if target == nil or not target:isAlive() then return end
	if target:unitID() == unit:unitID() then return end
	if immovable(target) then return end
	for _, ty in ipairs(self.immune or {}) do
		if target:hasBonuses({ type = ty }) then return end
	end
	if ownMarks(self, target, tag):size() > 0 then return end

	local chance = self.val or 100
	if chance < 100 and server:rngInt(1, 100) > chance then return end

	server:addUnitBonus(battle, target, {
		type       = self.mark,
		val        = tag,
		duration   = ENUM.BonusDuration.nTurns,
		turns      = 1,
		sourceType = ENUM.BonusSource.other,
		sourceID   = unit:getCreature():getJsonKey(),
		hidden     = true
	}, false)
end

--- Knockback: pushed along the attack direction
function Script:pushTarget(battle, unit, target)
	local pos = target:getPosition()
	local hexes = toList(target:getHexes())
	local mine = toList(unit:getHexes())

	-- Attack direction: the direction in which one step from a hex of the attacker reaches the target
	local dirs = {}
	for _, dir in ipairs(DIRS) do
		for _, a in ipairs(mine) do
			local n = a[dir](a)
			if n:isValid() and target:coversPos(n) then
				dirs[#dirs + 1] = dir
				break
			end
		end
	end

	for _, dir in ipairs(dirs) do
		local p, hs = pos, hexes
		local moved = 0
		for _ = 1, (self.range or 1) do
			local np, nh = step(battle, target, p, hs, dir)
			if np == nil then break end
			p, hs = np, nh
			moved = moved + 1
		end
		if moved > 0 then return p end
	end
	return nil
end

--- Pull: each step picks the direction nearest the shooter, without ending next to the shooter
function Script:pullTarget(battle, unit, target)
	local p = target:getPosition()
	local hs = toList(target:getHexes())
	local mine = toList(unit:getHexes())
	local moved = 0

	for _ = 1, (self.range or 2) do
		local current = minDistance(hs, mine)
		local bestPos, bestHexes, bestDist = nil, nil, current
		for _, dir in ipairs(DIRS) do
			local np, nh = step(battle, target, p, hs, dir)
			if np ~= nil then
				local d = minDistance(nh, mine)
				if d >= 2 and d < bestDist then
					bestPos, bestHexes, bestDist = np, nh, d
				end
			end
		end
		if bestPos == nil then break end
		p, hs = bestPos, bestHexes
		moved = moved + 1
	end

	if moved > 0 then return p end
	return nil
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end

	local tag = tagOf(unit)
	local marked = battle:getUnitsIf(function(u)
		return u:hasBonuses({ type = self.mark })
	end)

	for _, target in ipairs(marked) do
		local list = ownMarks(self, target, tag)
		if list:size() > 0 then
			server:removeUnitBonuses(battle, target, list)

			if unit:isAlive() and target:isAlive() and not immovable(target) then
				local dest
				if self.mode == "pull" then
					dest = self:pullTarget(battle, unit, target)
				else
					dest = self:pushTarget(battle, unit, target)
				end

				if dest ~= nil then
					if self.mode == "pull" then
						-- Pull: first play the vines of Binding on the target, then drag it over with a movement animation
						server:showBattleAnimation(battle, { { unit = target } }, "SP02_", "BIND", 1.0, true) server:refreshBattleUnits(battle)
						server:moveUnit(battle, target, dest, false)
					else
						-- Knockback: teleport to the new position (so the pushed stack does not turn and walk), then raise Earthquake dust where it lands
						server:moveUnit(battle, target, dest, true)
						local fx = self.fx or "C05SPW"
						if fx ~= "" then
							server:showBattleAnimation(battle, { { unit = target } }, fx, self.sound or "ERTHQUAK", 1.0, true) server:refreshBattleUnits(battle)
						end
					end
					server:appendLog(battle, {
						append         = { "core.bonus." .. self.mark .. ".description." .. (self.mode == "pull" and "2" or "1") },
						replaceStrings = {
							unit:getCreature():getNameTextID(2),
							target:getCreature():getNameTextID(2)
						}
					})
				end
			end
		end
	end
end

return Script
