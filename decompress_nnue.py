#!/usr/bin/env python3
"""Decompress zstd-compressed NNUE file to raw format."""
import struct
import shutil
import zstandard as zstd

NNUE_PATH = r"c:\Users\xzw65\Desktop\xiangqi\ChineseChess\app\android\app\src\main\assets\pikafish.nnue"

# Read compressed file
with open(NNUE_PATH, "rb") as f:
    compressed = f.read()

print(f"Compressed size: {len(compressed)} bytes ({len(compressed)/1024/1024:.2f} MB)")
print(f"Compressed header: {' '.join(f'{b:02X}' for b in compressed[:16])}")

# Verify it's zstd
assert compressed[:4] == b'\x28\xb5\x2f\xfd', "Not a zstd file!"

# Decompress
dctx = zstd.ZstdDecompressor()
# Content size not in frame header, use streaming decompression
reader = dctx.stream_reader(compressed)
chunks = []
while True:
    chunk = reader.read(1024 * 1024)  # 1MB chunks
    if not chunk:
        break
    chunks.append(chunk)
decompressed = b"".join(chunks)
print(f"Decompressed size: {len(decompressed)} bytes ({len(decompressed)/1024/1024:.2f} MB)")

# Verify NNUE header
version = struct.unpack("<I", decompressed[0:4])[0]
hash_val = struct.unpack("<I", decompressed[4:8])[0]
print(f"NNUE Version: 0x{version:08X}")
print(f"NNUE Hash: 0x{hash_val:08X}")
print(f"Raw header: {' '.join(f'{b:02X}' for b in decompressed[:16])}")

assert version == 0x7AF32F20, f"Unexpected version: 0x{version:08X}"
assert hash_val == 0x6E24D34A, f"Unexpected hash: 0x{hash_val:08X}"
print("NNUE header verified OK!")

# Backup compressed file
backup_path = NNUE_PATH + ".zst.bak"
shutil.copy2(NNUE_PATH, backup_path)
print(f"Backup saved to: {backup_path}")

# Write decompressed file
with open(NNUE_PATH, "wb") as f:
    f.write(decompressed)

print(f"Decompressed NNUE saved to: {NNUE_PATH}")
print(f"File size: {len(decompressed)} bytes ({len(decompressed)/1024/1024:.2f} MB)")
print("DONE!")
