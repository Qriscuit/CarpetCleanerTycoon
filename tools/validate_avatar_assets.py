"""Validate the exported player character GLBs using Python's standard library.

Run with Python 3: python tools/validate_avatar_assets.py
The body must be one continuous closed surface, rather than separate parts
joined into a single Blender object. Normal/material seam vertices are welded
by position before topology is checked. No source .blend or manifest geometry
counts are trusted as a substitute for reading the actual exported triangles.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from itertools import product
import json
import math
from pathlib import Path
import struct
import sys


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
              5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


class InvalidAsset(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidAsset(message)


def close_values(actual, expected, tolerance=2e-5):
    return len(actual) == len(expected) and all(
        math.isfinite(a) and math.isfinite(b) and abs(a - b) <= tolerance
        for a, b in zip(actual, expected))


class Glb:
    def __init__(self, path):
        self.path = path
        data = path.read_bytes()
        self.file_bytes = len(data)
        require(len(data) >= 20, "GLB header is truncated")
        magic, version, size = struct.unpack_from("<4sII", data)
        require(magic == b"glTF" and version == 2, "Expected a glTF 2 binary file")
        require(size == len(data), "GLB declared length differs from its actual length")
        chunks = []
        offset = 12
        while offset < len(data):
            require(offset + 8 <= len(data), "GLB chunk header is truncated")
            length, kind = struct.unpack_from("<II", data, offset)
            offset += 8
            require(length % 4 == 0 and offset + length <= len(data), "GLB chunk exceeds its buffer")
            chunks.append((kind, data[offset:offset + length]))
            offset += length
        require([kind for kind, _ in chunks] == [0x4E4F534A, 0x004E4942],
                "Expected one JSON chunk followed by one embedded binary chunk")
        self.doc = json.loads(chunks[0][1].decode("utf-8"))
        self.binary = chunks[1][1]
        require(self.doc.get("asset", {}).get("version") == "2.0", "glTF asset version differs")
        buffers = self.doc.get("buffers", [])
        require(len(buffers) == 1 and "uri" not in buffers[0], "All geometry must be embedded")
        self.buffer_length = buffers[0]["byteLength"]
        require(0 <= len(self.binary) - self.buffer_length <= 3, "Embedded buffer length is invalid")

    def accessor(self, index):
        accessors = self.doc.get("accessors", [])
        require(isinstance(index, int) and 0 <= index < len(accessors), "Invalid accessor index")
        accessor = accessors[index]
        require("sparse" not in accessor, "Sparse accessors are outside this export contract")
        require(accessor.get("componentType") in COMPONENTS and accessor.get("type") in WIDTHS,
                "Unsupported accessor component/type")
        views = self.doc.get("bufferViews", [])
        view_index = accessor.get("bufferView", -1)
        require(isinstance(view_index, int) and 0 <= view_index < len(views), "Invalid buffer view")
        view = views[view_index]
        require(view.get("buffer", 0) == 0, "Accessor uses an external buffer")
        component_format, component_bytes = COMPONENTS[accessor["componentType"]]
        width = WIDTHS[accessor["type"]]
        element_bytes = component_bytes * width
        stride = view.get("byteStride", element_bytes)
        count = accessor.get("count", 0)
        start = view.get("byteOffset", 0)
        length = view["byteLength"]
        inner = accessor.get("byteOffset", 0)
        require(isinstance(count, int) and count > 0, "Empty or invalid accessor count")
        require(start >= 0 and length >= 0 and start + length <= self.buffer_length,
                "Buffer view exceeds embedded geometry")
        require(inner >= 0 and stride >= element_bytes and stride % component_bytes == 0,
                "Invalid accessor offset/stride")
        require(inner + (count - 1) * stride + element_bytes <= length, "Accessor exceeds its buffer view")
        decoder = struct.Struct("<" + component_format * width)
        values = [decoder.unpack_from(self.binary, start + inner + i * stride) for i in range(count)]
        require(all(math.isfinite(v) for item in values for v in item), "Accessor contains non-finite values")
        return values, accessor

    def geometry(self):
        nodes = self.doc.get("nodes", [])
        meshes = self.doc.get("meshes", [])
        scenes = self.doc.get("scenes", [])
        require(len(nodes) == len(meshes) == len(scenes) == 1,
                "Each item must export one mesh node and one scene")
        node = nodes[0]
        require(node.get("mesh") == 0 and scenes[0].get("nodes") == [0], "Exported mesh root differs")
        for field, identity in [("translation", [0, 0, 0]), ("rotation", [0, 0, 0, 1]),
                                ("scale", [1, 1, 1]), ("matrix", IDENTITY)]:
            require(close_values(node.get(field, identity), identity, 1e-7),
                    f"Root {field} must be identity so hats share the body's origin")
        require(not node.get("children") and "skin" not in node, "Unexpected child/skin in static item")
        materials = self.doc.get("materials", [])
        positions, triangles, used_materials = [], [], set()
        primitives = meshes[0].get("primitives", [])
        require(primitives, "Mesh has no material surfaces")
        for primitive in primitives:
            require(primitive.get("mode", 4) == 4, "Every primitive must contain triangles")
            require(not primitive.get("targets"), "Unexpected shape-key geometry")
            material = primitive.get("material", -1)
            require(isinstance(material, int) and 0 <= material < len(materials), "Invalid material reference")
            used_materials.add(material)
            attributes = primitive.get("attributes", {})
            require("POSITION" in attributes and "NORMAL" in attributes, "Position/normal attributes are required")
            vertices, position_info = self.accessor(attributes["POSITION"])
            require(position_info["type"] == "VEC3" and position_info["componentType"] == 5126,
                    "Positions must be three float components")
            for attribute, accessor_index in attributes.items():
                values, attribute_info = self.accessor(accessor_index)
                require(len(values) == len(vertices), f"{attribute} count differs from the vertex count")
                if attribute == "NORMAL":
                    require(attribute_info["type"] == "VEC3", "Normals must have three components")
                    require(all(0.98 <= sum(v * v for v in normal) <= 1.02 for normal in values),
                            "Vertex normals must be finite unit vectors")
            require("COLOR_0" not in attributes, "Base body/item color must come from tintable materials")
            if "indices" in primitive:
                index_values, info = self.accessor(primitive["indices"])
                require(info["type"] == "SCALAR" and info["componentType"] in (5121, 5123, 5125)
                        and not info.get("normalized", False), "Triangle indices must be unsigned integers")
                indices = [item[0] for item in index_values]
            else:
                indices = list(range(len(vertices)))
            require(len(indices) % 3 == 0, "Triangle index count is not divisible by three")
            require(all(0 <= index < len(vertices) for index in indices), "Triangle index is out of range")
            base = len(positions)
            positions.extend(vertices)
            triangles.extend(tuple(base + index for index in indices[i:i + 3])
                             for i in range(0, len(indices), 3))
        require(triangles and len(used_materials) == len(materials), "Empty mesh or unused exported material")
        for triangle in triangles:
            a, b, c = (positions[i] for i in triangle)
            u, v = ([b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)])
            cross = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
            require(sum(value * value for value in cross) > 1e-18, "Export contains a degenerate triangle")
        used_positions = [positions[i] for triangle in triangles for i in triangle]
        return positions, triangles, {
            "triangles": len(triangles), "material_surfaces": len(primitives),
            "bounds_min": [min(p[axis] for p in used_positions) for axis in range(3)],
            "bounds_max": [max(p[axis] for p in used_positions) for axis in range(3)],
            "file_bytes": self.file_bytes,
        }


def topology(positions, triangles, tolerance=1e-6):
    buckets, welded, remap = defaultdict(list), [], []
    neighbors = list(product((-1, 0, 1), repeat=3))
    for point in positions:
        cell = tuple(math.floor(axis / tolerance) for axis in point)
        candidate = None
        for offset in neighbors:
            for index in buckets[tuple(cell[axis] + offset[axis] for axis in range(3))]:
                if sum((point[axis] - welded[index][axis]) ** 2 for axis in range(3)) <= tolerance ** 2:
                    candidate = index
                    break
            if candidate is not None:
                break
        if candidate is None:
            candidate = len(welded)
            welded.append(point)
            buckets[cell].append(candidate)
        remap.append(candidate)
    parent = list(range(len(welded)))

    def find(vertex):
        while parent[vertex] != vertex:
            parent[vertex] = parent[parent[vertex]]
            vertex = parent[vertex]
        return vertex

    edges, directions, faces, used = Counter(), Counter(), Counter(), set()
    vertex_links = defaultdict(list)
    for original in triangles:
        triangle = tuple(remap[i] for i in original)
        require(len(set(triangle)) == 3, "Position welding collapses a degenerate body triangle")
        faces[tuple(sorted(triangle))] += 1
        used.update(triangle)
        a, b, c = triangle
        vertex_links[a].append((b, c))
        vertex_links[b].append((c, a))
        vertex_links[c].append((a, b))
        for a, b in zip(triangle, triangle[1:] + triangle[:1]):
            parent[find(a)] = find(b)
            edge = (min(a, b), max(a, b))
            edges[edge] += 1
            directions[edge] += 1 if a < b else -1
    nonmanifold_vertices = 0
    for link_edges in vertex_links.values():
        link = defaultdict(set)
        for a, b in link_edges:
            link[a].add(b)
            link[b].add(a)
        visited, pending = set(), [next(iter(link))]
        while pending:
            neighbor = pending.pop()
            if neighbor not in visited:
                visited.add(neighbor)
                pending.extend(link[neighbor] - visited)
        # Two closed shells touching only at one vertex have watertight edges
        # but no manifold surface at that vertex. Its link is two cycles.
        if len(visited) != len(link) or any(len(adjacent) != 2 for adjacent in link.values()):
            nonmanifold_vertices += 1
    return {
        "welded_vertices": len(used),
        "connected_components": len({find(i) for i in used}),
        "boundary_edges": sum(count == 1 for count in edges.values()),
        "nonmanifold_edges": sum(count != 2 for count in edges.values()),
        "nonmanifold_vertices": nonmanifold_vertices,
        "inconsistent_edges": sum(count == 2 and directions[edge] != 0 for edge, count in edges.items()),
        "duplicate_faces": sum(count - 1 for count in faces.values()),
    }


def validate(folder):
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    errors, records = [], {}
    for name in ("avatar.glb", "pirate_hat.glb", "beanie.glb"):
        try:
            glb = Glb(folder / name)
            positions, triangles, record = glb.geometry()
            records[name] = record
            declared = manifest["assets"][name]
            for field in ("triangles", "material_surfaces", "file_bytes"):
                require(record[field] == declared[field], f"Manifest {field} differs from the binary GLB")
            for field in ("bounds_min", "bounds_max"):
                require(close_values(record[field], declared[field]), f"Manifest {field} differs from exported positions")
            if name == "avatar.glb":
                require(record["material_surfaces"] == len(glb.doc["materials"]) == 1,
                        "The body must have one tintable material surface")
                material = glb.doc["materials"][0]
                pbr = material.get("pbrMetallicRoughness", {})
                require(close_values(pbr.get("baseColorFactor", [1, 1, 1, 1]), [1, 1, 1, 1], 1e-6),
                        "The body material must be white before runtime tint")
                require(not glb.doc.get("images") and not glb.doc.get("textures")
                        and "baseColorTexture" not in pbr and material.get("alphaMode", "OPAQUE") == "OPAQUE",
                        "The body must be opaque and have no baked color textures")
                record.update(topology(positions, triangles))
                require(record["connected_components"] == 1,
                        f"Body has {record['connected_components']} disconnected surfaces; joining objects is insufficient")
                require(record["nonmanifold_edges"] == 0 and record["nonmanifold_vertices"] == 0 and record["inconsistent_edges"] == 0
                        and record["duplicate_faces"] == 0, "Body surface must be watertight with consistent winding")
                for field in ("connected_components", "nonmanifold_edges", "nonmanifold_vertices", "boundary_edges"):
                    if field in declared:
                        require(record[field] == declared[field], f"Manifest {field} differs from exported topology")
                if "vertices" in declared:
                    require(record["welded_vertices"] == declared["vertices"], "Manifest vertices differ from welded exported positions")
        except (InvalidAsset, OSError, KeyError, TypeError, ValueError, struct.error) as exc:
            errors.append(f"{name}: {exc}")
    if len(records) == 3:
        body = records["avatar.glb"]
        body_height = body["bounds_max"][1] - body["bounds_min"][1]
        if not 1.5 <= body_height <= 3.5 or abs(body["bounds_min"][1]) > 2e-4:
            errors.append("Body must be authored at the agreed humanoid scale with feet at Y=0")
        for name in ("pirate_hat.glb", "beanie.glb"):
            hat = records[name]
            low, high = hat["bounds_min"], hat["bounds_max"]
            head_top = body["bounds_max"][1]
            if not (head_top - 0.55 <= low[1] <= head_top + 0.01
                    and head_top <= high[1] <= head_top + 0.55
                    and abs((low[0] + high[0]) * 0.5) <= body_height * 0.05
                    and 0.15 < high[0] - low[0] <= body_height * 0.8
                    and max(abs(low[2]), abs(high[2])) <= body_height * 0.4):
                errors.append(f"{name}: bounds do not place the hat sensibly above the shared-origin head")
        equipped_triangles = body["triangles"] + max(records[name]["triangles"] for name in ("pirate_hat.glb", "beanie.glb"))
        equipped_surfaces = body["material_surfaces"] + max(records[name]["material_surfaces"] for name in ("pirate_hat.glb", "beanie.glb"))
        if equipped_triangles > 4000 or equipped_surfaces > 3:
            errors.append(f"Equipped budget exceeded: {equipped_triangles} triangles / {equipped_surfaces} surfaces")
        if equipped_triangles != manifest.get("equipped_max_triangles") or equipped_surfaces != manifest.get("equipped_max_material_surfaces"):
            errors.append("Manifest equipped maximum counts differ from the actual exported assets")
    for name, record in records.items():
        print(f"{name}: " + json.dumps(record, sort_keys=True))
    for error in errors:
        print("FAIL: " + error, file=sys.stderr)
    print(f"AVATAR_ASSET_VALIDATION {len(records)} GLBs, {len(errors)} failures")
    return 1 if errors else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, default=ROOT / "CarpetToy/assets/character")
    args = parser.parse_args()
    try:
        return validate(args.assets)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"FAIL: Could not validate avatar assets: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
