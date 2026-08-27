# Gridfinity Baseplate Gadget for VCarve

Creates a configurable negative Gridfinity baseplate pocket in VCarve Pro or
Aspire. The gadget draws the socket boundaries and creates exactly three
toolpaths: roughing, finishing, and 45-degree upper chamfers. Optional magnet
sub-pockets are machined below the standard 4.65 mm socket floor.

The gadget creates these toolpaths:

1. `Gridfinity 1 - Rough` — stepped raster clearing with the selected roughing end mill.
2. `Gridfinity 2 - Finish` — profiles the vertical wall; with positive roughing allowance it also finishes the socket floor.
3. `Gridfinity 3 - 45deg Chamfers` — cuts the 2.15 mm upper seating face with a V-bit.

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
- A 90° included-angle V-bit (its cutting edges are 45° to the material surface)

The Vectric tool database supplies each tool's diameter, stepdown, stepover,
feeds, speeds, and tool number. The gadget supports both metric and inch jobs.
Tool units do not need to match the job units.

For the simplified profile, a 1/4-inch roughing end mill, 1/8-inch finishing
end mill, and 1/2-inch 90° V-bit are suitable. The 1/8-inch cutter radius is
just under the 1.6 mm floor-plan corner radius. Roughing paths use a conservative
inner region whenever the roughing cutter is larger than a profile corner,
leaving that material for the finishing cutter rather than gouging the socket.
The V-bit cuts only the upper chamfer and never enters the lower corner.
When roughing allowance is zero, roughing clears to the terminal depth and the
finishing toolpath contains only wall profiles down to 4.65 mm. A positive
allowance retains the finishing raster across the socket floor.

## Install

Download `Gridfinity_Baseplate_<version>.vgadget` from a release, then choose **Gadgets →
Install New Gadget…** in VCarve Pro or Aspire. To build the installer locally:

```sh
./scripts/build-vgadget.sh
```

This writes `dist/Gridfinity_Baseplate.vgadget`. The archive contains the
required top-level `Gridfinity_Baseplate` directory and is checked with
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
2. Run **Gadgets → Gridfinity Baseplate**.
3. Enter rows and columns, choose centered or lower-left placement, and select
   all three tools.
4. Choose **Positive from Origin** (lower-left at the offset) or **Centered on
   Origin** (center at the offset). All definition inputs remain in millimeters,
   including in an inch job.
5. Optionally enable four round magnet sub-pockets per cell and set their
   diameter, depth, top chamfer, edge inset, and minimum retained base.
6. Create the baseplate, preview all three toolpaths, and inspect tool numbers,
   feeds, safe Z, and depths before posting code.

Cell width and height are independently adjustable and default to 42 mm. The
green, blue, orange, and purple preview-vector layers represent the top opening,
vertical wall, bottom opening, and magnet pockets. Re-running the gadget replaces those preview
vectors but adds a new set of toolpaths; delete obsolete toolpaths manually.

## Development

Run the pure geometry tests and Lua syntax check:

```sh
lua tests/test_core.lua
luac -p Gridfinity_Baseplate.lua tests/test_core.lua
```

External toolpaths are intentionally used because one toolpath must machine a
depth-varying socket profile. Vectric cannot recalculate external toolpaths after
creation; change inputs by deleting the old paths and running the gadget again.

Only properties that define removed material are carried into the CNC gadget.
FreeCAD's magnet edge thickness and center-cut fillets define the surrounding
positive skeleton solid, so they are not negative-pocket inputs here.
