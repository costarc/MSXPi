#!/usr/bin/env python3
"""Build PPOKER's card tiles from the X68000-Book PlayingCards deck.

The deck (``PlayingCards/PNG-cards-1.3`` in the book's ``code/poker`` tree;
David Bellot's vector playing cards, LGPL-2.1) is 500x726 per card, far too
large for a 256x212 SCREEN 5 screen and unreadable when simply downscaled:
the rank index of a card shrunk to 26x36 is two pixels tall.  So this tool
composes each tile from two pieces of the artwork, which stay legible at the
size the game draws them:

* the top-left corner index of the card (its rank and suit, exactly as the
  deck draws them), resized into the tile's left column;
* a large suit pip, cut from the same suit's ace, for the number cards, or
  the court figure of the J/Q/K card, for the face cards.

The result is written as C: one 26x36 tile per card at 2 bits per pixel
(four colours: white card, black ink, red ink, table felt), plus a card
back.  PPOKER.COM would carry 468 bytes per card at 4 bpp (25 KB of the
50 KB an MSX-DOS program has); two bits per pixel keeps the artwork near
12 KB and the client expands it into VRAM at start-up.

Usage:
    python make_poker_cards.py --cards-dir PATH/PlayingCards/PNG-cards-1.3
                               [--out software/Client/src/ppoker_cards.h]
                               [--preview work/cards-preview.png]
The header is checked in, so a normal build does not need the deck.
"""
import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - the build machine has Pillow
    sys.exit('make_poker_cards.py needs Pillow (pip install pillow)')

CARD_W, CARD_H = 26, 36
STRIDE = (CARD_W * 2 + 7) // 8          # 2 bpp, one row per STRIDE bytes
CARD_BYTES = STRIDE * CARD_H

# 2-bit palette indexes used in the tile data.  PPOKER sets the 16-colour
# palette so that each index is the colour named here.
WHITE, INK, RED, FELT = 0, 1, 2, 3

RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'jack', 'queen', 'king', 'ace']
SUITS = ['clubs', 'diamonds', 'hearts', 'spades']
FACES = {'jack', 'queen', 'king'}


def load(path):
    """The card on white, RGB."""
    im = Image.open(path).convert('RGBA')
    bg = Image.new('RGBA', im.size, (255, 255, 255, 255))
    bg.alpha_composite(im)
    return bg.convert('RGB')


def ink_bounds(im, box):
    """Bounding box of non-white pixels inside box, or the box itself."""
    crop = im.crop(box)
    grey = crop.convert('L')
    mask = grey.point(lambda v: 255 if v < 200 else 0)
    bb = mask.getbbox()
    if not bb:
        return box
    return (box[0] + bb[0], box[1] + bb[1], box[0] + bb[2], box[1] + bb[3])


# Rank glyphs, 3x5 cells doubled to 6x10 in the tile.  The deck's own rank
# letters are drawn for a 500-pixel card; shrunk to 12 pixels they fall apart,
# so the tile draws the rank with this font and takes the suit pips from the
# artwork.
RANK_FONT = {
    '0': ('111', '101', '101', '101', '111'),
    '1': ('010', '110', '010', '010', '111'),
    '2': ('111', '001', '111', '100', '111'),
    '3': ('111', '001', '111', '001', '111'),
    '4': ('101', '101', '111', '001', '001'),
    '5': ('111', '100', '111', '001', '111'),
    '6': ('111', '100', '111', '101', '111'),
    '7': ('111', '001', '001', '001', '001'),
    '8': ('111', '101', '111', '101', '111'),
    '9': ('111', '101', '111', '001', '111'),
    'J': ('001', '001', '001', '101', '111'),
    'Q': ('111', '101', '101', '111', '011'),
    'K': ('101', '101', '110', '101', '101'),
    'A': ('111', '101', '111', '101', '101'),
}


def draw_rank(tile, text, color):
    """Draw a rank (one or two characters) at 2x, top-left of the tile."""
    x = 1 if len(text) == 2 else 4
    for ch in text:
        glyph = RANK_FONT[ch]
        for row, bits in enumerate(glyph):
            for col, bit in enumerate(bits):
                if bit == '1':
                    for dy in (0, 1):
                        for dx in (0, 1):
                            tile.putpixel((x + col * 2 + dx, 3 + row * 2 + dy), color)
        x += 6


def fit(im, box, size):
    """Crop box, keep the aspect ratio, centre it in a white size canvas."""
    w, h = size
    piece = im.crop(box)
    scale = min(w / piece.width, h / piece.height)
    piece = piece.resize((max(1, round(piece.width * scale)),
                          max(1, round(piece.height * scale))), Image.LANCZOS)
    canvas = Image.new('RGB', size, (255, 255, 255))
    canvas.paste(piece, ((w - piece.width) // 2, (h - piece.height) // 2))
    return canvas


def suit_pip(cards_dir, suit, size):
    """The suit's pip, cut from that suit's ace and squared off."""
    ace = load(os.path.join(cards_dir, 'ace_of_%s.png' % suit))
    # The ace's pip sits in the middle of the card, under the index; the
    # index itself is above y=230.
    box = ink_bounds(ace, (60, 240, 440, 620))
    w, h = box[2] - box[0], box[3] - box[1]
    side = max(w, h)
    box = (box[0] - (side - w) // 2, box[1] - (side - h) // 2,
           box[0] - (side - w) // 2 + side, box[1] - (side - h) // 2 + side)
    return fit(ace, box, size)


def face_figure(card, size):
    """The court figure of a J/Q/K, index excluded."""
    box = ink_bounds(card, (165, 30, 470, 400))
    return fit(card, box, size)
def quantise(pixel, red):
    """One pixel to the tile's two-bit palette."""
    r, g, b = pixel
    if r > 235 and g > 235 and b > 235:
        return WHITE
    if red and r > 90 and r - max(g, b) > 30:
        return RED
    if r + g + b > 480:
        return WHITE
    return INK


def compose(cards_dir, rank, suit):
    """One 26x36 card face: felt-edged white card, index, pip or figure."""
    red = suit in ('diamonds', 'hearts')
    name = '%s_of_%s' % ('ace' if rank == 'ace' else rank, suit)
    card = load(os.path.join(cards_dir, name + '.png'))

    tile = Image.new('RGB', (CARD_W, CARD_H), (0, 0, 0))
    felt = (16, 88, 40)
    tile.paste(felt, (0, 0, CARD_W, CARD_H))
    # White card with a two-pixel rounded corner and a grey border.
    card_area = Image.new('RGB', (CARD_W, CARD_H), (120, 120, 120))
    card_area.paste((255, 255, 255), (1, 1, CARD_W - 1, CARD_H - 1))
    for x, y in ((0, 0), (1, 0), (0, 1), (CARD_W - 1, 0), (CARD_W - 2, 0),
                 (CARD_W - 1, 1), (0, CARD_H - 1), (1, CARD_H - 1), (0, CARD_H - 2),
                 (CARD_W - 1, CARD_H - 1), (CARD_W - 2, CARD_H - 1), (CARD_W - 1, CARD_H - 2)):
        card_area.putpixel((x, y), felt)
    tile.paste(card_area)

    # Rank from the tile's own font, in the suit's ink colour, then the deck's
    # suit pip under it: the corner index every card carries.
    ink = (190, 20, 40) if red else (24, 24, 24)
    draw_rank(tile, {'ace': 'A', 'jack': 'J', 'queen': 'Q', 'king': 'K'}.get(rank, rank), ink)
    tile.paste(suit_pip(cards_dir, suit, (12, 12)), (1, 15))

    # A second, larger pip from the same ace, where a real card's pip sits.
    # Court figures do not survive this size; the rank letter distinguishes
    # the face cards.
    if rank in FACES or rank == 'ace':
        tile.paste(suit_pip(cards_dir, suit, (13, 13)), (11, 10))
    else:
        tile.paste(suit_pip(cards_dir, suit, (13, 13)), (11, 20))
    return tile, red


def back():
    """A card back: blue lattice, white border, no artwork in the deck."""
    tile = Image.new('RGB', (CARD_W, CARD_H), (16, 88, 40))
    tile.paste((30, 40, 150), (1, 1, CARD_W - 1, CARD_H - 1))
    for y in range(2, CARD_H - 2):
        for x in range(2, CARD_W - 2):
            if (x + y) % 6 == 0 or (x - y) % 6 == 0:
                tile.putpixel((x, y), (150, 170, 240))
    tile.paste((255, 255, 255), (1, 1, CARD_W - 1, 2))
    tile.paste((255, 255, 255), (1, CARD_H - 2, CARD_W - 1, CARD_H - 1))
    return tile


def pack(tile, red):
    """2 bits per pixel, four pixels a byte, leftmost pixel in bits 7-6."""
    data = bytearray(CARD_BYTES)
    for y in range(CARD_H):
        for x in range(CARD_W):
            value = quantise(tile.getpixel((x, y)), red)
            data[y * STRIDE + x // 4] |= value << (6 - 2 * (x % 4))
    return bytes(data)


def unpack(data, red):
    """The packed tile as it will look on the MSX, for review."""
    palette = [(255, 255, 255), (24, 24, 24), (190, 20, 40), (16, 88, 40)]
    image = Image.new('RGB', (CARD_W, CARD_H))
    for y in range(CARD_H):
        for x in range(CARD_W):
            value = (data[y * STRIDE + x // 4] >> (6 - 2 * (x % 4))) & 3
            image.putpixel((x, y), palette[value])
    return image


def preview(tiles, path):
    scale = 3
    cols = 9
    sheet = Image.new('RGB', (cols * (CARD_W * scale + 4), 6 * (CARD_H * scale + 4)), (16, 88, 40))
    for i, (tile, red) in enumerate(tiles):
        big = unpack(pack(tile, red), red).resize((CARD_W * scale, CARD_H * scale), Image.NEAREST)
        sheet.paste(big, ((i % cols) * (CARD_W * scale + 4), (i // cols) * (CARD_H * scale + 4)))
    sheet.save(path)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--cards-dir', required=True,
                        help='the deck directory (PNG-cards-1.3)')
    parser.add_argument('--out', default=os.path.join(here, '..', 'Client', 'src', 'ppoker_cards.h'))
    parser.add_argument('--preview', default=None, help='write a scaled PNG sheet for review')
    args = parser.parse_args()

    tiles = []
    for rank in RANKS:
        for suit in SUITS:
            tiles.append(compose(args.cards_dir, rank, suit))
    tiles.append((back(), False))

    if args.preview:
        preview(tiles, args.preview)

    lines = [
        '/* Generated by software/tools/make_poker_cards.py - do not edit.',
        ' *',
        ' * Card faces composed from the PlayingCards deck of X68000-Book',
        ' * (code/poker/PlayingCards, David Bellot\'s vector playing cards,',
        ' * LGPL-2.1): the deck\'s own corner index plus its suit pip or court',
        ' * figure, at 26x36, 2 bits per pixel (white, black, red, felt).',
        ' * Card id = (rank-2)*4 + suit, rank 0..12 = 2..A, suit 0..3 =',
        ' * clubs, diamonds, hearts, spades.  Id 52 is the back. */',
        '#ifndef PPOKER_CARDS_H',
        '#define PPOKER_CARDS_H',
        '',
        '#include <stdint.h>',
        '',
        '#define CARD_W %d' % CARD_W,
        '#define CARD_H %d' % CARD_H,
        '#define CARD_STRIDE %d' % STRIDE,
        '#define CARD_BYTES %d' % CARD_BYTES,
        '#define CARD_BACK 52',
        '#define CARD_COUNT 53',
        '',
        'static const uint8_t card_tiles[CARD_COUNT][CARD_BYTES] = {',
    ]
    for index, (tile, red) in enumerate(tiles):
        data = pack(tile, red)
        lines.append('    { /* %s */' % ('back' if index == 52 else
                                         '%s%s' % (RANKS[index // 4], SUITS[index % 4].upper())))
        for row in range(0, CARD_BYTES, STRIDE):
            lines.append('        ' + ','.join('0x%02X' % b for b in data[row:row + STRIDE]) + ',')
        lines.append('    },')
    lines += ['};', '', '#endif', '']
    with open(args.out, 'w', newline='\n') as handle:
        handle.write('\n'.join(lines))
    print('%s: %d tiles, %d bytes of tile data' % (args.out, len(tiles), len(tiles) * CARD_BYTES))


if __name__ == '__main__':
    main()
