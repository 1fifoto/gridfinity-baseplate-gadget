#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dist_dir="$project_dir/dist"
stage_dir=$(mktemp -d)
trap 'rm -rf "$stage_dir"' EXIT INT TERM
gadget_name="Gridfinity_Toolpath"
version=${VERSION:-}

if [ -n "$version" ]; then
  artifact_name="${gadget_name}_${version}.vgadget"
else
  artifact_name="${gadget_name}.vgadget"
fi

test -f "$project_dir/Gridfinity_Toolpath.lua"
test -f "$project_dir/Gridfinity_Toolpath.htm"
test -f "$project_dir/README.md"

mkdir -p "$dist_dir" "$stage_dir/$gadget_name"
cp "$project_dir/Gridfinity_Toolpath.lua" "$stage_dir/$gadget_name/"
cp "$project_dir/Gridfinity_Toolpath.htm" "$stage_dir/$gadget_name/"
cp "$project_dir/README.md" "$stage_dir/$gadget_name/"
cp "$project_dir/LICENSE" "$stage_dir/$gadget_name/LICENSE.txt"

cd "$stage_dir"
rm -f "$dist_dir/$artifact_name"
zip -qr "$dist_dir/$artifact_name" "$gadget_name"

unzip -t "$dist_dir/$artifact_name" >/dev/null
echo "Built $dist_dir/$artifact_name"
