-- before spreading check the tile that it wasn't mined out
-- from underneath us. gotta be present to spread.

local fire = {
    FLAME_TICKS = 19,
    FLAMES_PER_TICK = 31,
    -- XXX: These need to be programmatic based on the creeper flames
    -- XXX: and vice versa.
    SPREAD_DELAY = { 300, 180 },
    SPREAD_N_DELAY = { 480, 480 },
    SPREAD_LIMIT = { 100, 1000 }
}


local util = require "util"
local table_deepcopy = util.table.deepcopy

print = function(...) end

function fire.on_init()
    global.active_flames = {}

    -- Indexed by the seed flame index. Used to track how many more
    -- flames can be spawned by it and its descendants.
    global.spread_limits = {}
end


function fire.on_configuration_changed()
    -- Added in 1.1.0
    global.active_flames = {}
    global.spread_limits = {}
end


function __debug()
    if global.active_flames == nil then
        fire.on_init()
    end
end


function pos_key (entity)
    return table.concat ({
        entity.surface.index, ":",
        entity.position.x, ":",
        entity.position.y
    })
end


function FlameEntity (entity)
    local flame = {}
    setmetatable (flame, { __index = entity })
    flame.index = pos_key (entity)

    return flame
end


function filter_flame (entity)
    if not (entity and entity.valid) then return nil end
    if not entity.surface.valid then return nil end
    if entity.type ~= "fire" then return nil end

    return FlameEntity (entity)
end


function when_spread (whence, how)
    local parts
    if how then
        parts = fire.SPREAD_N_DELAY
    else
        parts = fire.SPREAD_DELAY
    end

    return whence + math.random (parts[1], parts[1] + parts[2])
end


function fire.on_trigger_created_entity (event)
    local flame = filter_flame (event.entity)
    if not flame then return end

    local surface = flame.surface
    local tile = surface.get_tile (flame.position)
    -- XXX: Move filter_tile to lib.lua
    if tile and tile.valid and tile.name == "kr-creep" then
        surface.set_tiles ({
            { name = "landfill", position = tile.position }
        })

        __debug()  -- XXX: CONFIG

        global.active_flames[flame.index] = {
            create_tick = event.tick,
            flame = flame,
            seed_index = flame.index,
            spawned_flames = 0,
            spread_tick = when_spread (event.tick)
        }
        global.spread_limits[flame.index] = math.random (
                fire.SPREAD_LIMIT[1], fire.SPREAD_LIMIT[2]
        )
        print (event.tick, "active_flames", serpent.line (global.active_flames))
        print (event.tick, "spread_limits", serpent.line (global.spread_limits))
    end
end


function spread_flame (tick, flame_info, flame_count)
    -- Bind locally.
    local active_flames = global.active_flames
    local spread_limits = global.spread_limits

    local math_random = math.random
    local table_insert = table.insert

    local surface = flame_info.flame.surface
    local surface_create_entity = surface.create_entity

    local surrounding_creep = surface.find_tiles_filtered {
        name = "kr-creep",
        position = flame_info.flame.position,
        radius = 2
    }

    local found_creep = table_size (surrounding_creep)
    local seed_index = flame_info.seed_index
    flame_count = math.min (found_creep, flame_count)

    local creeper_flames = {
        [0] = "creeper-flame-0",
        [1] = "creeper-flame-1"
    }

    local new_flames = {}
    local random_offset = math_random (0, found_creep)

    while flame_count > 0 do
        local tile_index = (flame_count + random_offset) % found_creep + 1
        local entity = surface_create_entity {
            name = creeper_flames[math_random (0, 1)],
            position = surrounding_creep[tile_index].position,
            force = flame_info.flame.force
        }

        if entity then
            local flame = FlameEntity (entity)
            local how = flame_info.spawned_flames > 0

            table_insert (new_flames, {
                create_tick = tick,
                flame = flame,
                seed_index = seed_index,
                spawned_flames = 0,
                spread_tick = when_spread (tick, how)
            })

            flame_info.spawned_flames = flame_info.spawned_flames + 1
        end

        flame_count = flame_count - 1
    end

    return new_flames, found_creep - table_size (new_flames)
end


function fire.spread_flames (event)
    -- TODO: Allows the spread to trees and vice-versa
    -- TODO: Wind speeds up spreading to direction
    -- TODO: Creep health by evolution
    -- TODO: Remove decoratives from burning, and slowly have them restored
    __debug()  -- XXX: @CONFIG

    -- Bind locally.
    local active_flames = global.active_flames
    local spread_limits = global.spread_limits
    local math_random = math.random

    if table_size(active_flames) > 0 then
        print (event.tick, "A) active_flames", serpent.line (global.active_flames))
    end
    if table_size (spread_limits) > 0 then
        print (event.tick, "A) spread_limits", serpent.line (global.spread_limits))
    end

    -- Table that contains tables of new flames that were generated.
    local new_flames = {}

    local processed = 0
    local tick = event.tick
    for index, flame_info in pairs (active_flames) do
        local spread_limit = spread_limits[flame_info.seed_index]

        if not spread_limit or spread_limit <= 0 then
            active_flames[index] = nil
            spread_limits[flame_info.seed_index] = nil
        elseif tick > flame_info.spread_tick then
            print (event.tick, "spreading")
            local flames, remaining_tiles = spread_flame (tick, flame_info, 1)

            if flames then
                table.insert (new_flames, flames)
                spread_limits[flame_info.seed_index] = spread_limit - 1
            end

            if remaining_tiles == 0 then
                -- No need to monitor this. We still need the
                -- `spread_limits` if this was the original flame.
                active_flames[index] = nil
            end

            processed = processed + 1
            if processed > fire.FLAMES_PER_TICK then
                break
            end
        end
    end

    -- Finalize all the spread flames, killing off the creep, and
    -- setting them up in the global tables.
    local landfill_by_surface = {}

    for _, flames in pairs (new_flames) do
        for _, flame_info in pairs (flames) do
            local flame = flame_info.flame

            local surface_index = flame.surface.index
            local landfill = { name = "landfill", position = flame.position }

            if landfill_by_surface[surface_index] then
                table.insert (landfill_by_surface[surface_index], landfill)
            else
                landfill_by_surface[surface_index] = { landfill }
            end

            active_flames[flame.index] = flame_info
        end
    end

    -- Nothing left to monitor.
    if table_size (active_flames) == 0 then
        spread_limits = {}
    end

    if table_size(new_flames) > 0 then
        print (event.tick, "B) active_flames", serpent.line (global.active_flames))
        print (event.tick, "B) spread_limits", serpent.line (global.spread_limits))
    end

    for surface_index, landscape_tiles in pairs (landfill_by_surface) do
        local surface = game.surfaces[surface_index]
        if surface and surface.valid then
            surface.set_tiles (landscape_tiles)
        end
    end
end


return fire
