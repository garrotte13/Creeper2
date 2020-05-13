local util = require "utils"

local handler = require "event_handler"
handler.add_lib (require "fire")
handler.add_lib (require "pollution")
handler.add_lib (require "spawn")


local command_creepolution = function (args)
    local player = game.get_player (args.player_index)
    local f = game.forces.enemy
    if player and f then
        local evo = f.evolution_factor or 0
        local evo_t = f.evolution_factor_by_time or 0
        local evo_p = f.evolution_factor_by_pollution or 0
        local evo_s = f.evolution_factor_by_killing_spawners or 0
        local evo_c = global.evolution_factor_by_creep or 0

        -- Prevent divide-by-zero (w/ episilon)
        local evo_parts = evo_t + evo_p + evo_s + evo_c
        if evo_parts <= 0.00001 then
            evo_parts = 1
        end

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

        local creep_in_pollution = 0
        for _, chunk in pairs (global.evolution_chunks) do
            creep_in_pollution = creep_in_pollution + chunk.creep
        end

        player.print (string.format (
                "Creepolution factor: %0.08f (polluted creep %d)",
                evo_c,
                creep_in_pollution
        ))

        -- And debug stats to the log.
        local evo_string
        if game.map_settings.pollution.enabled then
            evo_string = string.format ("%0.08f", evo_c)
        else
            evo_string = "disabled"
        end

        print (string.format ("%d %s: monitored chunks=%d, "
                .. "deferred chunks=%d, evolution factor=%s, "
                .. "creep=%d, work items=%d, work index=%d",
                args.tick,
                util.modname,
                table_size (global.evolution_chunks or {}),
                table_size (global.deferred_chunks or {}),
                evo_string,
                creep_in_pollution,
                table_size (global.creep_state or {}),
                global.work_index or 0
        ))
    end
end


local register_commands = function()
    commands.add_command (
        "creepolution",
        "Display evolution accounting for creep.",
        command_creepolution
    )
end


local performance = function (event)
    local p1 = game.create_profiler()
    for i=1, 10000 do
    end
    p1.stop()

    game.print {"", "test1: ", p1}
end


local meta = {}


meta.events = {
    -- [defines.events.on_player_dropped_item] = performance,
}


-- Called on new game.
-- Called when added to exiting game.
meta.on_init = function()
    register_commands()
end


-- Not called when added to existing game.
-- Called when loaded after saved in existing game.
meta.on_load = function()
    register_commands()
end


handler.add_lib (meta)
