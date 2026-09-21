"""Build nine matte brush variants. Run with Blender 4.3 in background mode."""
import bpy
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "CarpetToy/assets/tools/progression"
OUT.mkdir(parents=True, exist_ok=True)

PALETTE = {
    "mint": (0.28, 0.67, 0.57, 1), "deep_mint": (0.08, 0.34, 0.29, 1),
    "cream": (0.91, 0.84, 0.66, 1), "coral": (0.87, 0.34, 0.27, 1),
    "bristle": (0.54, 0.34, 0.17, 1), "wood": (0.42, 0.21, 0.09, 1),
    "light_wood": (0.68, 0.43, 0.20, 1), "dark_wood": (0.20, 0.09, 0.04, 1),
    "jade": (0.22, 0.57, 0.49, 1), "gold": (0.83, 0.57, 0.20, 1),
    "red": (0.60, 0.13, 0.10, 1), "ink": (0.10, 0.12, 0.13, 1),
}

MATERIALS = {}
for name, color in PALETTE.items():
    material = bpy.data.materials.new("Matte " + name.replace("_", " ").title())
    material.diffuse_color = color
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.84
    bsdf.inputs["Specular IOR Level"].default_value = 0.18
    MATERIALS[name] = material

def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

def finish(obj, name, material):
    obj.name = name
    obj.data.materials.append(MATERIALS[material])
    return obj

def box(parts, name, location, size, material, bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = obj.modifiers.new("Rounded edges", "BEVEL")
    modifier.width = bevel
    modifier.segments = 2
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for face in obj.data.polygons:
        face.use_smooth = True
    parts.append(finish(obj, name, material))
    return obj

def rod(parts, name, start, end, radius, material, vertices=12):
    a, b = Vector(start), Vector(end)
    direction = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=direction.length, location=(a + b) / 2)
    obj = bpy.context.object
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    parts.append(finish(obj, name, material))
    return obj

def ellipsoid(parts, name, location, scale, material, segments=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=8, location=location)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for face in obj.data.polygons:
        face.use_smooth = True
    parts.append(finish(obj, name, material))
    return obj

def add_cloud(parts, x, y, z, scale, material):
    # Three shallow top-facing lobes and a curling tail read from the game's
    # near-overhead camera. Blender Z becomes Godot Y during export.
    ellipsoid(parts, "Cloud lobe", (x - 0.050 * scale, y, z), (0.050 * scale, 0.026 * scale, 0.010), material, 12)
    ellipsoid(parts, "Cloud lobe", (x, y + 0.014 * scale, z), (0.066 * scale, 0.035 * scale, 0.010), material, 12)
    ellipsoid(parts, "Cloud lobe", (x + 0.060 * scale, y, z), (0.045 * scale, 0.024 * scale, 0.010), material, 12)
    rod(parts, "Cloud curl", (x + 0.055 * scale, y - 0.010, z), (x + 0.105 * scale, y - 0.030 * scale, z), 0.011, material, 10)

def add_lattice(parts, width, y, z, material, rows=3):
    span = width * 0.72
    for row in range(rows):
        offset = (row - (rows - 1) / 2) * 0.055
        rod(parts, "Lattice inlay", (-span / 2, y + offset - 0.07, z), (span / 2, y + offset + 0.07, z), 0.008, material, 8)
        rod(parts, "Lattice inlay", (-span / 2, y + offset + 0.07, z), (span / 2, y + offset - 0.07, z), 0.008, material, 8)

def build_tier(index, filename, style, dense, detail):
    clear_scene()
    parts = []
    head_width = 0.78
    plastic = index <= 2
    head_material = "mint" if plastic else ("light_wood" if index <= 4 else "wood")
    accent = "cream" if plastic else ("dark_wood" if index <= 4 else ("jade" if index <= 7 else "gold"))
    bristle_material = "cream" if index == 0 else ("bristle" if index <= 4 else "ink")
    box(parts, "Rounded brush head", (0, 0, 0.17), (head_width, 0.27, 0.16), head_material, 0.055)
    box(parts, "Soft bumper", (0, -0.007, 0.105), (0.79, 0.28, 0.035), accent, 0.014)
    columns = 12 + dense * 2
    rows = 3 + (1 if dense >= 2 else 0)
    for row in range(rows):
        for column in range(columns):
            x = (column - (columns - 1) / 2) * (0.68 / max(columns - 1, 1))
            yy = (row - (rows - 1) / 2) * (0.20 / max(rows - 1, 1))
            box(parts, "Dense bristle tuft", (x, yy, 0.045), (0.032, 0.040, 0.080), bristle_material, 0.006)
    rod(parts, "Handle socket", (0, 0.04, 0.20), (0, 0.13, 0.35), 0.072, accent, 14)
    shaft_material = "cream" if plastic else "wood"
    rod(parts, "Handle shaft", (0, 0.10, 0.25), (0, 0.59, 1.42), 0.036 + detail * 0.002, shaft_material, 12 + detail * 2)
    rod(parts, "Rounded grip", (0, 0.51, 1.23), (0, 0.64, 1.54), 0.052, head_material, 14 + detail * 2)
    rod(parts, "Grip cap", (0, 0.63, 1.52), (0, 0.66, 1.59), 0.058, accent, 14 + detail * 2)
    if style in ("engraved", "cloud", "lattice", "master"):
        add_cloud(parts, 0, -0.01, 0.258, 1.0 if index < 7 else 1.25, accent)
    if style in ("lattice", "master"):
        add_lattice(parts, head_width, 0.0, 0.258, accent, 3 if index < 8 else 4)
    if index >= 5:
        for band in range(2 + detail):
            t = 0.28 + band * (0.44 / max(1, 1 + detail))
            a = Vector((0, 0.51, 1.23)).lerp(Vector((0, 0.64, 1.54)), t)
            rod(parts, "Carved grip band", a, a + Vector((0, 0.010, 0.022)), 0.053, "gold" if index == 8 else accent, 16)
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    brush = bpy.context.object
    brush.name = "BrushTier%d_%s" % (index, style.title())
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / filename), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True, export_cameras=False, export_lights=False,
    )
    brush.data.calc_loop_triangles()
    print(index, filename, len(brush.data.loop_triangles))

TIERS = [
    ("tier_0_current_plastic.glb", "plastic", 0, 0),
    ("tier_1_wide_plastic.glb", "wide", 0, 0),
    ("tier_2_dense_plastic.glb", "dense", 2, 0),
    ("tier_3_crafted_wood.glb", "crafted", 2, 1),
    ("tier_4_engraved_wood.glb", "engraved", 3, 1),
    ("tier_5_cloud_lacquer.glb", "cloud", 3, 2),
    ("tier_6_lattice_wood.glb", "lattice", 4, 2),
    ("tier_7_jade_cloud.glb", "cloud", 5, 3),
    ("tier_8_master_lattice.glb", "master", 6, 4),
]

for tier, args in enumerate(TIERS):
    build_tier(tier, *args)

# Keep an edit-friendly source lineup and a quick visual QA render.
clear_scene()
for tier, args in enumerate(TIERS):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(OUT / args[0]))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    column = tier if tier < 5 else tier - 5
    row = 0 if tier < 5 else 1
    for obj in imported:
        obj.location += Vector(((column - 2) * 1.15, 0.7 - row * 1.55, 0))

bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, -0.03))
ground = bpy.context.object
ground.data.materials.append(MATERIALS["cream"])

def aim(obj, point):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()

for location, energy, size in [((-4, -5, 7), 900, 5), ((5, 1, 5), 500, 4)]:
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    aim(light, (0, 0, 0.6))
bpy.ops.object.camera_add(location=(0, -8.0, 8.8))
camera = bpy.context.object
camera.data.type = "ORTHO"
camera.data.ortho_scale = 6.7
aim(camera, (0, 0, 0.68))
scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1400
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.world.color = (0.55, 0.68, 0.68)
scene.view_settings.look = "AgX - Medium High Contrast"
render_dir = ROOT / "art/renders"
render_dir.mkdir(parents=True, exist_ok=True)
scene.render.filepath = str(render_dir / "progression_tools.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art/blender/progression_tools.blend"))
bpy.ops.render.render(write_still=True)
