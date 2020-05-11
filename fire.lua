-- TODO: See about spreading from trees. Unfortunately, an event doesn't
-- TODO:   trigger when trees are damaged by fire, unlike other entities.

-- TODO: Address @CONFIG migration before ship

local fire = {
    FLAME_TICKS = 19,
    -- XXX: These need to be programmatic based on the creeper flames
    -- XXX: and vice versa.
    SPREAD_DELAY = { 300, 180 },
    SPREAD_N_DELAY = { 240, 240 },
    SPREAD_LIMIT = { 100, 1000 },

    creeper_flames = {
        [0] = "creeper-flame-0",
        [1] = "creeper-flame-1",
        [2] = "creeper-flame-2",
        [3] = "creeper-flame-3",
    }
}



-- XXX: FIRE
script.on_nth_tick (fire.FLAME_TICKS, fire.spread_flames)
script.on_event (defines.events.on_trigger_created_entity, function (event)
    fire.on_trigger_created_entity (event)
end)

local util = require "shared"


table.insert_keyed_list = function (tbl, key, value)
    if tbl[key] == nil then
        tbl[key] = { value }
    else
        table.insert (tbl[key], value)
    end
end


--print = function(...) end


function fire.on_event (event)
    local action = event.name
    if action == "nth_tick_handler" then
    end
end


function fire.on_init()
    global.conditional_events = {}

    global.active_flames = {}
    global.by_tick = {}

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
    __debug()  -- XXX: CONFIG

    local flame = filter_flame (event.entity)
    if not flame then return end

    local surface = flame.surface
    local tile = surface.get_tile (flame.position)
    -- XXX: Move filter_tile to lib.lua
    if tile and tile.valid and tile.name == "kr-creep" then
        surface.set_tiles ({
            { name = "landfill", position = tile.position }
        })

        local force = flame.force

        -- XXX: This doesn't work. It's as if the effect is
        -- something else, but I cannot "find" it to remove it.
        flame.destroy()

        -- Replace it with ours since it is on creep.
        local entity = surface.create_entity {
            name = fire.creeper_flames[0],
            position = tile.position,
            force = force
        }

        local new_flame = FlameEntity (entity)

        local flame_info = {
            create_tick = event.tick,
            flame = new_flame,
            seed_index = new_flame.index,
            spawned_flames = 0,
            spread_tick = when_spread (event.tick)
        }
        global.active_flames[new_flame.index] = flame_info
        table.insert_keyed_list (
                global.by_tick, flame_info.spread_tick, new_flame.index
        )
        global.spread_limits[new_flame.index] = math.random (
                fire.SPREAD_LIMIT[1], fire.SPREAD_LIMIT[2]
        )
    end
end


function spread_flame (tick, flame_info, flame_count)
    -- Bind locally.
    local math_random = math.random
    local table_insert = table.insert

    local surface = flame_info.flame.surface
    local surface_create_entity = surface.create_entity

    local surrounding_creep = surface.find_tiles_filtered {
        name = "kr-creep",
        position = flame_info.flame.position,
        radius = 2.5
    }

    local found_creep = table_size (surrounding_creep)
    local seed_index = flame_info.seed_index
    flame_count = math.min (found_creep, flame_count)

    local new_flames = {}
    local random_offset = math_random (0, found_creep)

    while flame_count > 0 do
        local tile_index = (flame_count + random_offset) % found_creep + 1
        local position = surrounding_creep[tile_index].position
        position.x = position.x + math_random() / 2
        position.y = position.y + math_random() / 2

        local entity = surface_create_entity {
            name = fire.creeper_flames[math_random (1, 3)],
            position = position,
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
    __debug()  -- XXX: @CONFIG

    -- Bind locally.
    local active_flames = global.active_flames
    local by_tick = global.by_tick
    local spread_limits = global.spread_limits

    -- Table that contains tables of new flames that were generated.
    local new_flames = {}

    if table_size(active_flames) > 0 or table_size(by_tick) > 0 or table_size (spread_limits) > 0 then
        --print (event.tick, table_size(active_flames), table_size(by_tick), table_size (spread_limits))
    end

    local tick = event.tick
    for t = tick - fire.FLAME_TICKS + 1, tick do
        local now_flame_indices = by_tick[t] or {}
        for k, index in pairs (now_flame_indices) do
            local flame_info = active_flames[index]
            if not flame_info then goto continue end

            local spread_limit = spread_limits[flame_info.seed_index]
            if not spread_limit or spread_limit <= 0 then
                active_flames[index] = nil
                spread_limits[flame_info.seed_index] = nil
            elseif not flame_info.flame.valid then
                active_flames[index] = nil
            else
                local flames, remaining_tiles = spread_flame (tick, flame_info, 1)
                flame_info.spread_tick = when_spread (tick, true)
                table.insert_keyed_list (
                        by_tick,
                        flame_info.spread_tick,
                        flame_info.flame.index
                )

                if flames then
                    table.insert (new_flames, flames)
                    spread_limits[flame_info.seed_index] = spread_limit - 1
                end

                if remaining_tiles == 0 then
                    -- No need to monitor this. We still need the
                    -- `spread_limits` if this was the original flame.
                    active_flames[index] = nil
                end
            end
            ::continue::
        end
        -- All of these for this tick has been processed.
        by_tick[t] = nil
    end

    -- Finalize all the spread flames, killing off the creep, and
    -- setting them up in the global tables.
    local landfill_by_surface = {}

    for _, flames in pairs (new_flames) do
        for _, flame_info in pairs (flames) do
            local flame = flame_info.flame

            local surface_index = flame.surface.index
            local landfill = { name = "landfill", position = flame.position }

            table.insert_keyed_list (
                    landfill_by_surface,
                    surface_index,
                    landfill
            )

            active_flames[flame.index] = flame_info
            table.insert_keyed_list (
                    by_tick, flame_info.spread_tick, flame.index
            )
        end
    end

    -- Nothing left to monitor.
    if table_size (active_flames) == 0 then
        global.spread_limits = {}
    end

    for surface_index, landscape_tiles in pairs (landfill_by_surface) do
        local surface = game.surfaces[surface_index]
        if surface and surface.valid then
            surface.set_tiles (landscape_tiles)
        end
    end
end


return fire
