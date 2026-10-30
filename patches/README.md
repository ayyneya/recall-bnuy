# Integration patches

## DXMT

These apply to commit `c5dc3a0dfe9108e667da43de871324bd298c9c02` of
[NerRobDog/dxmt](https://github.com/NerRobDog/dxmt), in this order.

`dxmt-v1-private.patch` is the complete DXMT integration patch: the fullscreen
canvas, presentation and shader/pipeline caching tuned for Overwatch.

`dxmt-v1-performance.patch` is the 1.0 performance work:
- Render targets that Overwatch marks as writable by compute shaders but never
  uses that way keep Apple's lossless compression; the first real use moves the
  texture to a writable copy. Each frame takes about a fifth less GPU time.
- CPU and GPU waits wake exactly when the work is done instead of polling.
- Frame pacing: after the frame-latency wait, the game thread sleeps for most
  of the time the GPU still needs, so the next frame samples input later at
  the same GPU load. It is on only when the renderer profile enables it
  (`dxgi.presentPacing`; the app's profile uses mode 3 with a 1 ms margin).
- Shader variants are prepared when the game creates its shaders
  (`DXMT_PREPARE_SHADERS=1`), and variants that translate to the same code share
  one cache entry.
- Developer diagnostics that stay off unless their environment variable is set:
  a frame log, a call recorder for off-screen replay, and replay tools.

`dxmt-portable-metal.patch` makes both Metal build steps run through
`scripts/portable_metal.py`, which keeps the build machine's paths out of the
compiled shaders.

`dxmt-shader-pack.patch` (1.4) lets the shader pack hold every pipeline the
game has used on the Mac. The pipeline cache keeps learning until the disk is
nearly full, with no size limit of its own; it checks each archive in 1 MiB
pieces instead of reading it into memory whole; and Recall's preparation tool
can add a batch of pipelines as one more archive (`DXMT_PIPELINE_CACHE_APPEND`)
instead of rebuilding the pack, so preparation after a session can be stopped
and resumed without losing finished work. A game checks the archives on all cores
at once and loads them in order, slowest pipelines first, as much as Recall's
Shader memory setting allows (`load.json` beside the pack: all of it unless the
player chose less), and keeps loading past its startup deadline; only the
preparation tool adds to the pack.

`dxmt-metalfx-upscaling.patch` is MetalFX upscaling (1.3): with Recall's
MetalFX upscaling setting on, Overwatch offers NVIDIA DLSS, which runs on
Apple's MetalFX temporal upscaler.
- The adapter and NVAPI report one NVIDIA GeForce RTX 4090, so the game offers
  DLSS. This happens only when `DXMT_ENABLE_NVEXT=1`; the stand-ins refuse to
  load otherwise.
- DXMT's DLSS stand-in (`nvngx.dll`) gains Direct3D 12 entry points that report
  "not supported" and NVIDIA's own failure codes. A `d3d12.dll` stand-in answers
  the setup questions of NVIDIA Streamline (shipped with the game), which builds
  a Direct3D 12 helper even in Direct3D 11 games; it creates nothing and refuses
  feature level 12_2, so the game stays on Direct3D 11.
- The DLSS output is made shader-writable before MetalFX writes it (see the
  compression change in `dxmt-v1-performance.patch`).
- Jittered motion vectors, which MetalFX cannot cancel, lose the change in
  jitter since the last frame in a small compute pass, as AMD FSR 2 does.
- The DLSS mode the player chooses is the lowest render size the stand-in
  offers.
- Optional sharpening after MetalFX (`d3d11.metalfxSharpness`, 0 to 1), with
  the method of AMD FidelityFX RCAS on tone-mapped values.
- Both compute passes are compiled by macOS at run time, so DXMT's precompiled
  shaders are unchanged.

`build_portable_dxmt.py` signs the built `nvngx.dll` (Authenticode, SHA-256)
with `scripts/sign_pe.py`: NVIDIA's loader, part of the game, loads only a
signed core DLL.

### Pawpad (Aniimo)

`build_portable_dxmt.py` applies these after the patches above, in this order,
each checked against its SHA-256 in the script:

- `dxmt-skip-failed-compute.patch`: dispatches of a compute pipeline Metal
  refused are skipped (Apple's driver otherwise divides by zero and the game
  freezes at 100% loading), and the refusal is logged.
- `dxmt-record-trigger.patch`: the call recorder starts when the file named by
  `DXMT_RECORD_TRIGGER` appears (checked every 30 presents, then deleted).
- `dxmt-upstream-airconv.patch`: upstream 3Shain/dxmt d1c926c, ae91269, 9839e55
  and 64ee6f5. d1c926c fixes the invalid IR for a vector `firstbit_shi` that made
  Metal refuse Aniimo's shader 32f49794 ("Failed to materializeAll").
  AIRCONV_VERSION becomes 124, so shaders translate again once.
- `dxmt-upstream-display-leaks.patch`: upstream d815f7f and a741a3f (a display
  query per Present leaked memory on macOS 27).
- `dxmt-upstream-texture-fixes.patch`: upstream e40c9d7 (copies between texture
  types were dropped) and f9beaea.
- `dxmt-log-refused-allocations.patch`: an error line, rate-limited, when Metal
  refuses a buffer or texture (a refused texture samples as black or clear).
- `dxmt-skip-failed-render.patch`: draws of a render pipeline Metal refused are
  skipped instead of running with the previous pipeline.
- `dxmt-depth-rename-cap.patch`: `DXMT_DEPTH_RENAME_CAP` (default 32) caps the
  copies a depth texture gets from full clears in one command buffer, and logs
  when they pile up.
- `dxmt-pass-timing.patch`: a diagnostic, off unless `DXMT_PASS_TIMING=<file>`
  is set: a GPU timestamp before every encoder, labelled with the pass and its
  shaders (`DXMT_PASS_TIMING_BARRIER=1` keeps the GPU from reordering them).
- `dxmt-frame-log-segments.patch`: the frame log keeps 3 x 8 MB instead of
  3 x 2 MB, about 80 minutes of frames at 45 FPS.
- `dxmt-defer-pixel-format-view.patch` (`DXMT_DEFER_PIXEL_FORMAT_VIEW=1`, set by
  Pawpad's Aniimo profile): typeless 2D colour render targets start without
  PixelFormatView, which on Apple GPUs turns off lossless compression. When a
  view in another format is created, the texture's next bind moves it to an
  allocation with that usage, in stream order (the path the deferred
  ShaderWrite of `dxmt-v1-performance.patch` already uses).
- `dxmt-review-fixes.patch`: fixes from the 30 Oct code review of the patches
  above. Views DXMT makes itself in another format (ResolveSubresource and the
  render+resolve merge, ClearView with rects, MetalFX's motion vectors) move a
  deferred texture first; a view in another format of an allocation without
  PixelFormatView is made when first used, not when queued commands touch the
  allocation; multisample targets aren't deferred. Metal refusing an
  allocation no longer leaves a resource without storage in use: a move or a
  depth rename keeps the texture where it is, and `Map(WRITE_DISCARD)`,
  CreateBuffer and texture creation fail with `E_OUTOFMEMORY`. The record
  trigger starts one recording per file and switches itself off when the file
  can't be deleted; `DXMT_PASS_TIMING` alone registers the shader tags; the
  display query frees every ICC tag it reads.
- `dxmt-rename-uav-buffers.patch` (`DXMT_RENAME_UAV_BUFFERS=1`, off by default):
  a whole-buffer `UpdateSubresource` of a GPU-writable (UAV) DEFAULT buffer gets
  a fresh CPU-writable allocation, as `Map(WRITE_DISCARD)` does for other
  buffers, instead of a staging copy in a blit encoder that splits the compute
  work around it. Aniimo does ~82 such updates a frame; replay of the hub with
  the screen covered: GPU 33.56 -> 33.41 ms a frame.
- `dxmt-gpu-error-detail.patch` (`DXMT_GPU_ERROR_DETAIL=1`, off by default):
  command buffers record every encoder's execution state, and a failed one logs
  which passes completed, were running (affected), faulted or never started,
  with their labels (`DXMT_BENCH_LABELS=1`). For diagnosing GPU hangs and
  resets; no measured GPU cost.
- `dxmt-ngx-evaluate-c.patch`: the DLSS stand-in (`nvngx.dll`) also exports
  `NVSDK_NGX_D3D11_EvaluateFeature_C` (and the D3D12 one, unsupported as
  before). NVIDIA's DLSS helpers evaluate through it.
- `dxmt-ngx-streamline-resources.patch`: NGX parameters stored through the
  `void *` setter read back as D3D11/D3D12 resources and the other way round.
  Streamline (`sl.dlss`) passes the color, depth, motion and output textures
  that way; the stand-in's evaluation failed at its first `Get` without a word,
  so Aniimo (DLSS through Streamline) showed a black world. A failed evaluation
  now names the input it lacked, once.

`build_portable_dxmt.py` resets its DXMT tree (`<workspace>/dxmt-source`) only
when it holds nothing but what an earlier run put there
(`<workspace>/dxmt-source.prepared.json`): edits or new files stop the build
until they are exported to a patch, or `--discard-dxmt-changes` throws them
away. A tree prepared from the same patches is reused as it is, so the build
stays incremental.

## Wine

These apply to the `sources/wine` subtree of the
[CodeWeavers Wine 26.3.0 source archive](https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz),
in this order, with `wine-portable-directory-boolean.patch` and Soju's
`ncrypt-persisted-keys.patch` after the second.

`wine-v1-canvas.patch` preserves the fullscreen and focus integration of the
Mac driver.

`wine-mouselook.patch` adds mouselook with raw mouse input for games listed in
`WINEMAC_MOUSELOOK`; the app lists `Overwatch.exe`. While such a game hides and
confines its cursor:
- the Mac pointer is frozen;
- mouse motion reaches Wine as raw mouse counts from Apple's Game Controller
  framework, at the mouse's full report rate, as on Windows;
- trackpads keep macOS pointer events.

`wine-server-registry-save.patch`: the Wine server writes its periodic registry
save from a forked copy of itself, so the game no longer pauses for about a
tenth of a second every 30 seconds. `WINESERVER_REGISTRY_LOG` names every change
to a saved key (off unless set).

`wine-ntdll-syscall-log.patch`: a DLL's Unix library is loaded without holding
Wine's virtual-memory lock, which removes the 150–400 ms freezes that hit during
matches. From 1.1, the programs named in `WINE_GAME_MODE` (Recall sets
`Overwatch.exe`) start from the engine's game app,
`lib/wine/game-mode/Overwatch.app`: a copy of Wine's loader in a bundle that
declares itself a game, which is what macOS needs to turn Game Mode on.
`scripts/game_mode_app.py` makes it. `WINE_SYSCALL_LOG` and `WINE_IO_ERROR_LOG`
are developer diagnostics (off unless set).

`wine-win32u-display-log.patch`: `WINE_DISPLAY_LOG` records each forced
display-device update with its reason and duration (off unless set). The
programs named in `WINE_APP_DPI` get their own DPI for the system and every
monitor, as Windows programs do at that scaling; everything else, and Wine's
shared record of the displays, keeps the session's DPI. Wine's Retina mode
shows each Windows pixel at half a point on every display, so Recall names
Battle.net's programs at 192, the size Battle.net has on Windows at 200%, while
Overwatch sees 96 as before.

`wine-winemac-activation.patch` applies to the Mac driver after the two driver
patches above:
- macOS announces the game as active again on every left click; the driver
  re-reads the display list only after the game had actually been inactive, so
  clicks no longer cost a frame;
- the fullscreen letterbox bars stay black, and on a 1x external monitor the
  drawable is capped at the monitor's own pixels;
- when the game moves or resizes its window in fullscreen, the driver answers
  with the fullscreen frame, so the pointer, the communication wheel and menu
  clicks stay lined up with what is drawn;
- the fullscreen canvas takes 1080p, 1440p and 4K in 16:10 and 16:9 (up to
  3840 × 2400), and each display lists those of them that fit it, so the game
  can choose them on a monitor that lacks the mode; setting the display itself
  to one still fails, and the canvas never changes the display's mode;
- it also takes any larger resolution that fits inside a display, such as an
  ultrawide or 5K monitor's own size (5120 × 2160, 5120 × 2880), which the game
  offers in its Video settings; the game had drawn those inside a 16:9 frame
  with black bars on all four sides;
- after you switch to another app from the game in fullscreen, the game stays
  minimized and out of fullscreen until you come back to it: on macOS its own
  requests to restore the window or re-enter fullscreen would bring it back to
  the front;
- with Korean account support on (`WINEMAC_SCREEN_READBACK=1`, which the app sets on the Korea region),
  reading the screen back (BitBlt or StretchBlt from the screen) gives a black
  image instead of failing, so the anti-cheat in the Korean build of Overwatch
  no longer crashes the game when it takes a screenshot. No pixels are read;
  without the variable the call fails as before;
- with `WINEMAC_INPUT_VARIANT=precise`, which the app sets from 1.5:
  - mouse buttons come from the Game Controller framework's mouse input, as the
    motion does, and each one reaches the game after the motion that came before
    it, as on Windows. macOS's own copy of each click held it until the next
    display refresh, so shots during a flick landed past where the player clicked;
  - moves carry the time they were delivered and go out as soon as a millisecond
    has passed since the last delivery;
  - if the Game Controller mouse input goes quiet, pointer events stand in at the
    mouse's own scale, and its handlers are set again. A trackpad alone keeps the
    pointer's scale, so it can aim too.

  Without the variable, input behaves as in 1.4.
`WINEMAC_INPUT_STATS` writes an input report (off unless set).

Menus, Battle.net and every other program keep the standard behavior.

`wine-rsaenh-hmac.patch` (Pawpad) applies after `wine-winemac-activation.patch`.
Aniimo's sign-in computes an HMAC-SHA256 through the legacy CryptoAPI
(`CryptSetHashParam(HP_HMAC_INFO)` with `CALG_SHA_256` on a `PROV_RSA_FULL`
provider). Wine 11.0's `rsaenh` refused SHA-256 as the inner hash because that
provider doesn't list it, reported success anyway and left the hash empty, so the
next `CryptHashData` crashed the game about 20 seconds after it opened
([Wine bug 60345](https://bugs.winehq.org/show_bug.cgi?id=60345), seen on
CrossOver 26.2 and 26.3). Windows accepts any hash it implements there. This is
upstream commit `4352d975bea6bd4d453b7d4e8875cc4b2335cfc4` (Wine 11.19), ported
from SymCrypt to the TomCrypt `rsaenh` that CrossOver 26.3 still has: the inner
hash comes from `init_hash_impl` whether or not the provider lists it, its size
from TomCrypt's descriptor, and an unknown hash fails with `NTE_BAD_ALGID`.

Apply each patch once, in this order, first using `git apply --check`.
Do not combine them with historical candidate patch variants.
See [build status](../docs/BUILDING.md) and
[third-party notices](../THIRD_PARTY_NOTICES.md).
