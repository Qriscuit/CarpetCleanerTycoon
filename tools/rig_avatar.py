"""Rig the authored continuous avatar without changing the static menu assets.

Run Blender --background --python tools/rig_avatar.py after build_avatar.py.
The saved source retains its editable body, construction graph and joint pivots.
Animation translates/rotates the pelvis locally; the root stays at identity.
The game owns locomotion, broom following and physical ragdoll simulation.
"""
from pathlib import Path
import json
import math

import bpy
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art/blender/avatar.blend'
ASSETS = ROOT / 'CarpetToy/assets/character'
RENDERS = ROOT / 'art/renders/avatar/rig'
RENDERS.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
scene.render.fps = 30
scene.render.fps_base = 1.0
body = bpy.data.objects['Body — continuous editable surface']
construction = bpy.data.objects['Body control graph — edit vertex radii']
WHITE = body.data.materials[0]
for obj in list(bpy.data.objects):
    if obj.name.startswith('AvatarRig') or obj.name.startswith('Rig QA'):
        bpy.data.objects.remove(obj, do_unlink=True)
for modifier in list(body.modifiers):
    if modifier.type == 'ARMATURE':
        body.modifiers.remove(modifier)
body.parent = None
body.matrix_world.identity()
body.vertex_groups.clear()
construction.vertex_groups.clear()
for action in list(bpy.data.actions):
    if action.name in ('idle', 'ride', 'run', 'get_up', 'dust_off', 'climb'):
        bpy.data.actions.remove(action)
rig_collection = bpy.data.collections.get('06 — Rig and animation')
if rig_collection is None:
    rig_collection = bpy.data.collections.new('06 — Rig and animation')
    scene.collection.children.link(rig_collection)
armature = bpy.data.armatures.new('AvatarRig skeleton')
rig = bpy.data.objects.new('AvatarRig', armature)
rig_collection.objects.link(rig)
rig.show_in_front = True
rig.display_type = 'WIRE'
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
# Stable names and origins are the contract used by Godot's ragdoll controller.
bones = {
    'root': ((0, 0, 0), (0, 0, .12), None, False),
    'pelvis': ((0, 0, .84), (0, 0, 1.08), 'root', True),
    'spine': ((0, 0, 1.08), (0, 0, 1.6751543), 'pelvis', True),
    'head': ((0, 0, 1.6751543), (0, 0, 2.13), 'spine', True),
}
for sign, side in ((1, 'l'), (-1, 'r')):
    bones.update({
        'upper_arm_' + side: ((sign * .37, 0, 1.45), (sign * .49, 0, 1.1451543), 'spine', True),
        'forearm_' + side: ((sign * .49, 0, 1.1451543), (sign * .50, 0, .8151543), 'upper_arm_' + side, True),
        'thigh_' + side: ((sign * .18, 0, .82), (sign * .18, 0, .40), 'pelvis', True),
        'shin_' + side: ((sign * .18, 0, .40), (sign * .18, 0, .06), 'thigh_' + side, True),
    })
for name, (head, tail, parent, deform) in bones.items():
    bone = armature.edit_bones.new(name)
    bone.head, bone.tail = head, tail
    bone.use_deform = deform
    if parent:
        bone.parent = armature.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')

# Assign weights on the source graph, then interpolate them through the same
# skin/subdivision construction that produced the body. This follows the mesh's
# actual limb topology and avoids weights leaking across the narrow arm gaps.
groups = {name: construction.vertex_groups.new(name=name) for name in bones if name != 'root'}
control_weights = {
    0: {'pelvis': 1}, 1: {'pelvis': .35, 'spine': .65}, 2: {'spine': 1},
    3: {'spine': .35, 'head': .65}, 4: {'head': 1}, 5: {'head': 1}, 6: {'head': 1},
}
for first, side in ((7, 'r'), (13, 'l')):
    control_weights.update({
        first: {'spine': .12, 'upper_arm_' + side: .88},
        first + 1: {'upper_arm_' + side: .5, 'forearm_' + side: .5},
        first + 2: {'forearm_' + side: 1},
        first + 3: {'pelvis': .12, 'thigh_' + side: .88},
        first + 4: {'thigh_' + side: .5, 'shin_' + side: .5},
        first + 5: {'shin_' + side: 1},
    })
for index, weights in control_weights.items():
    for name, weight in weights.items():
        groups[name].add([index], weight, 'REPLACE')
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
weighted_mesh = bpy.data.meshes.new_from_object(construction.evaluated_get(depsgraph), preserve_all_data_layers=True, depsgraph=depsgraph)
assert len(weighted_mesh.vertices) == len(body.data.vertices), 'Construction topology changed; rebuild static assets first.'
body_groups = {name: body.vertex_groups.new(name=name) for name in groups}
weight_errors = []
max_influences = 0


def smooth(a, b, value):
    t = min(1.0, max(0.0, (value - a) / (b - a)))
    return t * t * (3 - 2 * t)


for vertex in weighted_mesh.vertices:
    if body.data.vertices[vertex.index].co.z < 1.6:
        assert (body.data.vertices[vertex.index].co - vertex.co).length < .0001, 'Construction vertex order changed.'
    authored_weights = {construction.vertex_groups[item.group].name: item.weight for item in vertex.groups if item.weight > .00001}
    # The branching control graph gives uneven hip weights around each ring.
    # Use a smooth anatomical field here instead: each horizontal band shares
    # the same leg/pelvis blend, so a seated bend cannot form hanging lobes.
    # Elsewhere the graph weights preserve shoulder and elbow topology.
    point = body.data.vertices[vertex.index].co
    arm_share = sum(weight for name, weight in authored_weights.items() if 'arm_' in name)
    if point.z < 1.12 and arm_share < .15:
        leg_share = 1 - smooth(.54, 1.12, point.z)
        knee_share = 1 - smooth(.26, .54, point.z)
        width = .01 + .16 * smooth(.72, 1.0, point.z)
        left_share = smooth(-width, width, point.x)
        torso_total = authored_weights.get('pelvis', 0) + authored_weights.get('spine', 0)
        spine_share = authored_weights.get('spine', 0) / torso_total if torso_total > .00001 else 0
        authored_weights = {'pelvis': (1 - leg_share) * (1 - spine_share),
                            'spine': (1 - leg_share) * spine_share,
                            'thigh_l': leg_share * left_share * (1 - knee_share),
                            'thigh_r': leg_share * (1 - left_share) * (1 - knee_share),
                            'shin_l': leg_share * left_share * knee_share,
                            'shin_r': leg_share * (1 - left_share) * knee_share}
    weights = sorted([(name, weight) for name, weight in authored_weights.items() if weight > .00001], key=lambda item: -item[1])[:4]
    total = sum(weight for _, weight in weights)
    assert total > 0, ('Unweighted vertex', vertex.index)
    for name, weight in weights:
        body_groups[name].add([vertex.index], weight / total, 'REPLACE')
    max_influences = max(max_influences, len(weights))
    weight_errors.append(abs(sum(weight / total for _, weight in weights) - 1))
bpy.data.meshes.remove(weighted_mesh)
modifier = body.modifiers.new('Avatar skeletal deformation', 'ARMATURE')
modifier.object = rig
modifier.use_deform_preserve_volume = False  # Match linear glTF/Godot skinning.
body.parent = rig
body.matrix_parent_inverse = rig.matrix_world.inverted()
for bone in rig.pose.bones:
    bone.rotation_mode = 'QUATERNION'


def rotate(name, x=0, y=0, z=0):
    """Pose rotation around rest-world axes, independent of bone roll."""
    basis = armature.bones[name].matrix_local.to_quaternion()
    rotation = Quaternion((1, 0, 0), math.radians(x)) @ Quaternion((0, 1, 0), math.radians(y)) @ Quaternion((0, 0, 1), math.radians(z))
    rig.pose.bones[name].rotation_quaternion = basis.inverted() @ rotation @ basis


def pelvis(height=.84, lean=0, forward=0):
    rotate('pelvis', x=lean)
    basis = armature.bones['pelvis'].matrix_local.to_quaternion()
    rig.pose.bones['pelvis'].location = basis.inverted() @ Vector((0, forward, height - .84))


def reset_pose():
    for bone in rig.pose.bones:
        bone.location = (0, 0, 0)
        bone.rotation_quaternion = (1, 0, 0, 0)
        bone.scale = (1, 1, 1)


def distribute_hip_bend():
    # Share a deep two-leg bend between pelvis and hip joints, then compensate
    # the spine so the chest keeps its authored orientation. Each skinning
    # blend sees a moderate angle rather than one collapsing 85-degree hinge.
    def angle(name):
        basis = armature.bones[name].matrix_local.to_quaternion()
        world = basis @ rig.pose.bones[name].rotation_quaternion @ basis.inverted()
        return math.degrees(world.to_euler('XYZ').x)
    fold = min(max(0, angle('thigh_l')), max(0, angle('thigh_r')))
    share = max(0, fold - 20) * .70
    if share <= 0:
        return
    for name, delta in (('pelvis', share), ('spine', -share), ('thigh_l', -share), ('thigh_r', -share)):
        basis = armature.bones[name].matrix_local.to_quaternion()
        extra = basis.inverted() @ Quaternion((1, 0, 0), math.radians(delta)) @ basis
        rig.pose.bones[name].rotation_quaternion = extra @ rig.pose.bones[name].rotation_quaternion


def ride_pose(t=0):
    breath = math.sin(t * 2 * math.pi)
    pelvis(.88 + .006 * breath)
    rotate('spine', x=-6 + breath * .6)
    rotate('head', x=5)
    for side, sign in (('l', 1), ('r', -1)):
        rotate('thigh_' + side, x=85)
        rotate('shin_' + side, x=-80)
        rotate('upper_arm_' + side, x=32, y=sign * 10)
        rotate('forearm_' + side, x=35)


def idle_pose(t):
    wave = math.sin(t * 2 * math.pi)
    pelvis(.84)
    rotate('spine', x=wave * .7)
    rotate('head', z=wave * 1.3)
    rotate('upper_arm_l', x=wave * 1.2)
    rotate('upper_arm_r', x=-wave * 1.2)


def run_pose(t):
    phase = t * 2 * math.pi
    pelvis(.87 + .025 * math.cos(phase * 2))
    rotate('spine', x=-9, z=3 * math.sin(phase))
    rotate('head', x=5, z=-3 * math.sin(phase))
    for side, offset in (('l', 0), ('r', math.pi)):
        stride = math.sin(phase + offset)
        rotate('thigh_' + side, x=38 * stride + 5)
        rotate('shin_' + side, x=-15 - 45 * max(0, -stride))
        rotate('upper_arm_' + side, x=-30 * stride)
        rotate('forearm_' + side, x=45 + 10 * stride)


def lerp(a, b, t):
    return a + (b - a) * t


def sample_keys(keys, t):
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if t <= b[0]:
            blend = (t - a[0]) / (b[0] - a[0])
            blend = max(0, min(1, blend))
            blend = blend * blend * (3 - 2 * blend)
            return [lerp(x, y, blend) for x, y in zip(a[1:], b[1:])]
    return list(keys[-1][1:])


def get_up_pose(t):
    # height, body lean, thigh fold, knee fold, upper-arm reach, elbow fold
    h, lean, thigh, shin, upper, fore = sample_keys([
        (0, .28, -90, 0, 0, 25, -25),
        (.22, .36, -68, 35, -60, 85, -45),
        (.50, .53, -35, 60, -100, 55, -15),
        (.78, .76, -12, 22, -40, 20, 5),
        (1, .84, 0, 0, 0, 0, 0)], t)
    pelvis(h, lean)
    rotate('head', x=12 * math.sin(t * math.pi))
    for side, sign in (('l', 1), ('r', -1)):
        rotate('thigh_' + side, x=thigh)
        rotate('shin_' + side, x=shin)
        rotate('upper_arm_' + side, x=upper, y=sign * -10 * (1 - t))
        rotate('forearm_' + side, x=fore)


def dust_off_pose(t):
    reach = math.sin(min(1, t / .18) * math.pi / 2) * math.sin(min(1, (1 - t) / .18) * math.pi / 2)
    sweep = math.sin(t * 6 * math.pi) * 12 * reach
    pelvis(.84)
    rotate('spine', z=3 * math.sin(t * 2 * math.pi))
    rotate('head', x=-12 * reach)
    rotate('upper_arm_r', x=65 * reach, y=-40 * reach)
    rotate('forearm_r', x=(30 + sweep) * reach, y=-35 * reach)
    rotate('upper_arm_l', x=12 * reach)
    rotate('forearm_l', x=8 * reach)


def climb_pose(t):
    if t > .75:
        blend = (t - .75) / .25
        blend = blend * blend * (3 - 2 * blend)
        ride_pose(0)
        # Arrive at the ride pose without moving the world root.
        for side in ('l', 'r'):
            rotate('upper_arm_' + side, x=lerp(80, 32, blend), y=(10 if side == 'l' else -10))
            rotate('forearm_' + side, x=lerp(60, 35, blend))
        return
    h, lean, thigh, shin, upper, fore = sample_keys([
        (0, .84, 0, 0, 0, 0, 0),
        (.22, .80, -5, 15, -25, 145, 5),
        (.48, .82, -12, 65, -95, 115, 30),
        (.75, .88, 0, 85, -80, 80, 60)], t)
    pelvis(h, lean)
    rotate('spine', x=-6 * t / .75)
    rotate('head', x=5 * t / .75)
    for side, sign in (('l', 1), ('r', -1)):
        rotate('thigh_' + side, x=thigh)
        rotate('shin_' + side, x=shin)
        rotate('upper_arm_' + side, x=upper, y=sign * 10 * t / .75)
        rotate('forearm_' + side, x=fore)


clips = {'idle': (2.0, True, idle_pose), 'ride': (2.0, True, ride_pose),
         'run': (.8, True, run_pose), 'get_up': (1.4, False, get_up_pose),
         'dust_off': (1.0, False, dust_off_pose), 'climb': (1.2, False, climb_pose)}
rig.animation_data_create()
actions = {}
pose_bounds = {}
for name, (duration, loop, pose) in clips.items():
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    frames = round(duration * scene.render.fps)
    pose_bounds[name] = []
    for frame in range(frames + 1):
        scene.frame_set(frame)
        reset_pose()
        pose(frame / frames)
        distribute_hip_bend()
        bpy.context.view_layer.update()
        evaluated = body.evaluated_get(depsgraph)
        minimum = min(vertex.co.z for vertex in evaluated.data.vertices)
        # Keep recovery hands/knees above the floor. A running stride has a
        # short flight phase and plants the lowest foot at full extension.
        shift = 0.0
        if name in ('get_up', 'climb'):
            shift = max(0.0, -minimum)
        elif name == 'run':
            shift = .045 * math.cos(frame / frames * 2 * math.pi) ** 2 - minimum
        if abs(shift) > .000001:
            basis = armature.bones['pelvis'].matrix_local.to_quaternion()
            rig.pose.bones['pelvis'].location += basis.inverted() @ Vector((0, 0, shift))
            bpy.context.view_layer.update()
        pose_bounds[name].append(minimum + shift)
        for bone in rig.pose.bones:
            bone.keyframe_insert(data_path='location', frame=frame, group=bone.name)
            bone.keyframe_insert(data_path='rotation_quaternion', frame=frame, group=bone.name)
    actions[name] = action
rig.animation_data.action = None
reset_pose()
scene.frame_set(0)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(ASSETS / 'avatar_rig.glb'), export_format='GLB', use_selection=True,
    export_materials='EXPORT', export_animations=True, export_animation_mode='ACTIONS',
    export_anim_slide_to_zero=True, export_skins=True, export_yup=True, export_texcoords=False,
    export_cameras=False, export_lights=False, export_morph=False)


def godot(vector):
    return [round(vector[0], 7), round(vector[2], 7), round(-vector[1], 7)]


metadata = {
    'generator': 'tools/rig_avatar.py', 'source': 'art/blender/avatar.blend',
    'rig_scene': 'avatar_rig.glb', 'coordinates': 'Y-up, forward -Z, identity root; units match avatar.glb',
    'root_motion': 'None. root bone stays identity. Controller owns world locomotion; pelvis is local pose only.',
    'rest_height': 2.161513, 'ride_pelvis_height': .88,
    'hat_attachment_bone': 'head',
    'hat_local_transform': 'inverse(head global rest transform) * existing full-body hat transform',
    'physical_bone_candidates': ['pelvis', 'spine', 'head', 'upper_arm_l', 'upper_arm_r', 'thigh_l', 'thigh_r', 'shin_l', 'shin_r'],
    'bones': {name: {'head': godot(head), 'tail': godot(tail), 'parent': parent, 'deform': deform}
              for name, (head, tail, parent, deform) in bones.items()},
    'clips': {name: {'duration': duration, 'loop': loop, 'minimum_mesh_floor': round(min(pose_bounds[name]), 7)}
              for name, (duration, loop, _) in clips.items()},
    'skin': {'vertices': len(body.data.vertices), 'triangles': 2992, 'material_surfaces': 1,
             'max_vertex_influences': max_influences, 'max_weight_sum_error': max(weight_errors)},
}
(ASSETS / 'rig.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
manifest = json.loads((ASSETS / 'manifest.json').read_text(encoding='utf-8'))
manifest['assets']['avatar_rig.glb'] = dict(manifest['assets']['avatar.glb'])
manifest['assets']['avatar_rig.glb'].update(file_bytes=(ASSETS / 'avatar_rig.glb').stat().st_size, bones=len(bones), animations=list(clips), rig_metadata='rig.json')
manifest['rig_generator'] = 'tools/rig_avatar.py'
(ASSETS / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')

# Reuse the same clean studio and orange preview material. Rig pose renders are
# QA artifacts only; the exported body and saved authoring material stay white.
preview_material = WHITE.copy()
preview_material.name = 'Rig QA orange'
rgb = [int('F28C28'[i:i + 2], 16) / 255 for i in (0, 2, 4)]
color = tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb) + (1,)
preview_material.diffuse_color = color
preview_material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = color
body.data.materials[0] = preview_material
scene.camera.data.ortho_scale = 3.0
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.cycles.samples = 32
scene.render.film_transparent = True
pose_frames = {'idle': [0], 'ride': [0], 'run': [6, 18], 'get_up': [0, 9, 21, 33, 42], 'dust_off': [9, 16], 'climb': [8, 18, 36]}
for name, frames in pose_frames.items():
    rig.animation_data.action = actions[name]
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        target = Vector((0, .10, 1.05 if name != 'get_up' else .65))
        scene.camera.location = (4.8, 7.0, 3.4)
        scene.camera.rotation_euler = (target - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(RENDERS / ('%s_%02d.png' % (name, frame)))
        bpy.ops.render.render(write_still=True)
        if (name == 'ride' and frame == 0) or (name == 'climb' and frame == 18):
            scene.camera.location = (-4.8, -7.0, 3.4)
            scene.camera.rotation_euler = (target - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
            scene.render.filepath = str(RENDERS / ('%s_%02d_back.png' % (name, frame)))
            bpy.ops.render.render(write_still=True)
rig.animation_data.action = None
reset_pose()
scene.frame_set(0)
body.data.materials[0] = WHITE
scene['Rig notes'] = '12 bones, graph-interpolated skin weights, local-pose actions. Root is motion-free. Run tools/build_avatar.py then tools/rig_avatar.py to rebuild.'
scene['Rig metadata'] = 'CarpetToy/assets/character/rig.json'
bpy.context.view_layer.update()
bpy.data.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
print('AVATAR_RIG_OK ' + json.dumps(metadata))
