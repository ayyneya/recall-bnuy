/* Aniimo's settings: the environment every Wine process of Pawpad's gets, and the renderer
 * (DXMT) profile written to <data>/dxmt.conf for the game. Pawpad used to take both from Recall:
 * its Overwatch contract (candidateEnvironment, scripts/candidate_contract.generated.h) and the
 * engine's [Overwatch.exe] dxmt.conf, filtered. They are written out here instead, without the
 * Overwatch-only parts (the program names, the OW pipeline-cache namespace, DLSS, the fullscreen
 * canvas). Values marked "Recall's tuning" were tuned for Overwatch and are still to be measured
 * for Aniimo; a value changes here only with a measurement behind it (pawpad-lab perf-goal).
 *
 * pawpadProfileVersion goes into every session record, so reports can tell profiles apart. */
static NSString *const pawpadProfileVersion=@"aniimo-4";
static NSDictionary *aniimoEnvironment(NSString *game) {
    return @{
        // CrossOver's engine: DXMT for D3D10/11, built-in d3d11/dxgi/d3d10core/winemetal; no
        // D3D12, NVAPI or DLSS (Aniimo is D3D11 only).
        @"CX_ACTIVE_GRAPHICS_BACKEND":@"dxmt",@"CX_GRAPHICS_BACKEND":@"dxmt",
        @"WINEDLLOVERRIDES":@"d3d11,dxgi,d3d10core,winemetal=b;d3d12,nvapi64,nvngx=",
        // Without it Wine rebuilds ACLs from Unix modes (Recall's REC-6). Kept: general Wine
        // behaviour, untested for Aniimo without it.
        @"CX_HACK_FILESYSTEM_TYPE":@"1",
        // Presentation: three drawables, no overlay (Recall's tuning).
        @"DXMT_CANVAS_DRAWABLES":@"3",@"DXMT_CANVAS_OVERLAY":@"0",
        // Shaders: prepared on DXMT's compiler threads, Metal's own cache on, and the pipeline
        // cache in Pawpad's namespace. Prewarm 128 pipelines within 10 s (Recall's tuning: Overwatch
        // has far fewer shaders than Aniimo's ~3,900 a session).
        @"DXMT_PREPARE_SHADERS":@"1",@"DXMT_USE_DEFAULT_METAL_CACHE":@"1",
        @"DXMT_PIPELINE_CACHE_NAMESPACE":@"aniimo-v1",@"DXMT_PIPELINE_CACHE_PREFER_EXPENSIVE":@"1",
        @"DXMT_PIPELINE_CACHE_PREWARM_LIMIT":@"128",@"DXMT_PIPELINE_CACHE_PREWARM_MS":@"10000",
        // Typeless render targets without PixelFormatView until a view in another format needs it
        // (patches/dxmt-defer-pixel-format-view.patch): keeps Apple's lossless compression on the
        // game's HDR and G-buffer targets. Replay of the hub, 30 Oct: GPU 37.0-37.5 -> 34.7-35.0 ms
        // a frame, images within the engine's own noise, no Metal validation errors.
        @"DXMT_DEFER_PIXEL_FORMAT_VIEW":@"1",
        // GPU resets in play (30 Oct, 13 of ~10 s in 10 minutes: WindowServer's GPU timeout, the
        // game's work discarded): a failed command buffer logs which passes ran, faulted or never
        // started, by label (patches/dxmt-gpu-error-detail.patch). Covered replay: no GPU cost.
        @"DXMT_GPU_ERROR_DETAIL":@"1",@"DXMT_BENCH_LABELS":@"1",
        // Rosetta reports AVX (Unity's native code and Burst pick their paths from it).
        @"ROSETTA_ADVERTISE_AVX":@"1",
        // Synchronisation through Mach semaphores; write-copy simulation as Recall ships it.
        @"WINEESYNC":@"0",@"WINEMSYNC":@"1",@"WINE_SIMULATE_WRITECOPY":@"1",
        // Mouse: the precise input variant, and mouse-look for the game's camera.
        @"WINEMAC_INPUT_VARIANT":@"precise",@"WINEMAC_MOUSELOOK":game,
        // Game Mode for the game's own process (ntdll's game-mode bundles; Pawpad's app shell
        // covers it when the engine has no bundle for Aniimo).
        @"WINE_GAME_MODE":game,
    };
}
/* The renderer profile for the game (DXMT config syntax). Recall's tuning for Overwatch, kept until
 * measured for Aniimo: shader IR released after compiling, uncapped presentation, eight
 * normal-priority compiler threads, one frame of latency. Recall's present pacing (the game thread
 * sleeps so input is sampled late) is off for Aniimo: it is GPU-bound, and the sleep made frame times
 * uneven. Live, same spot, 2 runs each (30 Oct): 1% low 18.5/18.7 -> 22.8/22.9 FPS, stutters over
 * 50 ms 4.8/5.2 -> 2.2/2.1 a minute, p99 39.0/37.1 -> 36.6/36.4 ms, average FPS unchanged.
 * Left out from Recall's profile: the fullscreen canvas (dxgi.fullscreenCanvas*,
 * dxgi.nativeFullscreen, dxgi.sharpPresentation), which forced Overwatch's size and drawing onto
 * the screen and gave Aniimo a quarter of a 4K image (24 Oct 2026). */
static NSString *aniimoRendererProfile(NSString *game) {
    return [@[[NSString stringWithFormat:@"[%@]",game],
        @"d3d11.releaseShaderIR = True",
        @"d3d11.preferredMaxFrameRate = 0",
        @"d3d11.shaderCompilerThreads = 8",
        @"d3d11.shaderCompilerNormalPriority = True",
        @"dxgi.maxFrameLatency = 1",
        @"dxgi.presentPacing = False",@""] componentsJoinedByString:@"\n"];
}
