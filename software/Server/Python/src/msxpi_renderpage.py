"""Cached web pages and scanline encoding for SCREEN 4, 6 and 8."""
from io import BytesIO
from itertools import combinations_with_replacement
from urllib.parse import urlsplit
from dataclasses import dataclass
import shlex
import struct

# Explicit V9938 RGB palette; index 0 is transparent and never selected.
PALETTE = ((0,0,0), (0,0,0), (1,6,1), (3,7,3), (1,1,7),
           (2,3,7), (5,1,1), (2,6,7), (7,1,1), (7,3,3),
           (6,6,1), (6,6,4), (1,4,1), (6,2,5), (5,5,5), (7,7,7))
PAYLOAD_SIZE = 4 + 64 + 6144 * 2
SCREEN_SIZE = (256, 192)
BROWSER_SIZE = (1024, 768)


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
MAX_ROWS = 16
SCROLL_STEP = 8


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
        # One stable, page-wide four-colour palette avoids colour changes
        # while scrolling. Quantize first; send the matching V9938 palette.
        quantized = image.quantize(colors=4, method=Image.Quantize.MEDIANCUT,
                                   dither=Image.Dither.NONE)
        rgb = quantized.getpalette()
        entries = [tuple(round(c * 7 / 255) for c in rgb[i*3:i*3+3])
                   for i in range(4)] + [(0, 0, 0)] * 12
        palette = bytes(v for i, colour in enumerate(entries) for v in (i, *colour))
        pixels = quantized.tobytes()
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


def render_url(url, mode=4):
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
            render_width = native_width * 2
            render_height = native_height * 2
            page = browser.new_page(viewport={"width": render_width, "height": render_height},
                                    device_scale_factor=1)
            page.set_default_timeout(15000)
            response = page.goto(url, wait_until="load", timeout=30000)
            if response is not None and response.status >= 400:
                raise ValueError("HTTP %d" % response.status)
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


def handle_command(parameters):
    """One cached document for the server's single MSX command connection."""
    global _page
    tokens = shlex.split(parameters)
    if tokens and tokens[0].lower() == "rows":
        if len(tokens) != 3 or _page is None:
            raise ValueError("No cached page or invalid row request")
        return _page.rows(int(tokens[1]), int(tokens[2]))
    if tokens == ["close"]:
        _page = None
        return b"OK"
    mode, url = 4, None
    have_mode = False
    for token in tokens:
        if token.startswith("/"):
            if token not in ("/4", "/6", "/8") or have_mode:
                raise ValueError("Specify one screen mode: /4, /6 or /8")
            mode, have_mode = int(token[1:]), True
        elif url is None:
            url = token
        else:
            raise ValueError("Usage: RENDERPA [/4|/6|/8] http[s]://url")
    if url is None:
        raise ValueError("Usage: RENDERPA [/4|/6|/8] http[s]://url")
    # Release the old cache before starting another render, including failures.
    _page = None
    _page = render_url(url, mode)
    return _page.header()
