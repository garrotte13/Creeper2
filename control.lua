--[[--
IDEAS:
  - remote.call to print stats to console
  - setting for creep per spawn
  - setting for how much evolution per "new" creep (pollution_factor slider)
  - need to capture current pollution factor, and divine if it's been
    changed by someone other than me. and update the baseline so removal
    of creep does not go below the factor (i.e., the creep around the
    starter spawners are not counted)
  - requeue if at least one creep was spawned and there
    is left over creep
--]]--


local DEVELOP = false
local CREEP_PER_SPAWN = 3
local NTH_TICKS = 13
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


script.on_init (function ()
    global.creep_state = {}
    global.work_index = nil
end)


script.on_event (defines.events.on_tick, function(event)
    -- Useful for development to reset state.
    if DEVELOP then
        -- Indexed by spawner as each has it's own direction
        -- and creep count to track.
        global.creep_state = {}
        global.work_index = nil
    end

    -- And then disable the event callback.
    script.on_event (defines.events.on_tick, nil)
end)


script.on_nth_tick (NTH_TICKS, function (event)
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
            creep_iterative_search (creep)

            if creep.spawn_position then
                creep.state = "spawn"
            elseif not creep.search_position then
                -- No searches to continue
                fini = true
            end

        elseif creep.state == "spawn" then
            -- Search out local tiles to drop a creep.
            if creep.spawn_position then
                spawn_creep (creep.surface, creep.spawn_position, creep.creep_count)
            end

            -- Done with this one.
            fini = true

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
    creep.creep_count = creep.creep_count + CREEP_PER_SPAWN
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
    for _, tile in pairs (tiles) do
        table.insert (creep_tiles, tile)
    end

    surface.set_tiles (creep_tiles)
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
        return math.pow (what, POLLUTION_POWER) + fudge
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
