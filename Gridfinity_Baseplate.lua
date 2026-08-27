-- VECTRIC LUA SCRIPT
-- Gridfinity Baseplate Gadget
-- Generates three external toolpaths: rough, finish, and 45 degree chamfers.

require "strict"

local TITLE = "Gridfinity Baseplate"
local VERSION = "1.0.0"
local REGISTRY_SECTION = "GridfinityBaseplateGadget"
local LAYER_TOP = "Gridfinity - Top Opening"
local LAYER_MID = "Gridfinity - Vertical Wall"
local LAYER_BOTTOM = "Gridfinity - Bottom Opening"
local LAYER_MAGNETS = "Gridfinity - Magnet Pockets"
local BULGE_90 = 0.4142135623730951

local Core = nil

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

local function add_preview_geometry(job, options, unit)
  local manager = job.LayerManager
  local top_layer = manager:GetLayerWithName(LAYER_TOP)
  local mid_layer = manager:GetLayerWithName(LAYER_MID)
  local bottom_layer = manager:GetLayerWithName(LAYER_BOTTOM)
  local magnet_layer = manager:GetLayerWithName(LAYER_MAGNETS)
  clear_layer(top_layer)
  clear_layer(mid_layer)
  clear_layer(bottom_layer)
  clear_layer(magnet_layer)
  top_layer:SetColour(0.10, 0.55, 0.30)
  mid_layer:SetColour(0.15, 0.35, 0.80)
  bottom_layer:SetColour(0.80, 0.30, 0.15)
  magnet_layer:SetColour(0.55, 0.15, 0.65)

  for row = 0, options.rows - 1 do
    for col = 0, options.columns - 1 do
      local cx = options.origin_x + (col + 0.5) * options.cell_width_mm * unit
      local cy = options.origin_y + (row + 0.5) * options.cell_height_mm * unit
      local top_w, top_h, top_r = Core.profile_dimensions_at_depth_mm(0.0, options.cell_width_mm, options.cell_height_mm)
      local mid_w, mid_h, mid_r = Core.profile_dimensions_at_depth_mm(Core.MID_DEPTH_MM, options.cell_width_mm, options.cell_height_mm)
      local bottom_w, bottom_h, bottom_r = Core.profile_dimensions_at_depth_mm(Core.TOTAL_DEPTH_MM, options.cell_width_mm, options.cell_height_mm)
      top_layer:AddObject(CreateCadContour(rounded_rect(
        cx, cy, top_w * unit, top_h * unit, top_r * unit, 0.0)), true)
      mid_layer:AddObject(CreateCadContour(rounded_rect(
        cx, cy, mid_w * unit, mid_h * unit, mid_r * unit, 0.0)), true)
      bottom_layer:AddObject(CreateCadContour(rounded_rect(
        cx, cy, bottom_w * unit, bottom_h * unit, bottom_r * unit, 0.0)), true)
      if options.include_magnets then
        local points = {
          {cx - options.cell_width_mm * unit * 0.5 + options.magnet_inset_mm * unit,
           cy - options.cell_height_mm * unit * 0.5 + options.magnet_inset_mm * unit},
          {cx + options.cell_width_mm * unit * 0.5 - options.magnet_inset_mm * unit,
           cy - options.cell_height_mm * unit * 0.5 + options.magnet_inset_mm * unit},
          {cx + options.cell_width_mm * unit * 0.5 - options.magnet_inset_mm * unit,
           cy + options.cell_height_mm * unit * 0.5 - options.magnet_inset_mm * unit},
          {cx - options.cell_width_mm * unit * 0.5 + options.magnet_inset_mm * unit,
           cy + options.cell_height_mm * unit * 0.5 - options.magnet_inset_mm * unit}
        }
        for _, point in ipairs(points) do
          local diameter = options.magnet_diameter_mm * unit
          magnet_layer:AddObject(CreateCadContour(rounded_rect(
            point[1], point[2], diameter, diameter, diameter * 0.5, 0.0)), true)
        end
      end
    end
  end
end

local function x_extent_at_y(half_w, half_h, radius, y)
  if radius <= 0.000001 then
    return half_w
  end
  local straight_half_h = half_h - radius
  local ay = math.abs(y)
  if ay <= straight_half_h then
    return half_w
  end
  local dy = ay - straight_half_h
  local inside = math.max(0.0, radius * radius - dy * dy)
  return half_w - radius + math.sqrt(inside)
end

local function add_raster(group, cx, cy, width, height, radius, z, stepover)
  if width <= 0.0 or height <= 0.0 then
    return
  end
  local half_w = width * 0.5
  local half_h = height * 0.5
  local rows = math.max(1, math.ceil(height / math.max(stepover, height / 10000.0)))
  local spacing = height / rows
  local contour = Contour(0.0)
  for i = 0, rows do
    local y = -half_h + i * spacing
    local extent = x_extent_at_y(half_w, half_h, radius, y)
    local x1 = cx - extent
    local x2 = cx + extent
    if i % 2 == 1 then
      x1, x2 = x2, x1
    end
    if i == 0 then
      contour:AppendPoint(x1, cy + y, z)
    else
      contour:LineTo(x1, cy + y, z)
    end
    contour:LineTo(x2, cy + y, z)
  end
  group:AddTail(contour)
  group:AddTail(rounded_rect(cx, cy, width, height, radius, z))
end

local function cell_center(options, row, col, unit)
  return options.origin_x + (col + 0.5) * options.cell_width_mm * unit,
         options.origin_y + (row + 0.5) * options.cell_height_mm * unit
end

local function magnet_centers(options, cx, cy, unit)
  local dx = options.cell_width_mm * unit * 0.5 - options.magnet_inset_mm * unit
  local dy = options.cell_height_mm * unit * 0.5 - options.magnet_inset_mm * unit
  return {
    {cx - dx, cy - dy}, {cx + dx, cy - dy},
    {cx + dx, cy + dy}, {cx - dx, cy + dy}
  }
end

local function build_rough_paths(material, options, tool, unit)
  local group = ContourGroup(true)
  local radius = Core.tool_value_in_job_units(tool.ToolDia * 0.5, tool.InMM, material.InMM)
  local stepdown = Core.tool_value_in_job_units(tool.Stepdown, tool.InMM, material.InMM)
  local stepover = Core.tool_value_in_job_units(tool.Stepover, tool.InMM, material.InMM)
  local allowance = options.allowance_mm * unit
  stepdown = math.max(stepdown, 0.05 * unit)
  stepover = math.max(math.min(stepover, 2.0 * radius), 0.05 * unit)
  local target = (Core.TOTAL_DEPTH_MM - options.allowance_mm) * unit
  local depth = math.min(stepdown, target)

  while depth <= target + 0.0000001 do
    local width_mm, height_mm, profile_radius_mm = Core.profile_dimensions_at_depth_mm(
      depth / unit, options.cell_width_mm, options.cell_height_mm)
    local offset = radius + allowance
    local width, height, rr = Core.inset_profile(
      width_mm * unit, height_mm * unit, profile_radius_mm * unit, offset)
    rr = math.max(0.000001 * unit, rr)
    local z = material:CalcAbsoluteZ(-depth)
    for row = 0, options.rows - 1 do
      for col = 0, options.columns - 1 do
        local cx, cy = cell_center(options, row, col, unit)
        add_raster(group, cx, cy, width, height, rr, z, stepover)
      end
    end
    if depth >= target then
      break
    end
    depth = math.min(depth + stepdown, target)
  end
  return group
end

local function build_finish_paths(material, options, tool, unit)
  local group = ContourGroup(true)
  local tool_radius = Core.tool_value_in_job_units(tool.ToolDia * 0.5, tool.InMM, material.InMM)
  local stepdown = math.max(Core.tool_value_in_job_units(tool.Stepdown, tool.InMM, material.InMM), 0.05 * unit)
  local stepover = math.max(math.min(
    Core.tool_value_in_job_units(tool.Stepover, tool.InMM, material.InMM),
    2.0 * tool_radius), 0.05 * unit)
  local mid_depth = Core.MID_DEPTH_MM * unit
  local wall_bottom = Core.LOWER_START_DEPTH_MM * unit
  local depth = math.min(mid_depth + stepdown, wall_bottom)

  while depth <= wall_bottom + 0.0000001 do
    local mid_w, mid_h, mid_r = Core.profile_dimensions_at_depth_mm(
      Core.MID_DEPTH_MM, options.cell_width_mm, options.cell_height_mm)
    local width, height, rr = Core.inset_profile(
      mid_w * unit, mid_h * unit, mid_r * unit, tool_radius)
    rr = math.max(0.000001 * unit, rr)
    local z = material:CalcAbsoluteZ(-depth)
    for row = 0, options.rows - 1 do
      for col = 0, options.columns - 1 do
        local cx, cy = cell_center(options, row, col, unit)
        group:AddTail(rounded_rect(cx, cy, width, height, rr, z))
      end
    end
    if depth >= wall_bottom then
      break
    end
    depth = math.min(depth + stepdown, wall_bottom)
  end

  local bottom_w, bottom_h, bottom_r = Core.profile_dimensions_at_depth_mm(
    Core.TOTAL_DEPTH_MM, options.cell_width_mm, options.cell_height_mm)
  local floor_width, floor_height, floor_radius = Core.inset_profile(
    bottom_w * unit, bottom_h * unit, bottom_r * unit, tool_radius)
  floor_radius = math.max(0.000001 * unit, floor_radius)
  local floor_z = material:CalcAbsoluteZ(-Core.TOTAL_DEPTH_MM * unit)
  for row = 0, options.rows - 1 do
    for col = 0, options.columns - 1 do
      local cx, cy = cell_center(options, row, col, unit)
      add_raster(group, cx, cy, floor_width, floor_height, floor_radius, floor_z, stepover)
    end
  end

  if options.include_magnets then
    local hole_center_diameter = options.magnet_diameter_mm * unit - 2.0 * tool_radius
    local hole_center_radius = hole_center_diameter * 0.5
    local magnet_target = (Core.TOTAL_DEPTH_MM + options.magnet_depth_mm) * unit
    local magnet_depth = math.min(Core.TOTAL_DEPTH_MM * unit + stepdown, magnet_target)
    while magnet_depth <= magnet_target + 0.0000001 do
      local z = material:CalcAbsoluteZ(-magnet_depth)
      for row = 0, options.rows - 1 do
        for col = 0, options.columns - 1 do
          local cx, cy = cell_center(options, row, col, unit)
          for _, point in ipairs(magnet_centers(options, cx, cy, unit)) do
            add_raster(group, point[1], point[2], hole_center_diameter,
              hole_center_diameter, hole_center_radius, z, stepover)
          end
        end
      end
      if magnet_depth >= magnet_target then
        break
      end
      magnet_depth = math.min(magnet_depth + stepdown, magnet_target)
    end
  end
  return group
end

local function build_vbit_paths(material, options, unit)
  local group = ContourGroup(true)
  local mid_z = material:CalcAbsoluteZ(-Core.MID_DEPTH_MM * unit)
  local bottom_z = material:CalcAbsoluteZ(-Core.TOTAL_DEPTH_MM * unit)
  for row = 0, options.rows - 1 do
    for col = 0, options.columns - 1 do
      local cx, cy = cell_center(options, row, col, unit)
      local mid_w, mid_h, mid_r = Core.profile_dimensions_at_depth_mm(
        Core.MID_DEPTH_MM, options.cell_width_mm, options.cell_height_mm)
      local bottom_w, bottom_h, bottom_r = Core.profile_dimensions_at_depth_mm(
        Core.TOTAL_DEPTH_MM, options.cell_width_mm, options.cell_height_mm)
      group:AddTail(rounded_rect(cx, cy, mid_w * unit, mid_h * unit, mid_r * unit, mid_z))
      group:AddTail(rounded_rect(cx, cy, bottom_w * unit, bottom_h * unit, bottom_r * unit, bottom_z))
      if options.include_magnets and options.magnet_chamfer_mm > 0.0 then
        local magnet_z = material:CalcAbsoluteZ(
          -(Core.TOTAL_DEPTH_MM + options.magnet_chamfer_mm) * unit)
        local diameter = options.magnet_diameter_mm * unit
        for _, point in ipairs(magnet_centers(options, cx, cy, unit)) do
          group:AddTail(rounded_rect(point[1], point[2], diameter, diameter,
            diameter * 0.5, magnet_z))
        end
      end
    end
  end
  return group
end

local function create_external_toolpath(name, tool, paths, material)
  local box = material.MaterialBox
  local gap = math.max(Core.to_job_units(2.0, material.InMM), material.Thickness * 0.1)
  local pos_data = ToolpathPosData()
  pos_data:SetHomePosition(box.BLC.x, box.BLC.y, box.TRC.z + gap)
  pos_data.SafeZGap = gap
  pos_data.StartZGap = math.min(gap, Core.to_job_units(1.0, material.InMM))

  local external_options = ExternalToolpathOptions()
  external_options.StartDepth = 0.0
  external_options.CreatePreview = true
  local toolpath = ExternalToolpath(name, tool, pos_data, external_options, paths)
  if toolpath:Error() then
    return false
  end
  return ToolpathManager():AddExternalToolpath(toolpath)
end

local function load_options(material)
  local registry = Registry(REGISTRY_SECTION)
  local unit = Core.to_job_units(1.0, material.InMM)
  return {
    columns = registry:GetInt("Columns", 2),
    rows = registry:GetInt("Rows", 2),
    cell_width_mm = registry:GetDouble("CellWidthMM", 42.0),
    cell_height_mm = registry:GetDouble("CellHeightMM", 42.0),
    generation_location = registry:GetString("GenerationLocation", "Positive from Origin"),
    offset_x_mm = registry:GetDouble("OffsetXMM", 0.0),
    offset_y_mm = registry:GetDouble("OffsetYMM", 0.0),
    allowance_mm = registry:GetDouble("AllowanceMM", 0.2),
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
  registry:SetInt("Columns", options.columns)
  registry:SetInt("Rows", options.rows)
  registry:SetDouble("CellWidthMM", options.cell_width_mm)
  registry:SetDouble("CellHeightMM", options.cell_height_mm)
  registry:SetString("GenerationLocation", options.generation_location)
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
  dialog:AddIntegerField("Columns", options.columns)
  dialog:AddIntegerField("Rows", options.rows)
  dialog:AddDoubleField("CellWidth", options.cell_width_mm)
  dialog:AddDoubleField("CellHeight", options.cell_height_mm)
  dialog:AddDropDownList("GenerationLocation", options.generation_location)
  dialog:AddDropDownListValue("GenerationLocation", "Positive from Origin")
  dialog:AddDropDownListValue("GenerationLocation", "Centered on Origin")
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
    DisplayMessageBox("Select all three tools before creating the baseplate.")
    return nil
  end
  options.columns = dialog:GetIntegerField("Columns")
  options.rows = dialog:GetIntegerField("Rows")
  options.cell_width_mm = dialog:GetDoubleField("CellWidth")
  options.cell_height_mm = dialog:GetDoubleField("CellHeight")
  options.generation_location = dialog:GetDropDownListValue("GenerationLocation")
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

  Core = dofile(path_join(script_path, "gridfinity_core.lua"))
  local options = load_options(material)
  local rough_tool, finish_tool, vbit_tool
  options, rough_tool, finish_tool, vbit_tool = show_dialog(script_path, material, options)
  if options == nil then
    return false
  end

  local unit = options.unit
  local design_origin = material.ActualXYOrigin
  options.origin_x = design_origin.x + options.offset_x_mm * unit
  options.origin_y = design_origin.y + options.offset_y_mm * unit
  if options.generation_location == "Centered on Origin" then
    options.origin_x = options.origin_x - options.columns * options.cell_width_mm * unit * 0.5
    options.origin_y = options.origin_y - options.rows * options.cell_height_mm * unit * 0.5
  end
  local grid_ok, grid_error = Core.validate_grid(
    options.columns, options.rows, options.origin_x, options.origin_y,
    material.MaterialBox.BLC.x, material.MaterialBox.BLC.y,
    material.Width, material.Height, options.cell_width_mm * unit,
    options.cell_height_mm * unit)
  if not grid_ok then
    DisplayMessageBox(grid_error)
    return false
  end

  local rough_dia_mm = Core.tool_value_in_job_units(rough_tool.ToolDia, rough_tool.InMM, true)
  local finish_dia_mm = Core.tool_value_in_job_units(finish_tool.ToolDia, finish_tool.InMM, true)
  local vbit_dia_mm = Core.tool_value_in_job_units(vbit_tool.ToolDia, vbit_tool.InMM, true)
  local thickness_mm = material.InMM and material.Thickness or material.Thickness * 25.4
  local bottom_w_mm, bottom_h_mm = Core.profile_dimensions_at_depth_mm(
    Core.TOTAL_DEPTH_MM, options.cell_width_mm, options.cell_height_mm)
  local tools_ok, tools_error = Core.validate_tool_geometry(
    rough_dia_mm, finish_dia_mm, vbit_dia_mm, vbit_tool.VBitAngle,
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
  add_preview_geometry(job, options, unit)
  local rough_paths = build_rough_paths(material, options, rough_tool, unit)
  local finish_paths = build_finish_paths(material, options, finish_tool, unit)
  local vbit_paths = build_vbit_paths(material, options, unit)

  if not create_external_toolpath("Gridfinity 1 - Rough", rough_tool, rough_paths, material) then
    DisplayMessageBox("Could not create the Gridfinity roughing toolpath.")
    return false
  end
  if not create_external_toolpath("Gridfinity 2 - Finish", finish_tool, finish_paths, material) then
    DisplayMessageBox("The roughing path was created, but the finishing path failed.")
    return false
  end
  if not create_external_toolpath("Gridfinity 3 - 45deg Chamfers", vbit_tool, vbit_paths, material) then
    DisplayMessageBox("The end-mill paths were created, but the V-bit path failed.")
    return false
  end

  job:Refresh2DView()
  DisplayMessageBox(
    "Created a " .. options.columns .. " x " .. options.rows .. " Gridfinity baseplate.\n\n" ..
    "Preview every toolpath and verify tool numbers, feeds, safe Z, and cut depths before machining.")
  return true
end
