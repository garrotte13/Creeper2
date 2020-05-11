data:extend ({
    {
        type = "int-setting",
        name = "creep-growth",
        setting_type = "runtime-global",
        default_value = 21,
        minimum_value = 1,
        maximum_value = 128,
        order = "a"
    },
    {
        type = "double-setting",
        name = "creep-biter-death",
        setting_type = "runtime-global",
        default_value = 0.1,
        minimum_value = 0,
        maximum_value = 1.0,
        order = "am"
    },
    {
        type = "int-setting",
        name = "creep-evolution-factor",
        setting_type = "runtime-global",
        default_value = 90,    -- human-scaled
        minimum_value = 0,    -- disabled
        maximum_value = 1000,
        order = "b",
    },
    {
        type = "bool-setting",
        name = "creep-evolution-pollution-bonus",
        setting_type = "runtime-global",
        default_value = true,
        order = "c"
    },
    {
        type = "bool-setting",
        name = "creep-destroyed-by-fire",
        setting_type = "runtime-global",
        default_value = true,
        order = "d"
    }
})
