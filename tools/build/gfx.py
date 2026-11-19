"""Convert the arcade's 4-plane 16x16 tiles to Mega Drive 8x8 patterns.

The arcade stores four bit planes in the four quarters of a region, 32 bytes
per tile per plane: bytes 16-31 are the left half, 0-15 the right, one byte per
row. Bit 3 of a pixel is in quarter 1, bit 2 in quarter 3, bit 1 in quarter 0
and bit 0 in quarter 2.
"""
PLANES = (1, 3, 0, 2)


def tile_pixels(region, code):
    quarter = len(region) // 4
    rows = []
    for y in range(16):
        row = []
        for half in (16, 0):
            bits = [region[q * quarter + code * 32 + half + y] for q in PLANES]
            for x in range(8):
                shift = 7 - x
                row.append((bits[0] >> shift & 1) << 3 | (bits[1] >> shift & 1) << 2 |
                           (bits[2] >> shift & 1) << 1 | (bits[3] >> shift & 1))
        rows.append(row)
    return rows


def pattern(rows, x, y):
    out = bytearray()
    for r in range(y, y + 8):
        for c in range(x, x + 8, 2):
            out.append(rows[r][c] << 4 | rows[r][c + 1])
    return bytes(out)


def plane_tiles(region, tiles):
    """Each tile as four plane cells: top left, top right, bottom left, bottom right."""
    out = bytearray()
    for code in range(tiles):
        rows = tile_pixels(region, code)
        for y in (0, 8):
            for x in (0, 8):
                out += pattern(rows, x, y)
    return bytes(out)


def sprite_sets(region, tiles):
    """Singles: each tile as a 2x2-cell sprite. Pairs: tiles 2k and 2k+1 stacked as a 2x4-cell sprite.
    Sprite patterns run down each column, then across."""
    pixels = [tile_pixels(region, code) for code in range(tiles)]
    singles = b''.join(pattern(p, x, y) for p in pixels for x in (0, 8) for y in (0, 8))
    pairs = bytearray()
    for k in range(tiles // 2):
        rows = pixels[2 * k] + pixels[2 * k + 1]
        for x in (0, 8):
            for y in (0, 8, 16, 24):
                pairs += pattern(rows, x, y)
    return singles, bytes(pairs)
