#!/usr/bin/env python3
"""
Technologia Talks — YouTube Thumbnail Generator
TBPN-style bold thumbnails with guest photos, topic images, and vibrant colors.

Usage:
    python3 thumbnail_generator.py --topic "AI Is Replacing Jobs" --guest "Sam Altman" --guest-photo sam.jpg
    python3 thumbnail_generator.py --topic "Apple's Secret Chip" --topic-image apple_chip.jpg --hosts
    python3 thumbnail_generator.py --topic "The Future of Crypto" --episode 42

Outputs a 1280x720 JPG thumbnail ready for YouTube upload.
"""

import argparse
import math
import os
import random
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance, ImageOps


# ─── CONFIG ──────────────────────────────────────────────────────────────────

THUMB_W, THUMB_H = 1280, 720

# Font paths (adjust if your system differs)
FONT_BOLD = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"
FONT_BLACK = "/usr/share/fonts/truetype/lato/Lato-Black.ttf"
FONT_MEDIUM = "/usr/share/fonts/truetype/google-fonts/Poppins-Medium.ttf"
FONT_REGULAR = "/usr/share/fonts/truetype/google-fonts/Poppins-Regular.ttf"

# Color palettes — each is (bg_gradient_start, bg_gradient_end, accent, text)
PALETTES = [
    {"name": "electric_blue",  "bg1": "#0a0e27", "bg2": "#1a1a4e", "accent": "#00d4ff", "accent2": "#ff6b35", "text": "#ffffff"},
    {"name": "fire_red",       "bg1": "#1a0000", "bg2": "#3d0a0a", "accent": "#ff3b3b", "accent2": "#ffaa00", "text": "#ffffff"},
    {"name": "neon_green",     "bg1": "#0a1a0a", "bg2": "#0d2b0d", "accent": "#00ff88", "accent2": "#00bbff", "text": "#ffffff"},
    {"name": "purple_haze",    "bg1": "#120024", "bg2": "#2d0052", "accent": "#b44aff", "accent2": "#ff4a8d", "text": "#ffffff"},
    {"name": "golden_hour",    "bg1": "#1a1000", "bg2": "#332200", "accent": "#ffcc00", "accent2": "#ff6600", "text": "#ffffff"},
    {"name": "hot_pink",       "bg1": "#1a000d", "bg2": "#3d001a", "accent": "#ff2d7b", "accent2": "#ffaa00", "text": "#ffffff"},
    {"name": "ocean_teal",     "bg1": "#001a1a", "bg2": "#003333", "accent": "#00e5cc", "accent2": "#0088ff", "text": "#ffffff"},
]

SHOW_NAME = "TECHNOLOGIA TALKS"


# ─── HELPERS ─────────────────────────────────────────────────────────────────

def hex_to_rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def create_gradient(w: int, h: int, color1: str, color2: str, angle: float = 135) -> Image.Image:
    """Create a gradient background at an angle."""
    c1, c2 = hex_to_rgb(color1), hex_to_rgb(color2)
    img = Image.new("RGB", (w, h))
    pixels = img.load()

    rad = math.radians(angle)
    cos_a, sin_a = math.cos(rad), math.sin(rad)
    max_d = abs(w * cos_a) + abs(h * sin_a)

    for y in range(h):
        for x in range(w):
            d = (x * cos_a + y * sin_a) / max_d
            d = max(0, min(1, (d + 0.5)))
            r = int(c1[0] + (c2[0] - c1[0]) * d)
            g = int(c1[1] + (c2[1] - c1[1]) * d)
            b = int(c1[2] + (c2[2] - c1[2]) * d)
            pixels[x, y] = (r, g, b)
    return img


def add_glow(draw: ImageDraw.Draw, xy: tuple, radius: int, color: str, alpha: int = 40):
    """Add a soft circular glow effect."""
    c = hex_to_rgb(color)
    for r in range(radius, 0, -2):
        a = int(alpha * (r / radius))
        fill = (*c, a)
        x, y = xy
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def draw_text_with_outline(draw, position, text, font, fill, outline_color="#000000", outline_width=3):
    """Draw text with a dark outline for readability."""
    x, y = position
    oc = hex_to_rgb(outline_color)
    fc = hex_to_rgb(fill) if isinstance(fill, str) else fill

    # Draw outline
    for dx in range(-outline_width, outline_width + 1):
        for dy in range(-outline_width, outline_width + 1):
            if dx == 0 and dy == 0:
                continue
            draw.text((x + dx, y + dy), text, font=font, fill=oc)
    # Draw main text
    draw.text((x, y), text, font=font, fill=fc)


def fit_text_to_width(draw, text, font_path, max_width, max_size=72, min_size=32):
    """Find the largest font size that fits text within max_width, with word wrapping."""
    for size in range(max_size, min_size - 1, -2):
        font = ImageFont.truetype(font_path, size)
        # Try wrapping
        words = text.upper().split()
        lines = []
        current_line = ""
        for word in words:
            test = f"{current_line} {word}".strip()
            bbox = draw.textbbox((0, 0), test, font=font)
            if bbox[2] - bbox[0] <= max_width:
                current_line = test
            else:
                if current_line:
                    lines.append(current_line)
                current_line = word
        if current_line:
            lines.append(current_line)

        # Check if all lines fit and we have reasonable number of lines
        all_fit = all(
            draw.textbbox((0, 0), line, font=font)[2] - draw.textbbox((0, 0), line, font=font)[0] <= max_width
            for line in lines
        )
        if all_fit and len(lines) <= 4:
            return font, lines, size

    # Fallback
    font = ImageFont.truetype(font_path, min_size)
    return font, [text.upper()], min_size


def load_and_crop_person(photo_path: str, target_h: int) -> Image.Image:
    """Load a person photo, crop to upper body, and remove/fade edges."""
    img = Image.open(photo_path).convert("RGBA")

    # Crop to upper ~70% (head + shoulders)
    crop_h = int(img.height * 0.75)
    img = img.crop((0, 0, img.width, crop_h))

    # Scale to target height
    scale = target_h / img.height
    new_w = int(img.width * scale)
    img = img.resize((new_w, target_h), Image.LANCZOS)

    # Add fade on left edge for blending
    fade_w = int(new_w * 0.3)
    for x in range(fade_w):
        alpha = int(255 * (x / fade_w))
        for y in range(img.height):
            r, g, b, a = img.getpixel((x, y))
            img.putpixel((x, y), (r, g, b, min(a, alpha)))

    return img


def load_topic_image(image_path: str, target_size: tuple) -> Image.Image:
    """Load a topic image (company logo, product photo, etc.) and prepare it."""
    img = Image.open(image_path).convert("RGBA")
    img = ImageOps.fit(img, target_size, Image.LANCZOS)

    # Round corners
    mask = Image.new("L", target_size, 0)
    mask_draw = ImageDraw.Draw(mask)
    radius = 20
    mask_draw.rounded_rectangle([0, 0, target_size[0], target_size[1]], radius=radius, fill=255)
    img.putalpha(mask)

    return img


def draw_accent_bar(draw, x, y, width, height, color):
    """Draw a colored accent bar (used for visual emphasis)."""
    c = hex_to_rgb(color)
    draw.rounded_rectangle([x, y, x + width, y + height], radius=height // 2, fill=c)


# ─── MAIN GENERATOR ─────────────────────────────────────────────────────────

def generate_thumbnail(
    topic: str,
    guest_name: str = None,
    guest_photo: str = None,
    topic_image: str = None,
    hosts: bool = False,
    episode_num: int = None,
    palette_name: str = None,
    output_path: str = None,
) -> str:
    """
    Generate a TBPN-style YouTube thumbnail.

    Args:
        topic: The episode topic / title (required)
        guest_name: Guest's name (optional)
        guest_photo: Path to guest's photo (optional)
        topic_image: Path to topic-related image, e.g. company logo (optional)
        hosts: If True, indicates this is a hosts-only episode
        episode_num: Episode number (optional)
        palette_name: Force a specific color palette (optional)
        output_path: Output file path (optional, auto-generated if not set)

    Returns:
        Path to the generated thumbnail
    """

    # Pick palette
    if palette_name:
        palette = next((p for p in PALETTES if p["name"] == palette_name), random.choice(PALETTES))
    else:
        palette = random.choice(PALETTES)

    # ── Create base image with gradient background ──
    img = create_gradient(THUMB_W, THUMB_H, palette["bg1"], palette["bg2"], angle=135)
    img = img.convert("RGBA")

    # Create overlay for glow effects
    glow_layer = Image.new("RGBA", (THUMB_W, THUMB_H), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)

    # Add accent glows
    add_glow(glow_draw, (THUMB_W * 0.8, THUMB_H * 0.3), 300, palette["accent"], alpha=25)
    add_glow(glow_draw, (THUMB_W * 0.2, THUMB_H * 0.7), 250, palette["accent2"], alpha=20)
    img = Image.alpha_composite(img, glow_layer)

    # ── Determine layout based on content ──
    has_person = guest_photo and os.path.exists(guest_photo)
    has_topic_img = topic_image and os.path.exists(topic_image)

    # Text area width depends on whether we have images on the right
    if has_person or has_topic_img:
        text_area_w = int(THUMB_W * 0.58)
        image_area_x = int(THUMB_W * 0.55)
    else:
        text_area_w = int(THUMB_W * 0.85)
        image_area_x = None

    draw = ImageDraw.Draw(img)

    # ── Place person photo (right side) ──
    if has_person:
        person = load_and_crop_person(guest_photo, THUMB_H)
        person_x = THUMB_W - person.width + int(person.width * 0.1)
        img.paste(person, (person_x, 0), person)
        draw = ImageDraw.Draw(img)  # Refresh draw after paste

    # ── Place topic image (right side, centered) ──
    if has_topic_img and not has_person:
        topic_size = (int(THUMB_W * 0.35), int(THUMB_H * 0.55))
        topic_img = load_topic_image(topic_image, topic_size)
        tx = THUMB_W - topic_size[0] - 40
        ty = (THUMB_H - topic_size[1]) // 2

        # Add subtle border glow
        border_layer = Image.new("RGBA", (THUMB_W, THUMB_H), (0, 0, 0, 0))
        bd = ImageDraw.Draw(border_layer)
        accent_rgb = hex_to_rgb(palette["accent"])
        bd.rounded_rectangle(
            [tx - 3, ty - 3, tx + topic_size[0] + 3, ty + topic_size[1] + 3],
            radius=23, fill=(*accent_rgb, 120)
        )
        img = Image.alpha_composite(img, border_layer)
        img.paste(topic_img, (tx, ty), topic_img)
        draw = ImageDraw.Draw(img)

    # ── Draw show name (top left) ──
    show_font = ImageFont.truetype(FONT_MEDIUM, 22)
    accent_rgb = hex_to_rgb(palette["accent"])

    # Accent bar behind show name
    show_bbox = draw.textbbox((0, 0), SHOW_NAME, font=show_font)
    show_w = show_bbox[2] - show_bbox[0]
    bar_x, bar_y = 45, 32
    draw.rounded_rectangle(
        [bar_x, bar_y, bar_x + show_w + 24, bar_y + 34],
        radius=6, fill=(*accent_rgb, 180)
    )
    draw.text((bar_x + 12, bar_y + 4), SHOW_NAME, font=show_font, fill=(255, 255, 255))

    # ── Draw episode number (if provided) ──
    y_cursor = bar_y + 50
    if episode_num is not None:
        ep_font = ImageFont.truetype(FONT_REGULAR, 18)
        ep_text = f"EP. {episode_num}"
        draw.text((50, y_cursor), ep_text, font=ep_font, fill=(*accent_rgb,))
        y_cursor += 30

    # ── Draw main topic text ──
    text_margin_left = 50
    topic_max_w = text_area_w - text_margin_left - 20

    # Fit topic text
    topic_font, topic_lines, font_size = fit_text_to_width(
        draw, topic, FONT_BOLD, topic_max_w, max_size=72, min_size=36
    )

    # Calculate vertical position — center the text block in available space
    line_height = int(font_size * 1.15)
    total_text_h = len(topic_lines) * line_height

    # Position text in the vertical center, biased slightly up
    text_start_y = max(y_cursor + 20, (THUMB_H - total_text_h) // 2 - 30)

    for i, line in enumerate(topic_lines):
        ly = text_start_y + i * line_height
        draw_text_with_outline(
            draw, (text_margin_left, ly), line, topic_font,
            fill="#ffffff", outline_color="#000000", outline_width=3
        )

    # ── Draw accent underline below topic ──
    underline_y = text_start_y + total_text_h + 12
    draw_accent_bar(draw, text_margin_left, underline_y, int(topic_max_w * 0.4), 5, palette["accent"])

    # ── Draw guest name (below topic) ──
    if guest_name:
        name_y = underline_y + 20
        name_font = ImageFont.truetype(FONT_MEDIUM, 30)
        # "with" label
        with_font = ImageFont.truetype(FONT_REGULAR, 20)
        draw.text((text_margin_left, name_y), "with", font=with_font, fill=(*accent_rgb,))
        draw.text((text_margin_left, name_y + 24), guest_name.upper(), font=name_font, fill=(255, 255, 255))
    elif hosts:
        name_y = underline_y + 20
        name_font = ImageFont.truetype(FONT_MEDIUM, 24)
        draw.text((text_margin_left, name_y), "TADIWA × ELVIS", font=name_font, fill=(*accent_rgb,))

    # ── Add subtle noise texture for depth ──
    noise = Image.new("RGBA", (THUMB_W, THUMB_H), (0, 0, 0, 0))
    noise_pixels = noise.load()
    for ny in range(0, THUMB_H, 2):
        for nx in range(0, THUMB_W, 2):
            v = random.randint(0, 15)
            noise_pixels[nx, ny] = (v, v, v, 12)
    img = Image.alpha_composite(img, noise)

    # ── Add bottom gradient fade (for YouTube player UI) ──
    bottom_fade = Image.new("RGBA", (THUMB_W, THUMB_H), (0, 0, 0, 0))
    bf_draw = ImageDraw.Draw(bottom_fade)
    for y in range(THUMB_H - 80, THUMB_H):
        alpha = int(60 * ((y - (THUMB_H - 80)) / 80))
        bf_draw.line([(0, y), (THUMB_W, y)], fill=(0, 0, 0, alpha))
    img = Image.alpha_composite(img, bottom_fade)

    # ── Convert to RGB and save ──
    final = img.convert("RGB")

    if not output_path:
        safe_topic = topic.lower().replace(" ", "_")[:40]
        output_path = f"thumbnail_{safe_topic}.jpg"

    final.save(output_path, "JPEG", quality=95)
    return output_path


# ─── CLI ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Generate TBPN-style YouTube thumbnails for Technologia Talks")
    parser.add_argument("--topic", required=True, help="Episode topic / title")
    parser.add_argument("--guest", help="Guest name")
    parser.add_argument("--guest-photo", help="Path to guest photo")
    parser.add_argument("--topic-image", help="Path to topic-related image (company logo, product, etc.)")
    parser.add_argument("--hosts", action="store_true", help="Show host names (Tadiwa × Elvis)")
    parser.add_argument("--episode", type=int, help="Episode number")
    parser.add_argument("--palette", choices=[p["name"] for p in PALETTES], help="Color palette name")
    parser.add_argument("--output", "-o", help="Output file path")

    args = parser.parse_args()

    path = generate_thumbnail(
        topic=args.topic,
        guest_name=args.guest,
        guest_photo=args.guest_photo,
        topic_image=args.topic_image,
        hosts=args.hosts,
        episode_num=args.episode,
        palette_name=args.palette,
        output_path=args.output,
    )
    print(f"Thumbnail saved: {path}")


if __name__ == "__main__":
    main()
