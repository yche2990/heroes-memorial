local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Chain Shot (H5 Succubus Mistress)
--- After a shot hits, the arrow jumps to the enemy nearest to the previous target, at most targets more (default 3),
--- each jump dealing factor% (default 50%) of the previous. Demons are not affected by Chain Shot.
--- Parameters: targets, factor

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	local first, entry = A.primary(payload, other)
	if first == nil or entry == nil then return end
	local damage = entry.damage or 0
	if damage <= 0 then return end

	local side = unit:getSide()
	local hitIds = { [first:unitID()] = true }
	local last = first
	local factor = (self.factor or 50) / 100
	for _ = 1, (self.targets or 3) do
		damage = math.floor(damage * factor)
		if damage <= 0 then break end
		local cands = battle:getUnitsIf(function(u)
			return A.hostile(battle, unit, u) and A.damageable(u) and not hitIds[u:unitID()] and not A.isDemon(u)
		end)
		if #cands == 0 then break end
		table.sort(cands, function(a, b)
			local da, db = A.unitDistance(last, a), A.unitDistance(last, b)
			if da ~= db then return da < db end
			return a:unitID() < b:unitID()
		end)
		local nxt = cands[1]
		hitIds[nxt:unitID()] = true
		A.hit(server, battle, nxt, damage, "h5/fx/Characters_Creatures_Inferno_SuccubusShot_SuccubusShotHit", "")
		last = nxt
	end
end

return Script
