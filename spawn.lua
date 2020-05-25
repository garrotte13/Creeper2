local pollution = require "pollution"
local util = require "utils"


local CREEP_NTH_TICKS = 7
local CREEP_SEARCH_RADIUS = 12
local POLLUTION_POWER = 1.2
local THETA_OFFSET = math.pi / 4
local TILES_PER_INTERVAL = 16


-- Cached setting values.
local creep_chance_on_death = 0
local creep_growth = 0
local creep_tile_immunity = 0


-- Local binds.
local math_random = math.random
local filter_tile = util.filter_tile
local filter_spawner = util.filter_spawner
local filter_surface = util.filter_surface
local table_deepcopy = util.table.deepcopy


local creep_iterative_search = function (creep)
    -- REQUIRES: valid spawner/surface

    local surface = creep.spawner.surface
    creep.spawn_position = nil

    if not surface then
        creep.search_position = nil
        return
    end

    local creep_position
    local x = creep.search_position.x
    local y = creep.search_position.y
    local dx = creep.theta.dx
    local dy = creep.theta.dy
    local iterations = 0
    local position

    repeat
        x = x + dx
        y = y + dy

        position = { x = x, y = y }

        local tile = filter_tile (surface.get_tile (position))
        if not tile then
            -- Abort the iterative search.
            position = nil
        elseif tile.prototype.walking_speed_modifier >= creep_tile_immunity then
            -- Abort here to prevent spending time searching a
            -- huge swath of immune tiles (similar to lakes and
            -- ribbon world edges). It has the plus (or maybe it's a
            -- minus) that creep won't jump immune tiles, encouraging
            -- the "abuse" of the mechanic.
            position = nil
        elseif tile.name ~= "kr-creep" then
            creep_position = tile.position
        end

        iterations = iterations + 1
    until creep_position or iterations >= TILES_PER_INTERVAL or not position

    if creep_position then
        creep.spawn_position = creep_position
    else
        -- This will either be the save point to continue next time,
        -- or it will be nil indicating to stop completely.
        creep.search_position = position
    end

    return creep.search_position
end


local creep_search_position = function (surface, position)
    -- REQUIRES: valid surface

    local creeps = surface.find_tiles_filtered {
        position = position,
        radius = CREEP_SEARCH_RADIUS,
        name = "kr-creep",
    }
    local creeps_len = table_size (creeps)

    if creeps_len == 0 then
        -- This is a special case where Krastorio/Rampant didn't spawn
        -- creep under the spawner, or it's burned away and the
        -- spawner didn't die.
        local tile = filter_tile (surface.get_tile (position))
        if tile.name == "kr-creep" then
            -- We started on creep but couldn't find anything.
            return nil
        end

        creeps = { tile }
        creeps_len = 1
    end

    local search_position
    local rnd = math_random (1, creeps_len)
    for i=rnd, rnd + creeps_len do
        local tile = filter_tile (creeps[i % rnd + 1])
        if tile then
            search_position = tile.position
            break
        end
    end

    return search_position
end


local spawn_creep = function (surface, position, creeps)
    -- REQUIRES: valid surface

    local offsets = {
        {-1, -1}, {0, -1}, {1, -1},
        {-1,  0}, {0,  0}, {1,  0},
        {-1,  1}, {0,  1}, {1,  1}
    }
    local tiles = {}

    -- Bind locally.
    local surface_get_tile = surface.get_tile

    local find_free_tiles = function (find_pos)
        -- Used to track if we've found at least one drop-off
        -- in a full cycle. If we haven't, we abort wholesale
        -- because we may have wandered into the middle of an
        -- area that just wastes time finding nothing.
        local found_tile = true

        while creeps > 0 and found_tile do
            found_tile = false

            local dir = math_random (1, 9)
            for i = dir, dir+9 do
                local off = offsets[i % 9 + 1]
                local pos = { x = find_pos.x + off[1], y = find_pos.y + off[2] }

                local pt_key = pos.x .. ":" .. pos.y
                if not tiles[pt_key] then
                    local tile = filter_tile (surface_get_tile (pos))
                    if tile
                            and tile.name ~= "kr-creep"
                            and tile.prototype.walking_speed_modifier < creep_tile_immunity
                    then
                        tiles[pt_key] = {
                            name = "kr-creep",
                            position = tile.position
                        }

                        find_pos = tile.position
                        creeps = creeps - 1
                        found_tile = true
                        -- Break and and search the next near tile.
                        break
                    end
                end
            end
        end
    end

    find_free_tiles (position)

    local creep_tiles = {}
    local spawned = 0

    local table_insert = table.insert

    -- Not a fan of reaching over to `pollution` from here,
    local defer_chunk = pollution.defer_chunk
    for _, tile in pairs (tiles) do
        defer_chunk {surface, tile.position}

        table_insert (creep_tiles, tile)
        spawned = spawned + 1
    end

    surface.set_tiles (creep_tiles)

    -- If we were able to find space for some, then requeue the leftovers
    -- so it tries again.
    if spawned > 0 and creeps > 0 then
        return creeps
    end
end


local surrounding_chunk_pollutions = function (surface, position)
    -- REQUIRES: valid surface

    local chunks = {}
    local p = table_deepcopy (position)

    -- Bind locally.
    local math_pi = math.pi
    local surface_get_pollution = surface.get_pollution

    -- defines.direction.northwest
    p.x = p.x - 32
    p.y = p.y - 32
    chunks[1] = {
        pollution = surface_get_pollution (p),
        theta=3 * math_pi / 4
    }

    -- defines.direction.north
    p.x = p.x + 32
    chunks[2] = {
        pollution = surface_get_pollution (p),
        theta = math_pi / 2
    }

    -- defines.direction.northeast
    p.x = p.x + 32
    chunks[3] = {
        pollution = surface_get_pollution (p),
        theta = math_pi / 4
    }

    -- defines.direction.east
    p.y = p.y + 32
    chunks[4] = {
        pollution = surface_get_pollution (p),
        theta = 0
    }

    -- defines.direction.west
    p.x = p.x - (32 * 2)  -- skipping over this "position" chunk
    chunks[5] = {
        pollution = surface_get_pollution (p),
        theta = math_pi
    }

    -- defines.direction.southwest
    p.y = p.y - 32
    chunks[6] = {
        pollution = surface_get_pollution (p),
        theta = 5 * math_pi / 4
    }

    -- defines.direction.south
    p.x = p.x + 32
    chunks[7] = {
        pollution = surface_get_pollution (p),
        theta = 3 * math_pi / 2
    }

    -- defines.direction.southeast
    p.x = p.x + 32
    chunks[8] = {
        pollution=surface_get_pollution (p),
        theta = 7 * math_pi / 4
    }

    return chunks
end


local weighted_random_pollution = function (chunks)
    local fudge = table_size (chunks) / 1.0

    -- Bind locally.
    local math_pow = math.pow

    local function scaling (what)
        -- Moar weight!
        return math_pow (what+1, POLLUTION_POWER) + fudge
    end

    local factor = 0
    for _, chunk_data in ipairs (chunks) do
        factor = factor + scaling (chunk_data.pollution)
    end

    local random_value = math.random()
    local weight = 0
    for _, chunk_data in ipairs (chunks) do
        weight = weight + scaling (chunk_data.pollution)
        if random_value <= weight / factor then
            return chunk_data
        end
    end
end


local init_search_params = function (creep)
    -- REQUIRES: valid creep_state/spawner/surface

    local surface = creep.spawner.surface
    local position = creep.spawner.position

    creep.search_position = creep_search_position (surface, position)
    if not creep.search_position then
        return false
    end

    -- Figure out the target area the creep should grow toward.
    local chunks = surrounding_chunk_pollutions (surface, position)
    local target_chunk = weighted_random_pollution (chunks)

    local theta = target_chunk.theta

    -- Randomize the angle (within an arc) to search toward.
    local theta_min = theta - THETA_OFFSET
    theta = theta_min + THETA_OFFSET * math.random()

    local dx = math.cos (theta)
    local dy = -math.sin (theta)  -- y-axis goes down

    -- Path to search for free tiles.
    creep.theta = { dx = dx, dy = dy }
    return true
end


local init_creep_state = function (spawner)
    return {
        state = "wait",
        creep_count = 0,
        spawner = spawner,
    }
end


local spawner_event = function (spawner)
    if not filter_spawner (spawner) then return nil end

    local unit_number = spawner.unit_number

    if not global.creep_state[unit_number] then
        global.creep_state[unit_number] = init_creep_state (spawner)
    end

    local creep = global.creep_state[unit_number]

    -- In all states, when a unit spawns, the creep count can increase.
    local spawn = math_random (1, creep_growth)
    creep.creep_count = creep.creep_count + spawn

    return spawner
end



local on_biter_base_built = function (event)
    -- The only purpose for processing this event is to add a little
    -- variation to the perfect ellipses that Krastorio creates.
    -- Turrets are counted as a base being built and will be filtered out
    -- in the `spawner_event`.
    spawner_event (event.entity)
 end


local on_entity_died = function (event)
    local entity = event.entity
    if entity.type ~= "unit" then return end
    if not (string.match (entity.name, "biter")
            or string.match (entity.name, "spitter"))
    then return end

    if math_random() < creep_chance_on_death then
        local surface = entity.surface
        if filter_surface (surface) then
            local position = entity.position
            local tile = filter_tile (surface.get_tile (position))
            if tile
                    and tile.name ~= "kr-creep"
                    and tile.prototype.walking_speed_modifier < creep_tile_immunity
            then
                surface.set_tiles ({{ name = "kr-creep", position = position }})
            end
        end
    end
end


local on_entity_spawned = function (event)
    -- Spawning biters is a nice hook to "spanwer activity", for
    -- us to grow the active creep.
    spawner_event (event.spawner)
end


local on_player_used_capsule = function (event)
    if event.item and event.item.name == "kr-creep-virus" then
        local player = game.players[event.player_index]
        if player
                and player.valid
                and player.character
                and player.character.valid
        then
            local surface = player.character.surface
            global.surface_viruses[surface.index] = true
        end
    end
end


local on_creep_nth_tick = function (event)
    --[[--
     The creep states are:
       - wait   - batching unit spawns
       - search - walking the creep looking for drop-off point (TILES_PER_TICK)
       - spawn  - drop-off point located, spawn all neighbor creeps
    --]]--

    -- Bind locally.
    local global_creep_state = global.creep_state
    local work_index = global.work_index

    local creep = global_creep_state[work_index]

    local reset = function (windex)
        global_creep_state[work_index] = nil
        creep = nil
        work_index = 0
    end

    repeat
        if not creep then
            work_index, creep = next (global_creep_state)
        end

        if not creep then
            -- If still no creep, there's nothing to be done.
            break
        else
            local spawner = creep.spawner
            if not filter_spawner (spawner) then
                reset (work_index)
            elseif not filter_surface (spawner.surface) then
                reset (work_index)
            end
        end
    until creep

    if creep then
        local spawner = creep.spawner
        if creep.state == "wait" then
            if init_search_params (creep) then
                creep.state = "search"
            else
                reset (work_index)
            end
        elseif creep.state == "search" then
            -- Find a spot to being searching for free creep spots.
            -- It modifies some attributes hence the testing.
            creep_iterative_search (creep)
            if creep.spawn_position then
                creep.state = "spawn"
            elseif not creep.search_position then
                -- No searches to continue.
                reset (work_index)
            end
        elseif creep.state == "spawn" then
            -- Search out local tiles to drop a creep.
            local creeps
            if creep.spawn_position then
                creeps = spawn_creep (
                        spawner.surface,
                        creep.spawn_position,
                        creep.creep_count
                )
            end

            if creeps then
                -- Let someone else do some work since we didn't
                -- finish spawning all the creep by setting state
                -- to just like `on_entity_spawned`.
                creep.state = "wait"
                creep.creep_count = creeps
            else
                -- Totally finished, and legit or failed miserably.
                reset (work_index)
            end
        else
            util.crash ("ERROR: invalid state", creep.state, work_index)
        end
    end

    global.work_index = work_index or 0
end


local on_runtime_settings = function (event)
    if event.setting_type == "runtime-global" then
        if event.setting == "creep-biter-death" then
            creep_chance_on_death = settings.global[event.setting].value
        elseif event.setting == "creep-growth" then
            creep_growth = settings.global[event.setting].value
        end
    end
end


local lib = {}

lib.events = {
    [defines.events.on_biter_base_built] = on_biter_base_built,
    [defines.events.on_entity_died] = on_entity_died,
    [defines.events.on_entity_spawned] = on_entity_spawned,
    [defines.events.on_player_used_capsule] = on_player_used_capsule,
    [defines.events.on_runtime_mod_setting_changed] = on_runtime_settings
}

lib.event_filters = {
    [defines.events.on_entity_died] = {{ filter = "type", type = "unit" }}
}


lib.on_nth_tick = {
    [CREEP_NTH_TICKS] = on_creep_nth_tick,
}


local cache_settings = function()
    creep_chance_on_death = settings.global["creep-biter-death"].value
    creep_growth = settings.global["creep-growth-1_0_2"].value
    creep_tile_immunity = settings.global["creep-tile-immunity"].value / 100.0
end

-- Called on new game.
-- Called when added to exiting game.
lib.on_init = function()
    cache_settings()

    -- The Krastorio virus has been released on this surface.
    global.surface_viruses = {}

    -- Indexed by spawner as each has it's own direction
    -- and creep count to track.
    global.creep_state = {}
    global.work_index = nil

    util.update_event_filters (lib.event_filters)
end


-- Not called when added to existing game.
-- Called when loaded after saved in existing game.
lib.on_load = function()
    cache_settings()
    util.update_event_filters (lib.event_filters)
end


-- Not called on new game.
-- Called when added to existing game.
lib.on_configuration_changed = function (config)
    local modname = util.modname
    local creeper
    if config and config.mod_changes then
        creeper = config.mod_changes[modname]
    end

    if creeper then
        local old_version = creeper.old_version or "0.0.0"
        local new_version = creeper.new_version or "0.0.0"

        print (string.format (
                "%s (spawn): %s -> %s",
                modname, old_version, new_version
        ))

        if old_version < "1.0.1" then
            -- Added in 1.0.1
            global.surface_viruses = {}
        end

        if old_version >= "1.0.0" and new_version == "1.0.2" then
            game.print { "", "Creeper - Purging stale creepers, please wait." }
        end
    end
end


return lib