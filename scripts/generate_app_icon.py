#!/usr/bin/env python3
"""
Generates clean, native, minimal iOS AppIcon for PianoGlass.
Complies with Apple Human Interface Guidelines:
- Native 1024x1024 master resolution.
- Opaque 24-bit RGB (no alpha channel, square corners without artificial squircle masks).
- Minimalist sheet music & scan emblem inspired by Feather (feather.claration.dev).
- Downscales to all 18 standard iOS resolutions using Lanczos filtering.
- Updates Contents.json with clean Apple-standard specs.
"""

import os
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

def create_master_icon():
    W, H = 1024, 1024
    
    # 1. Base Gradient Background (Deep Obsidian Navy: #090D16 -> #131B2E)
    y_coords = np.linspace(0, 1, H)[:, None]
    x_coords = np.linspace(0, 1, W)[None, :]
    
    r_top, g_top, b_top = 9, 13, 22
    r_bot, g_bot, b_bot = 19, 27, 46
    
    r = (r_top + (r_bot - r_top) * y_coords).repeat(W, axis=1)
    g = (g_top + (g_bot - g_top) * y_coords).repeat(W, axis=1)
    b = (b_top + (b_bot - b_top) * y_coords).repeat(W, axis=1)
    
    bg_arr = np.stack([r, g, b], axis=-1).astype(np.uint8)
    master = Image.fromarray(bg_arr, mode="RGB")
    
    # 2. Ambient Soft Glow in upper center (Apple Blue / Cyan)
    glow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    glow_draw.ellipse([260, 200, 764, 700], fill=(0, 122, 255, 60))
    glow_draw.ellipse([340, 280, 684, 620], fill=(0, 229, 255, 45))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(80))
    master.paste(Image.alpha_composite(Image.new("RGBA", (W, H), (0,0,0,0)), glow_layer).convert("RGB"), (0,0), glow_layer)
    
    # 3. Document / Score Sheet Canvas (Centered: 620 x 740, corner radius 72)
    sheet_w, sheet_h = 620, 740
    sx0 = (W - sheet_w) // 2
    sy0 = (H - sheet_h) // 2 + 10
    sx1 = sx0 + sheet_w
    sy1 = sy0 + sheet_h
    
    sheet_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sheet_draw = ImageDraw.Draw(sheet_layer)
    
    # Sheet drop shadow
    shadow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    shadow_draw.rounded_rectangle([sx0, sy0 + 20, sx1, sy1 + 24], radius=72, fill=(0, 0, 0, 140))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(36))
    master.paste(Image.alpha_composite(Image.new("RGBA", (W, H), (0,0,0,0)), shadow_layer).convert("RGB"), (0,0), shadow_layer)
    
    # Sheet background: Dark elevated slate (#182030) with subtle glass rim
    sheet_draw.rounded_rectangle([sx0, sy0, sx1, sy1], radius=72, fill=(24, 32, 48, 245), outline=(56, 189, 248, 70), width=4)
    
    # 4. Viewfinder / Scan Corner Reticles on Sheet
    corner_len = 54
    reticle_color = (0, 229, 255, 230)
    ret_w = 6
    pad = 32
    
    rx0, ry0 = sx0 + pad, sy0 + pad
    rx1, ry1 = sx1 - pad, sy1 - pad
    
    # Top-Left
    sheet_draw.line([(rx0, ry0 + corner_len), (rx0, ry0), (rx0 + corner_len, ry0)], fill=reticle_color, width=ret_w)
    # Top-Right
    sheet_draw.line([(rx1 - corner_len, ry0), (rx1, ry0), (rx1, ry0 + corner_len)], fill=reticle_color, width=ret_w)
    # Bottom-Right
    sheet_draw.line([(rx1, ry1 - corner_len), (rx1, ry1), (rx1 - corner_len, ry1)], fill=reticle_color, width=ret_w)
    # Bottom-Left
    sheet_draw.line([(rx0 + corner_len, ry1), (rx0, ry1), (rx0, ry1 - corner_len)], fill=reticle_color, width=ret_w)
    
    # 5. Minimalist Musical Staff Lines (5 lines, centered)
    staff_start_y = sy0 + 260
    staff_line_spacing = 42
    staff_margin_x = sx0 + 72
    staff_end_x = sx1 - 72
    
    for i in range(5):
        ly = staff_start_y + i * staff_line_spacing
        sheet_draw.line([(staff_margin_x, ly), (staff_end_x, ly)], fill=(71, 85, 105, 160), width=3)
        
    # 6. Glowing Optical Music Recognition (OMR) Scan Laser Line
    scan_y = staff_start_y + 2 * staff_line_spacing
    laser_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    laser_draw = ImageDraw.Draw(laser_layer)
    laser_draw.line([(staff_margin_x - 20, scan_y), (staff_end_x + 20, scan_y)], fill=(0, 229, 255, 255), width=4)
    laser_glow = laser_layer.filter(ImageFilter.GaussianBlur(8))
    
    # 7. Iconic Beamed Eighth Notes (Music Emblem)
    # Left notehead at (420, 410), Right notehead at (604, 350)
    note_color = (0, 180, 255, 255)
    note_highlight = (0, 240, 255, 255)
    
    # Noteheads (tilted ellipses)
    def draw_tilted_ellipse(draw_target, cx, cy, rx, ry, angle_deg, fill):
        temp = Image.new("RGBA", (int(rx * 4), int(ry * 4)), (0, 0, 0, 0))
        tdraw = ImageDraw.Draw(temp)
        tdraw.ellipse([rx, ry, rx * 3, ry * 3], fill=fill)
        rotated = temp.rotate(angle_deg, resample=Image.BICUBIC)
        rw, rh = rotated.size
        draw_target.paste(rotated, (cx - rw // 2, cy - rh // 2), rotated)
        
    # Left Notehead
    n1_x, n1_y = 424, 436
    # Right Notehead
    n2_x, n2_y = 608, 380
    
    # Note stems
    stem_w = 12
    stem_top_left = 220
    stem_top_right = 164
    
    sheet_draw.rectangle([n1_x + 22, stem_top_left, n1_x + 22 + stem_w, n1_y], fill=(0, 190, 255, 255))
    sheet_draw.rectangle([n2_x + 22, stem_top_right, n2_x + 22 + stem_w, n2_y], fill=(0, 220, 255, 255))
    
    # Horizontal linking beam (thick polygon)
    beam_h = 28
    beam_points = [
        (n1_x + 22, stem_top_left),
        (n2_x + 22 + stem_w, stem_top_right),
        (n2_x + 22 + stem_w, stem_top_right + beam_h),
        (n1_x + 22, stem_top_left + beam_h)
    ]
    sheet_draw.polygon(beam_points, fill=(0, 210, 255, 255))
    
    # Draw noteheads with rotation
    draw_tilted_ellipse(sheet_layer, n1_x, n1_y, 38, 28, -25, (0, 180, 255, 255))
    draw_tilted_ellipse(sheet_layer, n2_x, n2_y, 38, 28, -25, (0, 225, 255, 255))
    
    # Notehead inner specular shine
    draw_tilted_ellipse(sheet_layer, n1_x - 4, n1_y - 4, 18, 12, -25, (255, 255, 255, 160))
    draw_tilted_ellipse(sheet_layer, n2_x - 4, n2_y - 4, 18, 12, -25, (255, 255, 255, 180))
    
    # Composite all layers onto master
    master.paste(sheet_layer, (0, 0), sheet_layer)
    master.paste(laser_glow, (0, 0), laser_glow)
    master.paste(laser_layer, (0, 0), laser_layer)
    
    return master

def main():
    print("Generating Master 1024x1024 PianoGlass AppIcon...")
    master = create_master_icon()
    
    catalog_dir = "Sources/PianoGlass/Resources/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(catalog_dir, exist_ok=True)
    
    # Standard clean 18-image specification
    specs = [
        # iPhone
        ("AppIcon-20x20@2x.png", 40, 40),
        ("AppIcon-20x20@3x.png", 60, 60),
        ("AppIcon-29x29@2x.png", 58, 58),
        ("AppIcon-29x29@3x.png", 87, 87),
        ("AppIcon-40x40@2x.png", 80, 80),
        ("AppIcon-40x40@3x.png", 120, 120),
        ("AppIcon-60x60@2x.png", 120, 120),
        ("AppIcon-60x60@3x.png", 180, 180),
        # iPad
        ("AppIcon-20x20@1x.png", 20, 20),
        ("AppIcon-20x20@2x~ipad.png", 40, 40),
        ("AppIcon-29x29@1x.png", 29, 29),
        ("AppIcon-29x29@2x~ipad.png", 58, 58),
        ("AppIcon-40x40@1x.png", 40, 40),
        ("AppIcon-40x40@2x~ipad.png", 80, 80),
        ("AppIcon-76x76@1x.png", 76, 76),
        ("AppIcon-76x76@2x.png", 152, 152),
        ("AppIcon-83.5x83.5@2x.png", 167, 167),
        # Marketing App Store
        ("AppIcon-1024x1024@1x.png", 1024, 1024),
    ]
    
    for filename, w, h in specs:
        resized = master.resize((w, h), Image.Resampling.LANCZOS)
        out_path = os.path.join(catalog_dir, filename)
        resized.save(out_path, format="PNG", optimize=True)
        print(f"  [OK] Saved {filename} ({w}x{h})")
        
    # Also save to assets and docs
    master.save("assets/app-icon.png", format="PNG", optimize=True)
    master.save("docs/assets/app-icon.png", format="PNG", optimize=True)
    print("  [OK] Updated assets/app-icon.png and docs/assets/app-icon.png")
    
    # Write clean Contents.json without conflicting universal idiom
    contents_data = {
        "images": [
            {"idiom": "iphone", "size": "20x20", "scale": "2x", "filename": "AppIcon-20x20@2x.png"},
            {"idiom": "iphone", "size": "20x20", "scale": "3x", "filename": "AppIcon-20x20@3x.png"},
            {"idiom": "iphone", "size": "29x29", "scale": "2x", "filename": "AppIcon-29x29@2x.png"},
            {"idiom": "iphone", "size": "29x29", "scale": "3x", "filename": "AppIcon-29x29@3x.png"},
            {"idiom": "iphone", "size": "40x40", "scale": "2x", "filename": "AppIcon-40x40@2x.png"},
            {"idiom": "iphone", "size": "40x40", "scale": "3x", "filename": "AppIcon-40x40@3x.png"},
            {"idiom": "iphone", "size": "60x60", "scale": "2x", "filename": "AppIcon-60x60@2x.png"},
            {"idiom": "iphone", "size": "60x60", "scale": "3x", "filename": "AppIcon-60x60@3x.png"},
            {"idiom": "ipad", "size": "20x20", "scale": "1x", "filename": "AppIcon-20x20@1x.png"},
            {"idiom": "ipad", "size": "20x20", "scale": "2x", "filename": "AppIcon-20x20@2x~ipad.png"},
            {"idiom": "ipad", "size": "29x29", "scale": "1x", "filename": "AppIcon-29x29@1x.png"},
            {"idiom": "ipad", "size": "29x29", "scale": "2x", "filename": "AppIcon-29x29@2x~ipad.png"},
            {"idiom": "ipad", "size": "40x40", "scale": "1x", "filename": "AppIcon-40x40@1x.png"},
            {"idiom": "ipad", "size": "40x40", "scale": "2x", "filename": "AppIcon-40x40@2x~ipad.png"},
            {"idiom": "ipad", "size": "76x76", "scale": "1x", "filename": "AppIcon-76x76@1x.png"},
            {"idiom": "ipad", "size": "76x76", "scale": "2x", "filename": "AppIcon-76x76@2x.png"},
            {"idiom": "ipad", "size": "83.5x83.5", "scale": "2x", "filename": "AppIcon-83.5x83.5@2x.png"},
            {"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "AppIcon-1024x1024@1x.png"}
        ],
        "info": {
            "author": "xcode",
            "version": 1
        }
    }
    
    with open(os.path.join(catalog_dir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents_data, f, indent=2)
    print("  [OK] Updated Contents.json with standard 18-image catalog specification.")

if __name__ == "__main__":
    main()
