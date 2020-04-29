local DEVELOP = false

-- This isn't pollution per se, but it's an easy way to think of
-- it during the calculations.
local CREEP_POLLUTION_PER_TICK = 0.0001 / 3600
local CREEP_TICKS = 13
local EVO_TICKS = 60
local POLLUTION_POWER = 1.2
local THETA_OFFSET = math.pi / 4
local TILES_PER_INTERVAL = 16
local UNIT_WAIT_TICKS = 60 * 3


function table.copy (tbl)
    local tbl_type = type (tbl)
    local copy
    if tbl_type == 'table' then
        copy = {}
        for key, value in pairs (tbl) do
            copy[key] = value
        end
    else
        copy = tbl
    end
    return copy
end


function reset_globals()
    -- Indexed by spawner as each has it's own direction
    -- and creep count to track.
    global.creep_state = {}
    global.evolution_factor_by_creep = 0
    global.spawned_creep = 0
    global.work_index = nil
end


script.on_init (reset_globals)

script.on_event (defines.events.on_tick, function(event)
    -- Useful for development to reset state.
    if DEVELOP then
        reset_globals()
    end

    commands.add_command (
        "creepolution",
        "Display evolution accounting for creep.",
        creepolution
    )

    -- And then disable the event callback.
    script.on_event (defines.events.on_tick, nil)
end)


function creepolution (args)
    local player = game.get_player (args.player_index)
    local f = game.forces.enemy
    if player and f then
        local evo = f.evolution_factor
        local evo_t = f.evolution_factor_by_time
        local evo_p = f.evolution_factor_by_pollution
        local evo_s = f.evolution_factor_by_killing_spawners
        local evo_c = global.evolution_factor_by_creep or 0

        local evo_parts = evo_t + evo_p + evo_s + evo_c

        player.print (string.format (
                "Evolution factor: %0.04f. (Time %d%%) "
                        .. "(Pollution %d%%) (Spawner kills %d%%) "
                        .. "(Creep %d%%) ",
                evo,
                evo_t * 100 / evo_parts,
                evo_p * 100 / evo_parts,
                evo_s * 100 / evo_parts,
                evo_c * 100 / evo_parts
        ))

        player.print (string.format (
                "Creepolution factor: %0.08f (creep %d)",
                evo_c,
                global.spawned_creep or 0
        ))
    end
end


script.on_nth_tick (EVO_TICKS, function (event)
    local cef = settings.global["creep-evolution-factor"].value
    if cef > 0 then
        -- This applies evolution to all forces, even though the lore
        -- of the creep is that it's spawner controlled, which implies
        -- specific forces and whatnot. But since the creep is just a
        -- tile and not associated w/ any spawner in specific, we'll
        -- just wing it for simplicity.

        local evo_c_previous = global.evolution_factor_by_creep

        -- How much psuedo-pollution generated per tick based on how
        -- many creep is dotting the landscape.
        local pollution = CREEP_POLLUTION_PER_TICK * global.spawned_creep

        -- And then account for how many ticks elapsed since last calc.
        pollution = pollution * EVO_TICKS

        -- Based on the creep evolution factor setting (scaled down from
        -- human form), calculate how much evolution factor from creep.
        -- Before applied to the base of 1 - evo.
        local evo_c_pollution = cef / 100000 * pollution

        -- Only updating the enemy as they are the ones with creep.
        local f = game.forces.enemy
        if f and f.valid then
            local evo = f.evolution_factor
            local evo_c_delta = (1 - evo) * evo_c_pollution

            f.evolution_factor = evo + evo_c_delta

            local evo_c = evo_c_previous + evo_c_delta
            global.evolution_factor_by_creep = evo_c
        end
    end
end)


function on_remove_tile (event)
    local creep_removed = 0

    for _, tile in pairs (event.tiles) do
        if tile.old_tile.name == "kr-creep" then
            creep_removed = creep_removed + 1
        end
    end

    -- Clamp it to zero as we only count creep that has crept, not
    -- the creep that has spawned around the spawners.
    global.spawned_creep = math.max (0, global.spawned_creep - creep_removed)
end


script.on_event (defines.events.on_player_mined_tile, on_remove_tile)
script.on_event (defines.events.on_robot_mined_tile, on_remove_tile)


script.on_nth_tick (CREEP_TICKS, function (event)
    --[[--
    States are:
      - wait - batching unit spawns
      - search - walking the creep looking for drop-off point (TILES_PER_TICK)
      - spawn - drop-off point located, spawn all neighbor creeps
    --]]--
    local creep

    if global.work_index then
        creep = global.creep_state[global.work_index]
    end

    if creep then
        local fini = false

        if not creep.surface.valid then
            fini = true

        elseif creep.state == "search" then
            -- Find a spot to begin searching for free creep spots.
            creep_iterative_search (creep)

            if creep.spawn_position then
                creep.state = "spawn"
            elseif not creep.search_position then
                -- No searches to continue
                fini = true
            end

        elseif creep.state == "spawn" then
            -- Search out local tiles to drop a creep.
            local creeps
            if creep.spawn_position then
                creeps = spawn_creep (
                        creep.surface,
                        creep.spawn_position,
                        creep.creep_count
                )
            end

            if creeps and creep.surface.valid then
                -- Let someone else do some work.
                global.work_index = nil

                -- This is just like `on_entity_spawned`.
                creep.state = "wait"
                creep.creep_count = creeps
                creep.search_tick = event.tick + UNIT_WAIT_TICKS
            else
                -- Done with this one.
                fini = true
            end

        else
            -- This is wrong. Just delete it and move on with your life.
            fini = true
        end

        if fini then
            global.creep_state[global.work_index] = nil
            global.work_index = nil
        end

    else
        -- There isn't an active search/spawn going so check the
        -- spawners to see if any are primed to creep.
        for index, state in pairs (global.creep_state) do
            if not state.surface.valid then
                global.creep_state[index] = nil

            elseif state.state == "wait" then
                if state.search_tick and event.tick >= state.search_tick then
                    if init_search_params (state) then
                        state.state = "search"
                        global.work_index = index

                        -- Only process one at a time.
                        break
                    end
                end
            end
        end
    end
end)


script.on_event (defines.events.on_entity_spawned, function (event)
    local spawner = event.spawner
    local unit_number = spawner.unit_number

    if not global.creep_state[unit_number] then
        init_creep_state (unit_number)
    end

    local creep = global.creep_state[unit_number]

    -- In all states, when a unit spawns, the creep count can increase.
    creep.surface = spawner.surface
    creep.position = spawner.position

    local spawn = math.random (1, settings.global["creep-growth"].value)
    creep.creep_count = creep.creep_count + spawn
    if not creep.search_tick then
        creep.search_tick = event.tick + UNIT_WAIT_TICKS
    end
end)


function filter_tile (tile)
    if not tile then return nil end
    if not tile.valid then return nil end
    if tile.collides_with ("player-layer") then return nil end

    return tile
end


function creep_iterative_search (creep)
    local surface = creep.surface
    creep.spawn_position = nil

    if not surface.valid then
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
end


function creep_search_position (surface, position)
    if not surface.valid then return nil end

    -- local creeps = surface.get_connected_tiles (position, { "kr-creep" })
    local creeps = surface.find_tiles_filtered{
        position = position,
        radius = 16,
        name = "kr-creep",
    }
    local creeps_len = table_size (creeps)

    -- Weird.
    if creeps_len == 0 then
        return nil
    end

    local stats_loops = 0
    local search_position
    local rnd = math.random (1, creeps_len)
    for i=rnd, rnd + creeps_len do
        local tile = filter_tile (creeps[i])
        if tile then
            search_position = tile.position
            break
        end
        stats_loops = stats_loops + 1
    end

    return search_position
end


function init_creep_state (unit_number)
    global.creep_state[unit_number] = {
        state = "wait",
        creep_count = 0,
    }
end


function init_search_params (creep)
    local surface = creep.surface
    local position = creep.position

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


function spawn_creep (surface, position, creeps)
    if not surface.valid then return nil end

    local offsets = {
        {-1, -1}, {0, -1}, {1, -1},
        {-1,  0}, {0,  0}, {1,  0},
        {-1,  1}, {0,  1}, {1,  1}
    }
    local tiles = {}

    local function find_free_tiles (find_pos)
        -- Used to track if we've found at least one drop-off
        -- in a full cycle. If we haven't, we abort wholesale
        -- because we may have wandered into the middle of an
        -- area that just wastes time finding nothing.
        local found_tile = true

        while creeps > 0 and found_tile do
            found_tile = false

            local dir = math.random (1, 9)
            for i = dir, dir+9 do
                local off = offsets[i % 9 + 1]
                local pos = { x = find_pos.x + off[1], y = find_pos.y + off[2] }

                local pt_key = table.concat ({pos.x, ":", pos.y})
                if not tiles[pt_key] then
                    local tile = filter_tile (surface.get_tile (pos))
                    if tile and tile.name ~= "kr-creep" then
                        tiles[pt_key] = {
                            name = "kr-creep",
                            position = tile.position
                        }

                        find_pos = tile.position
                        creeps = creeps - 1
                        found_tile = true

                        break
                    end
                end
            end
        end
    end

    find_free_tiles (position)

    local creep_tiles = {}
    local spawned = 0
    for _, tile in pairs (tiles) do
        table.insert (creep_tiles, tile)
        spawned = spawned + 1
    end

    surface.set_tiles (creep_tiles)
    global.spawned_creep = global.spawned_creep + spawned

    -- If we were able to find space for some, then requeue the leftovers
    -- so it tries again.
    if spawned > 0 and creeps > 0 then
        return creeps
    end
end


function surrounding_chunk_pollutions (surface, position)
    -- REQUIRES: valid surface

    local chunks = {}
    local p = table.copy (position)

    -- defines.direction.northwest
    p.x = p.x - 32
    p.y = p.y - 32
    chunks[1] = {
        pollution = surface.get_pollution (p),
        theta=3 * math.pi / 4
    }

    -- defines.direction.north
    p.x = p.x + 32
    chunks[2] = {
        pollution = surface.get_pollution (p),
        theta = math.pi / 2
    }

    -- defines.direction.northeast
    p.x = p.x + 32
    chunks[3] = {
        pollution = surface.get_pollution (p),
        theta = math.pi / 4
    }

    -- defines.direction.east
    p.y = p.y + 32
    chunks[4] = {
        pollution = surface.get_pollution (p),
        theta = 0
    }

    -- defines.direction.west
    p.x = p.x - (32 * 2)  -- skipping over this "position" chunk
    chunks[5] = {
        pollution = surface.get_pollution (p),
        theta = math.pi
    }

    -- defines.direction.southwest
    p.y = p.y - 32
    chunks[6] = {
        pollution = surface.get_pollution (p),
        theta = 5 * math.pi / 4
    }

    -- defines.direction.south
    p.x = p.x + 32
    chunks[7] = {
        pollution = surface.get_pollution (p),
        theta = 3 * math.pi / 2
    }

    -- defines.direction.southeast
    p.x = p.x + 32
    chunks[8] = {
        pollution=surface.get_pollution (p),
        theta = 7 * math.pi / 4
    }

    return chunks
end


function weighted_random_pollution (chunks)
    local fudge = table_size (chunks) / 1.0

    local function scaling (what)
        -- Moar weight!
        return math.pow (what+1, POLLUTION_POWER) + fudge
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
