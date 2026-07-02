"""Procedural 3D render of the Threkir marks (marketing / press / web hero).

NOT the app-icon pipeline — the packaged icons are flat and come from
assets/icon.svg via assets/gen-icons.sh (see decisions.md §193). This script
produces the dimensional, ray-traced hero renders used for store listings and
splash art.

Each mark is built as a mesh directly from its path geometry (no SVG import —
Blender's curve fill mishandles the compound thorn counter), extruded, bevelled,
and rendered in Cycles on the GPU (OptiX) with the brand ember->magenta gradient
as an emissive-tinted material on a transparent film.

Run (headless):
    blender --background --python assets/logo-render/render.py
    MARKS=thorn SAMPLES=300 RES=1600 blender -b --python assets/logo-render/render.py

Output: assets/logo-render/out/<mark>_3d.png (gitignored; regenerate on demand).
Requires: Blender 5.x with a CUDA/OptiX GPU (falls back to whatever Cycles finds).
"""
import bpy, bmesh, os, math
from mathutils import Vector

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, "out")
os.makedirs(OUT, exist_ok=True)

MARKS = os.environ.get("MARKS", "thorn,stave,loop,ridge").split(",")
SAMPLES = int(os.environ.get("SAMPLES", "240"))
RES = int(os.environ.get("RES", "1500"))

def srgb(c):
    return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
EMBER = tuple(srgb(c) for c in (0.996, 0.235, 0.129)) + (1.0,)     # #FE5932
MAGENTA = tuple(srgb(c) for c in (0.627, 0.055, 0.427)) + (1.0,)   # #A01E77

# ---------- geometry (SVG 100x100 space, y-down) ----------
def arc(cx, cy, r, a0, a1, n, endpoint=True):
    pts, steps = [], (n-1) if endpoint else n
    for i in range(n):
        a = math.radians(a0 + (a1-a0)*(i/steps))
        pts.append((cx + r*math.cos(a), cy + r*math.sin(a)))
    return pts

def thorn():
    # matches the shipped assets/icon.svg thorn (balanced ascender/descender)
    outer = ([(30,10),(44,10),(44,29),(58,29)] + arc(58,50,21,-90,90,18)[1:-1]
             + [(58,71),(44,71),(44,90),(30,90)])
    hole = [(44,42),(56,42)] + arc(56,50,8,-90,90,12)[1:-1] + [(56,58),(44,58)]
    return [[outer, hole]]

def stave():
    return [[[(33,8),(43,8),(43,22),(78,41),(43,60),(43,92),(33,92)]]]

def loop():
    return [[arc(50,50,32,0,360,64,endpoint=False), arc(50,50,19,0,360,48,endpoint=False)],
            [[(45,13),(55,13),(55,37),(45,37)]]]

def ridge():
    return [[[(10,82),(10,60),(26,70),(40,44),(56,58),(72,28),(90,40),(90,82)]],
            [arc(72,16,6.5,0,360,32,endpoint=False)]]

SHAPES = {"thorn": thorn, "stave": stave, "loop": loop, "ridge": ridge}

def build_mesh(name, thickness=0.26):
    shapes = SHAPES[name]()
    allpts = [p for sh in shapes for loop in sh for p in loop]
    xs = [p[0] for p in allpts]; ys = [p[1] for p in allpts]
    cx = (min(xs)+max(xs))/2; cy = (min(ys)+max(ys))/2
    scale = 2.0 / max(max(xs)-min(xs), max(ys)-min(ys))
    NX = lambda x: (x-cx)*scale
    NZ = lambda y: -(y-cy)*scale
    bm = bmesh.new()
    for sh in shapes:
        edges = []
        for loop in sh:
            vs = [bm.verts.new((NX(x), 0.0, NZ(y))) for (x, y) in loop]
            L = len(vs)
            for i in range(L):
                edges.append(bm.edges.new((vs[i], vs[(i+1) % L])))
        # triangle_fill respects inner loops as holes (the thorn counter)
        bmesh.ops.triangle_fill(bm, edges=edges, use_beauty=True, use_dissolve=False)
    faces = [f for f in bm.faces]
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    bmesh.ops.solidify(bm, geom=faces, thickness=thickness)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    obj = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS"); obj.location = (0, 0, 0)
    bev = obj.modifiers.new("bevel", "BEVEL")
    bev.width = 0.02; bev.segments = 3; bev.limit_method = "ANGLE"; bev.angle_limit = math.radians(35)
    bpy.ops.object.modifier_apply(modifier="bevel")
    return obj

def gradient_material():
    mat = bpy.data.materials.new("grad"); mat.use_nodes = True
    nt = mat.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.32
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping"); mp.inputs["Rotation"].default_value = (0, 0, math.radians(50))
    grad = nt.nodes.new("ShaderNodeTexGradient")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    # warm: ember holds ~58% of the sweep, magenta only blooms in the far corner
    e = ramp.color_ramp.elements
    e[0].position = 0.0; e[0].color = EMBER
    e[1].position = 1.0; e[1].color = MAGENTA
    hold = ramp.color_ramp.elements.new(0.58); hold.color = EMBER
    nt.links.new(tc.outputs["Generated"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], grad.inputs["Vector"])
    nt.links.new(grad.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.32
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat

def area(loc, energy, size, color, target):
    ld = bpy.data.lights.new("l", "AREA"); ld.energy = energy; ld.size = size; ld.color = color
    o = bpy.data.objects.new("l", ld); bpy.context.collection.objects.link(o); o.location = loc
    c = o.constraints.new("TRACK_TO"); c.target = target
    c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"

def setup_gpu():
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    try: prefs.refresh_devices()
    except Exception: pass
    for d in prefs.devices:
        d.use = d.type in ("OPTIX", "CUDA")

def render_one(name, mat):
    bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.delete()
    obj = build_mesh(name)
    obj.data.materials.append(mat)
    obj.rotation_euler = (math.radians(7), 0, math.radians(-20))

    tgt = bpy.data.objects.new("t", None); bpy.context.collection.objects.link(tgt); tgt.location = (0, 0, 0)
    area((2.6, -3.0, 3.4), 260, 5.0, (1.0, 0.96, 0.92), tgt)
    area((-3.0, -2.0, 1.0), 70, 6.0, (0.85, 0.88, 1.0), tgt)
    area((-1.8, 2.6, 2.4), 320, 3.0, (1.0, 0.9, 0.95), tgt)

    cd = bpy.data.cameras.new("c"); cd.type = "ORTHO"; cd.ortho_scale = 3.0
    cam = bpy.data.objects.new("c", cd); bpy.context.collection.objects.link(cam); cam.location = (0, -6.0, 0)
    cc = cam.constraints.new("TRACK_TO"); cc.target = tgt
    cc.track_axis = "TRACK_NEGATIVE_Z"; cc.up_axis = "UP_Y"
    bpy.context.scene.camera = cam

    w = bpy.data.worlds.new("w"); w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.03, 0.02, 0.045, 1.0); bg.inputs[1].default_value = 0.5
    bpy.context.scene.world = w

    sc = bpy.context.scene
    sc.render.engine = "CYCLES"; sc.cycles.device = "GPU"; sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    try: sc.cycles.denoiser = "OPTIX"
    except Exception: pass
    sc.render.resolution_x = RES; sc.render.resolution_y = RES
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.render.filepath = os.path.join(OUT, f"{name}_3d.png")
    bpy.ops.render.render(write_still=True)

setup_gpu()
mat = gradient_material()
for name in MARKS:
    print("== rendering", name)
    render_one(name, mat)
print("DONE")
