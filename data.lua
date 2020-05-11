local util = require "util"

local fireutil = {}


function fireutil.make_color (r, g, b, a)
  return { r = r * a, g = g * a, b = b * a, a = a }
end


function fireutil.foreach(table_, fun_)
  for k, tab in pairs(table_) do
    fun_(tab)
    if tab.hr_version then
      fun_(tab.hr_version)
    end
  end
  return table_
end


function fireutil.create_fire_pictures(opts)
  local fire_blend_mode = opts.blend_mode or "additive"
  local fire_animation_speed = opts.animation_speed or 0.5
  local fire_scale = opts.scale or 1
  local fire_tint = opts.tint or {r=1,g=1,b=1,a=1}
  local fire_flags = { "compressed" }
  local retval =
  {
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-13.png",
      line_length = 8,
      width = 60,
      height = 118,
      frame_count = 25,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { -0.0390625, -0.90625 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-12.png",
      line_length = 8,
      width = 63,
      height = 116,
      frame_count = 25,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { -0.015625, -0.914065 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-11.png",
      line_length = 8,
      width = 61,
      height = 122,
      frame_count = 25,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { -0.0078125, -0.90625 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-10.png",
      line_length = 8,
      width = 65,
      height = 108,
      frame_count = 25,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { -0.0625, -0.64844 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-09.png",
      line_length = 8,
      width = 64,
      height = 101,
      frame_count = 25,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { -0.03125, -0.695315 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-08.png",
      line_length = 8,
      width = 50,
      height = 98,
      frame_count = 32,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { -0.0546875, -0.77344 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-07.png",
      line_length = 8,
      width = 54,
      height = 84,
      frame_count = 32,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { 0.015625, -0.640625 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-06.png",
      line_length = 8,
      width = 65,
      height = 92,
      frame_count = 32,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { 0, -0.83594 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-05.png",
      line_length = 8,
      width = 59,
      height = 103,
      frame_count = 32,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { 0.03125, -0.882815 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-04.png",
      line_length = 8,
      width = 67,
      height = 130,
      frame_count = 32,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { 0.015625, -1.109375 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-03.png",
      line_length = 8,
      width = 74,
      height = 117,
      frame_count = 32,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { 0.046875, -0.984375 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-02.png",
      line_length = 8,
      width = 74,
      height = 114,
      frame_count = 32,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { 0.0078125, -0.96875 }
    },
    {
      filename = "__base__/graphics/entity/fire-flame/fire-flame-01.png",
      line_length = 8,
      width = 66,
      height = 119,
      frame_count = 32,
      axially_symmetrical = false,
      direction_count = 1,
      blend_mode = fire_blend_mode,
      animation_speed = fire_animation_speed,
      scale = fire_scale,
      tint = fire_tint,
      flags = fire_flags,
      shift = { -0.0703125, -1.039065 }
    }
  }
  return fireutil.foreach(retval, function(tab)
    if tab.shift and tab.scale then tab.shift = { tab.shift[1] * tab.scale, tab.shift[2] * tab.scale } end
  end)
end


function fireutil.update_lifetimes (flame)
  flame.maximum_lifetime = flame.initial_lifetime + 1800
  flame.burnt_patch_lifetime = flame.maximum_lifetime * 1.1
end


local picture_opts = {
  blend_mode = "normal",
  animation_speed = 0.5,
  scale = 1.1,
  tint = fireutil.make_color (1, 0.6, 1, 1)
}


-- By extending the `initial_flame_count` and `delay_between_initial_flames`,
-- the flames and its smoke can be extended for long periods, almost like
-- little brush fires are re-igniting.

local flame_0 = util.table.deepcopy (data.raw.fire["fire-flame"])
flame_0.name = "creeper-flame-0"
flame_0.initial_lifetime = 480  -- default: 120
flame_0.delay_between_initial_flames = 240 -- default: 10
flame_0.working_sound.match_volume_to_activity = false
flame_0.pictures = fireutil.create_fire_pictures (picture_opts)
for _, smoke in pairs (flame_0.smoke) do
  smoke.color = fireutil.make_color (1, 0.6, 1, 0.75)
  smoke.tint = fireutil.make_color (1, 0.6, 1, 0.75)
end
for _, smoke in pairs (flame_0.smoke_source_pictures) do
  smoke.color = fireutil.make_color (1, 0.6, 1, 0.75)
  smoke.tint = fireutil.make_color (1, 0.6, 1, 0.75)
end
fireutil.update_lifetimes (flame_0)

-- XXX: Iterate over sound to lower the volume based on the
-- XXX: the scale of the flame.

-- Reduce for the normal spreading flames.
picture_opts = util.table.deepcopy (picture_opts)
picture_opts.scale = 0.75

local flame_1 = util.table.deepcopy (flame_0)
flame_1.name = "creeper-flame-1"
flame_1.initial_lifetime = 480
flame_1.delay_between_initial_flames = 240
flame_1.light.intensity = 1 * picture_opts.scale -- default: 1
flame_1.light.size = 20 * picture_opts.scale  -- default: 20
flame_1.pictures = fireutil.create_fire_pictures (picture_opts)
fireutil.update_lifetimes (flame_1)

picture_opts = util.table.deepcopy (picture_opts)
picture_opts.scale = 0.5

local flame_2 = util.table.deepcopy (flame_1)
flame_2.name = "creeper-flame-2"
flame_2.initial_lifetime = 960
flame_2.delay_between_initial_flames = 480
flame_2.light.intensity = 1 * picture_opts.scale
flame_2.light.size = 20 * picture_opts.scale
fireutil.update_lifetimes (flame_2)

picture_opts = util.table.deepcopy (picture_opts)
picture_opts.scale = 0.25

local flame_3 = util.table.deepcopy (flame_2)
flame_3.name = "creeper-flame-3"
flame_3.initial_lifetime = 1920
flame_3.delay_between_initial_flames = 960
flame_2.light.intensity = 1 * picture_opts.scale
flame_2.light.size = 20 * picture_opts.scale
fireutil.update_lifetimes (flame_3)


data:extend ({ flame_0, flame_1, flame_2, flame_3})
