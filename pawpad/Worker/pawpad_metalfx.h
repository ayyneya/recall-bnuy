/* MetalFX upscaling for Aniimo (launch --metalfx 1, --sharpening off|low|high): off unless asked for.
 * As Recall does for Overwatch (scripts/portable_metalfx.h), the game then sees an NVIDIA card and
 * may offer NVIDIA DLSS in its own settings; the engine's DLSS stand-in runs it on Apple's MetalFX
 * temporal upscaler. A launch with it on:
 * - adds DXMT's NVIDIA identity (DXMT_ENABLE_NVEXT) and the engine's d3d12, NVAPI and DLSS
 *   stand-ins, which Pawpad's profile otherwise leaves off (Aniimo's DLSS goes through NVIDIA
 *   Streamline, whose sl.common.dll needs a d3d12.dll);
 * - puts the engine's signed DLSS stand-in in system32, where NVIDIA's loader looks for it; what
 *   was there is kept in metalfx/ and put back by the next launch without upscaling;
 * - adds the sharpening amount to this launch's dxmt.conf (d3d11.metalfxSharpness).
 * Overwatch's settings handling (its record of the card) has no counterpart for Aniimo. */
static NSString *const aniimoNVNGX=@"lib/wine/x86_64-windows/nvngx.dll";
static NSString *aniimoSystemDLSS(void) {return join(root,@"environment/drive_c/windows/system32/nvngx.dll");}
static NSDictionary *aniimoMetalFXEnvironment(void) {
    return @{@"DXMT_ENABLE_NVEXT":@"1",@"WINEDLLOVERRIDES":@"d3d11,dxgi,d3d10core,winemetal,d3d12,nvapi64,nvngx=b"};
}
static NSDictionary *aniimoMetalFXSharpening(void) {return @{@"high":@"0.8",@"low":@"0.4"};}
// The engine's DLSS stand-in by its manifest hash, or nil for an engine without the stand-ins.
static NSString *aniimoEngineDLSS(NSString *engine) {
    NSDictionary *files=readJSON(join(engine,@"runtime.json"))[@"files"];
    if(![files isKindOfClass:NSDictionary.class] || ![files[@"lib/wine/x86_64-windows/nvapi64.dll"] isKindOfClass:NSDictionary.class])return nil;
    NSDictionary *nvngx=files[aniimoNVNGX];
    return [nvngx isKindOfClass:NSDictionary.class] && matches(nvngx[@"sha256"],@"^[a-f0-9]{64}$") ? nvngx[@"sha256"] : nil;
}
static NSString *aniimoRegularFileHash(NSString *path) {
    struct stat st;
    return !lstat(path.fileSystemRepresentation,&st) && S_ISREG(st.st_mode) ? hashFile(path) : nil;
}
// Copies a file over target by renaming a copy beside it, so the game never sees half a file.
static BOOL aniimoReplaceFile(NSString *source, NSString *target) {
    NSString *part=[target stringByAppendingString:@".pawpad-part"];
    [fm removeItemAtPath:part error:nil];
    if(![fm copyItemAtPath:source toPath:part error:nil])return NO;
    if(rename(part.fileSystemRepresentation,target.fileSystemRepresentation)) {[fm removeItemAtPath:part error:nil];return NO;}
    return YES;
}
/* system32\nvngx.dll: the engine's stand-in with upscaling on (WANTED is its hash); with it off,
 * whatever was there before Pawpad put the stand-in there. Returns what was done. */
static NSString *configureAniimoDLSSFile(NSString *engine, NSString *wanted) {
    NSString *path=aniimoSystemDLSS(),*backup=join(root,@"metalfx/nvngx.dll");
    if(![fm fileExistsAtPath:path.stringByDeletingLastPathComponent])return @"none";
    NSString *current=aniimoRegularFileHash(path),*ours=state()[@"metalfx_nvngx"];
    if(wanted) {
        if([current isEqual:wanted])return @"kept";
        // A file Pawpad didn't put there (Wine's placeholder) is kept, to put back later.
        if(current && ![current isEqual:ours]) {mkdirs(backup.stringByDeletingLastPathComponent);if(!aniimoReplaceFile(path,backup))return @"failed";}
        if(!aniimoReplaceFile(join(engine,aniimoNVNGX),path) || ![aniimoRegularFileHash(path) isEqual:wanted])return @"failed";
        NSMutableDictionary *s=state();s[@"metalfx_nvngx"]=wanted;writeJSON(s,join(root,@"state.json"));
        return @"installed";
    }
    if(!current || ![current isEqual:ours])return @"none";
    NSString *done;
    if(aniimoRegularFileHash(backup)) {if(!aniimoReplaceFile(backup,path))return @"failed";done=@"restored";}
    else {if(![fm removeItemAtPath:path error:nil])return @"failed";done=@"removed";}
    NSMutableDictionary *s=state();[s removeObjectForKey:@"metalfx_nvngx"];writeJSON(s,join(root,@"state.json"));
    return done;
}
/* Sets up this launch with upscaling ENABLED or not and SHARPENING (off, low, high). An engine
 * without the stand-ins launches as with upscaling off. Returns whether the launch has upscaling
 * and sets AMOUNT to the sharpening amount for dxmt.conf (nil for none). Reports metalfx. */
static BOOL configureAniimoMetalFX(NSString *engine, BOOL enabled, NSString *sharpening, NSString **amount) {
    if(![sharpening isEqual:@"off"] && !aniimoMetalFXSharpening()[sharpening])fail(@"invalid_arguments");
    NSString *wanted=aniimoEngineDLSS(engine);
    BOOL on=enabled && wanted;
    *amount=on ? aniimoMetalFXSharpening()[sharpening] : nil;
    NSString *file=configureAniimoDLSSFile(engine,on ? wanted : nil);
    // Without the stand-in in place the game's loader can't find DLSS: launch without upscaling.
    if(on && [file isEqual:@"failed"]) {on=NO;*amount=nil;}
    NSMutableDictionary *details=[@{@"enabled":@(on),@"available":@(wanted!=nil),@"nvngx":file} mutableCopy];
    if(*amount)details[@"sharpness"]=*amount;
    event(@"metalfx",details);
    return on;
}
// This launch's dxmt.conf with the sharpening amount in the game's section.
static NSString *aniimoSharpeningProfile(NSString *profile, NSString *game, NSString *amount) {
    if(!amount)return profile;
    return [profile stringByAppendingFormat:@"%@[%@]\nd3d11.metalfxSharpness = %@\n",[profile hasSuffix:@"\n"]?@"":@"\n",game,amount];
}
