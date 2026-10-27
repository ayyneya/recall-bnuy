/* The screen as Windows programs see it, and the renderer's profile.
 *
 * Wine's Retina mode (HKCU\Software\Wine\Mac Driver, RetinaMode) is one switch for every display:
 * on, each Windows pixel is a physical pixel of a Retina screen, and a 1x monitor is shown at
 * twice its size (Wine took Brett's 1920x1080 monitor for 3840x2160). Recall keeps it on for
 * Overwatch, whose resolution it writes and whose frames its fullscreen canvas fits to the screen.
 * Aniimo chooses its own resolution from what Windows reports: with Retina mode on a 1x monitor it
 * opened at 4K, drew a 4K image into a 1080p window (a quarter of it visible) and changed size in a
 * loop (24 Oct 2026). So Pawpad gives Windows the main display's real pixels: Retina mode on only
 * when the main display is a Retina display, and the game, the launcher and the installer all
 * size themselves as on Windows. Wine reads the mode when its session starts, and a launch ends
 * a session from before a display change (displaySignature), so a change of main display gets
 * the right mode on the next Play. */
static BOOL mainDisplayIsRetina(void) {
    CGDisplayModeRef mode=CGDisplayCopyDisplayMode(CGMainDisplayID());
    if(!mode)return NO;
    BOOL retina=CGDisplayModeGetPixelWidth(mode)>CGDisplayModeGetWidth(mode);
    CGDisplayModeRelease(mode);
    return retina;
}
static BOOL retinaModeOn(void) {
    return [userRegistryValues(@"Software\\Wine\\Mac Driver")[@"RetinaMode"] isEqual:@"\"Y\""];
}
/* Sets Retina mode for the main display, only while nothing of Pawpad's runs (Wine keeps the
 * screen's geometry for its whole session). Fails only if the registry can't be written. */
static void configureRetinaMode(NSString *engine) {
    BOOL wanted=mainDisplayIsRetina();
    if(retinaModeOn()==wanted)return;
    if(sessionProcesses().count || busy(engine))fail(@"close_game_before_setup");
    if(!registryTool(engine,@[@"add",@"HKCU\\Software\\Wine\\Mac Driver",@"/v",@"RetinaMode",@"/t",@"REG_SZ",@"/d",wanted ? @"Y" : @"N",@"/f"],@"retina-mode.log"))
        fail(@"retina_configuration_failed");
    // The registry tool itself started Wine with the old geometry: let that session end.
    if(!registrySaved(engine,60))fail(@"environment_initialization_busy");
    event(@"retina_mode",@{@"on":@(wanted)});
}
/* The renderer profile for Aniimo: the engine's tuned profile (written for Overwatch.exe) for
 * the game's own program name, without the fullscreen canvas (dxgi.fullscreenCanvas*,
 * nativeFullscreen, sharpPresentation), which forced Overwatch's size and drawing onto the screen.
 * Shader compilation, frame latency and pacing stay as Recall tuned them. */
static NSString *rendererProfile(NSString *profile) {
    NSMutableArray *lines=[NSMutableArray array];BOOL section=NO;
    for(NSString *line in [profile componentsSeparatedByString:@"\n"]) {
        NSString *trimmed=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) {[lines addObject:[NSString stringWithFormat:@"[%@]",gameExecutable()]];section=YES;continue;}
        NSString *key=[[line componentsSeparatedByString:@"="][0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if([key hasPrefix:@"dxgi.fullscreenCanvas"] || [key isEqual:@"dxgi.nativeFullscreen"] || [key isEqual:@"dxgi.sharpPresentation"])continue;
        [lines addObject:line];
    }
    if(!section)fail(@"runtime_missing");
    return [lines componentsJoinedByString:@"\n"];
}
