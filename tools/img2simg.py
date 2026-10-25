#!/usr/bin/env python3
"""Convert a raw disk image to an Android sparse image (.simg)."""
import os
import struct
import sys

SPARSE_HEADER_MAGIC = 0xed26ff3a
CHUNK_TYPE_RAW = 0xcac1
CHUNK_TYPE_FILL = 0xcac2
CHUNK_TYPE_DONT_CARE = 0xcac3
CHUNK_TYPE_CRC32 = 0xcac4

BLOCK_SIZE = 4096


def raw_to_simg(in_path, out_path, chunk_blocks=16384):
    file_size = os.path.getsize(in_path)
    total_blocks = (file_size + BLOCK_SIZE - 1) // BLOCK_SIZE
    
    print(f"Converting {in_path} ({file_size / (1024**3):.2f} GiB, {total_blocks} blocks) -> {out_path}")
    
    # We will buffer chunk descriptors and write to out_path
    chunks = []
    
    with open(in_path, "rb") as fin, open(out_path, "wb") as fout:
        # Placeholder for sparse header
        fout.seek(28)
        
        cur_type = None
        cur_blocks = 0
        cur_data = bytearray()
        total_chunks = 0
        processed_blocks = 0
        
        def flush_chunk():
            nonlocal cur_type, cur_blocks, cur_data, total_chunks
            if cur_blocks == 0:
                return
            total_chunks += 1
            if cur_type == CHUNK_TYPE_DONT_CARE:
                # 12 bytes header, 0 bytes payload
                fout.write(struct.pack("<2H2I", CHUNK_TYPE_DONT_CARE, 0, cur_blocks, 12))
            elif cur_type == CHUNK_TYPE_FILL:
                fout.write(struct.pack("<2H2I", CHUNK_TYPE_FILL, 0, cur_blocks, 16))
                fout.write(b"\x00\x00\x00\x00")
            elif cur_type == CHUNK_TYPE_RAW:
                fout.write(struct.pack("<2H2I", CHUNK_TYPE_RAW, 0, cur_blocks, 12 + len(cur_data)))
                fout.write(cur_data)
            cur_blocks = 0
            cur_data = bytearray()
            cur_type = None

        ZERO_BLOCK = b"\x00" * BLOCK_SIZE
        
        while processed_blocks < total_blocks:
            buf = fin.read(BLOCK_SIZE)
            if not buf:
                # Remainder of file is empty
                remaining = total_blocks - processed_blocks
                if cur_type != CHUNK_TYPE_DONT_CARE:
                    flush_chunk()
                cur_type = CHUNK_TYPE_DONT_CARE
                cur_blocks += remaining
                processed_blocks += remaining
                break
            
            if len(buf) < BLOCK_SIZE:
                buf = buf + b"\x00" * (BLOCK_SIZE - len(buf))
                
            is_zero = (buf == ZERO_BLOCK)
            block_type = CHUNK_TYPE_DONT_CARE if is_zero else CHUNK_TYPE_RAW
            
            if cur_type is None:
                cur_type = block_type
                
            if block_type != cur_type or cur_blocks >= chunk_blocks:
                flush_chunk()
                cur_type = block_type
                
            cur_blocks += 1
            if block_type == CHUNK_TYPE_RAW:
                cur_data.extend(buf)
                
            processed_blocks += 1
            if processed_blocks % 500000 == 0:
                print(f"  Processed {processed_blocks}/{total_blocks} blocks ({processed_blocks * 100 // total_blocks}%)...")
                
        flush_chunk()
        
        # Write sparse header
        fout.seek(0)
        # magic (4), maj (2), min (2), file_hdr_sz (2), chunk_hdr_sz (2), blk_sz (4), total_blks (4), total_chunks (4), crc (4)
        header = struct.pack("<I4H4I", SPARSE_HEADER_MAGIC, 1, 0, 28, 12, BLOCK_SIZE, total_blocks, total_chunks, 0)
        fout.write(header)
        
    out_size = os.path.getsize(out_path)
    print(f"Done! Sparse image size: {out_size / (1024**3):.2f} GiB (saved {(file_size - out_size) / (1024**3):.2f} GiB)")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: img2simg.py <input.raw> <output.simg>")
        sys.exit(1)
    raw_to_simg(sys.argv[1], sys.argv[2])
