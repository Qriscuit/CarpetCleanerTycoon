"""Editable, independently grouped Blender assets for the floating-shop home.

Run with Blender 4.3 --background --python tools/build_floating_shop.py.
Exports only game meshes to GLB; cameras and studio lights stay in the blend.
"""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'CarpetToy/assets/floating_shop'
SOURCE = ROOT / 'art/blender/floating_shop.blend'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def linear(v):
    return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4

def material(name, hex_color):
    col = tuple(linear(int(hex_color[i:i+2], 16) / 255) for i in (0, 2, 4))
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*col, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*col, 1)
    shader.inputs['Roughness'].default_value = .8
    shader.inputs['Specular IOR Level'].default_value = .23
    return mat

M = {k: material(k, c) for k, c in {
    'Cream': 'FFF1D8', 'Ivory': 'FFFAEB', 'Mint': '85BE98',
    'Mint shade': '66A582', 'Grass': 'AED08A', 'Coral': 'EC9177',
    'Coral shade': 'CE725D', 'Window': '426D8E', 'Blue': '689ACA',
    'Navy': '304F65', 'Gold': 'F6C356', 'Gold shade': 'DC9E37',
    'Robot face': '294558', 'Brass': 'BB9873'
}.items()}
assets = {}
group = None

def collection(name):
    global group
    group = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(group)
    assets[name] = group
    return group

def finish(ob, name, color):
    ob.name = name
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    group.objects.link(ob)
    ob.data.materials.append(M[color])
    return ob

def smooth(ob):
    for p in ob.data.polygons:
        p.use_smooth = True
    mod = ob.modifiers.new('Weighted soft surface normals', 'WEIGHTED_NORMAL')
    mod.keep_sharp = True
    return ob

def box(name, loc, size, color, bevel=.08, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    ob = bpy.context.object
    ob.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = ob.modifiers.new('Rounded edges', 'BEVEL')
    mod.width = bevel
    mod.segments = 4
    smooth(ob)
    if rotation:
        ob.rotation_euler = rotation
    return finish(ob, name, color)

def sphere(name, loc, size, color):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=1, location=loc)
    ob = bpy.context.object
    ob.scale = size
    for p in ob.data.polygons:
        p.use_smooth = True
    return finish(ob, name, color)

def rod(name, a, b, radius, color, vertices=24):
    direction = Vector(b) - Vector(a)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
        depth=direction.length, location=(Vector(a) + Vector(b)) / 2)
    ob = bpy.context.object
    ob.rotation_euler = direction.to_track_quat('Z', 'Y').to_euler()
    bevel = ob.modifiers.new('Rounded rims', 'BEVEL')
    bevel.width = min(radius * .22, .035)
    bevel.segments = 3
    smooth(ob)
    return finish(ob, name, color)

def tube(name, points, radius, color):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 1
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    spline = curve.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1)
    ob = bpy.data.objects.new(name, curve)
    group.objects.link(ob)
    ob.data.materials.append(M[color])
    return ob

def arch(name, center, width, height, depth, color):
    # Extruded facade shape with a truly semicircular top, front faces -Y.
    x, y, z = center
    r = width / 2
    outline = [(-r, 0), (r, 0), (r, height-r)]
    outline += [(r*math.cos(t*math.pi/20), height-r+r*math.sin(t*math.pi/20)) for t in range(1,21)]
    n = len(outline)
    verts = [(x+a, y+d, z+b) for d in (-depth/2, depth/2) for a,b in outline]
    faces = [tuple(reversed(range(n))), tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    group.objects.link(ob)
    ob.data.materials.append(M[color])
    bevel = ob.modifiers.new('Soft arch edges', 'BEVEL')
    bevel.width = .035
    bevel.segments = 3
    smooth(ob)
    return ob

def rug_roll(name, x, y, z, radius, length, color='Coral', vertical=False):
    if vertical:
        rod(name, (x,y,z), (x,y,z+length), radius, color)
        spiral = []
        for i in range(80):
            t = i/79 * math.pi*4
            r = radius*(.08+.76*i/79)
            spiral.append((x+r*math.cos(t), y+r*math.sin(t), z+length+.016))
        tube(name+' rolled core', spiral, .015, 'Coral shade')
        for zz in [z+length*.28, z+length*.63]:
            tube(name+' woven zigzag', [(x+radius*math.cos(t),y+radius*math.sin(t),zz+.035*math.cos(t*10)) for t in [i*math.tau/80 for i in range(81)]], .016,'Cream')
    else:
        rod(name, (x-length/2,y,z), (x+length/2,y,z), radius, color)
        spiral=[]
        for i in range(65):
            t=i/64*math.pi*4
            r=radius*(.06+.76*i/64)
            spiral.append((x+length/2+.012, y+r*math.cos(t), z+r*math.sin(t)))
        tube(name+' rolled core', spiral, .013, 'Cream')

collection('FloatingShop')
box('Floating cream foundation', (0,0,.08), (3.75,3.15,.38), 'Cream', .23)
box('Mint garden platform', (0,0,.29), (3.58,2.98,.16), 'Grass', .18)
box('Cream shop walls', (0,.16,1.57), (2.96,2.18,2.5), 'Cream', .17)
box('Roof lower lip', (0,.15,2.82), (3.25,2.47,.24), 'Mint shade', .115)
box('Puffy mint roof', (0,.16,3.08), (3.27,2.49,.65), 'Mint', .27)
# Chunky front awning, all eight stripes are independently editable.
for i in range(8):
    x=(i-3.5)*.367
    box('Awning stripe %02d'%i, (x,-1.115,2.47), (.375,.88,.19), 'Mint' if i%2 else 'Ivory', .075, (math.radians(19),0,0))
    box('Awning scallop %02d'%i, (x,-1.535,2.31), (.372,.17,.28), 'Mint' if i%2 else 'Ivory', .08)
box('Window cream surround', (-.55,-.966,1.39), (1.47,.19,1.40), 'Ivory', .13)
box('Deep blue display glass', (-.55,-1.071,1.42), (1.28,.065,1.2), 'Window', .09)
box('Display sill', (-.55,-1.13,.8), (1.49,.29,.14), 'Ivory', .06)
for j, color in enumerate(['Blue','Cream','Coral']):
    rug_roll('Window rug '+color, -.64, -1.125, .98+j*.20, .095, .81-j*.09, color)
# Large arched door and arched glazed panel, matching reference proportions.
arch('Coral arched doorway', (.87,-.984,.37), .87,1.75,.20,'Coral shade')
arch('Coral arched door', (.87,-1.106,.40), .72,1.58,.08,'Coral')
arch('Blue door window', (.87,-1.158,1.03), .45,.72,.035,'Window')
box('Door window crossbar', (.87,-1.19,1.36), (.47,.026,.045),'Blue',.012)
box('Door window mullion', (.87,-1.19,1.38), (.044,.026,.67),'Blue',.012)
sphere('Golden door handle', (.61,-1.205,.88), (.071,.062,.071),'Gold')
box('Welcome step', (.87,-1.28,.41), (.95,.45,.14),'Brass',.07)
box('Step cream trim', (.87,-1.32,.35), (1.04,.53,.10),'Ivory',.06)
# Large raised rug medallion on roof.
arch('Cream rug emblem plaque', (0,-1.13,2.8), 1.30,.91,.20,'Ivory')
box('Coral rug emblem', (0,-1.263,3.24), (.77,.08,.48),'Coral',.05, (0,math.radians(8),0))
for x in [-.20,.13]:
    tube('Cream woven emblem', [(x+.05*math.sin(i*math.pi/2),-1.315,3.06+i*.065) for i in range(6)], .023,'Cream')
for z in [3.07,3.18,3.29,3.40]:
    box('Rug emblem fringe', (-.44,-1.26,z), (.15,.08,.045),'Cream',.021)
rod('Emblem rolled edge', (.4,-1.265,3.02),(.4,-1.265,3.5),.062,'Coral shade')
# Windows on other faces make every rotation useful.
for side in [-1,1]:
    box('Side cream window trim', (side*1.485,.22,1.7), (.12,.98,1.10),'Ivory',.07)
    box('Side blue glass', (side*1.553,.22,1.7), (.035,.81,.91),'Window',.06)
    box('Side window bar', (side*1.578,.22,1.7), (.025,.04,.93),'Blue',.014)
box('Back window trim', (0,1.27,1.68), (1.23,.10,1.1),'Ivory',.08)
box('Back blue window', (0,1.33,1.68), (1.06,.03,.92),'Window',.05)
box('Back window crossbar', (0,1.354,1.68), (1.06,.02,.04),'Blue',.012)
box('Back window mullion', (0,1.354,1.68), (.04,.02,.92),'Blue',.012)
rug_roll('Rolled rug by door',1.55,-.85,.38,.19,.86,vertical=True)
# Simple sculptural shrubs and stepping stones.
for x,y,s in [(-1.56,-.78,.29),(-1.60,-.44,.35),(1.58,.84,.34),(-1.55,.92,.28)]:
    sphere('Round garden shrub',(x,y,.40+s*.58),(s,s*.81,s),'Mint shade')
for x,y,s in [(-.60,-1.28,.19),(-.18,-1.33,.15)]:
    sphere('Cream path pebble',(x,y,.415),(s,s*.65,.047),'Ivory')
# Window plant, restrained and large enough to read on a phone.
box('Display plant pot',(-.08,-1.19,.97),(.23,.16,.23),'Cream',.05)
for dx,zz,ang in [(-.07,1.21,-.4),(.02,1.31,.1),(.10,1.19,.7)]:
    leaf=sphere('Display plant leaf',(-.08+dx,-1.19,zz),(.057,.042,.15),'Mint')
    leaf.rotation_euler[1]=ang

collection('BrushIcon')
box('Brush blue head',(0,0,.43),(1.12,.53,.27),'Blue',.13)
for row in range(2):
    for i in range(6):
        x=(i-2.5)*.164
        ob=box('Soft ivory bristle', (x,(row-.5)*.235,.21),(.173,.22,.40),'Cream',.075)
        ob.rotation_euler[1]=-x*.25
rod('Chunky blue handle',(0,.05,.50),(.10,.10,1.44),.135,'Blue')
sphere('Handle rounded end',(.10,.10,1.43),(.135,.135,.15),'Blue')
rod('Handle hole',(.105,-.03,1.35),(.105,-.046,1.35),.047,'Navy')

collection('BlueprintIcon')
box('Thick blue plan',(0,0,.71),(1.06,.14,1.23),'Blue',.07)
rod('Rolled left binding',(-.51,0,.08),(-.51,0,1.40),.12,'Window')
box('Plan cream border',(0,-.08,.74),(.78,.025,.91),'Cream',.025)
box('Plan blue inset',(0,-.10,.74),(.715,.022,.845),'Blue',.018)
tube('Drawn rug outline',[(-.23,-.13,.47),(.20,-.13,.47),(.20,-.13,1.02),(-.23,-.13,1.02),(-.23,-.13,.47)],.016,'Cream')
tube('Drawn rug chevron',[(-.2,-.14,.74),(-.07,-.14,.86),(.07,-.14,.64),(.18,-.14,.76)],.019,'Cream')
for x in [-.16,-.04,.08,.18]:
    tube('Drawn rug fringe',[(x,-.13,.42),(x,-.13,.48)],.012,'Cream')

collection('BonziIcon')
box('Robot cream body',(0,0,.65),(1.12,.79,.96),'Ivory',.27)
box('Robot dark face',(0,-.403,.72),(.85,.09,.53),'Robot face',.21)
for x in [-.20,.20]:
    tube('Happy eye',[(x+.085*math.cos(t),-.467,.71+.085*math.sin(t)) for t in [i*math.pi/16 for i in range(17)]],.025,'Blue')
rod('Top button',(0,0,1.12),(0,0,1.18),.16,'Blue')
for x in [-.56,.56]:
    rod('Side wheel',(x-.065,0,.32),(x+.065,0,.32),.24,'Navy')
    for i in range(3):
        box('Robot cleaning bristle',(x*.75+(i-1)*.1,-.30,.14),(.10,.25,.22),'Cream',.043)

collection('CoinIcon')
rod('Coin gold edge',(0,.045,.66),(0,-.09,.66),.58,'Gold shade',48)
rod('Coin gold face',(0,-.10,.66),(0,-.155,.66),.51,'Gold',48)
# Raised five-point star on the face.
star=[]
for i in range(10):
    t=math.pi/2+i*math.pi/5
    r=.32 if i%2==0 else .16
    star.append((math.cos(t)*r,-.194,.66+math.sin(t)*r))
mesh=bpy.data.meshes.new('Coin star')
mesh.from_pydata(star,[],[tuple(range(10))]); mesh.update()
ob=bpy.data.objects.new('Coin raised star',mesh); group.objects.link(ob); ob.data.materials.append(M['Cream'])
solid=ob.modifiers.new('Raised star depth','SOLIDIFY'); solid.thickness=.035
bevel=ob.modifiers.new('Soft star corners','BEVEL'); bevel.width=.025; bevel.segments=3
smooth(ob)

collection('SettingsIcon')
bpy.ops.mesh.primitive_torus_add(major_radius=.35,minor_radius=.12,major_segments=32,minor_segments=12,location=(0,0,.65),rotation=(math.pi/2,0,0))
finish(bpy.context.object,'Gear round hub','Window')
for i in range(8):
    t=i*math.tau/8
    box('Rounded gear tooth',(math.sin(t)*.43,0,.65+math.cos(t)*.43),(.20,.19,.26),'Window',.06,(0,t,0))

# Native meshes remain separate in the Blender source. Export copies are joined
# to reduce game draw calls to one surface per material rather than per object.
manifest={}
for name,col in assets.items():
    bpy.ops.object.select_all(action='DESELECT')
    copies=[]
    for original in list(col.objects):
        ob=original.copy(); ob.data=original.data.copy()
        bpy.context.scene.collection.objects.link(ob)
        ob.select_set(True); copies.append(ob)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.convert(target='MESH')
    bpy.ops.object.join()
    ob=bpy.context.object; ob.name=name
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    ob.data.calc_loop_triangles()
    manifest[name]={'triangles':len(ob.data.loop_triangles),'source_parts':len(col.objects),'file':name+'.glb'}
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_cameras=False,export_lights=False)
    bpy.data.objects.remove(ob,do_unlink=True)

# Studio camera and lighting used for transparent UI renders from actual assets.
studio=bpy.data.collections.new('Studio (not exported)'); bpy.context.scene.collection.children.link(studio)
group=studio
scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.samples=24; scene.cycles.use_denoising=True
scene.render.film_transparent=True
scene.world.use_nodes=True
scene.world.node_tree.nodes.get('Background').inputs[0].default_value=(.72,.81,.92,1)
scene.world.node_tree.nodes.get('Background').inputs[1].default_value=.5
scene.view_settings.view_transform='Standard'
scene.view_settings.look='Medium High Contrast'

def aim(ob,p):
    ob.rotation_euler=(Vector(p)-ob.location).to_track_quat('-Z','Y').to_euler()

for name,loc,power,size in [('Large softbox',(-3,-4,7),480,5),('Cool fill',(4,-1,5),180,4),('Roof rim',(0,4,6),300,3)]:
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size
    ob=bpy.data.objects.new(name,data); studio.objects.link(ob); ob.location=loc; aim(ob,(0,0,1))
data=bpy.data.cameras.new('Asset camera'); cam=bpy.data.objects.new('Asset camera',data); studio.objects.link(cam)
scene.camera=cam; data.type='ORTHO'
scene.render.image_settings.file_format='PNG'; scene.render.image_settings.color_mode='RGBA'
for name,col in assets.items():
    for asset in assets.values():
        asset.hide_render=asset!=col
    if name=='FloatingShop':
        cam.location=(6,-9,6.0); aim(cam,(0,0,1.6)); data.ortho_scale=5.55
        scene.render.resolution_x=768; scene.render.resolution_y=768
    else:
        cam.location=(2.1,-7,3.0); aim(cam,(0,0,.7)); data.ortho_scale=1.8
        if name in ['CoinIcon','SettingsIcon']:
            cam.location=(.25,-8,1.55); aim(cam,(0,0,.66)); data.ortho_scale=1.45
        scene.render.resolution_x=256; scene.render.resolution_y=256
    scene.render.resolution_percentage=100
    scene.render.filepath=str(OUT/(name+'.png'))
    bpy.ops.render.render(write_still=True)

# Open the source on the actual shop, other assets organized in hidden collections.
for name,col in assets.items():
    col.hide_render=name!='FloatingShop'
    col.hide_viewport=name!='FloatingShop'
cam.location=(6,-9,6.0); aim(cam,(0,0,1.6)); data.ortho_scale=5.55
scene.render.resolution_x=1024; scene.render.resolution_y=1024
bpy.ops.object.select_all(action='DESELECT')
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('FLOATING_SHOP_BUILD_COMPLETE '+json.dumps(manifest))
