"""Blender script: procedural Earth globe -> baked texture -> globe.usdz (+ preview PNG).

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/make_globe.py
Output: output/models/globe.usdz, globe_albedo.png, globe_preview.png
The app spins the model slowly (SceneKit); the texture is baked so no shader nodes are needed at runtime.
"""
import bpy, math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "output", "models")
OUT = os.path.abspath(OUT)
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 8

# --- sphere ---------------------------------------------------------------
bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=48, radius=1.0)
globe = bpy.context.active_object
globe.name = "Globe"
bpy.ops.object.shade_smooth()

# --- procedural material (used only for baking) ---------------------------
mat = bpy.data.materials.new("EarthProc")
mat.use_nodes = True
nt = mat.node_tree
nt.nodes.clear()
n = nt.nodes
l = nt.links
out = n.new("ShaderNodeOutputMaterial")
bsdf = n.new("ShaderNodeBsdfPrincipled")
tc = n.new("ShaderNodeTexCoord")
mp = n.new("ShaderNodeMapping")
mp.inputs["Scale"].default_value = (1.4, 1.4, 1.4)

def noise(scale, detail, rough, loc, dims="3D"):
    nd = n.new("ShaderNodeTexNoise")
    nd.noise_dimensions = dims
    nd.inputs["Scale"].default_value = scale
    nd.inputs["Detail"].default_value = detail
    nd.inputs["Roughness"].default_value = rough
    nd.location = loc
    l.new(mp.outputs["Vector"], nd.inputs["Vector"])
    return nd

continents = noise(2.2, 6, 0.55, (-600, 300))
detail = noise(9.0, 4, 0.6, (-600, 0))
clouds = noise(3.2, 7, 0.65, (-600, -300), dims="4D")
clouds.inputs["W"].default_value = 3.7

# land mask: continents + a little detail
add = n.new("ShaderNodeMath"); add.operation = "ADD"
l.new(continents.outputs["Fac"], add.inputs[0])
mul = n.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
mul.inputs[1].default_value = 0.12
l.new(detail.outputs["Fac"], mul.inputs[0])
l.new(mul.outputs["Value"], add.inputs[1])
land = n.new("ShaderNodeValToRGB")          # 0 ocean ... 1 land
land.color_ramp.elements[0].position = 0.585
land.color_ramp.elements[1].position = 0.605
l.new(add.outputs["Value"], land.inputs["Fac"])

# ocean: deep -> shallow by noise
ocean = n.new("ShaderNodeValToRGB")
ocean.color_ramp.elements[0].color = (0.01, 0.07, 0.30, 1)
ocean.color_ramp.elements[1].color = (0.03, 0.30, 0.62, 1)
l.new(continents.outputs["Fac"], ocean.inputs["Fac"])

# land: lowland green -> highland brown -> desert-ish by detail
landcol = n.new("ShaderNodeValToRGB")
landcol.color_ramp.elements[0].position = 0.35
landcol.color_ramp.elements[0].color = (0.10, 0.36, 0.10, 1)
landcol.color_ramp.elements[1].position = 0.75
landcol.color_ramp.elements[1].color = (0.52, 0.40, 0.20, 1)
l.new(detail.outputs["Fac"], landcol.inputs["Fac"])

mix_land = n.new("ShaderNodeMix"); mix_land.data_type = "RGBA"
l.new(land.outputs["Color"], mix_land.inputs["Factor"])
l.new(ocean.outputs["Color"], mix_land.inputs["A"])
l.new(landcol.outputs["Color"], mix_land.inputs["B"])

# polar ice: world-space Z
sep = n.new("ShaderNodeSeparateXYZ")
l.new(tc.outputs["Object"], sep.inputs["Vector"])
absz = n.new("ShaderNodeMath"); absz.operation = "ABSOLUTE"
l.new(sep.outputs["Z"], absz.inputs[0])
ice = n.new("ShaderNodeMapRange")
ice.inputs["From Min"].default_value = 0.86
ice.inputs["From Max"].default_value = 0.93
l.new(absz.outputs["Value"], ice.inputs["Value"])
mix_ice = n.new("ShaderNodeMix"); mix_ice.data_type = "RGBA"
l.new(ice.outputs["Result"], mix_ice.inputs["Factor"])
l.new(mix_land.outputs["Result"], mix_ice.inputs["A"])
mix_ice.inputs["B"].default_value = (0.93, 0.96, 1.0, 1)

# clouds (white wisps over everything)
cl = n.new("ShaderNodeMapRange")
cl.inputs["From Min"].default_value = 0.56
cl.inputs["From Max"].default_value = 0.72
cl.inputs["To Max"].default_value = 0.75
l.new(clouds.outputs["Fac"], cl.inputs["Value"])
mix_cl = n.new("ShaderNodeMix"); mix_cl.data_type = "RGBA"
l.new(cl.outputs["Result"], mix_cl.inputs["Factor"])
l.new(mix_ice.outputs["Result"], mix_cl.inputs["A"])
mix_cl.inputs["B"].default_value = (1, 1, 1, 1)

l.new(tc.outputs["Object"], mp.inputs["Vector"])
l.new(mix_cl.outputs["Result"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.65
l.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
globe.data.materials.append(mat)

# --- bake the albedo to an equirectangular image --------------------------
W, H = 2048, 1024
img = bpy.data.images.new("globe_albedo", W, H)
tex = n.new("ShaderNodeTexImage"); tex.image = img
nt.nodes.active = tex
scene.cycles.bake_type = "DIFFUSE"
scene.render.bake.use_pass_direct = False
scene.render.bake.use_pass_indirect = False
scene.render.bake.use_pass_color = True
bpy.ops.object.bake(type="DIFFUSE")
albedo_path = os.path.join(OUT, "globe_albedo.png")
img.filepath_raw = albedo_path
img.file_format = "PNG"
img.save()

# --- runtime material: just the baked image -------------------------------
rt = bpy.data.materials.new("Earth")
rt.use_nodes = True
rn = rt.node_tree.nodes
rl = rt.node_tree.links
rb = rn["Principled BSDF"]
rtex = rn.new("ShaderNodeTexImage")
rtex.image = bpy.data.images.load(albedo_path)
rl.new(rtex.outputs["Color"], rb.inputs["Base Color"])
rb.inputs["Roughness"].default_value = 0.6
globe.data.materials.clear()
globe.data.materials.append(rt)
globe.rotation_euler = (math.radians(0), 0, 0)

# --- export ---------------------------------------------------------------
bpy.ops.wm.usd_export(filepath=os.path.join(OUT, "globe.usdz"), export_materials=True,
                      generate_preview_surface=True, export_textures_mode="NEW")

# --- preview render --------------------------------------------------------
scene.render.engine = "BLENDER_EEVEE"
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = 768
cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
cam.location = (0, -3.2, 0.5); cam.rotation_euler = (math.radians(82), 0, 0)
scene.camera = cam
sun_data = bpy.data.lights.new("Sun", "SUN"); sun_data.energy = 4
sun = bpy.data.objects.new("Sun", sun_data)
sun.rotation_euler = (math.radians(55), 0, math.radians(35))
scene.collection.objects.link(sun)
scene.render.filepath = os.path.join(OUT, "globe_preview.png")
bpy.ops.render.render(write_still=True)
print("DONE", OUT)
