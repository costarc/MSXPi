"""Cached web pages and scanline encoding for SCREEN 4, 6 and 8."""
from io import BytesIO
from itertools import combinations_with_replacement
from urllib.parse import urlsplit
from dataclasses import dataclass
import re
import shlex
import struct

# Explicit V9938 RGB palette; index 0 is transparent and never selected.
PALETTE = ((0,0,0), (0,0,0), (1,6,1), (3,7,3), (1,1,7),
           (2,3,7), (5,1,1), (2,6,7), (7,1,1), (7,3,3),
           (6,6,1), (6,6,4), (1,4,1), (6,2,5), (5,5,5), (7,7,7))
PAYLOAD_SIZE = 4 + 64 + 6144 * 2
SCREEN_SIZE = (256, 192)
SCREEN6_GREYS = [(0, 0, 0), (3, 3, 3), (5, 5, 5), (7, 7, 7)]
BROWSER_SIZE = (1024, 768)
# Browser width used for every page. Below ~1000px responsive sites switch to
# one column (sidebars move under the content); 768 keeps text smaller than a
# phone layout while staying readable on the MSX.
RENDER_WIDTH = 768
# Smallest readable glyph on the MSX, in native lines (the MSX font is 8).
# /f<n> overrides it per page, within FONT_LINES_RANGE.
MIN_TEXT_LINES = 10
FONT_LINES_RANGE = range(4, 33)
USAGE = "Usage: P SHOWPAGE [/4|/6|/8] [/f<4-32>] http[s]://url"
# Raise every text size to at least %dpx; em keeps larger headings larger.
# A fixed line-height would make the enlarged lines overlap.
MIN_FONT_CSS = "body * { font-size: max(1em, %dpx) !important; line-height: 1.25 !important; }"


def resize_page(image, mode=4, source_size=BROWSER_SIZE):
    """Fit document width to native pixels, keeping its scrollable height.

    All modes map a 4:3 browser viewport onto the physical MSX display;
    SCREEN 6 uses twice the horizontal samples to account for narrow pixels.
    """
    from PIL import Image
    width, visible, _ = MODES[mode]
    rgba = image.convert("RGBA")
    background = Image.new("RGBA", rgba.size, "white")
    background.alpha_composite(rgba)
    source_width, source_height = source_size
    denominator = image.width * source_height
    height = max(1, (image.height * visible * source_width + denominator - 1) // denominator)
    resized = background.convert("RGB").resize((width, height), Image.Resampling.LANCZOS)
    if height < visible:
        canvas = Image.new("RGB", (width, visible), "white")
        canvas.paste(resized, (0, 0))
        return canvas
    return resized


def encode_screen4(image):
    """Minimise RGB squared error over each horizontal eight-pixel stripe."""
    if image.size != (256, 192):
        raise ValueError("SCREEN 4 requires a 256x192 image")
    pixels = image.convert("RGB").load()
    rgb = [tuple(round(c * 255 / 7) for c in colour) for colour in PALETTE]
    pairs = list(combinations_with_replacement(range(1, 16), 2))
    patterns, colours = bytearray(6144), bytearray(6144)
    cache = {}
    for y in range(192):
        for x in range(0, 256, 8):
            stripe = tuple(pixels[x + i, y] for i in range(8))
            if stripe not in cache:
                distances = [[sum((p[c] - colour[c]) ** 2 for c in range(3))
                              for colour in rgb] for p in stripe]
                bg, fg = min(pairs, key=lambda pair: sum(
                    min(d[pair[0]], d[pair[1]]) for d in distances))
                bits = 0
                for d in distances:
                    bits = (bits << 1) | (d[fg] < d[bg])
                cache[stripe] = bits, (fg << 4) | bg
            # Three banks of 256 tiles, eight scanlines per tile.
            offset = (y // 8) * 256 + x + (y & 7)
            patterns[offset], colours[offset] = cache[stripe]
    palette = bytes(v for i, colour in enumerate(PALETTE) for v in (i, *colour))
    return b"RP4\x01" + palette + patterns + colours


# mode: (native width, visible lines, encoded bytes per scanline)
MODES = {4: (256, 192, 64), 6: (512, 212, 128), 8: (256, 212, 256)}
MAX_CSS_HEIGHT = 163840
MAX_CSS_WIDTH = 4096
# Rows per request. Responses larger than one 4KB block are streamed with
# sendmultiblock(); every stride divides 4096, so blocks hold whole rows.
MAX_ROWS = 256


@dataclass(frozen=True)
class RenderedPage:
    mode: int
    height: int
    palette: bytes
    data: bytes

    def header(self):
        width, visible, stride = MODES[self.mode]
        return struct.pack("<4sBHHI H", b"RPG2", self.mode, width, visible,
                           self.height, stride) + self.palette

    def rows(self, start, count):
        if not 1 <= count <= MAX_ROWS or start < 0 or start + count > self.height:
            raise ValueError("Page row range is out of bounds")
        stride = MODES[self.mode][2]
        return self.data[start * stride:(start + count) * stride]


def encode_page(image, mode):
    """Store row-major native VDP bytes, ready for repeated line requests."""
    from PIL import Image
    width, visible, stride = MODES[mode]
    if image.width != width or not visible <= image.height <= 65535:
        raise ValueError("Invalid rendered page dimensions")
    image = image.convert("RGB")
    palette = bytes(v for i, colour in enumerate(PALETTE) for v in (i, *colour))
    data = bytearray()
    if mode == 4:
        # Reuse the SCREEN 4 stripe encoder in 192-line bands, then transpose
        # tile order to scanline order. Bound the stripe cache to each band.
        for top in range(0, image.height, 192):
            count = min(192, image.height - top)
            band = Image.new("RGB", (256, 192), "white")
            band.paste(image.crop((0, top, 256, top + count)))
            encoded = encode_screen4(band)
            for y in range(count):
                offsets = [(y // 8) * 256 + x * 8 + (y & 7) for x in range(32)]
                data.extend(encoded[68 + i] for i in offsets)
                data.extend(encoded[6212 + i] for i in offsets)
    elif mode == 6:
        # Fixed four-level grey scale. A per-page adaptive palette spends its
        # four entries on the (mostly white) background and leaves text a
        # single mid tone; by brightness, text is always dark on light.
        entries = SCREEN6_GREYS + [(0, 0, 0)] * 12
        palette = bytes(v for i, colour in enumerate(entries) for v in (i, *colour))
        # Nearest of the levels 0, 3/7, 5/7 and 1 of full brightness.
        pixels = image.convert("L").point(
            lambda v: 0 if v < 55 else 1 if v < 146 else 2 if v < 219 else 3).tobytes()
        for i in range(0, len(pixels), 4):
            data.append((pixels[i] << 6) | (pixels[i+1] << 4) |
                        (pixels[i+2] << 2) | pixels[i+3])
    else:
        # SCREEN 8 native layout: GGGRRRBB, no programmable image palette.
        pixels = image.tobytes()
        for i in range(0, len(pixels), 3):
            r, g, b = pixels[i:i+3]
            data.append(((g * 7 + 127) // 255 << 5) |
                        ((r * 7 + 127) // 255 << 2) | ((b * 3 + 127) // 255))
    assert len(data) == image.height * stride
    return RenderedPage(mode, image.height, palette, bytes(data))


def render_url(url, mode=4, text_lines=MIN_TEXT_LINES):
    """Capture once, resize to the selected MSX display and cache every row."""
    if mode not in MODES:
        raise ValueError("Screen mode must be /4, /6 or /8")
    parsed = urlsplit(url)
    if parsed.scheme.lower() not in ("http", "https") or not parsed.hostname:
        raise ValueError("Use an http:// or https:// URL")
    if any(c.isspace() for c in url):
        raise ValueError("Encode spaces in the URL as %20")
    try:
        from PIL import Image
        from playwright.sync_api import sync_playwright
    except ImportError as exc:
        raise RuntimeError("Install Pillow and Playwright; then run python -m playwright install chromium") from exc
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True, timeout=30000)
        try:
            native_width, native_height, _ = MODES[mode]
            # A native-width viewport activates mobile reflow, but also makes
            # responsive sites choose oversized mobile typography. Capture at
            # 2x and downsample to native pixels for a more usable balance.
            # One layout width for every mode; 4:3 for SCREEN 6, whose 512
            # pixels are narrow, and the native aspect for SCREEN 4 and 8.
            render_width = RENDER_WIDTH
            render_height = (RENDER_WIDTH * 3 // 4 if mode == 6 else
                             RENDER_WIDTH * native_height // native_width)
            page = browser.new_page(viewport={"width": render_width, "height": render_height},
                                    device_scale_factor=1)
            page.set_default_timeout(15000)
            response = page.goto(url, wait_until="load", timeout=30000)
            if response is not None and response.status >= 400:
                raise ValueError("HTTP %d" % response.status)
            # Downscaling makes 14-16px body text about 5 lines tall, which is
            # unreadable; enforce a minimum size before the page is measured.
            min_font = -(-text_lines * render_height // native_height)
            page.add_style_tag(content=MIN_FONT_CSS % min_font)
            # Full-page screenshots do not reliably trigger lazy-loaded
            # images. Force image loading, visit each document band so
            # IntersectionObserver-based sites schedule their resources, and
            # wait until every image has either loaded or failed.
            page.evaluate("""async () => {
                for (const image of document.images) {
                    image.loading = 'eager';
                    image.removeAttribute('loading');
                }
                // Visit every viewport so IntersectionObserver-based sites
                // schedule images that are initially below the fold.
                const step = Math.max(window.innerHeight, 256);
                const height = document.documentElement.scrollHeight;
                for (let y = 0; y < height; y += step) {
                    window.scrollTo(0, y);
                    await new Promise(resolve => requestAnimationFrame(resolve));
                }
                window.scrollTo(0, 0);
            }""")
            # complete is true for both successful and failed requests. Some
            # sites leave placeholder/tracking images incomplete indefinitely,
            # so readiness is best-effort and must not abort the whole page.
            try:
                page.wait_for_function("""() => Array.from(document.images).every(
                    image => image.complete)""", timeout=5000)
            except Exception:
                pass
            css_width, css_height = page.evaluate("""() => [
                Math.max(innerWidth, document.documentElement.scrollWidth, document.body?.scrollWidth || 0),
                Math.max(innerHeight, document.documentElement.scrollHeight, document.body?.scrollHeight || 0)]""")
            if css_width > MAX_CSS_WIDTH or css_height > MAX_CSS_HEIGHT:
                raise ValueError("Page too large (maximum 4096 x 163840 browser pixels)")
            png = page.screenshot(type="png", full_page=True, animations="disabled", timeout=15000)
        finally:
            browser.close()
    with Image.open(BytesIO(png)) as image:
        if image.width > MAX_CSS_WIDTH or image.height > MAX_CSS_HEIGHT:
            raise ValueError("Page grew beyond the render size limit")
        resized = resize_page(image, mode, (render_width, render_height))
    return encode_page(resized, mode)


_page = None
_top = 0


def scroll_page(page, top, lines):
    """Move the view by lines (negative = up), clamped to the document.

    Returns (new_top, rows). Down: the rows entering at the bottom, top to
    bottom. Up: the rows entering at the top, bottom to top, so the client
    can place each row as it arrives without knowing the final count.
    """
    visible = MODES[page.mode][1]
    new_top = max(0, min(top + lines, page.height - visible))
    stride = MODES[page.mode][2]
    if new_top > top:
        return new_top, page.data[(top + visible) * stride:(new_top + visible) * stride]
    rows = bytearray()
    for row in range(top - 1, new_top - 1, -1):
        rows += page.data[row * stride:(row + 1) * stride]
    return new_top, bytes(rows)


def handle_command(parameters):
    """One cached document for the server's single MSX command connection.

    An empty result means there was nothing to send (scroll at top/bottom)."""
    global _page, _top
    tokens = shlex.split(parameters)
    if tokens and tokens[0].lower() == "rows":
        if len(tokens) != 3 or _page is None:
            raise ValueError("No cached page or invalid row request")
        return _page.rows(int(tokens[1]), int(tokens[2]))
    if tokens and tokens[0].lower() == "scroll":
        if len(tokens) != 2 or _page is None:
            raise ValueError("No cached page or invalid scroll request")
        _top, rows = scroll_page(_page, _top, int(tokens[1]))
        return rows
    if tokens == ["close"]:
        _page = None
        return b"OK"
    mode, url, text_lines = 4, None, None
    have_mode = False
    for token in tokens:
        font = re.fullmatch(r"/f(\d+)", token, re.I)
        if font:
            if text_lines is not None or int(font.group(1)) not in FONT_LINES_RANGE:
                raise ValueError("Font size: one /f<n>, n from 4 to 32 (default 10)")
            text_lines = int(font.group(1))
        elif token.startswith("/"):
            if token not in ("/4", "/6", "/8") or have_mode:
                raise ValueError("Specify one screen mode: /4, /6 or /8")
            mode, have_mode = int(token[1:]), True
        elif url is None:
            url = token
        else:
            raise ValueError(USAGE)
    if url is None:
        raise ValueError(USAGE)
    # Release the old cache before starting another render, including failures.
    _page = None
    _top = 0
    _page = render_url(url, mode, text_lines or MIN_TEXT_LINES)
    return _page.header()
