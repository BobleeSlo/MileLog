"""Render the MileLog app icon: a road curving up to a destination pin,
on the app's brand gradient (Theme.brandStart -> Theme.brandEnd).
Writes light, dark and tinted 1024x1024 variants."""
import math, sys
from PIL import Image, ImageDraw

OUT = sys.argv[1]
S = 4                      # supersampling factor
N = 1024 * S
BRAND_START = (0x4D, 0x45, 0xE5)
BRAND_END   = (0x00, 0x7A, 0xFF)

def gradient(c0, c1):
    """Diagonal gradient, top-left -> bottom-right."""
    img = Image.new("RGB", (N, N))
    px = img.load()
    small = 256
    g = Image.new("RGB", (small, small))
    gp = g.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            gp[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))
    return g.resize((N, N), Image.BICUBIC)

def bezier(p0, p1, p2, p3, steps=400):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t**3*p3[0]
        y = u**3*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t**3*p3[1]
        pts.append((x * S, y * S))
    return pts

# Route in 1024-space: from lower-left, sweeping right then up to the pin.
ROUTE = bezier((250, 830), (330, 540), (760, 760), (690, 470))
PIN_TIP = (690, 470)

def resample(pts, step):
    """Points every `step` px along the polyline, so stamping is gap-free."""
    out = [pts[0]]
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        d = math.dist(a, b)
        pos = step - carry
        while pos <= d:
            t = pos / d
            out.append((a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t))
            pos += step
        carry = d - (pos - step)
    out.append(pts[-1])
    return out

def stroke(draw, pts, width, fill):
    """Round-capped thick stroke by stamping discs densely along the path —
    clean edges, unlike a wide polyline, which leaves seams on curves."""
    r = width * S / 2
    for (x, y) in resample(pts, 2 * S):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)

def dashed(draw, pts, width, fill, dash=46, gap=34):
    # walk the polyline, emitting dash segments by arc length
    seg, acc, on, cur = [], 0.0, True, [pts[0]]
    period = [dash * S, gap * S]
    idx = 0
    for a, b in zip(pts, pts[1:]):
        d = math.dist(a, b)
        while d > 0:
            left = period[idx] - acc
            if d < left:
                acc += d
                if on: cur.append(b)
                d = 0
            else:
                t = left / d
                m = (a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t)
                if on:
                    cur.append(m)
                    stroke(draw, cur, width, fill)
                cur = [m]
                a, d, acc = m, d - left, 0.0
                on = not on
                idx = 1 - idx
    if on and len(cur) > 1:
        stroke(draw, cur, width, fill)

def pin(draw, tip, body, hole):
    """Map pin whose point sits on `tip` (1024-space)."""
    tx, ty = tip[0] * S, tip[1] * S
    R = 128 * S                    # head radius
    cx, cy = tx, ty - R * 1.75     # head centre above the tip
    # tangent points for the point of the pin
    ang = math.asin(R / (ty - cy))
    dx = R * math.cos(ang)
    dy = R * math.sin(ang)
    draw.polygon([(tx, ty), (cx - dx, cy + dy), (cx + dx, cy + dy)], fill=body)
    draw.ellipse((cx - R, cy - R, cx + R, cy + R), fill=body)
    r = R * 0.42
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=hole)

def render(bg, road, centre, pin_body, pin_hole, start_dot):
    img = bg.copy()
    d = ImageDraw.Draw(img)
    stroke(d, ROUTE, 116, road)
    dashed(d, ROUTE[45:-70], 16, centre)
    x, y = ROUTE[0]
    r = 40 * S
    d.ellipse((x - r, y - r, x + r, y + r), fill=start_dot)
    pin(d, PIN_TIP, pin_body, pin_hole)
    return img.resize((1024, 1024), Image.LANCZOS)

white = (255, 255, 255)
light = render(gradient(BRAND_START, BRAND_END), white, BRAND_START, white, BRAND_END, BRAND_START)
light.save(f"{OUT}/AppIcon-light.png", optimize=True)

dark_bg = gradient((0x1C, 0x1C, 0x2E), (0x0A, 0x0A, 0x14))
dark = render(dark_bg, (0x3A, 0x6F, 0xF7), (0xFF, 0xFF, 0xFF), (0x5B, 0x8C, 0xFF), (0x10, 0x10, 0x1C), (0xFF, 0xFF, 0xFF))
dark.save(f"{OUT}/AppIcon-dark.png", optimize=True)

# Tinted: grayscale artwork; iOS applies the user's tint colour on top.
tint_bg = Image.new("RGB", (N, N), (0, 0, 0))
tinted = render(tint_bg, (0xE6, 0xE6, 0xE6), (0x30, 0x30, 0x30), (0xFF, 0xFF, 0xFF), (0, 0, 0), (0x30, 0x30, 0x30)).convert("L")
tinted.save(f"{OUT}/AppIcon-tinted.png", optimize=True)
print("written")
