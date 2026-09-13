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

local saved_registry_values = {}
Registry = function(section)
  assert(section == "GridfinityToolpathGadget", "options should use the gadget registry section")
  return {
    SetString = function(_, key, value) saved_registry_values[key] = value end,
    SetInt = function(_, key, value) saved_registry_values[key] = value end,
    SetDouble = function(_, key, value) saved_registry_values[key] = value end,
    SetBool = function(_, key, value) saved_registry_values[key] = value end
  }
end

local saved_tools = {}
local function test_tool(label)
  return {
    ToolDBId = {
      SaveDefaults = function(_, section, key)
        assert(section == "GridfinityToolpathGadget", "tools should use the gadget registry section")
        saved_tools[key] = label
      end
    }
  }
end

core.save_options({
  output_type = "Baseplate",
  size_mode = "Overall Dimensions",
  columns = 3,
  rows = 2,
  overall_x_mm = -1,
  overall_y_mm = 84,
  cell_width_mm = 42,
  cell_height_mm = 42,
  origin_from = "Top Right",
  offset_x_mm = 1.25,
  offset_y_mm = -2.5,
  allowance_mm = 0.2,
  include_magnets = true,
  magnet_diameter_mm = 6.2,
  magnet_depth_mm = 2.4,
  magnet_chamfer_mm = 0.25,
  magnet_inset_mm = 8,
  magnet_base_mm = 0.4
}, test_tool("rough"), nil, test_tool("vbit"))
assert(saved_registry_values.OverallXMM == -1,
  "submitted values must be saved even when later validation will reject them")
assert(saved_registry_values.OriginFrom == "Top Right", "origin should be persisted")
assert(saved_registry_values.IncludeMagnets, "magnet selection should be persisted")
assert(saved_tools.Rough == "rough" and saved_tools.VBit == "vbit",
  "selected tools should be persisted even when another tool is missing")
assert(saved_tools.Finish == nil, "a missing tool should not prevent parameter persistence")

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

near(core.FILLER_TOTAL_DEPTH_MM, 4.75, 1e-9, "filler foot total height")
local fw, fh, fr = core.filler_profile_dimensions_at_depth_mm(0, 42, 42)
near(fw, 41.5, 1e-9, "filler top width")
near(fh, 41.5, 1e-9, "filler top height")
near(fr, 3.75, 1e-9, "filler top radius")
fw, fh, fr = core.filler_profile_dimensions_at_depth_mm(2.15, 42, 42)
near(fw, 37.2, 1e-9, "filler wall width")
near(fh, 37.2, 1e-9, "filler wall height")
near(fr, 1.6, 1e-9, "filler wall radius")
fw, fh, fr = core.filler_profile_dimensions_at_depth_mm(3.95, 42, 42)
near(fw, 37.2, 1e-9, "filler lower-chamfer start width")
near(fr, 1.6, 1e-9, "filler lower-chamfer start radius")
fw, fh, fr = core.filler_profile_dimensions_at_depth_mm(4.75, 42, 42)
near(fw, 35.6, 1e-9, "filler bottom width")
near(fh, 35.6, 1e-9, "filler bottom height")
near(fr, 0.8, 1e-9, "filler bottom radius")

near(core.to_job_units(25.4, false), 1.0, 1e-9, "mm to inch")
near(core.from_job_units(1.0, false), 25.4, 1e-9, "inch job value to mm")
near(core.tool_value_in_job_units(0.25, false, true), 6.35, 1e-9, "inch tool to mm job")
assert(not core.finish_uses_pocket(0.0), "zero allowance should create a native profile finish")
assert(core.finish_uses_pocket(0.01), "positive allowance should create a native pocket finish")
near(core.magnet_outer_diameter_mm(6.2, 0.25), 6.7, 1e-9,
  "magnet outer edge should include the chamfer on both sides")
assert(core.circle_fits_rounded_rect(13, 13, 3.35, 35.6, 35.6, 0.8),
  "standard filler magnet chamfer should fit inside the foot bottom")
assert(not core.circle_fits_rounded_rect(16, 16, 3.35, 35.6, 35.6, 0.8),
  "a circle crossing the rounded foot corner should be rejected")

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
assert(size.columns == 2, "100 mm should fit two complete 42 mm columns")
assert(size.rows == 2, "85 mm should fit two complete 42 mm rows")

size = assert(core.resolve_size(layout_options({
  size_mode = "Overall Dimensions",
  overall_x_mm = 126,
  overall_y_mm = 84
})))
assert(size.columns == 3 and size.rows == 2,
  "exact overall dimensions should preserve every complete cell")

local undersized, undersized_error = core.resolve_size(layout_options({
  size_mode = "Overall Dimensions",
  overall_x_mm = 0.001,
  overall_y_mm = 0.001
}))
assert(undersized == nil and string.find(undersized_error, "complete cell", 1, true),
  "an overall size smaller than one cell should be rejected")

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
local filler_geometry = assert(core.filler_geometry(layout))
local shared_cells = core.layout_cells(layout)
assert(#filler_geometry.cells == #shared_cells,
  "Filler Plate geometry should consume every shared layout cell")
for index, filler_cell in ipairs(filler_geometry.cells) do
  near(filler_cell.cx, shared_cells[index].cx, 1e-9, "shared filler center X")
  near(filler_cell.cy, shared_cells[index].cy, 1e-9, "shared filler center Y")
end
near(filler_geometry.boundary.min_x, layout.min_x, 1e-9, "shared filler boundary min X")
near(filler_geometry.boundary.max_y, layout.max_y, 1e-9, "shared filler boundary max Y")

local custom_filler_layout = assert(core.create_layout(layout_options({
  cell_width_mm = 50,
  cell_height_mm = 40
}), 0, 0))
local custom_filler = assert(core.filler_geometry(custom_filler_layout))
near(custom_filler.cells[1].top.width, 49.5, 1e-9, "custom filler top width")
near(custom_filler.cells[1].top.height, 39.5, 1e-9, "custom filler top height")
near(custom_filler.cells[1].bottom.width, 43.6, 1e-9, "custom filler bottom width")
near(custom_filler.cells[1].bottom.height, 33.6, 1e-9, "custom filler bottom height")
local undersized_filler, undersized_filler_error = core.filler_geometry({
  min_x = 0,
  min_y = 0,
  max_x = 7,
  max_y = 7,
  rows = 1,
  columns = 1,
  grid_min_x = 0,
  grid_min_y = 0,
  cell_width_mm = 7,
  cell_height_mm = 7
})
assert(undersized_filler == nil and
       string.find(undersized_filler_error, "too small", 1, true),
  "cells too small for the nominal bottom radius should be rejected")

local inserted_tab_count = 0
Contour = function()
  return {
    AppendPoint = function() end,
    LineTo = function() end,
    ArcTo = function() end,
    InsertToolpathTabAtPoint = function()
      inserted_tab_count = inserted_tab_count + 1
    end
  }
end
Point3D = function(x, y, z) return {x = x, y = y, z = z} end
Point2D = function(x, y) return {x = x, y = y} end
CreateCadContour = function(contour) return contour end
local filler_layers = {}
local filler_layer_manager = {
  GetLayerWithName = function(_, name)
    local layer = filler_layers[name]
    if layer == nil then
      layer = {
        IsEmpty = true,
        object_count = 0,
        SetColour = function() end,
        AddObject = function(self)
          self.object_count = self.object_count + 1
        end
      }
      filler_layers[name] = layer
    end
    return layer
  end,
  FindLayerWithName = function(_, name)
    return filler_layers[name]
  end
}
assert(core.add_filler_geometry({LayerManager = filler_layer_manager}, layout, 1.0))
assert(filler_layers["Gridfinity - Filler Plate Boundary"].object_count == 1,
  "Filler Plate geometry should create one overall boundary")
assert(filler_layers["Gridfinity - Filler Foot Top Edge"].object_count == #shared_cells,
  "Filler Plate geometry should create one top contour per shared cell")
assert(filler_layers["Gridfinity - Filler Foot Wall Edge"].object_count == #shared_cells,
  "Filler Plate geometry should create one wall contour per shared cell")
assert(filler_layers["Gridfinity - Filler Foot Bottom Edge"].object_count == #shared_cells,
  "Filler Plate geometry should create one bottom contour per shared cell")

local filler_magnet_options = {
  include_magnets = true,
  magnet_diameter_mm = 6.2,
  magnet_depth_mm = 2.4,
  magnet_chamfer_mm = 0.25,
  magnet_inset_mm = 8,
  magnet_base_mm = 0.4,
  cell_width_mm = 42,
  cell_height_mm = 42
}
local filler_magnets = assert(core.filler_magnet_geometry(layout, filler_magnet_options))
assert(#filler_magnets == #shared_cells * 4,
  "Filler Plate magnets should be created four times per complete cell")
near(filler_magnets[1].cx, shared_cells[1].cx - 13, 1e-9,
  "Filler Plate magnet X should reuse per-cell placement")
near(filler_magnets[1].cy, shared_cells[1].cy - 13, 1e-9,
  "Filler Plate magnet Y should reuse per-cell placement")
near(filler_magnets[1].outer_diameter, 6.7, 1e-9,
  "Filler Plate magnet outer vector should include the chamfer")
assert(core.add_filler_geometry(
  {LayerManager = filler_layer_manager}, layout, 1.0, filler_magnet_options))
assert(filler_layers["Gridfinity - Magnet Outer Edge"].object_count == #shared_cells * 4,
  "Filler Plate geometry should create one outer magnet contour per magnet")
assert(filler_layers["Gridfinity - Magnet Inner Edge"].object_count == #shared_cells * 4,
  "Filler Plate geometry should create one inner magnet contour per magnet")

local no_filler_magnets = assert(core.filler_magnet_geometry(layout, {
  include_magnets = false
}))
assert(#no_filler_magnets == 0, "disabled Filler Plate magnets should create no geometry")

local custom_filler_magnets = assert(core.filler_magnet_geometry(
  custom_filler_layout, {
    include_magnets = true,
    magnet_diameter_mm = 6.2,
    magnet_depth_mm = 2.4,
    magnet_chamfer_mm = 0.25,
    magnet_inset_mm = 8,
    magnet_base_mm = 0.4,
    cell_width_mm = 50,
    cell_height_mm = 40
  }))
near(custom_filler_magnets[1].cx, 8, 1e-9,
  "custom-pitch Filler Plate magnet should retain its edge inset in X")
near(custom_filler_magnets[1].cy, 8, 1e-9,
  "custom-pitch Filler Plate magnet should retain its edge inset in Y")

local margin_magnet_layout = assert(core.create_layout(layout_options({
  size_mode = "Overall Dimensions",
  overall_x_mm = 100,
  overall_y_mm = 85,
  origin_from = "Top Right"
}), 100, 85))
local margin_filler_magnets = assert(core.filler_magnet_geometry(
  margin_magnet_layout, filler_magnet_options))
assert(#margin_filler_magnets == 16,
  "unused margins should not create magnets outside the four complete cells")
near(margin_filler_magnets[14].cx, 92, 1e-9,
  "right-origin Filler Plate magnets should align to the shared grid")

local function filler_magnet_validation(overrides)
  local options = {}
  for key, value in pairs(filler_magnet_options) do options[key] = value end
  for key, value in pairs(overrides or {}) do options[key] = value end
  return core.validate_filler_magnets(options)
end

local filler_magnets_ok, filler_magnets_error = filler_magnet_validation()
assert(filler_magnets_ok, "standard Filler Plate magnets should validate")
filler_magnets_ok, filler_magnets_error = filler_magnet_validation({magnet_inset_mm = 2})
assert(not filler_magnets_ok and string.find(filler_magnets_error, "foot bottom", 1, true),
  "Filler Plate magnet chamfers outside the bottom profile should be rejected")
filler_magnets_ok, filler_magnets_error = filler_magnet_validation({magnet_inset_mm = 20})
assert(not filler_magnets_ok and string.find(filler_magnets_error, "overlap", 1, true),
  "overlapping Filler Plate magnets should be rejected")
filler_magnets_ok, filler_magnets_error = filler_magnet_validation({
  magnet_depth_mm = 4.76
})
assert(not filler_magnets_ok and string.find(filler_magnets_error, "within", 1, true),
  "Filler Plate magnets must remain within the mating foot")
filler_magnets_ok, filler_magnets_error = filler_magnet_validation({
  magnet_depth_mm = 0.2,
  magnet_chamfer_mm = 0.25
})
assert(not filler_magnets_ok and string.find(filler_magnets_error, "deeper", 1, true),
  "Filler Plate magnet chamfers deeper than their pockets should be rejected")

local filler_plan_options = {
  allowance_mm = 0.2,
  include_magnets = false,
  magnet_diameter_mm = 6.2,
  magnet_depth_mm = 2.4,
  magnet_chamfer_mm = 0.25,
  magnet_inset_mm = 8,
  magnet_base_mm = 0.4,
  cell_width_mm = 42,
  cell_height_mm = 42,
  layout = layout
}
local filler_tools = {
  rough_diameter_mm = 6.35,
  finish_diameter_mm = 3.175,
  vbit_diameter_mm = 3.175,
  vbit_angle = 90
}
local filler_plan = assert(core.build_filler_operation_plan(
  filler_plan_options, filler_tools, 6.0))
near(filler_plan.minimum_thickness_mm, 5.4, 1e-9,
  "multi-cell Filler Plate stock should include the deeper seam pass")
near(filler_plan.deepest_cut_mm, 6.0, 1e-9,
  "the outside cutout should be the deepest operation")
assert(filler_plan.seam_count == 3,
  "a 3 by 2 plate should have two vertical and one horizontal seam")
assert(#filler_plan.lower_chamfer_passes == 1,
  "a 1/8-inch V-bit should cut the lower chamfer in one contour pass")
assert(#filler_plan.upper_chamfer_passes == 2,
  "a 1/8-inch V-bit should cut the upper chamfer in two contour passes")
near(filler_plan.lower_chamfer_passes[1].target_depth_mm, 0.8, 1e-9,
  "lower chamfer should end at the exposed-face depth")
near(filler_plan.lower_chamfer_passes[1].width, 37.2, 1e-9,
  "lower chamfer tool tip should follow the wall contour")
near(filler_plan.upper_chamfer_passes[2].target_depth_mm, 4.75, 1e-9,
  "final upper chamfer pass should reach the plate interface")
near(filler_plan.upper_chamfer_passes[2].width, 41.5, 1e-9,
  "final upper chamfer tool tip should follow the top contour")
near(filler_plan.rough_clearance_expansion_mm, 3.375, 1e-9,
  "rough clearance should expand by cutter radius plus allowance")
near(filler_plan.finish_clearance_expansion_mm, 1.5875, 1e-9,
  "finish clearance should expand by cutter radius")
near(filler_plan.interface_clearance_expansion_mm, 3.175, 1e-9,
  "interface clearance should provide an accessible perimeter beyond the plate")
near(filler_plan.wall_clearance_mm, 4.8, 1e-9,
  "standard wall profiles should leave 4.8 mm clearance")
assert(not filler_plan.use_rough_clearance,
  "a quarter-inch rougher plus allowance should not fit the wall clearance")
assert(filler_plan.expected_operations == 8,
  "a multi-cell Filler Plate should include seam and outside-cutout operations")
assert(filler_plan.operations[1].layer_names[1] ==
       "Gridfinity - Filler Finish Clearance Boundary" and
       filler_plan.operations[1].layer_names[2] ==
       "Gridfinity - Filler Foot Wall Edge" and
       filler_plan.operations[1].cut_depth_mm == 2.6,
  "finishing clearance should use wall islands and stop at wall depth")
assert(filler_plan.operations[2].layer_names[1] ==
       "Gridfinity - Filler Plate Interface Clearance Boundary" and
       filler_plan.operations[2].layer_names[2] ==
       "Gridfinity - Filler Foot Top Edge" and
       filler_plan.operations[2].start_depth_mm == 2.6 and
       filler_plan.operations[2].cut_depth_mm == 2.15,
  "plate-interface clearance should protect foot tops and finish at 4.75 mm")
assert(filler_plan.operations[3].profile_side == "outside" and
       filler_plan.operations[3].start_depth_mm == 0.8 and
       filler_plan.operations[3].cut_depth_mm == 1.8,
  "wall finishing should run outside the wall from 0.8 through 2.6 mm")
assert(filler_plan.operations[7].label == "Upper Chamfer Seam Pass" and
       filler_plan.operations[7].layer_names[1] ==
         "Gridfinity - Filler Upper Chamfer Seam Pass" and
       filler_plan.operations[7].start_depth_mm == 2.6 and
       filler_plan.operations[7].cut_depth_mm == 2.4 and
       filler_plan.operations[7].allow_open,
  "the final upper-chamfer operation should clean open seams to 5 mm")
assert(filler_plan.operations[8].label == "Rough Outside Cutout" and
       filler_plan.operations[8].tool == "rough" and
       filler_plan.operations[8].profile_side == "outside" and
       filler_plan.operations[8].cut_depth_mm == 6.0 and
       filler_plan.operations[8].allowance_mm == 0.0 and
       filler_plan.operations[8].use_tabs,
  "the rough tool should cut the boundary through stock with tabs")
assert(core.add_filler_geometry(
  {LayerManager = filler_layer_manager}, layout, 1.0,
  filler_plan_options, filler_plan))
assert(filler_layers["Gridfinity - Filler Lower Chamfer Pass 1"].object_count ==
       #shared_cells,
  "each lower-chamfer pass should have one derived contour per complete cell")
assert(filler_layers["Gridfinity - Filler Upper Chamfer Pass 2"].object_count ==
       #shared_cells,
  "each upper-chamfer pass should have one derived contour per complete cell")
assert(filler_layers["Gridfinity - Filler Upper Chamfer Seam Pass"].object_count == 3,
  "the upper-chamfer seam layer should contain every internal grid centerline")
assert(inserted_tab_count == 4,
  "the Filler Plate boundary should receive one tab on each side")
assert(filler_layers["Gridfinity - Filler Rough Clearance Boundary"] == nil and
       filler_layers["Gridfinity - Filler Finish Clearance Boundary"].object_count == 1 and
       filler_layers["Gridfinity - Filler Plate Interface Clearance Boundary"].object_count == 1,
  "both finishing stages should have expanded clearance boundaries")
local magnet_plan_options = {}
for key, value in pairs(filler_plan_options) do magnet_plan_options[key] = value end
magnet_plan_options.include_magnets = true
local magnet_plan = assert(core.build_filler_operation_plan(
  magnet_plan_options, filler_tools, 6.0))
assert(magnet_plan.expected_operations == 10,
  "magnets should add pocket and chamfer operations to the Filler Plate plan")

local margin_plan_options = {}
for key, value in pairs(filler_plan_options) do margin_plan_options[key] = value end
margin_plan_options.layout = margin_magnet_layout
local margin_plan = assert(core.build_filler_operation_plan(
  margin_plan_options, filler_tools, 6.0))
assert(margin_plan.expected_operations == 8 and
       margin_plan.operations[1].kind == "pocket",
  "finishing clearance should be retained for arbitrary-size plates")
assert(margin_plan.operations[1].layer_names[1] ==
       "Gridfinity - Filler Finish Clearance Boundary" and
       margin_plan.operations[1].layer_names[2] ==
       "Gridfinity - Filler Foot Wall Edge",
  "clearance pockets should use expanded boundaries with wall contours as islands")

local small_rough_tools = {}
for key, value in pairs(filler_tools) do small_rough_tools[key] = value end
small_rough_tools.rough_diameter_mm = 3.0
local small_rough_plan = assert(core.build_filler_operation_plan(
  filler_plan_options, small_rough_tools, 6.0))
assert(small_rough_plan.use_rough_clearance and
       small_rough_plan.expected_operations == 10 and
       small_rough_plan.operations[1].layer_names[1] ==
       "Gridfinity - Filler Rough Clearance Boundary",
  "rough clearance should be generated independently when its tool fits")
assert(small_rough_plan.operations[9].label == "Rough Outside Cutout" and
       small_rough_plan.operations[9].allowance_mm == 0.2 and
       small_rough_plan.operations[10].label == "Finish Outside Cutout" and
       small_rough_plan.operations[10].tool == "finish" and
       small_rough_plan.operations[10].use_tabs,
  "a rough-clearance plan should finish the allowed rough outside cutout")

local invalid_filler_plan, invalid_filler_error = core.build_filler_operation_plan(
  filler_plan_options, {
    rough_diameter_mm = 6.35,
    finish_diameter_mm = 3.175,
    vbit_diameter_mm = 6.35,
    vbit_angle = 90
  }, 6.0)
assert(invalid_filler_plan == nil and
       string.find(invalid_filler_error, "vertical wall", 1, true),
  "a V-bit cone wider than the upper chamfer should be rejected")
invalid_filler_plan, invalid_filler_error = core.build_filler_operation_plan(
  filler_plan_options, {
    rough_diameter_mm = 6.35,
    finish_diameter_mm = 5.0,
    vbit_diameter_mm = 3.175,
    vbit_angle = 90
  }, 6.0)
assert(invalid_filler_plan == nil and
       string.find(invalid_filler_error, "does not fit", 1, true),
  "a finishing tool wider than the wall clearance should be rejected")
invalid_filler_plan, invalid_filler_error = core.build_filler_operation_plan(
  filler_plan_options, filler_tools, 5.399)
assert(invalid_filler_plan == nil and string.find(invalid_filler_error, "too thin", 1, true),
  "Filler Plate stock thinner than the foot plus flat top should be rejected")
assert(core.build_filler_operation_plan(
  filler_plan_options, filler_tools, 5.4),
  "Filler Plate stock exactly at the calculated minimum should be accepted")
assert(core.build_filler_operation_plan(
  filler_plan_options, filler_tools,
  core.from_job_units(5.401 / 25.4, false)),
  "inch-job stock above the calculated minimum should be accepted")

local single_cell_plan_options = {}
for key, value in pairs(filler_plan_options) do
  single_cell_plan_options[key] = value
end
single_cell_plan_options.layout = assert(core.create_layout(
  layout_options({columns = 1, rows = 1}), 0, 0))
local single_cell_plan = assert(core.build_filler_operation_plan(
  single_cell_plan_options, filler_tools, 5.15))
assert(single_cell_plan.seam_count == 0 and
       single_cell_plan.expected_operations == 7,
  "a one-cell plate should omit the seam but retain its outside cutout")
near(single_cell_plan.minimum_thickness_mm, 5.15, 1e-9,
  "a one-cell plate should retain the original minimum stock thickness")

local expected_origins = {
  ["Bottom Left"] = {0, 0},
  ["Bottom Right"] = {-100, 0},
  ["Top Left"] = {0, -85},
  ["Top Right"] = {-100, -85},
  ["Center"] = {-50, -42.5}
}
local expected_grid_origins = {
  ["Bottom Left"] = {0, 0},
  ["Bottom Right"] = {-84, 0},
  ["Top Left"] = {0, -84},
  ["Top Right"] = {-84, -84},
  ["Center"] = {-42, -42}
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
  assert(layout.columns == 2 and layout.rows == 2,
    origin_from .. " should preserve the shared complete-cell count")
  local expected_grid = expected_grid_origins[origin_from]
  local origin_filler = assert(core.filler_geometry(layout))
  near(origin_filler.cells[1].cx, expected_grid[1] + 21, 1e-9,
    origin_from .. " filler center X")
  near(origin_filler.cells[1].cy, expected_grid[2] + 21, 1e-9,
    origin_from .. " filler center Y")
end

layout = assert(core.create_layout(layout_options({
  size_mode = "Overall Dimensions",
  overall_x_mm = 100,
  overall_y_mm = 85,
  origin_from = "Bottom Left"
}), 10, 15))
local offset_filler = assert(core.filler_geometry(layout))
near(offset_filler.cells[1].cx, 31, 1e-9, "filler X offset should use shared layout")
near(offset_filler.cells[1].cy, 36, 1e-9, "filler Y offset should use shared layout")

layout = assert(core.create_layout(layout_options({
  size_mode = "Overall Dimensions",
  overall_x_mm = 100,
  overall_y_mm = 85,
  origin_from = "Bottom Right"
}), 100, 0))
near(layout.grid_min_x, 16, 1e-9, "right origin should place unused width on the left")
cells = core.layout_cells(layout)
assert(#cells == 4, "100 x 85 mm should enumerate a 2 x 2 complete-cell grid")
near(cells[1].clip_min_x, 16, 1e-9, "left cell should remain complete")
near(cells[2].clip_max_x, 100, 1e-9, "right cell should end at the requested edge")

local layout_ok = core.validate_layout(layout, 0, 0, 100, 85)
assert(layout_ok,
  "a plate boundary may exactly fill the job even when helper paths cut air")
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

local open_selector_applied = false
local open_selector = {
  AddLayerName = function() end,
  ApplySelector = function()
    open_selector_applied = true
  end
}
core.configure_layer_selector(open_selector, "Open Layer", true)
assert(not open_selector.SelectClosed,
  "an open-vector selector should not also select closed vectors")
assert(open_selector.SelectOpen and open_selector.AllowOpen,
  "the seam profile selector should select and allow open vectors")
assert(open_selector_applied,
  "the open-vector selector must be applied before toolpath calculation")

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
assert(not ok, "45 degree V-bit should fail")
ok, vbit_error = core.validate_tool_geometry(6.35, 3.175, 6.35, nil, 0.2, 4.65, 6)
assert(not ok, "missing V-bit angle should fail without a Lua error")
assert(string.find(vbit_error, "valid angle", 1, true), "missing-angle error should explain the problem")
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
