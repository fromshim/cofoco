# TodoCrew Usagi generation — blocked at native alpha gate

Date: 2026-09-10  
Overall result: **FAIL / incomplete — 0 of 10 accepted candidate frames.**

This validation record was created while the product's working name was TodoCrew; the current name is Cofoco. Original prompts below are retained verbatim as evidence.

The built-in image-generation tool was called sequentially three times for idle-1. Every returned PNG decoded as RGB (PNG IHDR color type 2), without alpha or a transparency chunk, and visually contained an opaque checkerboard. The original identity input was RGBA. Two targeted transparency corrections did not resolve the failure. This is observed behavior in these three calls; it does not establish a universal limitation of every image model.

The tool exposed no model, native background, or output-format selection parameters. The actual selected model was **not selectable**; “GPT Image 2.5 Sunburst” was not available as a selectable option. PNG/alpha and high-resolution landscape requirements were explicitly requested in every prompt.

## Evidence and prompts

- [All three raw rejected generations](raw/)
- [Rejected-attempt comparison](review/rejected-idle-1-attempts.png) — failure evidence only, not a candidate contact sheet
- [Exact prompts actually submitted, including both corrections](review/prompts.json)
- [Decoded output validation and hashes](review/validation.json)
- [Existing accepted-source measurements](review/source-inventory.json)
- [Existing-source contact sheet](review/source-contact.png) — existing assets only
- [Before hashes of protected files](review/protected-hashes.json)

## Per-frame status

A dash means no valid candidate measurement exists, not a passed or zero-valued measurement.

| Requested candidate | Calls | Canvas | Alpha / opaque | Bounds / center / baseline / margins | Result |
|---|---:|---|---|---|---|
| idle-1 | 3 | raw: 1536×1024 | absent / true | — | All 3 rejected |
| idle-2 | 0 | — | — | — | Not generated |
| noticed-1 | 0 | — | — | — | Not generated |
| noticed-2 | 0 | — | — | — | Not generated |
| noticed-3 | 0 | — | — | — | Not generated |
| working-1 | 0 | — | — | — | Not generated |
| working-2 | 0 | — | — | — | Not generated |
| working-3 | 0 | — | — | — | Not generated |
| resting-1 | 0 | — | — | — | Not generated |
| resting-2 | 0 | — | — | — | Not generated |

No rejected generation was used as an accepted continuity reference. Subsequent groups were not generated once the native-alpha prerequisite repeatedly failed.

## Retry history

1. **idle-1, attempt 1:** initial identity-preserving redraw, true RGBA PNG requested. Rejected: RGB, no alpha, baked checkerboard.
2. **idle-1, attempt 2:** targeted actual-file transparency correction; explicitly prohibited illustrating a transparency grid. Rejected for the same decoded and visible failure.
3. **idle-1, attempt 3:** targeted alpha-preserving edit of the original RGBA reference; required preservation of the input's native alpha. Rejected for the same failure.

The final executed idle-group prompt is attempt 3 in prompts.json. No noticed, working, or resting prompt was submitted, so there are no final executed prompts for those groups.

## Completed and outstanding validation

Completed: source inspection and canvas/alpha-bounds/center/baseline measurements; three sequential built-in generation calls; raw preservation; PNG decoding; alpha/corner checks; visual inspection of the baked backgrounds; unique raw SHA-256 hashes; source preservation checks.

All 10 existing smooth frames are 768×512 RGBA. Existing upright alpha height is approximately 428–430px; existing resting width is 480px. Nine of the existing files have nontransparent pixels on their bottom canvas edge; working-3 has a five-pixel bottom margin. These are source measurements, not candidate acceptance evidence.

Not performed because no valid transparent source was produced: normalization, a ten-file candidate inventory, three candidate QA background contact sheets, four candidate motion sheets, candidate wireframe preview, browser timing/loop-boundary/hold verification, Reduce Motion verification, quantitative 3% feature consistency, and candidate anatomy/expression acceptance. In particular, no claim is made that noticed-2's tail, idle-2's neutral eyes, or resting frames pass.

No foreground extraction, chroma key, background deletion, or opaque-to-RGBA conversion was used to fabricate transparency. No fallback API/CLI workflow was used.

## Preservation and cleanup

SHA-256 comparison verified **30 protected files unchanged**, including every existing asset, the accepted wireframe, AGENTS.md, product documents and ADR 0002. No commit or publication was made. No temporary script, server or candidate preview was created. All retained files under this directory are raw failure evidence or review records.

The accepted wireframe assets remain untouched pending explicit approval of a future valid candidate set. These user-supplied character derivatives remain visual reference material and are **not approved distributable Cofoco artwork**.
