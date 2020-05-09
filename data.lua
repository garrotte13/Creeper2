local util = require "util"

-- By extending the `initial_flame_count` and `delay_between_initial_flames`,
-- the flames and its smoke can be extended for long periods, almost like
-- little brush fires are re-igniting.

local flame_0 = util.table.deepcopy (data.raw.fire["fire-flame"])
flame_0.name = "creeper-flame-0"
flame_0.initial_lifetime = 480  -- default: 120
flame_0.delay_between_initial_flames = 240 -- default: 10
flame_0.light.size = 10  -- default: 20
flame_0.working_sound.match_volume_to_activity = false

local flame_1 = util.table.deepcopy (flame_0)
flame_1.name = "creeper-flame-1"
flame_1.initial_lifetime = 960
flame_1.delay_between_initial_flames = 480

data:extend ({ flame_0, flame_1 })
