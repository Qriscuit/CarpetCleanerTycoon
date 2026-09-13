"""Build the editable Mint Meadow rug in Blender and export a portable GLB.
Run with Blender 4.3+: blender --background --factory-startup --python tools/build_carpet.py
"""
from pathlib import Path
import bpy
import numpy as np
import math
import json
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'CarpetToy/assets/carpet'
ASSETS.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def linear(c):
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)

def color(hexcode):
    return np.array([int(hexcode[i:i+2], 16)/255 for i in (0, 2, 4)])

W, H = 1024, 1536
x, y = np.meshgrid(np.linspace(-1, 1, W), np.linspace(-1.5, 1.5, H))
rgb = np.empty((H, W, 3), np.float32)
rgb[:] = color('72C8AB')

def paint(mask, hexcode):
    rgb[mask] = color(hexcode)

def rounded_box(cx, cy, hx, hy, r):
    qx = np.abs(x-cx) - hx + r
    qy = np.abs(y-cy) - hy + r
    return np.sqrt(np.maximum(qx, 0)**2 + np.maximum(qy, 0)**2) + np.minimum(np.maximum(qx, qy), 0) - r

def ellipse(cx, cy, rx, ry, angle=0):
    a, b = x-cx, y-cy
    u = a*np.cos(angle) + b*np.sin(angle)
    v = -a*np.sin(angle) + b*np.cos(angle)
    return (u/rx)**2 + (v/ry)**2 < 1

# Wide inset border and a warm cream arch medallion, all printed in the pile.
paint(rounded_box(0, 0, .915, 1.415, .16) < 0, 'F8EED4')
paint(rounded_box(0, 0, .868, 1.368, .14) < 0, '72C8AB')
paint(rounded_box(0, 0, .635, 1.08, .60) < 0, 'F8EED4')
# Cheerful sun, tiny golden accents and a deliberately simple sprout.
paint(ellipse(0, .49, .34, .34), 'F58C74')
paint(ellipse(-.055, .55, .24, .24), 'FFAB85')
paint(rounded_box(0, -.39, .026, .40, .023) < 0, '308E7D')
paint(ellipse(-.20, -.20, .255, .13, -.56), '308E7D')
paint(ellipse(.19, -.40, .25, .135, .52), '49AE87')
paint(ellipse(-.16, -.60, .20, .11, -.40), '49AE87')
for cx, cy in [(-.73, .90), (.73, -.90)]:
    paint(ellipse(cx, cy, .06, .06), 'F4C45F')
for cx, cy in [(-.74, -.60), (.74, .60)]:
    paint(rounded_box(cx, cy, .028, .14, .027) < 0, '359D88')

# Low-contrast woven marks: no noisy photographed fabric and no fur geometry.
weave = (.60*np.cos(x*math.pi*85)*np.cos(y*math.pi*85)
         + .25*np.sin(y*math.pi*170))
rgb = np.clip(rgb * (1 + .032*weave[..., None]), 0, 1)

def save_image(name, pixels, noncolor=False):
    im = bpy.data.images.new(name, width=W, height=H, alpha=True)
    im.colorspace_settings.name = 'Non-Color' if noncolor else 'sRGB'
    rgba = np.ones((H, W, 4), np.float32)
    rgba[:, :, :3] = pixels
    im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw = str(ASSETS / (name + '.png'))
    im.file_format = 'PNG'
    im.save()
    im.pack()
    return im

albedo = save_image('mint_meadow_albedo', rgb)
dx = .18*np.sin(x*math.pi*85)*np.cos(y*math.pi*85)
dy = .18*np.cos(x*math.pi*85)*np.sin(y*math.pi*85)
n = np.stack([dx, dy, np.ones_like(dx)], axis=-1)
n /= np.linalg.norm(n, axis=-1)[..., None]
normal = save_image('mint_meadow_normal', n*.5+.5, True)

def material(name, hexcode, texture=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*linear(color(hexcode)), 1)
    bs = mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = mat.diffuse_color
    bs.inputs['Roughness'].default_value = .93
    bs.inputs['Specular IOR Level'].default_value = .18
    if texture:
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = albedo
        mat.node_tree.links.new(tex.outputs['Color'], bs.inputs['Base Color'])
        tex.location = (-540, 160)
        nt = mat.node_tree.nodes.new('ShaderNodeTexImage')
        nt.image = normal
        nt.location = (-540, -160)
        nm = mat.node_tree.nodes.new('ShaderNodeNormalMap')
        nm.inputs['Strength'].default_value = .32
        nm.location = (-220, -140)
        mat.node_tree.links.new(nt.outputs['Color'], nm.inputs['Color'])
        mat.node_tree.links.new(nm.outputs['Normal'], bs.inputs['Normal'])
    return mat

pile_mat = material('Pile • mint meadow / woven matte', '72C8AB', True)
edge_mat = material('Binding • sea glass', '359D88')
fringe_mat = material('Fringe • warm oat', 'F8EED4')

def outline(hx, hy, r, steps=10):
    pts=[]
    for cx, cy, start in [(hx-r,hy-r,0),(-hx+r,hy-r,90),(-hx+r,-hy+r,180),(hx-r,-hy+r,270)]:
        for i in range(steps+1):
            a=math.radians(start+i*90/steps)
            pts.append((cx+r*math.cos(a), cy+r*math.sin(a)))
    return pts

def rounded_slab(name, hx, hy, r, rings, mat, steps=10):
    vertices=[]
    for inset,z in rings:
        vertices.extend((px,py,z) for px,py in outline(hx-inset, hy-inset, max(.012,r-inset),steps))
    count=len(vertices)//len(rings)
    faces=[tuple(reversed(range(count)))]
    for k in range(len(rings)-1):
        for j in range(count):
            a=k*count+j; b=k*count+(j+1)%count
            faces.append((a,b,b+count,a+count))
    faces.append(tuple(range((len(rings)-1)*count,len(rings)*count)))
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vertices,[],faces)
    mesh.materials.append(mat)
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(obj)
    uv=mesh.uv_layers.new(name='UVMap')
    for polygon in mesh.polygons:
        polygon.use_smooth = len(polygon.vertices)==4
        for li in polygon.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=(co.x/2+.5,co.y/3+.5)
    return obj

body=rounded_slab('Carpet_Binding',1,1.5,.17,[(.018,0),(0,.016),(0,.032),(.016,.049),(.04,.052)],edge_mat)
surface=rounded_slab('Carpet_Pile',.975,1.475,.15,[(.015,.035),(0,.047),(.006,.06),(.020,.067)],pile_mat)
fringes=[]
for side in [-1,1]:
    for i in range(13):
        xx=(i-6)*.134
        length=.165 + .013*math.cos(i*1.7)
        ob=rounded_slab('Fringe',.039,length/2,.036,[(.010,.013),(0,.025),(.012,.040)],fringe_mat,steps=3)
        ob.location=(xx,side*(1.476+length/2),0)
        ob.rotation_euler[2]=math.sin(i*2.2)*.045
        fringes.append(ob)
bpy.ops.object.select_all(action='DESELECT')
for ob in fringes: ob.select_set(True)
bpy.context.view_layer.objects.active=fringes[0]
bpy.ops.object.join()
fringes[0].name='Carpet_Fringe'
asset_objects=[body,surface,fringes[0]]
for ob in asset_objects:
    ob['asset']='Mint Meadow / Carpet 01'
    ob['purpose']='Clean rug art prototype, meters, ground pivot'

# Asset-only export: three surfaces; cameras, lights and floor stay out of the GLB.
bpy.ops.object.select_all(action='DESELECT')
for ob in asset_objects: ob.select_set(True)
bpy.context.view_layer.objects.active=surface
bpy.ops.export_scene.gltf(filepath=str(ASSETS/'mint_meadow.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
triangles=0
for ob in asset_objects:
    ob.data.calc_loop_triangles()
    triangles+=len(ob.data.loop_triangles)

# Reusable Blender studio, separate from the model.
studio=bpy.data.collections.new('STUDIO • excluded from export')
bpy.context.scene.collection.children.link(studio)
def to_studio(ob):
    for c in list(ob.users_collection): c.objects.unlink(ob)
    studio.objects.link(ob)

bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012))
floor=bpy.context.object
floor.name='Studio Ground'
floor.data.materials.append(material('Studio • mist','DFEBE5'))
to_studio(floor)
def aim(ob,at): ob.rotation_euler=(Vector(at)-ob.location).to_track_quat('-Z','Y').to_euler()
for name,loc,power,size in [('Key',(-3,-4,7),470,5),('Fill',(4,1,5),170,4)]:
    bpy.ops.object.light_add(type='AREA',location=loc)
    ob=bpy.context.object; ob.name=name; ob.data.energy=power; ob.data.shape='DISK'; ob.data.size=size
    aim(ob,(0,0,0)); to_studio(ob)
bpy.ops.object.camera_add(location=(3,-4.4,6.5))
cam=bpy.context.object; cam.name='Carpet portrait'; cam.data.type='ORTHO'; cam.data.ortho_scale=5.1
aim(cam,(0,0,0)); to_studio(cam)
scene=bpy.context.scene
scene.camera=cam
scene.render.engine='CYCLES'
scene.cycles.samples=32
scene.cycles.use_denoising=True
scene.render.resolution_x=1000
scene.render.resolution_y=1100
scene.render.resolution_percentage=100
scene.world.color=(.30,.30,.30)
scene.view_settings.view_transform='Standard'
scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(ROOT/'art/renders/mint_meadow_blender.png')
bpy.ops.object.select_all(action='DESELECT')
surface.select_set(True)
bpy.context.view_layer.objects.active=surface
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/mint_meadow.blend'))
(ROOT/'art/asset_manifest.json').write_text(json.dumps({'name':'Mint Meadow','dimensions_m':[2,3.32,.067],'triangles':triangles,'mesh_objects':3,'materials':3,'albedo_resolution':[W,H],'normal_resolution':[W,H],'roughness':.93,'godot_up_axis':'Y','pivot':'ground center','source':'art/blender/mint_meadow.blend','export':'CarpetToy/assets/carpet/mint_meadow.glb'},indent=2))
print('ASSET_TRIANGLES',triangles)
bpy.ops.render.render(write_still=True)
