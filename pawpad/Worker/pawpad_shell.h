/* The game's app identity. Wine's loader has no app bundle, so macOS shows every Wine window as an
 * anonymous "wine" process: no name in the Dock, no games category for Game Mode, and nothing an
 * app permission (screen control, the microphone) can be given to. Each engine gets a small
 * bundle, app-shell/<engine>/Aniimo.app, around copies of its loader and ntdll.so: Wine starts
 * every Windows program with the loader beside ntdll.so, so the launcher and the game it starts
 * both run inside the bundle. Everything else is linked from the engine.
 *
 * Layout, from where ntdll.so looks (it treats its own folder as lib/wine): Contents/MacOS holds
 * wine, ntdll.so, links to the engine's unix modules, lib dylibs and the x86_64-unix,
 * x86_64-windows, i386-windows and game-mode folders; Aniimo.app/share and Aniimo.app/bin link
 * to the engine's. The loader copy is signed ad hoc with the original's entitlements, outside the
 * bundle: signed in place, codesign would want to seal the links, and a copy keeping CodeWeavers'
 * signature is killed for an invalid signature once a bundle's Info.plist is beside it.
 *
 * The copy also gets its own LC_UUID, as scripts/game_mode_app.py gives Recall's: local network
 * privacy keys apps by their main executable's UUID, and the loader's is shared by every Wine
 * process of every engine (Recall's included), which would all take the game's choice. */
static NSString *const shellBundleID=@"dev.neya.pawpad.game";
static NSString *const shellLayout=@"3";
static NSString *shellFolder(NSString *engine) { return join(join(root,@"app-shell"),engine.lastPathComponent); }
static NSString *shellLoader(NSString *engine) { return join(shellFolder(engine),@"Aniimo.app/Contents/MacOS/wine"); }
static BOOL linkInto(NSString *target, NSString *link) {
    return [fm createSymbolicLinkAtPath:link withDestinationPath:target error:nil];
}
// The LC_UUID of a 64-bit Mach-O file becomes uuid5(its UUID, identifier), as game_mode_app.py makes it.
static BOOL giveOwnUUID(NSString *path, NSString *identifier) {
    NSMutableData *data=[NSMutableData dataWithContentsOfFile:path];
    uint8_t *bytes=data.mutableBytes;uint32_t magic=0,count=0;
    if(data.length<32)return NO;
    memcpy(&magic,bytes,4);memcpy(&count,bytes+16,4);
    if(magic!=0xfeedfacf)return NO;
    for(size_t offset=32,i=0;i<count && offset+8<=data.length;i++) {
        uint32_t cmd=0,size=0;memcpy(&cmd,bytes+offset,4);memcpy(&size,bytes+offset+4,4);
        if(cmd==0x1b && offset+24<=data.length) {
            NSMutableData *name=[NSMutableData dataWithBytes:bytes+offset+8 length:16];
            [name appendData:[identifier dataUsingEncoding:NSUTF8StringEncoding]];
            uint8_t digest[CC_SHA1_DIGEST_LENGTH];CC_SHA1(name.bytes,(CC_LONG)name.length,digest);
            digest[6]=(uint8_t)((digest[6]&0x0f)|0x50);digest[8]=(uint8_t)((digest[8]&0x3f)|0x80);
            memcpy(bytes+offset+8,digest,16);
            return [data writeToFile:path options:0 error:nil];
        }
        if(size<8)return NO;
        offset+=size;
    }
    return NO;
}
static NSString *ensureShell(NSString *engine) {
    NSString *folder=shellFolder(engine),*unix=join(engine,@"lib/wine/x86_64-unix");
    // The engine's own path is in the stamp, and a kept shell must still reach the engine: its links
    // are absolute, so a data folder that moved (another account, Migration Assistant) rebuilds it.
    NSString *stamp=[NSString stringWithFormat:@"%@ %@ %@ %@",shellLayout,engine.stringByResolvingSymlinksInPath,hashFile(join(unix,@"wine")),hashFile(join(unix,@"ntdll.so"))];
    NSString *kept=[NSString stringWithContentsOfFile:join(folder,@"stamp") encoding:NSUTF8StringEncoding error:nil];
    if([kept isEqual:stamp] && [fm isExecutableFileAtPath:shellLoader(engine)] &&
       [fm fileExistsAtPath:join(folder,@"Aniimo.app/Contents/MacOS/x86_64-windows")])return shellLoader(engine);
    NSString *build=[folder stringByAppendingString:@".building"];
    [fm removeItemAtPath:build error:nil];
    NSString *app=join(build,@"Aniimo.app"),*macos=join(app,@"Contents/MacOS");
    mkdirs(macos);
    if(![fm copyItemAtPath:join(unix,@"ntdll.so") toPath:join(macos,@"ntdll.so") error:nil])fail(@"app_shell_failed");
    // Hidden files (a .DS_Store Finder left, which verifyRuntime accepts) aren't linked: the same name
    // in both folders would make the second link fail.
    for(NSString *name in [fm contentsOfDirectoryAtPath:unix error:nil]) {
        if([name hasPrefix:@"."] || [name isEqual:@"wine"] || [name isEqual:@"ntdll.so"])continue;
        if(!linkInto(join(unix,name),join(macos,name)))fail(@"app_shell_failed");
    }
    for(NSString *name in [fm contentsOfDirectoryAtPath:join(engine,@"lib") error:nil]) {
        if([name hasPrefix:@"."] || [name isEqual:@"wine"])continue;
        if(!linkInto(join(join(engine,@"lib"),name),join(macos,name)))fail(@"app_shell_failed");
    }
    for(NSString *name in @[@"x86_64-unix",@"x86_64-windows",@"i386-windows",@"game-mode"])
        if([fm fileExistsAtPath:join(engine,join(@"lib/wine",name))] && !linkInto(join(engine,join(@"lib/wine",name)),join(macos,name)))fail(@"app_shell_failed");
    if(!linkInto(join(engine,@"share"),join(app,@"share")) || !linkInto(join(engine,@"bin"),join(app,@"bin")))fail(@"app_shell_failed");
    // The loader's own embedded Info.plist (so Wine behaves as with the bare loader: its
    // application class, no Dock icon until it shows a window), plus the bundle's identity and the
    // keys Recall's Game Mode bundle uses (scripts/game_mode_app.py): macOS turns Game Mode on for
    // a game-category app in full screen. The engine only carries game-mode/Overwatch.app, so
    // WINE_GAME_MODE=Aniimo.exe never found a bundle and Aniimo ran without Game Mode before this.
    NSDictionary *info=@{@"CFBundleIdentifier":shellBundleID,@"CFBundleName":@"Aniimo",@"CFBundleDisplayName":@"Aniimo (Pawpad)",
        @"CFBundleExecutable":@"wine",@"CFBundlePackageType":@"APPL",@"CFBundleSignature":@"????",
        @"CFBundleShortVersionString":@"11.0",@"CFBundleVersion":@"11.0",@"CFBundleInfoDictionaryVersion":@"6.0",
        @"CFBundleDevelopmentRegion":@"English",@"CFBundleAllowMixedLocalizations":@YES,
        @"NSPrincipalClass":@"WineApplication",@"LSUIElement":@"1",
        @"LSApplicationCategoryType":@"public.app-category.action-games",@"LSSupportsGameMode":@YES,@"GCSupportsGameMode":@YES,
        @"NSMicrophoneUsageDescription":@"Voice chat in Aniimo uses your microphone.",
        @"NSLocalNetworkUsageDescription":@"Aniimo looks up your Mac's address on your local network when it starts."};
    if(![info writeToFile:join(app,@"Contents/Info.plist") atomically:YES])fail(@"app_shell_failed");
    NSString *entitlements=join(build,@"entitlements.plist"),*signedCopy=join(build,@"wine");
    if(![fm copyItemAtPath:join(unix,@"wine") toPath:signedCopy error:nil] || !giveOwnUUID(signedCopy,shellBundleID))fail(@"app_shell_failed");
    if(waitTask(task(@"/usr/bin/codesign",@[@"-d",@"--entitlements",entitlements,@"--xml",join(unix,@"wine")],@{},@"app-shell.log"),30) ||
       waitTask(task(@"/usr/bin/codesign",@[@"-f",@"-s",@"-",@"--options",@"runtime",@"--entitlements",entitlements,@"--identifier",shellBundleID,signedCopy],@{},@"app-shell.log"),30))
        fail(@"app_shell_signing_failed");
    if(![fm moveItemAtPath:signedCopy toPath:join(macos,@"wine") error:nil])fail(@"app_shell_failed");
    [fm removeItemAtPath:entitlements error:nil];
    if(![stamp writeToFile:join(build,@"stamp") atomically:YES encoding:NSUTF8StringEncoding error:nil])fail(@"app_shell_failed");
    [fm removeItemAtPath:folder error:nil];
    if(![fm moveItemAtPath:build toPath:folder error:nil])fail(@"app_shell_failed");
    event(@"app_shell",@{@"bundle":shellBundleID,@"engine":engine.lastPathComponent});
    return shellLoader(engine);
}
