local Base = require("combat/combatScript")
local A = require("heroes-memorial.h7:combat/h7AuraLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 adjacent ally aura (visible ability on aura creatures; shared by Pure Aura, Light Resistance of Heart of Darkness, Raise Shields, Soul Fire, Inspiring Presence and Fire Aura).
--- The aura kind comes from the subtype (script name), the value from val; the actual effects are in KINDS of combat/h7AuraLib.
--- This only recalculates at battle start, at the start of each round and when the aura creature dies; after other stacks act, the battle-wide hidden script combat/h7AuraZone recalculates.

function Script:onBattleStart(server, battle, unit) A.refresh(server, battle) end
function Script:onRoundStart(server, battle, unit) A.refresh(server, battle) end
function Script:onDeath(server, battle, unit) A.refresh(server, battle) end

return Script
