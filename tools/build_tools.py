"""Author the three starter tools and dry-soil assets using Blender's mesh API."""
import bpy, math, json
import numpy as np
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'CarpetToy/assets/tools'
DIRT=ROOT/'CarpetToy/assets/dirt'
OUT.mkdir(parents=True,exist_ok=True); DIRT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
COLORS=['72C8AB','308E7D','F8EED4','F58C74','F4C45F','344E55','B4DBD1','B88B50']
def rgb(h): return np.array([int(h[i:i+2],16)/255 for i in (0,2,4)])
palette=np.ones((8,64,4),np.float32)
for i,h in enumerate(COLORS): palette[:,i*8:(i+1)*8,:3]=rgb(h)
im=bpy.data.images.new('Starter tools palette',width=64,height=8,alpha=True)
im.pixels.foreach_set(palette.ravel()); im.filepath_raw=str(OUT/'tool_palette.png'); im.file_format='PNG'; im.save(); im.pack()
mat=bpy.data.materials.new('Starter kit • matte palette'); mat.use_nodes=True
bs=mat.node_tree.nodes.get('Principled BSDF'); bs.inputs['Roughness'].default_value=.86; bs.inputs['Specular IOR Level'].default_value=.18
tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=im; tex.interpolation='Closest'; mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
parts=[]; assets=[]; manifest={}
def finish(ob,name,ci):
    ob.name=name; ob.data.materials.clear(); ob.data.materials.append(mat)
    uv=ob.data.uv_layers.get('UVMap') or ob.data.uv_layers.new(name='UVMap')
    for loop in uv.data: loop.uv=((ci+.5)/8,.5)
    parts.append(ob); return ob
def box(name,loc,size,ci,bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); ob=bpy.context.object; ob.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    mod=ob.modifiers.new('Soft toy edges','BEVEL'); mod.width=bevel; mod.segments=1 if name=='Bristle tuft' else 2
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in ob.data.polygons: p.use_smooth=True
    mod=ob.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL'); mod.keep_sharp=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(ob,name,ci)
def rod(name,a,b,r,ci,vertices=12):
    mid=(Vector(a)+Vector(b))/2; direction=Vector(b)-Vector(a)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=direction.length,location=mid)
    ob=bpy.context.object; ob.rotation_euler=direction.to_track_quat('Z','Y').to_euler()
    for p in ob.data.polygons: p.use_smooth=len(p.vertices)==4
    return finish(ob,name,ci)
def tool_export(name):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts: ob.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join(); ob=bpy.context.object
    bpy.context.scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    ob.name=name; ob.data.calc_loop_triangles()
    manifest[name]={'triangles':len(ob.data.loop_triangles),'mesh_surfaces':1,'palette':'64x8 shared colors','up':'Godot Y','pivot':'head contact / nozzle contact'}
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True)
    assets.append(ob); parts.clear(); return ob

# Broad scrub brush: grouped bristles, split color tips, socket and chunky grip.
box('Brush head',(0,0,.17),(.78,.27,.16),0,.06)
box('Ivory bumper',(0,-.007,.113),(.79,.28,.045),2,.018)
for row in range(3):
    for col in range(12):
        xx=(col-5.5)*.06; yy=(row-1)*.084
        box('Bristle tuft',(xx,yy,.053),(.043,.055,.092),7 if (col+row)%3==0 else 4,.007)
rod('Socket',(0,.04,.2),(0,.13,.35),.074,1)
rod('Shaft',(0,.10,.25),(0,.59,1.42),.035,2)
rod('Grip',(0,.51,1.23),(0,.64,1.54),.052,0)
rod('Grip cap',(0,.63,1.52),(0,.66,1.59),.058,1)
for t in [.78,.83,.88]:
    a=Vector((0,.51,1.23)).lerp(Vector((0,.64,1.54)),t)
    rod('Grip band',a,a+Vector((0,.011,.024)),.053,1)
brush=tool_export('large_brush')

# Wide squeegee: coral housing, a visibly thin rubber blade and a long ivory shaft.
box('Rubber blade',(0,-.025,.031),(.85,.055,.062),5,.012)
box('Blade backing',(0,.003,.09),(.88,.17,.12),3,.04)
box('Blade accent',(0,-.084,.10),(.63,.016,.043),2,.012)
rod('Swivel',(0,.02,.10),(0,.02,.23),.075,1)
rod('Shaft',(0,.02,.20),(0,.53,1.40),.033,2)
rod('Coral grip',(0,.46,1.23),(0,.60,1.56),.05,3)
rod('End cap',(0,.59,1.53),(0,.62,1.60),.055,1)
squeegee=tool_export('squeegee')

# Handheld jet sprayer, chunky pistol grip and clearly readable nozzle/trigger.
rod('Lance',(0,-.05,.24),(0,-.53,.24),.035,2)
rod('Nozzle collar',(0,-.46,.24),(0,-.60,.24),.065,1)
rod('Jet nozzle',(0,-.60,.24),(0,-.68,.24),.079,4)
rod('Dark outlet',(0,-.681,.24),(0,-.689,.24),.050,5)
box('Sprayer body',(0,.08,.24),(.21,.36,.21),0,.07)
box('Top shell',(0,.075,.355),(.15,.25,.06),6,.025)
grip=box('Pistol grip',(0,.26,.10),(.125,.14,.31),1,.035); grip.rotation_euler[0]=-.28
box('Grip inlay',(0,.325,.085),(.09,.04,.14),0,.018)
box('Trigger',(0,.10,.09),(.054,.057,.14),4,.013)
box('Trigger guard lower',(0,.13,-.005),(.09,.21,.045),1,.016)
rod('Hose quick connector',(0,.31,-.07),(0,.33,-.145),.052,4)
jet=tool_export('jet_spray')

# One 20-triangle pebble-like soil crumb for GPU instancing.
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1)
clump=bpy.context.object; clump.name='soil_clump'
for v in clump.data.vertices:
    v.co.x*=1+.1*math.sin(v.index*3.1); v.co.y*=.82
    v.co.z=(v.co.z+1)*.34
for p in clump.data.polygons: p.use_smooth=True
bpy.ops.object.select_all(action='DESELECT'); clump.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(DIRT/'soil_clump.glb'),export_format='GLB',use_selection=True)
clump.hide_render=True; clump.hide_set(True)

# Bake all soil texture work offline: broad mottles + fine grit, no runtime noise loops.
W,H=512,768
x,y=np.meshgrid(np.linspace(-1,1,W),np.linspace(-1.5,1.5,H))
rng=np.random.default_rng(421)
h=np.zeros((H,W),np.float32)
for _ in range(55):
    xx,yy=rng.uniform(-1,1),rng.uniform(-1.5,1.5); r=rng.uniform(.045,.32)
    h+=rng.uniform(-.45,.6)*np.exp(-((x-xx)**2+(y-yy)**2)/(r*r))
h=(h-h.min())/(h.max()-h.min())
base=rgb('A88762')[None,None,:]+(h[...,None]-.5)*np.array([.14,.12,.09])
for _ in range(450):
    xx,yy=rng.uniform(-1,1),rng.uniform(-1.5,1.5); r=rng.uniform(.003,.016)
    mask=((x-xx)/r)**2+((y-yy)/(r*.65))**2<1
    base[mask]*=rng.choice([.74,.85,1.10])
base+=rng.uniform(-.008,.008,(H,W,1))
def save(name,pixels,noncolor=False):
    im=bpy.data.images.new(name,width=W,height=H,alpha=True)
    im.colorspace_settings.name='Non-Color' if noncolor else 'sRGB'
    a=np.ones((H,W,4),np.float32); a[:,:,:3]=np.clip(pixels,0,1)
    im.pixels.foreach_set(a.ravel()); im.filepath_raw=str(DIRT/(name+'.png')); im.file_format='PNG'; im.save(); im.pack()
save('dry_soil_albedo',base)
gy,gx=np.gradient(h)
n=np.stack([-gx*12,-gy*12,np.ones_like(h)],axis=-1); n/=np.linalg.norm(n,axis=-1)[...,None]
save('dry_soil_normal',n*.5+.5,True)

# Edit-friendly source assembly and a single studio render.
for ob,xx in zip(assets,[-1.15,0,1.05]): ob.location.x=xx
scene=bpy.context.scene
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.16)); ground=bpy.context.object
gm=bpy.data.materials.new('Studio mist'); gm.diffuse_color=(.69,.80,.74,1); ground.data.materials.append(gm)
def aim(ob,p): ob.rotation_euler=(Vector(p)-ob.location).to_track_quat('-Z','Y').to_euler()
for loc,power,size in [((-3,-4,6),450,5),((4,1,4),150,4)]:
    bpy.ops.object.light_add(type='AREA',location=loc); ob=bpy.context.object; ob.data.energy=power; ob.data.size=size; aim(ob,(0,0,.5))
bpy.ops.object.camera_add(location=(3,-5,3.1)); cam=bpy.context.object; cam.data.type='ORTHO'; cam.data.ortho_scale=4.3; aim(cam,(0,0,.65)); scene.camera=cam
scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True; scene.world.color=(.3,.3,.3)
scene.view_settings.view_transform='Standard'; scene.render.resolution_x=1300; scene.render.resolution_y=950; scene.render.resolution_percentage=100
scene.render.filepath=str(ROOT/'art/renders/starter_tools_blender.png')
for screen in bpy.data.screens:
    for a in screen.areas:
        if a.type=='VIEW_3D': a.spaces.active.region_3d.view_perspective='CAMERA'; a.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/starter_tools.blend'))
(ROOT/'art/tools_manifest.json').write_text(json.dumps(manifest,indent=2))
print(json.dumps(manifest)); bpy.ops.render.render(write_still=True)
