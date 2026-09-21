# Floating shop home screen — reference v1

Generated using the built-in image generation tool. These images are design references, not implemented game screens or device compatibility evidence. No game scenes or project settings were changed in this reference pass.

## Direction

A single matte, rounded floating shop is the focal point. Light blue bubbles and sparkle patterns sit behind it. The top row contains cash and settings; the bottom dock contains Home, Items, Blueprints and Bonzi. The building itself starts/resumes a rug; the only persistent instruction is “Tap to clean” (or “Tap to resume”). The reference number 120 is illustrative; implementation must use saved cash.

In the live scene the shop should be a real 3D model with slow rotation and a gentle bob, not a rotating screenshot. Keep icons and text as independent native controls. Keep quests, upgrade descriptions and detailed income data in their appropriate panels, opened by the dock. Surface actionable messages temporarily, and keep existing return-reward acknowledgement and error handling accessible.

## Existing project inspection

- Main scene: CarpetToy/scenes/test/shop_hub.tscn.
- Controller: CarpetToy/scripts/shop_hub.gd.
- Existing storefront is an editable 2D illustration scene.
- Current project viewport: 720 × 1000, canvas_items stretch, portrait orientation setting.
- Existing pages already use containers and preserve state. Retain their functional bindings and saved economy when implementing the new home.
- No running Godot editor process was detected during inspection; source files were inspected directly.

## Responsive implementation specification

- Full-rect patterned background extends to all edges with no stretched pattern.
- Layout within the device safe area, accounting for camera cutouts and gesture bars.
- Independent anchored top controls and centered bottom dock; never bake them into the background.
- Fit the building uniformly into the space between top controls and dock, taking both width and height into account. Reserve a separate small hint slot.
- In portrait, the dock fills available width with modest side margins. In landscape, cap dock width and center it, leaving open space at either side of the building.
- Use a dedicated 3D viewport/camera with framing based on its available rectangle. Allow enough room for the complete model through every rotation angle and the full bob amplitude.
- Keep touch targets at least 48 logical pixels, with distinct focus/pressed states. Icon-only tabs need accessible names/tooltips.
- Respect reduced-motion preferences with a stationary alternative. A tap activates cleaning; dragging should not accidentally trigger a job.
- Expand layout with viewport aspect ratio instead of stretching the composed reference image. Support orientation changes explicitly if landscape play is enabled.
- Verify portrait and landscape at logical sizes 320×568, 360×800, 390×844, 430×932, and 768×1024 plus reversed dimensions. Check notches/insets, large cash values, resume state, and error/return messages.
- Desktop layout checks are insufficient to claim every-phone compatibility: Android/iOS export, safe-area handling and real-device input remain to be tested.

## References

- home-portrait-v1.png
- home-landscape-v1.png

The landscape reference has the desired opaque edge-to-edge background. The portrait generation has faint edge artifacts; these should not be reproduced in the live background.

## Exact portrait prompt

Use case: ui-mockup
Asset type: polished mobile game home screen visual reference, portrait 9:19.5 composition, full bleed screen with no phone frame.
Primary request: A beautifully uncluttered main home screen for a cozy carpet-cleaning game. A single floating 3D shop building is the centerpiece, inviting the player to tap it to open a rug-cleaning job. Friendly Duolingo-inspired visual simplicity, chunky matte shapes and softly curved beveled edges, original art with no Duolingo characters or branding.
Scene/backdrop: powder light blue background with a very subtle repeating pattern of widely spaced tone-on-tone bubbles, tiny four-point clean sparkles and curved swishes. Very low contrast, lots of calm empty blue space.
Subject: one charming miniature carpet cleaning shop on a small rounded square floating foundation, shown in three-quarter isometric view. Cream walls, soft mint-green rounded roof, mint and cream striped awning, large deep blue shop window, warm coral rounded door, small simple rug emblem above the awning instead of text. One rolled rug beside the door. Building feels like a tactile matte 3D game asset, broad rounded edges and soft ambient occlusion, almost no texture. An elliptical diffuse blue shadow below visibly separates the floating foundation from the background. This is a building meant to slowly rotate in the actual game; show a clean still frame, no motion trails or arrows.
Composition/framing: Center the building horizontally around 48 percent screen height. Building occupies about 65 percent of screen width and 28 percent of screen height. Preserve abundant negative space above and below. At top left, one small off-white rounded pill with a chunky golden coin icon and the number '120'. At top right, a single off-white circular settings gear button. Keep the top controls inside a generous phone safe area. Just beneath the building show only the small friendly rounded dark-blue text 'Tap to clean'. No other central text.
At bottom, a softly rounded off-white navigation dock inset generously from left/right and bottom safe areas, with exactly four equally spaced large chunky icons: home building, cleaning brush, blueprint sheet, friendly small cleaning robot. First home icon selected with a pale mint rounded square background. No text labels. Controls look touchable, with subtle lower rim depth. Dock must remain visually subordinate to the building. Lots of clear air between dock and building.
Lighting/mood: soft studio daylight, gentle shadows, cozy, playful, calm, premium mobile game art.
Palette: light blue background, cream white surfaces, mint green, restrained coral accents, muted navy details, gold coin.
Text (verbatim): '120', 'Tap to clean'. These are the ONLY words/numbers on screen.
Constraints: one screen only, no framing device, no presentation headings, no caption outside the interface. Clear touch targets, very little text. No quest cards, no banners, no large title, no popups, no extra currencies, no status bar, no landscape scenery, no clouds obscuring the building, no glossy plastic, no photorealism, no thin wireframe icons, no watermarks.

## Exact landscape prompt

Use case: ui-mockup
Create a second, LANDSCAPE mobile game home screen reference adapting the previous portrait image. Wide horizontal canvas, approximately 19.5:9. Input image role: visual style and interface reference. Preserve the exact same charming matte rounded mint-roof carpet shop, cream walls, coral door, rug emblem, floating foundation, light blue subtle bubble/sparkle pattern, coin pill, gear button and four navigation icons. Recompose for LANDSCAPE, do not crop or stretch the portrait screenshot. The whole building floats at the screen center and is fully visible, scaled to comfortably fit the available HEIGHT between the upper controls and bottom dock; generous open blue space at either side. Top left inset coin pill with '120'; top right inset circular gear button. Small text 'Tap to clean' just beneath building. Compact horizontally centered cream navigation dock near the bottom with four chunky icons (home selected pale mint, brush, blueprint, cleaning robot); dock occupies only about 40 percent screen width and is comfortably separated from hint and building. Controls comfortably inset from all edges for phone safe areas. Keep whole screen sparse, clear and calm. Same soft matte 3D art style. Full bleed OPAQUE light blue background all the way to every edge, no transparency or distressed edges. ONLY text is '120' and 'Tap to clean'. No device frame, no extra cards, captions, headings, characters or labels. Single wide screen.

