GRIDFINITY_TEST_MODE = true
local core = dofile("Gridfinity_Toolpath.lua")
GRIDFINITY_TEST_MODE = nil

local function near(actual, expected, epsilon, label)
  if math.abs(actual - expected) > epsilon then
    error(label .. ": expected " .. expected .. ", got " .. actual)
  end
end

local function layout_options(overrides)
  local options = {
    size_mode = "Grid Rows / Columns",
    columns = 3,
    rows = 2,
    overall_x_mm = 126,
    overall_y_mm = 84,
    cell_width_mm = 42,
    cell_height_mm = 42,
    origin_from = "Bottom Left"
  }
  for key, value in pairs(overrides or {}) do
    options[key] = value
  end
  return options
end

local w, r = core.profile_at_depth_mm(0)
near(w, 41.5, 1e-9, "top width")
near(r, 3.75, 1e-9, "top radius")

w, r = core.profile_at_depth_mm(2.15)
near(w, 37.2, 1e-9, "mid width")
near(r, 1.6, 1e-9, "mid radius")

w, r = core.profile_at_depth_mm(3.95)
near(w, 37.2, 1e-9, "wall bottom width")
near(r, 1.6, 1e-9, "wall bottom radius")

w, r = core.profile_at_depth_mm(4.65)
near(w, 35.8, 1e-9, "bottom width")
near(r, 0.9, 1e-9, "bottom radius")

local mw, mh, mr = core.machining_profile_dimensions_at_depth_mm(4.65, 42, 42)
near(mw, 37.2, 1e-9, "unchamfered machined bottom width")
near(mh, 37.2, 1e-9, "unchamfered machined bottom height")
near(mr, 1.6, 1e-9, "unchamfered machined bottom radius")

near(core.to_job_units(25.4, false), 1.0, 1e-9, "mm to inch")
near(core.tool_value_in_job_units(0.25, false, true), 6.35, 1e-9, "inch tool to mm job")
assert(not core.finish_uses_pocket(0.0), "zero allowance should create a native profile finish")
assert(core.finish_uses_pocket(0.01), "positive allowance should create a native pocket finish")
near(core.magnet_outer_diameter_mm(6.2, 0.25), 6.7, 1e-9,
  "magnet outer edge should include the chamfer on both sides")

local grid_w, grid_h = core.grid_size_mm(3, 2, 50, 40)
near(grid_w, 150, 1e-9, "custom X pitch should determine grid width")
near(grid_h, 80, 1e-9, "custom Y pitch should determine grid height")

local size = assert(core.resolve_size(layout_options({
  cell_width_mm = 50,
  cell_height_mm = 40
})))
near(size.overall_x_mm, 150, 1e-9, "grid-sized overall X")
near(size.overall_y_mm, 80, 1e-9, "grid-sized overall Y")

size = assert(core.resolve_size(layout_options({
  size_mode = "Overall Dimensions",
  overall_x_mm = 100,
  overall_y_mm = 85
})))
assert(size.columns == 3, "arbitrary overall X should include the partial edge column")
assert(size.rows == 3, "arbitrary overall Y should include the partial edge row")

size = assert(core.resolve_size(layout_options({
  size_mode = "Overall Dimensions",
  overall_x_mm = 0.001,
  overall_y_mm = 0.001
})))
assert(size.columns == 1 and size.rows == 1,
  "a positive overall size smaller than one cell should still produce one partial cell")

-- The two original placement modes map exactly to Bottom Left and Center.
local layout = assert(core.create_layout(layout_options(), 10, 20))
near(layout.grid_min_x, 10, 1e-9, "legacy positive-origin X")
near(layout.grid_min_y, 20, 1e-9, "legacy positive-origin Y")
near(layout.max_x, 136, 1e-9, "legacy positive-origin right edge")
near(layout.max_y, 104, 1e-9, "legacy positive-origin top edge")
local cells = core.layout_cells(layout)
assert(#cells == 6, "grid layout should enumerate every cell")
near(cells[1].cx, 31, 1e-9, "legacy first-cell center X")
near(cells[1].cy, 41, 1e-9, "legacy first-cell center Y")

layout = assert(core.create_layout(layout_options({origin_from = "Center"}), 10, 20))
near(layout.grid_min_x, -53, 1e-9, "legacy centered-origin X")
near(layout.grid_min_y, -22, 1e-9, "legacy centered-origin Y")

local expected_origins = {
  ["Bottom Left"] = {0, 0},
  ["Bottom Right"] = {-100, 0},
  ["Top Left"] = {0, -85},
  ["Top Right"] = {-100, -85},
  ["Center"] = {-50, -42.5}
}
for origin_from, expected in pairs(expected_origins) do
  layout = assert(core.create_layout(layout_options({
    size_mode = "Overall Dimensions",
    overall_x_mm = 100,
    overall_y_mm = 85,
    origin_from = origin_from
  }), 0, 0))
  near(layout.min_x, expected[1], 1e-9, origin_from .. " requested min X")
  near(layout.min_y, expected[2], 1e-9, origin_from .. " requested min Y")
  assert(layout.columns == 3 and layout.rows == 3,
    origin_from .. " should preserve shared derived grid size")
end

layout = assert(core.create_layout(layout_options({
  size_mode = "Overall Dimensions",
  overall_x_mm = 100,
  overall_y_mm = 85,
  origin_from = "Bottom Right"
}), 100, 0))
near(layout.grid_min_x, -26, 1e-9, "right origin should clip the leftmost column")
cells = core.layout_cells(layout)
near(cells[1].clip_min_x, 0, 1e-9, "partial left cell should clip at the requested edge")
near(cells[3].clip_max_x, 100, 1e-9, "rightmost cell should end at the requested edge")

local layout_ok = core.validate_layout(layout, 0, 0, 100, 85)
assert(layout_ok, "arbitrary overall layout should fit its matching job bounds")
layout_ok = core.validate_layout(layout, 0, 0, 99, 85)
assert(not layout_ok, "requested physical layout outside the job should fail")

local selector_applied = false
local selected_layer = nil
local selector = {
  AddLayerName = function(_, layer_name)
    selected_layer = layer_name
  end,
  ApplySelector = function()
    selector_applied = true
  end
}
local configured_selector = core.configure_layer_selector(selector, "Test Layer")
assert(configured_selector == selector, "layer selector configuration should return its selector")
assert(selector.GeometryFilterUsed, "layer selector must be active for initial toolpath calculation")
assert(selector.OnlyOnLayers, "layer selector should restrict selection to its configured layers")
assert(selector.SelectClosed, "layer selector should select closed vectors")
assert(not selector.SelectOpen, "layer selector should not select open vectors")
assert(not selector.AllowOpen, "layer selector should not allow open vectors")
assert(selected_layer == "Test Layer", "layer selector should retain its layer name")
assert(selector_applied, "layer selector must select vectors before initial toolpath calculation")

local created_layers = {}
local existing_layers = {
  ["Gridfinity - Magnet Outer Edge"] = {name = "existing outer"}
}
local layer_manager = {
  GetLayerWithName = function(_, layer_name)
    created_layers[#created_layers + 1] = layer_name
    return {name = layer_name}
  end,
  FindLayerWithName = function(_, layer_name)
    return existing_layers[layer_name]
  end
}
local magnet_outer, magnet_inner = core.get_magnet_layers(layer_manager, false)
assert(#created_layers == 0, "magnet layers must not be created when magnets are disabled")
assert(magnet_outer == existing_layers["Gridfinity - Magnet Outer Edge"],
  "an existing magnet layer should be returned for stale-geometry cleanup")
assert(magnet_inner == nil, "a missing disabled magnet layer should remain missing")
magnet_outer, magnet_inner = core.get_magnet_layers(layer_manager, true)
assert(#created_layers == 2, "both magnet layers should be created when magnets are enabled")
assert(magnet_outer.name == "Gridfinity - Magnet Outer Edge",
  "enabled magnets should use the outer magnet layer")
assert(magnet_inner.name == "Gridfinity - Magnet Inner Edge",
  "enabled magnets should use the inner magnet layer")

local iw, ih, ir = core.inset_profile(35.8, 35.8, 0.9, 3.375)
near(iw, 27.25, 1e-9, "conservative large-tool inset width")
near(ih, 27.25, 1e-9, "conservative large-tool inset height")
near(ir, 0.0, 1e-9, "conservative large-tool inset radius")

local dw, dh, dr = core.profile_dimensions_at_depth_mm(0, 50, 40)
near(dw, 49.5, 1e-9, "custom cell top width")
near(dh, 39.5, 1e-9, "custom cell top height")
near(dr, 3.75, 1e-9, "custom cell radius")

local ok = core.validate_grid(3, 2, 0, 0, 0, 0, 126, 84, 42, 42)
assert(ok, "exact-sized grid should fit")
ok = core.validate_grid(3, 2, 1, 0, 0, 0, 126, 84, 42, 42)
assert(not ok, "out-of-bounds grid should fail")

local vbit_error
ok, vbit_error = core.validate_tool_geometry(6.35, 3.175, 6.35, 90, 0.2, 4.65, 6)
assert(ok, "one-eighth inch finish and one-quarter inch V-bit should fit simplified geometry")
ok, vbit_error = core.validate_tool_geometry(6.35, 3.175, 12.7, 90, 0.2, 4.65, 6)
assert(not ok, "one-half inch V-bit should be rejected for Gridfinity chamfers")
assert(string.find(vbit_error, "1/2 inch V-bit is too large", 1, true),
  "oversized V-bit error should identify the rejected one-half inch tool")
ok = core.validate_tool_geometry(6.35, 1.5875, 6.35, 45, 0.2, 4.65, 6)
assert(not ok, "45 degree included-angle bit should fail")
ok, vbit_error = core.validate_tool_geometry(6.35, 3.175, 6.35, nil, 0.2, 4.65, 6)
assert(not ok, "missing V-bit angle should fail without a Lua error")
assert(string.find(vbit_error, "valid included angle", 1, true), "missing-angle error should explain the problem")
ok, vbit_error = core.validate_tool_geometry(6.35, 3.175, 1.4, 90, 0.2, 4.65, 6)
assert(not ok, "small V-bit should fail the upper-chamfer requirement")
assert(string.find(vbit_error, "at least 4.3 mm", 1, true), "small V-bit error should explain upper requirement")
ok = core.validate_tool_geometry(6.35, 1.5875, 6.35, 90, 0.2, 4.65, 4)
assert(not ok, "thin material should fail")
local tool_error
ok, tool_error = core.validate_tool_geometry(6.35, 6.35, 6.35, 90, 0.2, 4.65, 8)
assert(not ok, "one-quarter inch finish cutter should fail the machined floor corner")
assert(string.find(tool_error, "0.2500 in", 1, true), "finish-tool error should show selected inch size")

ok = core.validate_magnets(true, 6.2, 2.4, 0.25, 8, 0.4, 42, 42, 3.175, 4.65, 7.45)
assert(ok, "standard magnet parameters should validate")
ok = core.validate_magnets(true, 6.2, 2.4, 0.25, 8, 0.4, 42, 42, 6.35, 4.65, 7.45)
assert(not ok, "oversized magnet end mill should fail")

print("Gridfinity Toolpath core tests passed")
