# Astra prompt — regenerate the Cofoco Usagi motion set

Recommended task settings:

- Model: `gpt-6-astra`
- Reasoning: `xhigh`
- Run from the Cofoco repository root

Copy the prompt below into a new Codex task.

```text
You are working in the Cofoco repository. Regenerate a coherent candidate set of the Usagi wireframe animation assets using the built-in image-generation tool, then validate the complete set in the local wireframe. This is a visual reference exercise only: the character is user-supplied reference material and is not approved distributable Cofoco artwork. Do not change that rights boundary in product documentation.

Carry the work through generation, normalization, automated checks, contact-sheet review, and motion-preview verification. Do not stop after proposing a plan. Ask a question only if an essential input file is genuinely unavailable. Do not replace the current accepted assets until I explicitly approve the candidate contact sheet and motion preview.

## Sources of truth

Read these before generating:

1. `AGENTS.md`
2. `docs/product-spec.md`
3. `docs/ui-direction.md`
4. `docs/wireframes/todocrew-v1.html`

Inspect the current files in `docs/wireframes/assets/` and measure their actual canvas, alpha bounds, scale, baseline, and center. Use:

- `usagi-smooth-idle-1.png` as the primary character identity, outline, face-to-body ratio, ear, color, and upright visual-scale lock.
- The other current `usagi-smooth-*.png` files only as pose and motion references for their corresponding slots.
- Any Usagi screenshots attached to this task as higher-priority pose references when they show the requested motion more clearly.
- Do not restore outdated poses from `usagi-pixel-*` or `usagi-reference-*`. Those are historical references and conflict with the latest accepted motion design.

## Required deliverables

Create exactly ten independent final PNG candidate frames with genuine alpha transparency:

- `idle`: 2 frames
- `noticed`: 3 frames
- `working`: 3 frames
- `resting`: 2 frames

Save candidates without overwriting the current assets:

`docs/wireframes/assets/astra-candidate/usagi-smooth-{motion}-{frame}.png`

Do not ask the image model for a sprite sheet or a contact sheet as the source asset. Make one image-generation call per frame. Generate sequentially rather than in parallel so every accepted frame can become a reference for the next frame.

Use the built-in image-generation tool. If it exposes an image-model choice, prefer the quality-oriented GPT Image 2.5 Sunburst model; otherwise use the available built-in model and report that the model was not selectable. Do not switch to an API/CLI workflow or require an API key unless I explicitly request it.

## Character lock — invariant across all ten frames

The character must remain recognizably the same drawing across every frame:

- smooth, ordinary non-pixel outline;
- thick, clean, dark brown-black line with the same apparent stroke weight;
- pale cream-yellow body, pink inner ears, pink oval cheeks, and three dark cheek marks;
- large round head and face, slender upright ears, tiny fluffy tail;
- extremely short arms and feet with almost no articulated hand/foot form;
- simple, round, minimally articulated silhouette;
- carefree, empty-headed, cheerfully excited personality; never brave, fierce, determined, athletic, or heroic;
- stable eye size and spacing, eyebrow placement, cheek position, mouth scale, head width, ear width and length, body width, outline weight, palette, and shading treatment;
- no detailed fingers, long limbs, detached arms, stretched body, extra limbs, extra tail, or changing facial anatomy.

Treat `usagi-smooth-idle-1.png` as the identity authority. For each new frame, pass that identity authority, the corresponding pose reference, and the immediately previous accepted candidate in the same motion group as clearly labelled inputs. State the role of each input explicitly in every image prompt: identity/style lock, pose/action reference, or prior accepted continuity frame.

## Style master — palette and line lock

Before generating the first candidate, inspect `usagi-smooth-idle-1.png` and record a compact style master. Reuse this one master for all ten frames; do not let each newly generated frame redefine the style for the next frame.

- Measure and record representative color samples for the body fill, pink inner ears, pink cheeks, dark outline/features, and mouth accents from `usagi-smooth-idle-1.png`. Measure the yellow outfit separately from the current `usagi-smooth-working-1.png`, using that file only as the outfit-color reference. Record actual RGB or Lab values rather than relying only on names such as “cream” or “pink.”
- Measure the apparent outline thickness at several clean locations on the head, ears, and torso at the normalized 768×512 size. Record the median and reasonable range.
- Record whether fills are flat or softly shaded, the shading direction and strength, edge antialiasing, line-cap/line-join character, and the relative thickness of outer contours versus facial features.
- Treat these measured values and `idle-1` together as the fixed style authority. A previous candidate is a continuity reference for pose geometry only; never copy accumulated color, contrast, outline, or proportion drift from it.
- Across the set, keep the same body hue and brightness, cheek and inner-ear pink, outline brown-black, saturation, contrast, highlight/shadow treatment, outer-contour weight, and facial-feature weight. Do not introduce frame-specific warmth, yellowing, desaturation, gradients, glow, texture, or softer/harder lines.
- If pose references have different colors, backgrounds, line weights, proportions, or rendering treatment, copy only their action and silhouette. Never inherit their style.
- After each frame, compare it with the style master before proceeding. Correct only the drifting attribute while preserving the accepted pose and anatomy.

## Frame specifications

### Idle — `idle-1`, `idle-2`

- Frame 1: standing upright, centered, eyes open, neutral carefree face.
- Frame 2: the exact same silhouette and posture; only the eyes close neutrally.
- Closed eyes are not a smile. Do not turn them into happy crescent eyes and do not add a smiling expression. Keep the mouth and all other facial geometry unchanged.
- Motion preview order: `1 → 2 → 1`; frame 2 is visible from 450–1150ms in a 6-second cycle.

### Noticed — `noticed-1`, `noticed-2`, `noticed-3`

- Alert-present motion, replacing every older staff-poke or running interpretation.
- Two extremely short arms stay attached close to the torso, overlap in front, and alternately circle up and down.
- The arm shapes must follow the latest current three noticed frames or attached arm-circle screenshots very closely. Do not reinterpret them as long arms, rings, noodles, a horizontal band, detailed hands, or a fighting pose.
- Frame 1: first arm overlap; head and ears very slightly forward.
- Frame 2: opposite/lower arm overlap; head and ears very slightly back.
- Frame 3: the other arm leads; head and ears return very slightly forward.
- Preserve the full fluffy tail and its small motion marks in every frame. Frame 2 is a known failure case: the complete tail contour and motion marks must be visible with safe transparent margin and must never touch or cross the right canvas edge.
- Expression: open eyes and a small carefree excited open mouth. No aggression or bravery.
- Motion preview order: `1 → 2 → 3 → 2 → 1`, 320ms between every adjacent frame and the next-loop boundary, 1.28 seconds per loop, four loops, then frame 1 held for four seconds.

### Working — `working-1`, `working-2`, `working-3`

- In-progress yellow-outfit dance.
- Frame A/1: centered neutral dance-ready pose.
- Frames B/2 and C/3: the face and ears retain the same upright angle and facial geometry as A. The head must not rotate.
- The torso/body below the head leans strongly in opposite directions for B and C.
- Only the character's left arm—the arm visible on the right side of the image—points outward in both B and C. Do not alternate arms.
- Keep the yellow outfit, face opening, button placement, and outfit outline consistent across all three frames.
- Motion preview order: `A → B → A → C → A`, 160ms between every adjacent frame and the next-loop boundary, 0.64 seconds per loop, four loops, then A held for four seconds.

### Resting — `resting-1`, `resting-2`

- Frame 1: lying down after exhaling, eyes simply closed and neutral.
- Frame 2: the same lying pose while inhaling; only the torso rises/thickens slightly as if breathing in.
- Keep the face, ears, tail, outline, and horizontal body length stable. Do not simulate breathing by scaling the entire image.
- The resting character previously became too large. Match its face/head scale and perceived visual mass to the upright identity frame rather than filling the canvas.
- Motion preview order: `1 → 2 → 1`; frame 2 is visible from 450–1150ms in a 6-second cycle.

## Per-frame image-generation prompt contract

For every image call, include all of the following in a structured prompt:

- Use case: identity-preserving character-frame edit.
- Asset: one Cofoco wireframe pet animation frame.
- Input roles: identify the identity/style lock, pose reference, and prior accepted continuity frame by filename.
- Primary request: redraw one complete character as a new high-resolution raster illustration matching the specified pose.
- Invariants: repeat the character-lock properties, measured palette anchors, outline-weight target, and rendering treatment, and name everything that must remain unchanged from the identity frame.
- Intended change: describe only the pose or eye/breath change for this one frame.
- Composition: exactly one centered full character with the full ears, feet, hands, tail, and motion marks visible.
- Background: perform one real-alpha capability test for the set by requesting genuine alpha transparency and PNG output. If the tool returns an opaque file or bakes a checkerboard despite that request, switch the whole remaining set to the deterministic foreground-segmentation workflow below rather than repeating transparency-only redraws.
- Avoid: scenery, patterned or checkerboard backgrounds, environmental shadows, grass, props, text, watermark, cropping, extra anatomy, long limbs, detailed hands, altered face, altered character scale. A plain temporary matte is permitted only as the documented source for foreground segmentation after real-alpha generation has failed.

Do not use vague phrases such as “same as before” for critical invariants. Restate them on every call. If a frame drifts, edit or regenerate only that frame and request only the single correction while restating all invariants.

## Transparency and file rules

Transparency is a hard final-file acceptance condition, but it is separate from character generation quality. This section replaces any earlier instruction that prohibited foreground extraction or background removal.

- At the start of the set, perform one capability test by explicitly requesting transparent background and PNG output, then decode the returned file instead of trusting its extension or preview. If `docs/wireframes/assets/astra-candidate/README.md` already records a decoded RGB/checkerboard failure from the same built-in workflow, treat that evidence as the test and do not spend another generation on it. A drawn gray/white checkerboard is an opaque RGB background, not transparency.
- If the capability-test output has genuine alpha, continue requesting genuine alpha for subsequent frames after confirming RGBA/sRGBA, `opaque=False`, and alpha 0 at all four corners.
- If the capability test is opaque or contains a baked checkerboard, stop transparency-only retries for the entire set. For subsequent generations request a plain, textureless temporary matte that contrasts with the character—never a checkerboard, scenery, shadow, or patterned background—then remove that matte with the subject-aware foreground-segmentation workflow. The matte is a processing source, never a final asset.
- If an opaque/checkerboard output's character, pose, anatomy, palette, scale, and outline pass visual review, do not regenerate merely to obtain transparency. Preserve it as the accepted raw source and derive the final transparent candidate with foreground segmentation.
- Prefer a subject-aware foreground mask such as macOS Vision `VNGenerateForegroundInstanceMaskRequest`. Do not use checkerboard-color deletion, a simple color key, flood fill, or thresholding as the primary method; those methods can erase the pale body and contaminate antialiased outlines.
- Background removal may change only alpha. It must not repaint, recolor, reshape, translate, rotate, scale, sharpen, or blur the character. It does not make a structurally incorrect generated frame acceptable.
- Preserve the entire dark outline, ear tips, tiny feet and arms, fluffy tail, and antialiased edge pixels. Explicitly inspect isolated motion marks, which a subject mask may omit; refine or union the mask when needed instead of silently dropping them.
- Inspect the source and transparent result side by side at 200% on white, mid-gray, and near-black backgrounds. Reject halos, checkerboard remnants, jagged cutouts, missing lines, thinned outlines, filled interior holes, and clipped appendages.
- Save the unmodified generated source under `docs/wireframes/assets/astra-candidate/raw/` and the alpha-cleaned final frame at the required candidate path. Record the source-to-final mapping and the extraction method used.
- A frame may receive one targeted regeneration for an actual character, pose, anatomy, style, or cropping failure. Do not spend repeated generation attempts on transparency alone once foreground segmentation is available.
- Final candidates must decode as RGBA/sRGBA PNG, report `opaque=False`, have alpha 0 at all four corners, and contain no baked checkerboard or matte pixels outside the intended foreground.
- Do not leave project-consumed assets only under `$CODEX_HOME/generated_images`.

## Canvas, scale, and normalization

Generate at the tool's supported high-resolution landscape size with generous clear space around the subject. After genuine-alpha generation or foreground extraction, normalize accepted candidates to 768×512 transparent PNG without stretching, rotating, skewing, or non-uniform scaling.

- Preserve aspect ratio.
- Center the upright character at x=384 within a few pixels.
- Upright frames should have approximately 420–430px of visible alpha height, with a small transparent safety margin on every edge.
- Match core head and torso scale across idle, noticed, and working within roughly 3%; extended arms may widen the outer alpha bounds but must not change the core character scale.
- Resting frames may be wider, but their face/head size and perceived mass must match the upright frames. Use approximately the current 465–480px outer width only as a starting reference, not a reason to enlarge the head.
- Frames within one motion group must share the same baseline. Intentional body lean, head bob, arm extension, and breathing are allowed; accidental whole-character jumps are not.
- Normalization may align canvas, scale, and baseline. It must not manufacture animation by translating or rotating one frame, and it must not conceal a mismatched drawing.
- Ensure no nontransparent pixel touches a canvas edge. Tail and ear cropping are automatic failures.

## Validation before asking for approval

Validate every candidate and record the evidence:

1. File inventory: exactly 10 candidate PNGs with unique hashes.
2. Canvas: every file exactly 768×512.
3. Alpha: every file has a real alpha channel, is not fully opaque, and has transparent corners.
4. Bounds: report the nontransparent bounding box, center, baseline, and safe edge margins for every frame.
5. Consistency: compare head width/height, ear width/length, eye spacing, cheek placement, and core torso size. Compare every frame against the recorded style master for body/ear/cheek/outline colors, saturation and brightness, shading treatment, and apparent outline/facial-feature weight. Report measured samples and representative stroke-width readings; flag geometry deviations over roughly 3% and visible or measured style drift unless clearly required by the intended pose.
6. Anatomy: inspect all arms, feet, ears, tails, and motion marks. Explicitly confirm that noticed frame 2's tail is complete.
7. Expression: explicitly confirm idle frame 2 and both resting frames use neutral closed eyes rather than a smiling expression.
8. Contact sheets: render the 10 candidates at the same display scale on light gray, dark gray, and checkerboard QA backgrounds. Checkerboard is for the QA sheet only, never baked into the asset.
9. Motion sheets: render the exact orders `idle 1-2-1`, `noticed 1-2-3-2-1`, `working A-B-A-C-A`, and `resting 1-2-1` side by side.
10. Preview: make a temporary candidate preview of `docs/wireframes/todocrew-v1.html` without overwriting the accepted wireframe or assets. Verify the four motion toggles at their current timing, including every next-loop boundary and the four-second holds for noticed/working.
11. Reduce Motion: verify that each motion remains static on its primary frame.
12. Cleanup: remove temporary scripts, servers, and preview files that are not part of the review deliverable.

If a check fails, regenerate only the failing frame. Do not lower an acceptance threshold merely to finish. Do not overwrite the existing `usagi-smooth-*` assets, edit the accepted wireframe, or update product decisions before I approve the candidate set.

## Final response

Lead with whether the full candidate set passed. Include:

- links to the candidate directory, three QA contact sheets, four motion sheets, and the temporary motion preview;
- a compact per-frame validation table;
- every regenerated frame and why it was retried;
- every frame that required foreground segmentation, its raw source, the method used, and whether mask refinement was needed;
- the actual image-generation model used or “not selectable”;
- the measured style-master palette and outline-weight range, plus any remaining per-frame drift;
- the final prompt used for each motion group;
- any remaining mismatch or uncertainty;
- a clear statement that the accepted wireframe assets remain untouched pending approval.

Do not commit, publish, or claim these user-supplied character derivatives as distributable Cofoco artwork.
```
