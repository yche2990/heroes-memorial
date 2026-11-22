local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Flamewave (H5 Warlord)
--- After an active melee attack there is a chance (trigger factor pf, default 2) to raise a fan-shaped flame wave: length rows behind the target (default 5),
--- row N is 2N-1 hexes wide (1, 3, 5, 7, 9); stacks in the rows behind the target (friend or foe, this stack excepted, Fire-immune ones unaffected) take D/N Fire damage,
--- D = this stack's count x random damage (no attack/defense factor). The target itself already took this hit and is not counted as row 1.
--- Parameters: pf, length

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	local target, entry = A.primary(payload, other)
	if target == nil then return end
	local before = entry and entry.healthBeforeAttack or nil
	local chance = A.procChance(unit, target, self.pf or 2, before)
	if not A.roll(server, battle, unit, chance) then return end

	local from = A.nearestHex(unit, target)
	local to = A.nearestHex(target, unit)
	local dA = A.hexDistance(from, to)
	if dA == 0 then return end
	local length = self.length or 5
	local base = A.rawDamage(server, unit, 100, false)
	local arr = battle:getAllPossibleHexes()
	local victims, seen = {}, { [unit:unitID()] = true, [target:unitID()] = true }
	for i = 1, arr:size() do
		local h = arr:at(i)
		local row = A.unitHexDistance(target, h) + 1 -- Which row (the target's is row 1)
		if row >= 2 and row <= length and A.hexDistance(from, h) >= dA + (row - 1) then
			local u = battle:getUnitByPos(h, true)
			if u ~= nil and not seen[u:unitID()] and A.damageable(u) and not A.fireImmune(u) then
				seen[u:unitID()] = true
				table.insert(victims, { unit = u, row = row })
			end
		end
	end
	if #victims == 0 then return end
	table.sort(victims, function(a, b) return a.unit:unitID() < b.unit:unitID() end)
	server:showBattleAnimation(battle, { { unit = target } }, "h5/fx/Characters_Creatures_Dwarves_Flamewave_Effect", "SPONTCOMB", 1.0, true)
	for _, v in ipairs(victims) do
		local u = v.unit
		if u:isAlive() then
			local dmg = math.floor(base / v.row * (100 - A.fireReduction(u)) / 100)
			if dmg > 0 then A.hit(server, battle, u, dmg, nil, nil) end
		end
	end
end

return Script
