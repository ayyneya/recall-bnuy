/* What Pawpad knows about Aniimo's PC client, inside the Wine environment's drive C.
 *
 * Aniimo installs through its own installer (aniimo-global.exe from aniimo.com, signed by
 * PAWPRINT INTERACTIVE ENTERTAINMENT PTE. LTD.), which installs a Qt launcher; the launcher
 * downloads the game (Unity 2022.3, Direct3D 11 by default) and starts it. Which drive the
 * installer offers: see configureDrives.
 *
 * Where the launcher and the game end up is found, not assumed: the launcher from the
 * installer's uninstall entry, the game as the program beside UnityPlayer.dll. Each found path
 * is kept in state.json (relative to drive C) and checked again before it is used. */
// From portable_network.h, which is included after this file (it needs gameExecutable).
static NSDictionary *registryFileValues(NSString *file, NSString *key);
static BOOL registryTool(NSString *engine, NSArray *arguments, NSString *log);
static NSString *const aniimoInstaller=@"aniimo-global.exe";
// Until the game has been found once: the name its folder is expected to use.
static NSString *const provisionalGameExecutable=@"Aniimo.exe";

static NSString *driveC(void) { return join(root,@"environment/drive_c"); }
// C:\a\b for a path inside drive C, nil for anything else.
static NSString *windowsPath(NSString *path) {
    NSString *drive=[driveC() stringByAppendingString:@"/"];
    if(![path hasPrefix:drive])return nil;
    return [@"C:\\" stringByAppendingString:[[path substringFromIndex:drive.length] stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]];
}
// A path kept in state.json, relative to drive C, if it is still a file inside it.
static NSString *keptProgram(NSString *key) {
    NSString *relative=state()[key];
    if(![relative isKindOfClass:NSString.class] || !safePath(relative))return nil;
    NSString *path=join(driveC(),relative);struct stat st;
    return !lstat(path.fileSystemRepresentation,&st) && S_ISREG(st.st_mode) ? path : nil;
}
static void keepProgram(NSString *key, NSString *path) {
    NSString *drive=[driveC() stringByAppendingString:@"/"];
    NSMutableDictionary *s=state();
    NSString *relative=[path hasPrefix:drive] ? [path substringFromIndex:drive.length] : nil;
    if([s[key] isEqual:relative])return;
    if(relative)s[key]=relative;else[s removeObjectForKey:key];
    writeJSON(s,join(root,@"state.json"));
}
// Folders the launcher and the game may be in: the installer's default and the usual ones.
static NSArray *programRoots(void) {
    return @[join(driveC(),@"PawPrint"),join(driveC(),@"Program Files"),join(driveC(),@"Program Files (x86)")];
}
/* The first program under the roots, at most DEPTH folders down, for which accept(folder,
 * name) says yes. Folders named *_Data (a Unity game's assets) and resources are never
 * entered; names compare in a fixed order, so the same tree gives the same answer. */
static NSString *findProgram(NSArray *roots, int depth, BOOL (^accept)(NSString *folder, NSString *name)) {
    for(NSString *top in roots) {
        NSMutableArray *level=[NSMutableArray arrayWithObject:top];
        for(int d=0;d<=depth && level.count;d++) {
            NSMutableArray *next=[NSMutableArray array];
            for(NSString *folder in level) {
                NSArray *names=[[fm contentsOfDirectoryAtPath:folder error:nil] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
                for(NSString *name in names) {
                    NSString *path=join(folder,name);struct stat st;
                    if(lstat(path.fileSystemRepresentation,&st))continue;
                    if(S_ISREG(st.st_mode) && [name.lowercaseString hasSuffix:@".exe"] && accept(folder,name))return path;
                    if(S_ISDIR(st.st_mode) && ![name hasSuffix:@"_Data"] && ![name.lowercaseString isEqual:@"resources"])[next addObject:path];
                }
            }
            level=next;
        }
    }
    return nil;
}
// The path inside drive C for a C:\ path, nil for anything else.
static NSString *unixPath(NSString *windows) {
    if(windows.length<4 || ![[windows substringToIndex:3].uppercaseString isEqual:@"C:\\"])return nil;
    NSString *relative=[[windows substringFromIndex:3] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    return safePath(relative) ? join(driveC(),relative) : nil;
}
// A REG_SZ value as system.reg writes it ("\"C:\\a\\b.exe\""), unescaped, without the quotes
// Windows puts around a path with spaces.
static NSString *registryString(NSString *value) {
    if(value.length<2 || ![value hasPrefix:@"\""] || ![value hasSuffix:@"\""])return nil;
    NSMutableString *text=[NSMutableString string];
    for(NSUInteger i=1;i+1<value.length;i++) {
        unichar c=[value characterAtIndex:i];
        if(c=='\\' && i+2<value.length)c=[value characterAtIndex:++i];
        [text appendFormat:@"%C",c];
    }
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
}
/* Aniimo's launcher: Launcher.exe in the folder the installer registers (its uninstall entry's
 * DisplayIcon; C:\Program Files (x86)\PawPrint\Aniimo on 24 Oct 2026). It is a stub that starts
 * the current version's Qt launcher (1.0.0.281\PC-Launcher.exe) and keeps it updated, as
 * Windows' shortcut does. Without the entry: a Launcher.exe beside uninstall.exe and
 * config\version.ini. */
static NSString *launcherPath(void) {
    NSString *kept=keptProgram(@"launcher_path");
    if(kept)return kept;
    NSString *found=unixPath(registryString(registryFileValues(@"system.reg",@"Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Aniimo")[@"DisplayIcon"]));
    struct stat st;
    if(!found || lstat(found.fileSystemRepresentation,&st) || !S_ISREG(st.st_mode))
        found=findProgram(programRoots(),3,^BOOL(NSString *folder, NSString *name) {
            return [name.lowercaseString isEqual:@"launcher.exe"] && [fm fileExistsAtPath:join(folder,@"uninstall.exe")] &&
                [fm fileExistsAtPath:join(folder,@"config/version.ini")];
        });
    if(found)keepProgram(@"launcher_path",found);
    return found;
}
// The game: the program beside UnityPlayer.dll, under the launcher's folder first.
static NSString *gamePath(void) {
    NSString *kept=keptProgram(@"game_path");
    if(kept)return kept;
    NSString *launcher=launcherPath();
    NSArray *roots=launcher ? [@[launcher.stringByDeletingLastPathComponent] arrayByAddingObjectsFromArray:programRoots()] : programRoots();
    NSString *found=findProgram(roots,5,^BOOL(NSString *folder, NSString *name) {
        return ![name.lowercaseString hasPrefix:@"unitycrashhandler"] && [fm fileExistsAtPath:join(folder,@"UnityPlayer.dll")];
    });
    if(found)keepProgram(@"game_path",found);
    return found;
}
// The game's file name, which Wine's per-program settings (mouselook, the Option key, the
// renderer profile) are keyed by.
static NSString *gameExecutable(void) {
    NSString *path=keptProgram(@"game_path");
    return path ? path.lastPathComponent : provisionalGameExecutable;
}

/* The installer lists the drives (GetLogicalDriveStringsW), keeps the local fixed ones
 * (GetDriveTypeW) and offers <drive>:\PawPrint\Aniimo on the one it prefers by free space.
 * Wine's Z: is the Mac's own disk, the same volume as C:, and the installer chose it, then
 * refused the folder it offered. Marked as a network drive (HKLM\Software\Wine\Drives "z:" =
 * "network", which Wine's mount manager reads when its session starts), Z: reports
 * DRIVE_REMOTE, the installer only looks at C: (traced with +volume, 24 Oct 2026), and the
 * launcher won't offer the Mac's disk for the game either. Wine still reads files through Z:
 * as before (the renderer profile lives there). YES when the value changed: the session must
 * restart before a program sees it. */
static BOOL configureDrives(NSString *engine) {
    BOOL set=[registryFileValues(@"system.reg",@"Software\\Wine\\Drives")[@"z:"] isEqual:@"\"network\""];
    if(set || !engine)return NO;
    BOOL ok=registryTool(engine,@[@"add",@"HKLM\\Software\\Wine\\Drives",@"/v",@"z:",@"/t",@"REG_SZ",@"/d",@"network",@"/f"],@"drives.log");
    event(@"drives",@{@"z":@"network",@"ok":@((BOOL)ok)});
    return ok;
}

/* Aniimo signs in with HMAC-SHA256 through the legacy CryptoAPI: CryptSetHashParam(HP_HMAC_INFO)
 * with CALG_SHA_256 on the default PROV_RSA_FULL provider. Wine 11.0's rsaenh (the engine Pawpad
 * shares with Recall) accepts an HMAC's inner hash only if the provider lists it, which the RSA
 * full provider doesn't for SHA-256, and still reported success, so the next CryptHashData
 * crashed the game about 20 seconds in (Wine bug 60345; Proton issue 9427).
 * patches/wine-rsaenh-hmac.patch fixes rsaenh itself; until Pawpad ships an engine built with it,
 * PROV_RSA_FULL's default provider is the one rsaenh gives the AES algorithm set, SHA-256
 * included, by name: "Microsoft Enhanced RSA and AES Cryptographic Provider (Prototype)", made a
 * type 1 provider. Checked in system.reg; the registry tool runs only when a value is missing.
 * Never fails: setup and launches go on, and the next launch tries again. */
static NSString *const cryptoProvider=@"Microsoft Enhanced RSA and AES Cryptographic Provider (Prototype)";
static BOOL configureCryptoProvider(NSString *engine) {
    NSString *defaults=@"Software\\Microsoft\\Cryptography\\Defaults";
    NSString *providerKey=[NSString stringWithFormat:@"%@\\Provider\\%@",defaults,cryptoProvider],*typeKey=[defaults stringByAppendingString:@"\\Provider Types\\Type 001"];
    NSDictionary *provider=registryFileValues(@"system.reg",providerKey),*type=registryFileValues(@"system.reg",typeKey);
    BOOL typeSet=[provider[@"Type"] isEqual:@"dword:00000001"];
    BOOL nameSet=[type[@"Name"] isEqual:[NSString stringWithFormat:@"\"%@\"",cryptoProvider]];
    BOOL ok=YES;
    if(engine && !typeSet)ok&=registryTool(engine,@[@"add",[@"HKLM\\" stringByAppendingString:providerKey],@"/v",@"Type",@"/t",@"REG_DWORD",@"/d",@"1",@"/f"],@"crypto.log");
    if(engine && !nameSet)ok&=registryTool(engine,@[@"add",[@"HKLM\\" stringByAppendingString:typeKey],@"/v",@"Name",@"/t",@"REG_SZ",@"/d",cryptoProvider,@"/f"],@"crypto.log");
    event(@"crypto_provider",@{@"changed":@((BOOL)(engine && (!typeSet || !nameSet))),@"ok":@((BOOL)ok),@"registry":(provider && type) ? @"read" : @"unreadable"});
    return ok;
}
