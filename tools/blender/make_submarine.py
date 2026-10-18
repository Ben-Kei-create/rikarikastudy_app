"""Blender script: brass-and-steel exploration submersible -> submarine.usdz (+ preview PNG).

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/make_submarine.py
Nose points to +X; the app can rotate / bob it. Windows and the searchlight are emissive.
"""
import bpy, math, os

OUT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "output", "models"))
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

def material(name, color, metallic=0.0, rough=0.5, emit=None, strength=0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = emit
        b.inputs["Emission Strength"].default_value = strength
    return m

brass = material("Brass", (0.72, 0.48, 0.16, 1), 1.0, 0.32)
steel = material("Steel", (0.30, 0.34, 0.38, 1), 0.9, 0.45)
dark = material("Dark", (0.05, 0.06, 0.07, 1), 0.3, 0.6)
glass = material("Window", (1, 0.82, 0.45, 1), 0.0, 0.2, emit=(1.0, 0.78, 0.35, 1), strength=4)
lamp = material("Lamp", (1, 1, 0.9, 1), 0.0, 0.2, emit=(0.85, 0.95, 1.0, 1), strength=12)

def add(obj, mat, name):
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj

# hull: capsule = cylinder + two caps
bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.55, depth=1.8, rotation=(0, math.radians(90), 0))
hull = add(bpy.context.active_object, brass, "Hull")
for sx in (-1, 1):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=0.55, location=(sx * 0.9, 0, 0))
    add(bpy.context.active_object, brass, f"Cap{sx}")
# reinforcing steel bands
for x in (-0.6, -0.2, 0.2, 0.6):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.555, minor_radius=0.035, location=(x, 0, 0),
                                     rotation=(0, math.radians(90), 0), major_segments=48, minor_segments=12)
    add(bpy.context.active_object, steel, f"Band{x}")
# conning tower + periscope
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.2, depth=0.35, location=(0.05, 0, 0.66))
add(bpy.context.active_object, steel, "Tower")
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.035, depth=0.4, location=(0.12, 0, 0.98))
add(bpy.context.active_object, steel, "Periscope")
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.03, depth=0.14, location=(0.2, 0, 1.12), rotation=(0, math.radians(90), 0))
add(bpy.context.active_object, steel, "PeriscopeHead")
# round windows along the side
for i, x in enumerate((0.55, 0.2, -0.15)):
    for sy in (-1, 1):
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.095, depth=0.06,
                                            location=(x, sy * 0.535, 0.12), rotation=(math.radians(90), 0, 0))
        add(bpy.context.active_object, glass, f"Window{i}{sy}")
        bpy.ops.mesh.primitive_torus_add(major_radius=0.105, minor_radius=0.022, location=(x, sy * 0.54, 0.12),
                                         rotation=(math.radians(90), 0, 0), major_segments=32, minor_segments=10)
        add(bpy.context.active_object, steel, f"Rim{i}{sy}")
# front viewport dome
bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=0.22, location=(1.36, 0, 0.05))
add(bpy.context.active_object, glass, "FrontPort")
# searchlight on the nose
bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.12, radius2=0.05, depth=0.2, location=(1.2, 0, -0.32),
                                rotation=(0, math.radians(90), 0))
add(bpy.context.active_object, steel, "LampHousing")
bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.07, location=(1.32, 0, -0.32))
add(bpy.context.active_object, lamp, "Lamp")
# tail: fins + propeller
for ang in (0, 90, 180, 270):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(-1.35, 0, 0), scale=(0.24, 0.02, 0.28))
    fin = bpy.context.active_object
    fin.location = (-1.28, math.sin(math.radians(ang)) * 0.4, math.cos(math.radians(ang)) * 0.4)
    fin.rotation_euler = (math.radians(ang), 0, 0)
    add(fin, steel, f"Fin{ang}")
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.07, depth=0.16, location=(-1.52, 0, 0), rotation=(0, math.radians(90), 0))
add(bpy.context.active_object, dark, "Hub")
for k in range(4):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(-1.6, 0, 0), scale=(0.02, 0.07, 0.3))
    bl = bpy.context.active_object
    bl.location = (-1.6, math.sin(math.radians(k * 90)) * 0.18, math.cos(math.radians(k * 90)) * 0.18)
    bl.rotation_euler = (math.radians(k * 90), 0, math.radians(18))
    add(bl, steel, f"Blade{k}")

# slight nose-down tilt looks like it is diving
for o in scene.objects:
    o.select_set(True)
bpy.ops.object.join() if False else None

bpy.ops.wm.usd_export(filepath=os.path.join(OUT, "submarine.usdz"), export_materials=True,
                      generate_preview_surface=True)

scene.render.engine = "BLENDER_EEVEE"
scene.render.film_transparent = True
scene.render.resolution_x, scene.render.resolution_y = 1024, 640
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scene.collection.objects.link(cam)
cam.location = (3.6, -4.2, 1.5); cam.rotation_euler = (math.radians(76), 0, math.radians(40))
scene.camera = cam
key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "AREA"))
key.data.energy = 600; key.data.size = 4
key.location = (2, -3, 4); key.rotation_euler = (math.radians(40), 0, math.radians(25))
scene.collection.objects.link(key)
fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
fill.data.energy = 1.5; fill.rotation_euler = (math.radians(60), 0, math.radians(-120))
scene.collection.objects.link(fill)
scene.render.filepath = os.path.join(OUT, "submarine_preview.png")
bpy.ops.render.render(write_still=True)
print("DONE", OUT)
