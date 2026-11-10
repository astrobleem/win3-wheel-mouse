"""Convert this fixture's relocation-free, ORG 100h MZ image to a DOS COM."""
from pathlib import Path
import struct

base = Path(__file__).resolve().parent
blob = (base / "MOCK33.EXE").read_bytes()
header = struct.unpack("<14H", blob[:28])
if not (header[0] == 0x5A4D and header[3] == 0 and
        header[10] == 0x100 and header[11] == 0):
    raise ValueError("Unexpected EXE layout; refusing COM conversion")
image = blob[header[4] * 16:]
if image[:256] != bytes(256) or not 256 < len(image) < 65536:
    raise ValueError("Unexpected ORG 100h image")
(base / "MOCK33.COM").write_bytes(image[256:])
