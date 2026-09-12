-- VECTRIC LUA SCRIPT
-- Gridfinity Baseplate Gadget
-- Generates editable Vectric pocket and profile toolpaths from layer-associated
-- socket and magnet geometry.

local GRIDFINITY_TEST_MODE = rawget(_G, "GRIDFINITY_TEST_MODE") == true
if not GRIDFINITY_TEST_MODE then
  require "strict"
end

local TITLE = "Gridfinity"
local VERSION = "1.1.0"
local REGISTRY_SECTION = "GridfinityBaseplateGadget"
local LAYER_SOCKET_OUTER = "Gridfinity - Socket Outer Edge"
local LAYER_SOCKET_INNER = "Gridfinity - Socket Inner Edge"
local LAYER_MAGNET_OUTER = "Gridfinity - Magnet Outer Edge"
local LAYER_MAGNET_INNER = "Gridfinity - Magnet Inner Edge"
local LEGACY_LAYERS = {
  "Gridfinity - Top Opening",
  "Gridfinity - Vertical Wall",
  "Gridfinity - Bottom Opening",
  "Gridfinity - Magnet Pockets"
}
local BULGE_90 = 0.4142135623730951

-- Geometry and validation live in this script so VCarve discovers only one
-- runnable .lua file in the gadget directory.
local Core = {}

Core.PITCH_MM = 42.0
Core.CLEARANCE_MM = 0.25
Core.TOP_OPENING_MM = Core.PITCH_MM - 2.0 * Core.CLEARANCE_MM
Core.TOP_RADIUS_MM = 3.75
Core.UPPER_CHAMFER_MM = 2.15
Core.VERTICAL_WALL_MM = 1.8
Core.LOWER_CHAMFER_MM = 0.7
Core.MID_OPENING_MM = Core.TOP_OPENING_MM - 2.0 * Core.UPPER_CHAMFER_MM
Core.MID_RADIUS_MM = Core.TOP_RADIUS_MM - Core.UPPER_CHAMFER_MM
Core.BOTTOM_OPENING_MM = Core.MID_OPENING_MM - 2.0 * Core.LOWER_CHAMFER_MM
Core.BOTTOM_RADIUS_MM = Core.MID_RADIUS_MM - Core.LOWER_CHAMFER_MM
Core.MID_DEPTH_MM = Core.UPPER_CHAMFER_MM
Core.LOWER_START_DEPTH_MM = Core.UPPER_CHAMFER_MM + Core.VERTICAL_WALL_MM
Core.TOTAL_DEPTH_MM = Core.LOWER_START_DEPTH_MM + Core.LOWER_CHAMFER_MM
-- The lower 0.7 mm chamfer is intentionally omitted from machining for now.
-- The end mills continue the vertical wall to the 4.65 mm terminal depth.
Core.MACHINED_BOTTOM_OPENING_MM = Core.MID_OPENING_MM
Core.MACHINED_BOTTOM_RADIUS_MM = Core.MID_RADIUS_MM
-- The agreed CNC tooling limit applies to both Baseplate and Filler Plate
-- chamfers. A 1/2-inch V-bit is not permitted for either output.
Core.MAX_CHAMFER_TOOL_DIAMETER_MM = 6.35

function Core.to_job_units(value_mm, job_in_mm)
  if job_in_mm then
    return value_mm
  end
  return value_mm / 25.4
end

function Core.tool_value_in_job_units(value, tool_in_mm, job_in_mm)
  if tool_in_mm == job_in_mm then
    return value
  end
  if tool_in_mm then
    return value / 25.4
  end
  return value * 25.4
end

function Core.profile_at_depth_mm(depth_mm)
  local d = math.max(0.0, math.min(depth_mm, Core.TOTAL_DEPTH_MM))
  if d <= Core.MID_DEPTH_MM then
    return Core.TOP_OPENING_MM - 2.0 * d, Core.TOP_RADIUS_MM - d
  end
  if d <= Core.LOWER_START_DEPTH_MM then
    return Core.MID_OPENING_MM, Core.MID_RADIUS_MM
  end
  local lower_depth = d - Core.LOWER_START_DEPTH_MM
  return Core.MID_OPENING_MM - 2.0 * lower_depth,
         Core.MID_RADIUS_MM - lower_depth
end

function Core.profile_dimensions_at_depth_mm(depth_mm, cell_width_mm, cell_height_mm)
  local standard_width, radius = Core.profile_at_depth_mm(depth_mm)
  local inset = (Core.TOP_OPENING_MM - standard_width) * 0.5
  return cell_width_mm - 2.0 * Core.CLEARANCE_MM - 2.0 * inset,
         cell_height_mm - 2.0 * Core.CLEARANCE_MM - 2.0 * inset,
         radius
end

function Core.machining_profile_dimensions_at_depth_mm(depth_mm, cell_width_mm, cell_height_mm)
  local machined_depth = math.min(depth_mm, Core.LOWER_START_DEPTH_MM)
  return Core.profile_dimensions_at_depth_mm(machined_depth, cell_width_mm, cell_height_mm)
end

-- Return a conservative centerline region for a circular cutter. When the
-- cutter is larger than the desired corner radius, stay inside the rectangular
-- core instead of approximating an unsafe negative corner radius.
function Core.inset_profile(width, height, radius, offset)
  if offset <= radius then
    return width - 2.0 * offset, height - 2.0 * offset, radius - offset
  end
  return width - 2.0 * radius - 2.0 * offset,
         height - 2.0 * radius - 2.0 * offset,
         0.0
end

function Core.grid_size_mm(columns, rows, cell_width_mm, cell_height_mm)
  return columns * (cell_width_mm or Core.PITCH_MM),
         rows * (cell_height_mm or Core.PITCH_MM)
end

function Core.resolve_size(options)
  local cell_w = options.cell_width_mm
  local cell_h = options.cell_height_mm
  if cell_w <= 0.0 or cell_h <= 0.0 then
    return nil, "Cell width and height must both be positive."
  end
  if options.size_mode == "Overall Dimensions" then
    if options.overall_x_mm <= 0.0 or options.overall_y_mm <= 0.0 then
      return nil, "Overall X and Overall Y must both be positive."
    end
    return {
      columns = math.max(1, math.ceil(options.overall_x_mm / cell_w - 0.000000001)),
      rows = math.max(1, math.ceil(options.overall_y_mm / cell_h - 0.000000001)),
      overall_x_mm = options.overall_x_mm,
      overall_y_mm = options.overall_y_mm
    }, nil
  end
  if options.columns < 1 or options.rows < 1 then
    return nil, "Rows and columns must both be at least 1."
  end
  local overall_x, overall_y = Core.grid_size_mm(
    options.columns, options.rows, cell_w, cell_h)
  return {
    columns = options.columns,
    rows = options.rows,
    overall_x_mm = overall_x,
    overall_y_mm = overall_y
  }, nil
end

function Core.create_layout(options, anchor_x, anchor_y)
  local size, size_error = Core.resolve_size(options)
  if size == nil then
    return nil, size_error
  end
  if size.columns > 100 or size.rows > 100 then
    return nil, "Rows and columns are limited to 100 to avoid oversized toolpaths."
  end

  local min_x, min_y = anchor_x, anchor_y
  local origin_from = options.origin_from
  if origin_from == "Bottom Right" then
    min_x = anchor_x - size.overall_x_mm
  elseif origin_from == "Top Left" then
    min_y = anchor_y - size.overall_y_mm
  elseif origin_from == "Top Right" then
    min_x = anchor_x - size.overall_x_mm
    min_y = anchor_y - size.overall_y_mm
  elseif origin_from == "Center" then
    min_x = anchor_x - size.overall_x_mm * 0.5
    min_y = anchor_y - size.overall_y_mm * 0.5
  end

  local grid_w, grid_h = Core.grid_size_mm(
    size.columns, size.rows, options.cell_width_mm, options.cell_height_mm)
  local grid_min_x, grid_min_y = min_x, min_y
  if origin_from == "Bottom Right" or origin_from == "Top Right" then
    grid_min_x = min_x + size.overall_x_mm - grid_w
  elseif origin_from == "Center" then
    grid_min_x = min_x + (size.overall_x_mm - grid_w) * 0.5
  end
  if origin_from == "Top Left" or origin_from == "Top Right" then
    grid_min_y = min_y + size.overall_y_mm - grid_h
  elseif origin_from == "Center" then
    grid_min_y = min_y + (size.overall_y_mm - grid_h) * 0.5
  end

  return {
    columns = size.columns,
    rows = size.rows,
    overall_x_mm = size.overall_x_mm,
    overall_y_mm = size.overall_y_mm,
    min_x = min_x,
    min_y = min_y,
    max_x = min_x + size.overall_x_mm,
    max_y = min_y + size.overall_y_mm,
    grid_min_x = grid_min_x,
    grid_min_y = grid_min_y,
    cell_width_mm = options.cell_width_mm,
    cell_height_mm = options.cell_height_mm
  }, nil
end

function Core.layout_cells(layout)
  local cells = {}
  for row = 0, layout.rows - 1 do
    for col = 0, layout.columns - 1 do
      local cell_min_x = layout.grid_min_x + col * layout.cell_width_mm
      local cell_min_y = layout.grid_min_y + row * layout.cell_height_mm
      cells[#cells + 1] = {
        row = row,
        column = col,
        cx = cell_min_x + layout.cell_width_mm * 0.5,
        cy = cell_min_y + layout.cell_height_mm * 0.5,
        clip_min_x = math.max(cell_min_x, layout.min_x),
        clip_min_y = math.max(cell_min_y, layout.min_y),
        clip_max_x = math.min(cell_min_x + layout.cell_width_mm, layout.max_x),
        clip_max_y = math.min(cell_min_y + layout.cell_height_mm, layout.max_y)
      }
    end
  end
  return cells
end

function Core.finish_uses_pocket(allowance_mm)
  return allowance_mm > 0.000001
end

function Core.magnet_outer_diameter_mm(hole_diameter_mm, chamfer_mm)
  return hole_diameter_mm + 2.0 * chamfer_mm
end

function Core.validate_grid(columns, rows, origin_x, origin_y, job_min_x, job_min_y,
                            job_width, job_height, pitch_x, pitch_y)
  if columns < 1 or rows < 1 then
    return false, "Rows and columns must both be at least 1."
  end
  if columns > 100 or rows > 100 then
    return false, "Rows and columns are limited to 100 to avoid oversized toolpaths."
  end
  if pitch_x <= 0.0 or pitch_y <= 0.0 then
    return false, "Cell width and height must both be positive."
  end
  local width = columns * pitch_x
  local height = rows * pitch_y
  local eps = math.max(pitch_x, pitch_y) * 0.000001
  if origin_x < job_min_x - eps or origin_y < job_min_y - eps or
     origin_x + width > job_min_x + job_width + eps or
     origin_y + height > job_min_y + job_height + eps then
    return false, "The baseplate does not fit inside the current job."
  end
  return true, nil
end

function Core.validate_layout(layout, job_min_x, job_min_y, job_width, job_height)
  local eps = math.max(layout.cell_width_mm, layout.cell_height_mm) * 0.000001
  if layout.min_x < job_min_x - eps or layout.min_y < job_min_y - eps or
     layout.max_x > job_min_x + job_width + eps or
     layout.max_y > job_min_y + job_height + eps then
    return false, "The requested Gridfinity layout does not fit inside the current job."
  end
  return true, nil
end

function Core.validate_tool_geometry(rough_dia, finish_dia, vbit_dia, vbit_angle,
                                     allowance, total_depth, material_thickness,
                                     minimum_opening)
  if rough_dia <= 0.0 or finish_dia <= 0.0 or vbit_dia <= 0.0 then
    return false, "All selected tools must have a positive diameter."
  end
  if type(vbit_angle) ~= "number" then
    return false, "The selected V-bit does not provide a valid included angle. Edit or reselect it in the Vectric tool database."
  end
  local smallest_opening = minimum_opening or Core.BOTTOM_OPENING_MM
  if smallest_opening <= 0.0 then
    return false, "The custom cell size is too small for the Gridfinity profile."
  end
  if rough_dia >= smallest_opening or finish_dia >= smallest_opening then
    return false, string.format(
      "The selected end mills do not fit the %.3f mm bottom opening. " ..
      "Roughing: %.3f mm (%.4f in); finishing: %.3f mm (%.4f in). " ..
      "Choose smaller end mills.",
      smallest_opening, rough_dia, rough_dia / 25.4,
      finish_dia, finish_dia / 25.4)
  end
  if finish_dia * 0.5 > Core.MACHINED_BOTTOM_RADIUS_MM + 0.000001 then
    return false, string.format(
      "The selected finishing end mill is %.3f mm (%.4f in). " ..
      "It is too large for the %.1f mm machined floor corner radius. " ..
      "Choose a finishing end mill no larger than %.1f mm (%.4f in).",
      finish_dia, finish_dia / 25.4, Core.MACHINED_BOTTOM_RADIUS_MM,
      2.0 * Core.MACHINED_BOTTOM_RADIUS_MM,
      2.0 * Core.MACHINED_BOTTOM_RADIUS_MM / 25.4)
  end
  if math.abs(vbit_angle - 90.0) > 0.5 then
    return false, string.format(
      "The selected V-bit has a %.1f degree included angle. " ..
      "Change it to a 90 degree included-angle V-bit (45 degrees per side).",
      vbit_angle)
  end
  if vbit_dia > Core.MAX_CHAMFER_TOOL_DIAMETER_MM + 0.000001 then
    return false, string.format(
      "The selected V-bit is %.3f mm (%.4f in) in diameter. " ..
      "Gridfinity chamfers require a 90 degree V-bit no larger than " ..
      "6.35 mm (0.2500 in). The 1/2 inch V-bit is too large.",
      vbit_dia, vbit_dia / 25.4)
  end
  if vbit_dia + 0.000001 < 2.0 * Core.UPPER_CHAMFER_MM then
    return false, string.format(
      "The selected V-bit is %.3f mm (%.4f in) in diameter. " ..
      "Change it to a V-bit at least 4.3 mm in diameter for the 2.15 mm upper chamfer.",
      vbit_dia, vbit_dia / 25.4)
  end
  if allowance < 0.0 or allowance >= 1.0 then
    return false, "Roughing allowance must be between 0 and 1 mm."
  end
  if material_thickness + 0.000001 < total_depth then
    return false, "Material must be at least 4.65 mm thick."
  end
  return true, nil
end

function Core.validate_magnets(include_magnets, hole_diameter, hole_depth, chamfer,
                               edge_inset, base_thickness, cell_width, cell_height,
                               finish_diameter, total_depth, material_thickness)
  if not include_magnets then
    return true, nil
  end
  if hole_diameter <= 0.0 or hole_depth <= 0.0 then
    return false, "Magnet-hole diameter and depth must be positive."
  end
  if finish_diameter >= hole_diameter then
    return false, "The finishing end mill must be smaller than the magnet-hole diameter."
  end
  if chamfer < 0.0 or chamfer >= hole_diameter * 0.5 then
    return false, "Magnet-hole chamfer must be non-negative and smaller than the hole radius."
  end
  if edge_inset <= hole_diameter * 0.5 + chamfer or
     edge_inset >= math.min(cell_width, cell_height) * 0.5 then
    return false, "Magnet-hole inset does not keep the chamfer inside each cell."
  end
  if base_thickness < 0.0 then
    return false, "Magnet base thickness cannot be negative."
  end
  if material_thickness + 0.000001 < total_depth + hole_depth + base_thickness then
    return false, "The material is too thin for the socket, magnet depth, and retained base."
  end
  return true, nil
end

local function path_join(base, filename)
  local sep = "\\"
  if string.sub(base, -1) == "\\" or string.sub(base, -1) == "/" then
    return base .. filename
  end
  return base .. sep .. filename
end

local function clear_layer(layer)
  while not layer.IsEmpty do
    local pos = layer:GetHeadPosition()
    layer:RemoveAt(pos)
  end
end

local function rounded_rect(cx, cy, width, height, radius, z)
  local half_w = width * 0.5
  local half_h = height * 0.5
  local r = math.max(0.000001, math.min(radius, half_w, half_h))
  local c = Contour(0.0)
  c:AppendPoint(cx - half_w + r, cy - half_h, z)
  c:LineTo(cx + half_w - r, cy - half_h, z)
  c:ArcTo(Point3D(cx + half_w, cy - half_h + r, z), BULGE_90)
  c:LineTo(cx + half_w, cy + half_h - r, z)
  c:ArcTo(Point3D(cx + half_w - r, cy + half_h, z), BULGE_90)
  c:LineTo(cx - half_w + r, cy + half_h, z)
  c:ArcTo(Point3D(cx - half_w, cy + half_h - r, z), BULGE_90)
  c:LineTo(cx - half_w, cy - half_h + r, z)
  c:ArcTo(Point3D(cx - half_w + r, cy - half_h, z), BULGE_90)
  return c
end

local function rounded_rect_points(cx, cy, width, height, radius)
  local half_w = width * 0.5
  local half_h = height * 0.5
  local r = math.max(0.000001, math.min(radius, half_w, half_h))
  local points = {}
  local corners = {
    {cx + half_w - r, cy - half_h + r, -90.0},
    {cx + half_w - r, cy + half_h - r, 0.0},
    {cx - half_w + r, cy + half_h - r, 90.0},
    {cx - half_w + r, cy - half_h + r, 180.0}
  }
  for _, corner in ipairs(corners) do
    for step = 0, 12 do
      local angle = math.rad(corner[3] + step * 7.5)
      points[#points + 1] = {
        x = corner[1] + r * math.cos(angle),
        y = corner[2] + r * math.sin(angle)
      }
    end
  end
  return points
end

local function clip_polygon_axis(points, axis, boundary, keep_greater)
  local result = {}
  if #points == 0 then
    return result
  end
  local function inside(point)
    if keep_greater then
      return point[axis] >= boundary - 0.000000001
    end
    return point[axis] <= boundary + 0.000000001
  end
  local function intersection(a, b)
    local delta = b[axis] - a[axis]
    local t = math.abs(delta) < 0.000000001 and 0.0 or (boundary - a[axis]) / delta
    return {
      x = a.x + (b.x - a.x) * t,
      y = a.y + (b.y - a.y) * t
    }
  end
  local previous = points[#points]
  local previous_inside = inside(previous)
  for _, current in ipairs(points) do
    local current_inside = inside(current)
    if current_inside ~= previous_inside then
      result[#result + 1] = intersection(previous, current)
    end
    if current_inside then
      result[#result + 1] = current
    end
    previous = current
    previous_inside = current_inside
  end
  return result
end

local function clipped_rounded_rect(cx, cy, width, height, radius, bounds, z)
  local half_w = width * 0.5
  local half_h = height * 0.5
  if cx - half_w >= bounds.min_x and cx + half_w <= bounds.max_x and
     cy - half_h >= bounds.min_y and cy + half_h <= bounds.max_y then
    return rounded_rect(cx, cy, width, height, radius, z)
  end
  local points = rounded_rect_points(cx, cy, width, height, radius)
  points = clip_polygon_axis(points, "x", bounds.min_x, true)
  points = clip_polygon_axis(points, "x", bounds.max_x, false)
  points = clip_polygon_axis(points, "y", bounds.min_y, true)
  points = clip_polygon_axis(points, "y", bounds.max_y, false)
  if #points < 3 then
    return nil
  end
  local contour = Contour(0.0)
  contour:AppendPoint(points[1].x, points[1].y, z)
  for index = 2, #points do
    contour:LineTo(points[index].x, points[index].y, z)
  end
  contour:LineTo(points[1].x, points[1].y, z)
  return contour
end

local function magnet_centers(options, cx, cy, unit)
  local dx = options.cell_width_mm * unit * 0.5 - options.magnet_inset_mm * unit
  local dy = options.cell_height_mm * unit * 0.5 - options.magnet_inset_mm * unit
  return {
    {cx - dx, cy - dy}, {cx + dx, cy - dy},
    {cx + dx, cy + dy}, {cx - dx, cy + dy}
  }
end

function Core.get_magnet_layers(manager, include_magnets)
  if include_magnets then
    return manager:GetLayerWithName(LAYER_MAGNET_OUTER),
           manager:GetLayerWithName(LAYER_MAGNET_INNER)
  end
  -- FindLayerWithName does not create a missing layer. Existing layers are
  -- returned so stale geometry from an earlier magnet-enabled run can be
  -- cleared without adding magnet layers to a socket-only job.
  return manager:FindLayerWithName(LAYER_MAGNET_OUTER),
         manager:FindLayerWithName(LAYER_MAGNET_INNER)
end

local function add_geometry(job, options, unit)
  local manager = job.LayerManager
  local socket_outer_layer = manager:GetLayerWithName(LAYER_SOCKET_OUTER)
  local socket_inner_layer = manager:GetLayerWithName(LAYER_SOCKET_INNER)
  local magnet_outer_layer, magnet_inner_layer = Core.get_magnet_layers(
    manager, options.include_magnets)
  clear_layer(socket_outer_layer)
  clear_layer(socket_inner_layer)
  if magnet_outer_layer ~= nil then
    clear_layer(magnet_outer_layer)
  end
  if magnet_inner_layer ~= nil then
    clear_layer(magnet_inner_layer)
  end
  for _, layer_name in ipairs(LEGACY_LAYERS) do
    local legacy_layer = manager:FindLayerWithName(layer_name)
    if legacy_layer ~= nil then
      clear_layer(legacy_layer)
    end
  end
  socket_outer_layer:SetColour(0.10, 0.55, 0.30)
  socket_inner_layer:SetColour(0.15, 0.35, 0.80)
  if options.include_magnets then
    magnet_outer_layer:SetColour(0.85, 0.45, 0.10)
    magnet_inner_layer:SetColour(0.55, 0.15, 0.65)
  end

  local layout = options.layout
  local bounds = {
    min_x = layout.min_x * unit,
    min_y = layout.min_y * unit,
    max_x = layout.max_x * unit,
    max_y = layout.max_y * unit
  }
  for _, cell in ipairs(Core.layout_cells(layout)) do
      local cx = cell.cx * unit
      local cy = cell.cy * unit
      local top_w, top_h, top_r = Core.machining_profile_dimensions_at_depth_mm(0.0, options.cell_width_mm, options.cell_height_mm)
      local mid_w, mid_h, mid_r = Core.machining_profile_dimensions_at_depth_mm(Core.MID_DEPTH_MM, options.cell_width_mm, options.cell_height_mm)
      local outer = clipped_rounded_rect(
        cx, cy, top_w * unit, top_h * unit, top_r * unit, bounds, 0.0)
      local inner = clipped_rounded_rect(
        cx, cy, mid_w * unit, mid_h * unit, mid_r * unit, bounds, 0.0)
      if outer ~= nil then
        socket_outer_layer:AddObject(CreateCadContour(outer), true)
      end
      if inner ~= nil then
        socket_inner_layer:AddObject(CreateCadContour(inner), true)
      end
      if options.include_magnets then
        local inner_diameter = options.magnet_diameter_mm * unit
        local outer_diameter = Core.magnet_outer_diameter_mm(
          options.magnet_diameter_mm, options.magnet_chamfer_mm) * unit
        for _, point in ipairs(magnet_centers(options, cx, cy, unit)) do
          magnet_outer_layer:AddObject(CreateCadContour(rounded_rect(
            point[1], point[2], outer_diameter, outer_diameter,
            outer_diameter * 0.5, 0.0)), true)
          magnet_inner_layer:AddObject(CreateCadContour(rounded_rect(
            point[1], point[2], inner_diameter, inner_diameter,
            inner_diameter * 0.5, 0.0)), true)
        end
      end
  end
end

local function create_position_data(material, unit)
  local box = material.MaterialBox
  local gap = math.max(Core.to_job_units(2.0, material.InMM), material.Thickness * 0.1)
  local pos_data = ToolpathPosData()
  pos_data:SetHomePosition(box.BLC.x, box.BLC.y, box.TRC.z + gap)
  pos_data.SafeZGap = gap
  pos_data.StartZGap = math.min(gap, Core.to_job_units(1.0, material.InMM))
  return pos_data
end

function Core.configure_layer_selector(selector, layer_name)
  -- GeometrySelector starts inactive. Activating and applying it selects the
  -- vectors needed for the initial calculation; retaining it on the native
  -- toolpath also allows Vectric to find the layer again when recalculating.
  selector.GeometryFilterUsed = true
  selector.OnlyOnLayers = true
  selector.SelectClosed = true
  selector.SelectOpen = false
  selector.AllowOpen = false
  selector:AddLayerName(layer_name)
  selector:ApplySelector()
  return selector
end

local function create_layer_selector(layer_name)
  return Core.configure_layer_selector(GeometrySelector(), layer_name)
end

local function create_pocket_toolpath(name, tool, material, unit, layer_name,
                                      start_depth_mm, cut_depth_mm, allowance_mm)
  local pocket_data = PocketParameterData()
  pocket_data.StartDepth = start_depth_mm * unit
  pocket_data.CutDepth = cut_depth_mm * unit
  pocket_data.CutDirection = ProfileParameterData.CLIMB_DIRECTION
  pocket_data.Allowance = allowance_mm * unit
  pocket_data.DoRasterClearance = true
  pocket_data.RasterAngle = 0.0
  pocket_data.ProfilePassType = PocketParameterData.PROFILE_LAST
  pocket_data.DoRamping = false
  pocket_data.RampDistance = 10.0 * unit
  pocket_data.ProjectToolpath = false

  local toolpath_id = ToolpathManager():CreatePocketingToolpath(
    name, tool, nil, pocket_data, create_position_data(material, unit),
    create_layer_selector(layer_name), true, true)
  return toolpath_id ~= nil
end

local function create_profile_toolpath(name, tool, material, unit, layer_name,
                                       start_depth_mm, cut_depth_mm, profile_side)
  local profile_data = ProfileParameterData()
  profile_data.StartDepth = start_depth_mm * unit
  profile_data.CutDepth = cut_depth_mm * unit
  profile_data.CutDirection = ProfileParameterData.CLIMB_DIRECTION
  profile_data.ProfileSide = profile_side
  profile_data.Allowance = 0.0
  profile_data.KeepStartPoints = false
  profile_data.CreateSquareCorners = false
  profile_data.CornerSharpen = false
  profile_data.UseTabs = false
  profile_data.ProjectToolpath = false

  local ramping_data = RampingData()
  ramping_data.DoRamping = false
  local lead_data = LeadInOutData()
  lead_data.DoLeadIn = false
  lead_data.DoLeadOut = false

  local toolpath_id = ToolpathManager():CreateProfilingToolpath(
    name, tool, profile_data, ramping_data, lead_data,
    create_position_data(material, unit), create_layer_selector(layer_name),
    true, true)
  return toolpath_id ~= nil
end

local function load_options(material)
  local registry = Registry(REGISTRY_SECTION)
  local unit = Core.to_job_units(1.0, material.InMM)
  local columns = registry:GetInt("Columns", 2)
  local rows = registry:GetInt("Rows", 2)
  local cell_width_mm = registry:GetDouble("CellWidthMM", 42.0)
  local cell_height_mm = registry:GetDouble("CellHeightMM", 42.0)
  return {
    output_type = registry:GetString("OutputType", "Baseplate"),
    size_mode = registry:GetString("SizeMode", "Grid Rows / Columns"),
    columns = columns,
    rows = rows,
    overall_x_mm = registry:GetDouble("OverallXMM", columns * cell_width_mm),
    overall_y_mm = registry:GetDouble("OverallYMM", rows * cell_height_mm),
    cell_width_mm = cell_width_mm,
    cell_height_mm = cell_height_mm,
    origin_from = registry:GetString("OriginFrom", "Bottom Left"),
    offset_x_mm = registry:GetDouble("OffsetXMM", 0.0),
    offset_y_mm = registry:GetDouble("OffsetYMM", 0.0),
    allowance_mm = registry:GetDouble("AllowanceMM", 0.0),
    include_magnets = registry:GetBool("IncludeMagnets", false),
    magnet_diameter_mm = registry:GetDouble("MagnetDiameterMM", 6.2),
    magnet_depth_mm = registry:GetDouble("MagnetDepthMM", 2.4),
    magnet_chamfer_mm = registry:GetDouble("MagnetChamferMM", 0.25),
    magnet_inset_mm = registry:GetDouble("MagnetInsetMM", 8.0),
    magnet_base_mm = registry:GetDouble("MagnetBaseMM", 0.4),
    origin_x = 0.0,
    origin_y = 0.0,
    unit = unit
  }
end

local function save_options(options, rough_tool, finish_tool, vbit_tool)
  local registry = Registry(REGISTRY_SECTION)
  registry:SetString("OutputType", options.output_type)
  registry:SetString("SizeMode", options.size_mode)
  registry:SetInt("Columns", options.columns)
  registry:SetInt("Rows", options.rows)
  registry:SetDouble("OverallXMM", options.overall_x_mm)
  registry:SetDouble("OverallYMM", options.overall_y_mm)
  registry:SetDouble("CellWidthMM", options.cell_width_mm)
  registry:SetDouble("CellHeightMM", options.cell_height_mm)
  registry:SetString("OriginFrom", options.origin_from)
  registry:SetDouble("OffsetXMM", options.offset_x_mm)
  registry:SetDouble("OffsetYMM", options.offset_y_mm)
  registry:SetDouble("AllowanceMM", options.allowance_mm)
  registry:SetBool("IncludeMagnets", options.include_magnets)
  registry:SetDouble("MagnetDiameterMM", options.magnet_diameter_mm)
  registry:SetDouble("MagnetDepthMM", options.magnet_depth_mm)
  registry:SetDouble("MagnetChamferMM", options.magnet_chamfer_mm)
  registry:SetDouble("MagnetInsetMM", options.magnet_inset_mm)
  registry:SetDouble("MagnetBaseMM", options.magnet_base_mm)
  rough_tool.ToolDBId:SaveDefaults(REGISTRY_SECTION, "Rough")
  finish_tool.ToolDBId:SaveDefaults(REGISTRY_SECTION, "Finish")
  vbit_tool.ToolDBId:SaveDefaults(REGISTRY_SECTION, "VBit")
end

local function show_dialog(script_path, material, options)
  local html_path = "file:" .. path_join(script_path, "Gridfinity_Baseplate.htm")
  local dialog = HTML_Dialog(false, html_path, 650, 780, TITLE .. " " .. VERSION)
  dialog:AddRadioGroup("OutputType", options.output_type == "Filler Plate" and 2 or 1)
  dialog:AddRadioGroup("SizeMode", options.size_mode == "Overall Dimensions" and 1 or 2)
  dialog:AddDoubleField("OverallX", options.overall_x_mm)
  dialog:AddDoubleField("OverallY", options.overall_y_mm)
  dialog:AddIntegerField("Columns", options.columns)
  dialog:AddIntegerField("Rows", options.rows)
  dialog:AddDoubleField("CellWidth", options.cell_width_mm)
  dialog:AddDoubleField("CellHeight", options.cell_height_mm)
  local origin_indexes = {
    ["Top Left"] = 1,
    ["Top Right"] = 2,
    ["Center"] = 3,
    ["Bottom Left"] = 4,
    ["Bottom Right"] = 5
  }
  dialog:AddRadioGroup("OriginFrom", origin_indexes[options.origin_from] or 4)
  dialog:AddDoubleField("OffsetX", options.offset_x_mm)
  dialog:AddDoubleField("OffsetY", options.offset_y_mm)
  dialog:AddDoubleField("Allowance", options.allowance_mm)
  dialog:AddCheckBox("IncludeMagnets", options.include_magnets)
  dialog:AddDoubleField("MagnetDiameter", options.magnet_diameter_mm)
  dialog:AddDoubleField("MagnetDepth", options.magnet_depth_mm)
  dialog:AddDoubleField("MagnetChamfer", options.magnet_chamfer_mm)
  dialog:AddDoubleField("MagnetInset", options.magnet_inset_mm)
  dialog:AddDoubleField("MagnetBase", options.magnet_base_mm)

  dialog:AddLabelField("RoughToolName", "")
  dialog:AddToolPicker("RoughToolButton", "RoughToolName", ToolDBId(REGISTRY_SECTION, "Rough"))
  dialog:AddToolPickerValidToolType("RoughToolButton", Tool.END_MILL)
  dialog:AddLabelField("FinishToolName", "")
  dialog:AddToolPicker("FinishToolButton", "FinishToolName", ToolDBId(REGISTRY_SECTION, "Finish"))
  dialog:AddToolPickerValidToolType("FinishToolButton", Tool.END_MILL)
  dialog:AddLabelField("VBitToolName", "")
  dialog:AddToolPicker("VBitToolButton", "VBitToolName", ToolDBId(REGISTRY_SECTION, "VBit"))
  dialog:AddToolPickerValidToolType("VBitToolButton", Tool.VBIT)

  if not dialog:ShowDialog() then
    return nil
  end
  local rough_tool = dialog:GetTool("RoughToolButton")
  local finish_tool = dialog:GetTool("FinishToolButton")
  local vbit_tool = dialog:GetTool("VBitToolButton")
  if rough_tool == nil or finish_tool == nil or vbit_tool == nil then
    DisplayMessageBox("Select all three tools before creating the Gridfinity design.")
    return nil
  end
  options.output_type = dialog:GetRadioIndex("OutputType") == 2 and "Filler Plate" or "Baseplate"
  options.size_mode = dialog:GetRadioIndex("SizeMode") == 1 and "Overall Dimensions" or "Grid Rows / Columns"
  options.overall_x_mm = dialog:GetDoubleField("OverallX")
  options.overall_y_mm = dialog:GetDoubleField("OverallY")
  options.columns = dialog:GetIntegerField("Columns")
  options.rows = dialog:GetIntegerField("Rows")
  options.cell_width_mm = dialog:GetDoubleField("CellWidth")
  options.cell_height_mm = dialog:GetDoubleField("CellHeight")
  local origin_values = {"Top Left", "Top Right", "Center", "Bottom Left", "Bottom Right"}
  options.origin_from = origin_values[dialog:GetRadioIndex("OriginFrom")] or "Bottom Left"
  options.offset_x_mm = dialog:GetDoubleField("OffsetX")
  options.offset_y_mm = dialog:GetDoubleField("OffsetY")
  options.allowance_mm = dialog:GetDoubleField("Allowance")
  options.include_magnets = dialog:GetCheckBox("IncludeMagnets")
  options.magnet_diameter_mm = dialog:GetDoubleField("MagnetDiameter")
  options.magnet_depth_mm = dialog:GetDoubleField("MagnetDepth")
  options.magnet_chamfer_mm = dialog:GetDoubleField("MagnetChamfer")
  options.magnet_inset_mm = dialog:GetDoubleField("MagnetInset")
  options.magnet_base_mm = dialog:GetDoubleField("MagnetBase")
  return options, rough_tool, finish_tool, vbit_tool
end

function main(script_path)
  local job = VectricJob()
  if not job.Exists then
    DisplayMessageBox("Open or create a job before running " .. TITLE .. ".")
    return false
  end
  local material = MaterialBlock()
  if material.JobType ~= MaterialBlock.SINGLE_SIDED then
    DisplayMessageBox(TITLE .. " currently supports single-sided, flat jobs only.")
    return false
  end

  local options = load_options(material)
  local rough_tool, finish_tool, vbit_tool
  options, rough_tool, finish_tool, vbit_tool = show_dialog(script_path, material, options)
  if options == nil then
    return false
  end

  if options.output_type == "Filler Plate" then
    DisplayMessageBox("Filler Plate geometry will be added in the next implementation stage.")
    return false
  end

  local unit = options.unit
  local design_origin = material.ActualXYOrigin
  local anchor_x_mm = design_origin.x / unit + options.offset_x_mm
  local anchor_y_mm = design_origin.y / unit + options.offset_y_mm
  local layout, layout_error = Core.create_layout(options, anchor_x_mm, anchor_y_mm)
  if layout == nil then
    DisplayMessageBox(layout_error)
    return false
  end
  options.layout = layout
  options.columns = layout.columns
  options.rows = layout.rows
  options.overall_x_mm = layout.overall_x_mm
  options.overall_y_mm = layout.overall_y_mm
  local grid_ok, grid_error = Core.validate_layout(
    layout, material.MaterialBox.BLC.x / unit, material.MaterialBox.BLC.y / unit,
    material.Width / unit, material.Height / unit)
  if not grid_ok then
    DisplayMessageBox(grid_error)
    return false
  end

  local rough_dia_mm = Core.tool_value_in_job_units(rough_tool.ToolDia, rough_tool.InMM, true)
  local finish_dia_mm = Core.tool_value_in_job_units(finish_tool.ToolDia, finish_tool.InMM, true)
  local vbit_dia_mm = Core.tool_value_in_job_units(vbit_tool.ToolDia, vbit_tool.InMM, true)
  local thickness_mm = material.InMM and material.Thickness or material.Thickness * 25.4
  local bottom_w_mm, bottom_h_mm = Core.machining_profile_dimensions_at_depth_mm(
    Core.TOTAL_DEPTH_MM, options.cell_width_mm, options.cell_height_mm)
  local tools_ok, tools_error = Core.validate_tool_geometry(
    rough_dia_mm, finish_dia_mm, vbit_dia_mm, vbit_tool.VBit_Angle,
    options.allowance_mm, Core.TOTAL_DEPTH_MM, thickness_mm,
    math.min(bottom_w_mm, bottom_h_mm))
  if not tools_ok then
    DisplayMessageBox("Tool selection must change before toolpaths can be created:\n\n" .. tools_error)
    return false
  end
  local magnets_ok, magnets_error = Core.validate_magnets(
    options.include_magnets, options.magnet_diameter_mm, options.magnet_depth_mm,
    options.magnet_chamfer_mm, options.magnet_inset_mm, options.magnet_base_mm,
    options.cell_width_mm, options.cell_height_mm, finish_dia_mm,
    Core.TOTAL_DEPTH_MM, thickness_mm)
  if not magnets_ok then
    DisplayMessageBox(magnets_error)
    return false
  end
  if rough_tool.Stepdown <= 0.0 or rough_tool.Stepover <= 0.0 or
     finish_tool.Stepdown <= 0.0 or finish_tool.Stepover <= 0.0 then
    DisplayMessageBox("The selected end mills must have positive stepdown and stepover values.")
    return false
  end

  save_options(options, rough_tool, finish_tool, vbit_tool)
  add_geometry(job, options, unit)

  if not create_pocket_toolpath(
      "Gridfinity 1 - Rough", rough_tool, material, unit,
      LAYER_SOCKET_INNER, 0.0, Core.TOTAL_DEPTH_MM - options.allowance_mm,
      options.allowance_mm) then
    DisplayMessageBox("Could not create the Gridfinity roughing toolpath.")
    return false
  end

  local finish_ok
  if Core.finish_uses_pocket(options.allowance_mm) then
    finish_ok = create_pocket_toolpath(
      "Gridfinity 2 - Finish", finish_tool, material, unit,
      LAYER_SOCKET_INNER, 0.0, Core.TOTAL_DEPTH_MM, 0.0)
  else
    finish_ok = create_profile_toolpath(
      "Gridfinity 2 - Finish", finish_tool, material, unit,
      LAYER_SOCKET_INNER, Core.MID_DEPTH_MM,
      Core.TOTAL_DEPTH_MM - Core.MID_DEPTH_MM,
      ProfileParameterData.PROFILE_INSIDE)
  end
  if not finish_ok then
    DisplayMessageBox("The roughing path was created, but the finishing path failed.")
    return false
  end

  if options.include_magnets and not create_pocket_toolpath(
      "Gridfinity 3 - Magnet Pockets", finish_tool, material, unit,
      LAYER_MAGNET_INNER, Core.TOTAL_DEPTH_MM, options.magnet_depth_mm, 0.0) then
    DisplayMessageBox("The socket paths were created, but the magnet-pocket path failed.")
    return false
  end

  local chamfer_number = options.include_magnets and 4 or 3
  if not create_profile_toolpath(
      "Gridfinity " .. chamfer_number .. " - 45deg Socket Chamfers",
      vbit_tool, material, unit, LAYER_SOCKET_INNER, 0.0,
      Core.UPPER_CHAMFER_MM, ProfileParameterData.PROFILE_ON) then
    DisplayMessageBox("The end-mill paths were created, but the V-bit path failed.")
    return false
  end

  if options.include_magnets and options.magnet_chamfer_mm > 0.000001 and
     not create_profile_toolpath(
       "Gridfinity 5 - 45deg Magnet Chamfers", vbit_tool, material, unit,
       LAYER_MAGNET_INNER, Core.TOTAL_DEPTH_MM, options.magnet_chamfer_mm,
       ProfileParameterData.PROFILE_ON) then
    DisplayMessageBox("The socket chamfer was created, but the magnet-chamfer path failed.")
    return false
  end

  job:Refresh2DView()
  DisplayMessageBox(
    "Created a " .. options.columns .. " x " .. options.rows .. " Gridfinity baseplate " ..
    "with editable native toolpaths.\n\n" ..
    "Preview every toolpath and verify tool numbers, feeds, safe Z, and cut depths before machining.")
  return true
end

if GRIDFINITY_TEST_MODE then
  return Core
end
