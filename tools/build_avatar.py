"""Author the editable player toy and its small, portable Godot assets.

Run with an installed Blender (5.2 tested):
    blender --background --factory-startup --python tools/build_avatar.py
Then rebuild the optional gameplay rig with:
    blender --background --factory-startup --python tools/rig_avatar.py

Blender source is Z-up and faces +Y. GLB export converts to Y-up, facing -Z.
All exports share a feet-at-origin coordinate system; hats need no offset.
The .blend retains a continuous body, editable construction graph and joint pivots.
Runtime exports contain one connected watertight body, with no textures.
"""

from pathlib import Path
import json
import math

import bpy
import bmesh
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "CarpetToy/assets/character"
THUMBS = ASSETS / "thumbnails"
SOURCE = ROOT / "art/blender/avatar.blend"
RENDERS = ROOT / "art/renders/avatar"
for folder in (ASSETS, THUMBS, SOURCE.parent, RENDERS):
    folder.mkdir(parents=True, exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    if collection.name != "Collection":
        bpy.data.collections.remove(collection)
default_collection = bpy.data.collections.get("Collection")
if default_collection:
    bpy.data.collections.remove(default_collection)


def collection(name):
    result = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(result)
    return result


BODY = collection("01 — Editable body (white / tint at runtime)")
PIRATE = collection("02 — Pirate hat")
BEANIE = collection("03 — Beanie")
STUDIO = collection("04 — Thumbnail studio (not exported)")
CONTROLS = collection("05 — Body construction and joint pivots (not exported)")


def rgba(hex_code):
    values = [int(hex_code[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in values) + (1,)


def material(name, hex_code, roughness=0.65):
    result = bpy.data.materials.new(name)
    result.diffuse_color = rgba(hex_code)
    result.use_nodes = True
    result.use_backface_culling = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = result.diffuse_color
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Specular IOR Level"].default_value = 0.23
    return result


WHITE = material("Body — white tintable", "FFFFFF", 0.61)
ORANGE = material("Thumbnail orange — preview only", "F28C28", 0.61)
INK = material("Pirate — midnight", "25363C", 0.72)
GOLD = material("Pirate — warm gold piping", "D4A654", 0.54)
TEAL = material("Beanie — deep teal", "267C79", 0.84)


def move_to(obj, target):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    target.objects.link(obj)


def set_origin(obj, point):
    # Move the origin without moving authored vertices or changing export placement.
    offset = Vector(point) - obj.location
    for vertex in obj.data.vertices:
        vertex.co -= offset
    obj.location = point


def finish(obj, name, mat, target, pivot=None):
    obj.name = name
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for face in obj.data.polygons:
        face.use_smooth = True
    obj.data.materials.append(mat)
    move_to(obj, target)
    if pivot is not None:
        set_origin(obj, pivot)
    obj.select_set(False)
    return obj


def ellipsoid(name, location, size, mat, target, segments=16, rings=10, pivot=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=location)
    obj = bpy.context.object
    obj.scale = size
    return finish(obj, name, mat, target, pivot)


def mesh(name, vertices, faces, mat, target, pivot=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    editable = bmesh.new()
    editable.from_mesh(data)
    bmesh.ops.recalc_face_normals(editable, faces=list(editable.faces))
    editable.to_mesh(data)
    editable.free()
    obj = bpy.data.objects.new(name, data)
    target.objects.link(obj)
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    if pivot is not None:
        set_origin(obj, pivot)
    return obj


def lathe(name, profile, radii, mat, target, segments=24, center=(0, 0, 0)):
    """Elliptical, closed ring-profile mesh. Endpoints may have radius zero."""
    vertices = []
    for z, radius in profile:
        for i in range(segments):
            angle = 2 * math.pi * i / segments
            vertices.append((center[0] + math.cos(angle) * radii[0] * radius,
                             center[1] + math.sin(angle) * radii[1] * radius,
                             center[2] + z))
    faces = []
    for row in range(len(profile) - 1):
        for i in range(segments):
            a, b = row * segments + i, row * segments + (i + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    result = mesh(name, vertices, faces, mat, target)
    # Weld radial poles so counts reflect real triangles and avoid degenerate faces.
    bpy.ops.object.select_all(action="DESELECT")
    result.select_set(True)
    bpy.context.view_layer.objects.active = result
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.00001)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    result.select_set(False)
    return result


def build_continuous_body():
    # A branching control graph creates one closed quad cage. Catmull-Clark
    # subdivision rounds its cross-sections without separate overlapping limbs,
    # voxel remeshing, joint balls, enlarged hands or projecting boots.
    points = [(0, 0, 1.03), (0, 0, 1.32), (0, 0, 1.65),
              (0, 0, 1.83), (0, 0, 1.94), (0, 0, 2.16), (0, 0, 2.33)]
    radii = [(0.29, 0.23), (0.34, 0.23), (0.30, 0.23),
             (0.135, 0.135), (0.26, 0.25), (0.30, 0.28), (0.20, 0.20)]
    edges = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6)]
    joints = {"Hips": points[0], "Chest": points[2], "Neck": points[3], "Head": points[5]}
    for sign, side in ((-1, "Right"), (1, "Left")):
        first = len(points)
        points += [(sign * 0.43, 0, 1.56), (sign * 0.49, 0, 1.30), (sign * 0.50, 0, 0.97)]
        radii += [(0.15, 0.15), (0.15, 0.15), (0.15, 0.15)]
        edges += [(2, first), (first, first + 1), (first + 1, first + 2)]
        joints.update({side + " shoulder": points[first], side + " elbow": points[first + 1], side + " wrist": points[first + 2]})
        first = len(points)
        points += [(sign * 0.18, 0, 0.86), (sign * 0.18, 0, 0.51), (sign * 0.18, 0, 0.14)]
        radii += [(0.17, 0.17)] * 3
        edges += [(0, first), (first, first + 1), (first + 1, first + 2)]
        joints.update({side + " hip": points[first], side + " knee": points[first + 1], side + " ankle": points[first + 2]})
    data = bpy.data.meshes.new("Body construction graph")
    data.from_pydata(points, edges, [])
    data.update()
    source = bpy.data.objects.new("Body control graph — edit vertex radii", data)
    CONTROLS.objects.link(source)
    skin = source.modifiers.new("Continuous quad skin", "SKIN")
    skin.use_smooth_shade = True
    skin.branch_smoothing = 0.15
    for vertex, radius in zip(source.data.skin_vertices[0].data, radii):
        vertex.radius = radius
    source.data.skin_vertices[0].data[0].use_root = True
    subdiv = source.modifiers.new("Smooth continuous surface", "SUBSURF")
    subdiv.levels = 2
    subdiv.render_levels = 2
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    body_data = bpy.data.meshes.new_from_object(source.evaluated_get(depsgraph), depsgraph=depsgraph)
    body = bpy.data.objects.new("Body — continuous editable surface", body_data)
    BODY.objects.link(body)
    bottom = min(vertex.co.z for vertex in body_data.vertices)
    for vertex in body_data.vertices:
        vertex.co.z -= bottom
    # The graph provides clean quad flow through the neck. Project its upper
    # head section onto a soft sphere so the crown is round rather than a
    # subdivided-box cap; blend only the short neck transition below the jaw.
    head_top = max(vertex.co.z for vertex in body_data.vertices)
    head_center = Vector((0, 0, head_top - 0.265))
    head_radii = Vector((0.265, 0.25, 0.265))
    for vertex in body_data.vertices:
        if vertex.co.z <= head_center.z - 0.225:
            continue
        t = min(1.0, max(0.0, (vertex.co.z - (head_center.z - 0.225)) / 0.09))
        blend = t * t * (3.0 - 2.0 * t)
        delta = vertex.co - head_center
        normal = Vector((delta.x / head_radii.x, delta.y / head_radii.y, delta.z / head_radii.z)).normalized()
        rounded = head_center + Vector((normal.x * head_radii.x, normal.y * head_radii.y, normal.z * head_radii.z))
        vertex.co = vertex.co.lerp(rounded, blend)
    for vertex in source.data.vertices:
        vertex.co.z -= bottom
    for face in body_data.polygons:
        face.use_smooth = True
    body_data.materials.append(WHITE)
    for name, point in joints.items():
        pivot = bpy.data.objects.new("Joint — " + name, None)
        pivot.empty_display_type = "SPHERE"
        pivot.empty_display_size = 0.045
        pivot.location = (point[0], point[1], point[2] - bottom)
        CONTROLS.objects.link(pivot)
    for obj in CONTROLS.objects:
        obj.hide_render = True
        obj.hide_set(True)
    return body


body = build_continuous_body()

# Pirate crown and a softly rolled triangular brim; the only accent is a fine gold edge.
lathe("Pirate crown", [(2.20, 0), (2.20, 0.91), (2.31, 1), (2.46, 0.87),
                       (2.56, 0.56), (2.585, 0)], (0.365, 0.315), INK, PIRATE, segments=20)
N = 30
brim_vertices = []
outer_points = []
for row in range(4):
    for i in range(N):
        angle = 2 * math.pi * i / N
        # Corners extend and sit low; the three intervening folds rise gently.
        tri = math.cos(3 * (angle - math.pi / 2))
        radius = 0.56 + 0.085 * tri
        lift = 0.22 * ((1 - tri) / 2) ** 0.72
        x, y = math.cos(angle), math.sin(angle)
        if row == 0:
            point = (x * 0.33, y * 0.285, 2.23)
        elif row == 1:
            point = (x * radius, y * radius * 0.84, 2.25 + lift)
            outer_points.append(Vector(point))
        elif row == 2:
            point = (x * radius, y * radius * 0.84, 2.215 + lift)
        else:
            point = (x * 0.33, y * 0.285, 2.20)
        brim_vertices.append(point)
brim_faces = []
for row in range(4):
    next_row = (row + 1) % 4
    for i in range(N):
        brim_faces.append((row * N + i, row * N + (i + 1) % N,
                           next_row * N + (i + 1) % N, next_row * N + i))
mesh("Pirate rolled brim", brim_vertices, brim_faces, INK, PIRATE)
trim_vertices, trim_faces = [], []
for i, point in enumerate(outer_points):
    tangent = (outer_points[(i + 1) % N] - outer_points[(i - 1) % N]).normalized()
    normal = tangent.cross(Vector((0, 0, 1))).normalized()
    binormal = tangent.cross(normal).normalized()
    for j in range(4):
        angle = 2 * math.pi * j / 4
        trim_vertices.append(point + 0.012 * (math.cos(angle) * normal + math.sin(angle) * binormal))
for i in range(N):
    for j in range(4):
        trim_faces.append((i * 4 + j, ((i + 1) % N) * 4 + j,
                           ((i + 1) % N) * 4 + (j + 1) % 4, i * 4 + (j + 1) % 4))
mesh("Pirate gold piping", trim_vertices, trim_faces, GOLD, PIRATE)

# A clean knit-cap shape, with a broad rolled cuff instead of texture or stitches.
lathe("Beanie crown", [(2.205, 0), (2.205, 0.93), (2.30, 1), (2.41, 0.91),
                       (2.51, 0.66), (2.565, 0.28), (2.575, 0)],
      (0.365, 0.32), TEAL, BEANIE, segments=20)
lathe("Beanie folded cuff", [(2.20, 0.92), (2.185, 0.97), (2.20, 1.04), (2.265, 1.04),
                             (2.285, 0.985), (2.275, 0.92), (2.20, 0.92)],
      (0.365, 0.32), TEAL, BEANIE, segments=20)

# Fit both accessories to the new modest spherical head. Their mesh coordinates
# remain in the body's feet-at-origin space, so neither item needs a game offset.
head_top = max(vertex.co.z for vertex in body.data.vertices)
for group in (PIRATE, BEANIE):
    for obj in group.objects:
        for vertex in obj.data.vertices:
            vertex.co.x *= 0.70
            vertex.co.y *= 0.70
            vertex.co.z = head_top + (vertex.co.z - 2.39) * 0.70


def topology(obj):
    editable = bmesh.new()
    editable.from_mesh(obj.data)
    remaining = set(editable.verts)
    components = 0
    while remaining:
        components += 1
        pending = [remaining.pop()]
        while pending:
            for edge in pending.pop().link_edges:
                for vertex in edge.verts:
                    if vertex in remaining:
                        remaining.remove(vertex)
                        pending.append(vertex)
    result = {"connected_components": components,
              "nonmanifold_edges": sum(not edge.is_manifold for edge in editable.edges),
              "boundary_edges": sum(edge.is_boundary for edge in editable.edges),
              "vertices": len(editable.verts)}
    editable.free()
    return result


def statistics(objects):
    triangles = 0
    materials = set()
    points = []
    for obj in objects:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
        materials.update(mat.name for mat in obj.data.materials if mat)
        points += [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    # Convert Blender (X,Y,Z) coordinates to GLB / Godot (X,Z,-Y).
    converted = [(p.x, p.z, -p.y) for p in points]
    return {"triangles": triangles, "material_surfaces": len(materials),
            "bounds_min": [round(min(p[i] for p in converted), 6) for i in range(3)],
            "bounds_max": [round(max(p[i] for p in converted), 6) for i in range(3)]}


def export_group(group, filename):
    bpy.ops.object.select_all(action="DESELECT")
    temporary = []
    for source in group.objects:
        obj = source.copy()
        obj.data = source.data.copy()
        bpy.context.scene.collection.objects.link(obj)
        obj.select_set(True)
        temporary.append(obj)
    bpy.context.view_layer.objects.active = temporary[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = Path(filename).stem
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    # Collapse duplicate material slots produced by joining individual source parts.
    slots = list(obj.data.materials)
    unique = list(dict.fromkeys(slots))
    indices = [unique.index(slots[polygon.material_index]) for polygon in obj.data.polygons]
    obj.data.materials.clear()
    for mat in unique:
        obj.data.materials.append(mat)
    for polygon, index in zip(obj.data.polygons, indices):
        polygon.material_index = index
    info = statistics([obj])
    bpy.ops.export_scene.gltf(filepath=str(ASSETS / filename), export_format="GLB",
                              use_selection=True, export_materials="EXPORT",
                              export_animations=False, export_yup=True,
                              export_texcoords=False, export_normals=True,
                              export_cameras=False, export_lights=False)
    info["file_bytes"] = (ASSETS / filename).stat().st_size
    bpy.data.objects.remove(obj, do_unlink=True)
    return info


bpy.context.view_layer.update()
manifest = {
    "generator": "tools/build_avatar.py",
    "editable_source": "art/blender/avatar.blend",
    "coordinates": "Y-up, front -Z, feet Y=0; all GLBs have the same origin",
    "body_tint": "#F28C28",
    "attachment": "Hats are siblings of avatar with identity transform; never re-center hats",
    "assets": {
        "avatar.glb": export_group(BODY, "avatar.glb"),
        "pirate_hat.glb": export_group(PIRATE, "pirate_hat.glb"),
        "beanie.glb": export_group(BEANIE, "beanie.glb"),
    },
}
body_info = manifest["assets"]["avatar.glb"]
body_info.update(topology(body))
assert body_info["connected_components"] == 1, body_info
assert body_info["nonmanifold_edges"] == 0, body_info
assert body_info["boundary_edges"] == 0, body_info
manifest["equipped_max_triangles"] = body_info["triangles"] + max(
    manifest["assets"]["pirate_hat.glb"]["triangles"], manifest["assets"]["beanie.glb"]["triangles"])
manifest["equipped_max_material_surfaces"] = body_info["material_surfaces"] + max(
    manifest["assets"]["pirate_hat.glb"]["material_surfaces"], manifest["assets"]["beanie.glb"]["material_surfaces"])
assert manifest["equipped_max_triangles"] <= 4000, manifest
assert manifest["equipped_max_material_surfaces"] <= 3, manifest
(ASSETS / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

# Lightweight studio renders only become static thumbnails. No studio nodes enter GLBs.
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = True
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.65, 0.72, 0.78, 1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"


def area_light(name, location, energy, size, tint):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.shape, data.size = energy, "DISK", size
    data.color = tint
    obj = bpy.data.objects.new(name, data)
    STUDIO.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, 1.5)) - obj.location).to_track_quat("-Z", "Y").to_euler()


area_light("Soft key", (-3, 4, 5), 350, 4, (1, 0.91, 0.78))
area_light("Cool fill", (3, 1, 3), 180, 3, (0.74, 0.88, 1))
area_light("Rim", (0, -3, 4), 300, 3, (1, 0.90, 0.73))
camera_data = bpy.data.cameras.new("Thumbnail camera")
camera = bpy.data.objects.new("Thumbnail camera", camera_data)
STUDIO.objects.link(camera)
scene.camera = camera
camera_data.type = "ORTHO"


def visibility(group, value):
    for obj in group.objects:
        obj.hide_render = not value
        obj.hide_set(not value)


def render(path, look_at=(0, 0, 1.10), scale=2.65, angle=0.17):
    camera.location = (math.sin(angle) * 7, math.cos(angle) * 7, look_at[2] + 1.65)
    camera.rotation_euler = (Vector(look_at) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.ortho_scale = scale
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


for obj in BODY.objects:
    obj.data.materials[0] = ORANGE
visibility(PIRATE, False)
visibility(BEANIE, False)
render(THUMBS / "portrait.png", look_at=(0, 0, 1.43), scale=1.80, angle=0.12)
render(THUMBS / "none.png")
visibility(PIRATE, True)
render(THUMBS / "pirate.png")
visibility(PIRATE, False)
visibility(BEANIE, True)
render(THUMBS / "beanie.png")
visibility(BEANIE, False)
render(RENDERS / "body_front.png", angle=0)
render(RENDERS / "body_side.png", angle=math.pi / 2)
render(RENDERS / "body_back.png", angle=math.pi)
render(RENDERS / "body_three_quarter.png", angle=math.pi / 5)
visibility(PIRATE, True)
render(RENDERS / "pirate_three_quarter.png", angle=math.pi / 5)
visibility(PIRATE, False)
visibility(BEANIE, True)
render(RENDERS / "beanie_three_quarter.png", angle=math.pi / 5)

# Save the editable source with the white body and bare head visible.
visibility(BEANIE, False)
for obj in BODY.objects:
    obj.data.materials[0] = WHITE
for obj in STUDIO.objects:
    obj.hide_set(True)
bpy.ops.object.select_all(action="DESELECT")
for obj in BODY.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(iter(BODY.objects))
scene["Character notes"] = "Continuous featureless default humanoid; +Y forward in Blender, -Z in Godot. Body is one manifold surface. Hidden graph and joint pivots remain editable. Hats share origin. White body is tinted in game."
scene["Default runtime color"] = "#F28C28"
scene["Mobile geometry budget"] = "Equipped <=4000 triangles, <=3 material surfaces"
scene.unit_settings.system = "METRIC"
bpy.data.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
print("AVATAR_ASSETS_OK " + json.dumps(manifest))
