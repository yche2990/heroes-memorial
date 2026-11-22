--- Anathema (H6 Memorial Sanctum, Haven Warcry): all enemies for turns rounds: damage dealt -pct%, Defense -pct%, Morale and Luck -luck.
--- The source is not a spell effect, so it cannot be dispelled; each carries a visible "Anathema" status (H6_MM_STATUS_H6C, stacking h6MmAnathema), which Moment of Judgment recognizes.
--- Parameters: pct (4 numbers), luck, turns, animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script
Script.KEY = M.ANATHEMA

function Script:isValidTarget(mechanics, unit)
	return M.real(unit) and unit:getSide() ~= mechanics:getCasterSide()
end
function Script:isReceptive(mechanics, unit) return M.receptive(mechanics, unit) end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local p = S.pick(mechanics, self.pct)
	local turns = self.turns or 3
	local luck = self.luck or 1
	local units = {}
	for _, dest in ipairs(target) do if dest.unit and M.real(dest.unit) then units[#units + 1] = dest.unit end end
	if Proxy.trial(server) then
		for _, u in ipairs(units) do
			Proxy.buff(server, battle, u, { type = "GENERAL_DAMAGE_PREMY", val = -p, turns = turns })
			Proxy.buff(server, battle, u, { type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = -p, valueType = ENUM.BonusValueType.percentToAll, turns = turns })
		end
		return
	end
	L.show(server, battle, units, self.animation, self.sound)
	for _, u in ipairs(units) do
		M.clearAnathema(server, battle, u)
		local h = { hidden = true, stacking = Script.KEY }
		local function add(d) for k, v in pairs(h) do if d[k] == nil then d[k] = v end end; M.addOther(server, battle, u, d, turns) end
		add({ type = "GENERAL_DAMAGE_PREMY", val = -p })
		add({ type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = -p, valueType = ENUM.BonusValueType.percentToAll })
		add({ type = "MORALE", val = -luck })
		add({ type = "LUCK", val = -luck })
		add({ type = "H6_MM_ANATHEMA_H6C", val = p, hidden = false, icon = "h6/abilities/mm_Anathema" })
	end
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
