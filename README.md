# Gridfinity Toolpath Gadget for VCarve

Creates a configurable negative Gridfinity baseplate pocket in VCarve Pro or
Aspire. The gadget draws the machining boundaries on dedicated layers and
creates editable native Vectric pocket and profile toolpaths. Optional magnet
sub-pockets are machined below the standard 4.65 mm socket floor.

The gadget creates these toolpaths:

1. `Gridfinity 1 - Rough` — pockets the socket with the selected roughing end mill, leaving the specified radial and axial allowance.
2. `Gridfinity 2 - Finish` — profiles the wall when allowance is zero, or pockets the complete socket when allowance is positive.
3. `Gridfinity 3 - 45deg Socket Chamfers` — cuts the 2.15 mm upper seating face with a V-bit when magnets are disabled.

When magnets are enabled, their different cutting depths require separate
native operations: `Gridfinity 3 - Magnet Pockets`, `Gridfinity 4 - 45deg
Socket Chamfers`, and, when the magnet chamfer is positive, `Gridfinity 5 -
45deg Magnet Chamfers`.

## Gridfinity specification

The referenced negative-pocket geometry uses a 42 mm pitch, 2.15 mm upper
chamfer, 1.8 mm vertical wall, 0.7 mm lower chamfer, and 4.65 mm terminal depth.
For now, the gadget intentionally omits the 0.7 mm lower chamfer: the end mills
continue the 37.2 mm vertical pocket directly to the 4.65 mm terminal depth.

The pocket profile follows the
[Gridfinity Design Reference](https://gridfinity.xyz/assets/img/spec_draft_willtree8.jpg).
The [FreeCAD Gridfinity Workbench](https://github.com/Stu142/FreeCAD-Gridfinity-Workbench)
is used as a parameter reference for configurable baseplates and optional
magnet pockets. It produces positive solids, while this gadget generates the
negative volume removed by CNC tooling.

## Requirements

- VCarve Pro or Aspire with Gadget support (V12 SDK API)
- A single-sided flat job with material at least 4.65 mm thick
- Roughing and finishing flat end mills
- A 90° V-bit

The Vectric tool database supplies each tool's diameter, stepdown, stepover,
feeds, speeds, and tool number. The gadget supports both metric and inch jobs.
Tool units do not need to match the job units.

For the simplified profile, a 1/4-inch roughing end mill, 1/8-inch finishing
end mill, and 1/2-inch 90° V-bit are suitable. The 1/8-inch cutter radius is
just under the 1.6 mm floor-plan corner radius. Vectric's native pocket
calculation leaves material which the roughing cutter cannot reach in the
rounded corners rather than gouging the socket. The V-bit cuts only the upper
chamfer and never enters the lower corner. When roughing allowance is zero,
roughing clears to the terminal depth and finishing profiles the straight wall
from 2.15 mm to 4.65 mm. A positive allowance causes the finishing tool to
pocket the complete socket to its terminal depth.

The generated vectors are organized on four layers:

- `Gridfinity - Socket Outer Edge` — the visible top edge of the main chamfer.
- `Gridfinity - Socket Inner Edge` — the socket wall and driving vector for socket toolpaths.
- `Gridfinity - Magnet Outer Edge` — the visible top edge of each optional magnet chamfer.
- `Gridfinity - Magnet Inner Edge` — the finished magnet-hole wall and driving vector for magnet toolpaths.

Every native toolpath uses a layer-based vector selector. Recalculate the
toolpaths after changing a selected tool, its cutting parameters, material
settings, or geometry on one of these layers.

## Install

Download `Gridfinity_Toolpath_<version>.vgadget` from a release, then choose **Gadgets →
Install New Gadget…** in VCarve Pro or Aspire. To build the installer locally:

```sh
./scripts/build-vgadget.sh
```

This writes `dist/Gridfinity_Toolpath.vgadget`. The archive contains the
required top-level `Gridfinity_Toolpath` directory and is checked with
`unzip -t` before the build succeeds.

To rebuild automatically whenever a gadget source file changes:

```sh
make watch-start
```

Use `make watch-status` to inspect the watcher and `make watch-stop` to stop it.
Build output is written to `dist/build-watch.log`.

GitHub Actions also tests and packages the gadget on every push and pull
request. Workflow builds are downloadable artifacts. Tags matching `v*` create
a GitHub Release and attach a versioned `.vgadget` installer.

## Use

1. Create a job large enough for `columns × 42 mm` by `rows × 42 mm` and set
   the actual material thickness.
2. Run **Gadgets → Gridfinity Toolpath**.
3. Enter rows and columns, choose centered or lower-left placement, and select
   all three tools.
4. Choose **Positive from Origin** (lower-left at the offset) or **Centered on
   Origin** (center at the offset). All definition inputs remain in millimeters,
   including in an inch job.
5. Optionally enable four round magnet sub-pockets per cell and set their
   diameter, depth, top chamfer, edge inset, and minimum retained base.
6. Create the baseplate, preview all generated toolpaths, and inspect tool numbers,
   feeds, safe Z, and depths before posting code.

Cell width and height are independently adjustable and default to 42 mm. The
Overall Dimensions mode generates only complete cells: for example, a 100 mm ×
85 mm area at the default pitch produces a 2 × 2 pattern. Any unused space is
placed outside the pattern according to the selected origin. The
green and blue socket layers represent the outer and inner socket edges; the
orange and purple magnet layers represent the outer and inner magnet edges.
Re-running the gadget replaces the vectors on these named layers but adds a new
set of toolpaths; delete obsolete toolpaths manually.

## Filler Plate vector checkpoint

Selecting `Filler Plate` currently creates vector geometry for inspection only;
it does not create Filler Plate toolpaths or magnet geometry. The flat plate
boundary and positive mating-foot contours are placed on four dedicated layers:

- `Gridfinity - Filler Plate Boundary`
- `Gridfinity - Filler Foot Top Edge`
- `Gridfinity - Filler Foot Wall Edge`
- `Gridfinity - Filler Foot Bottom Edge`

The nominal foot follows the willtree8 design reference: 41.5 mm at the plate
interface, 37.2 mm at the vertical wall, and 35.6 mm at the bottom, with a total
height of 4.75 mm. Inspect these vectors in VCarve before Filler Plate machining
operations are implemented.

## Development

Run the pure geometry tests and Lua syntax check:

```sh
lua tests/test_core.lua
luac -p Gridfinity_Toolpath.lua tests/test_core.lua
```

Version 1.1 and later use standard Vectric pocket and profile toolpaths instead
of external toolpaths. They can be edited and recalculated in VCarve or Aspire,
and their layer selectors continue to find regenerated vectors by layer name.

Only properties that define removed material are carried into the CNC gadget.
FreeCAD's magnet edge thickness and center-cut fillets define the surrounding
positive skeleton solid, so they are not negative-pocket inputs here.
