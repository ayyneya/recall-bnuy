/* Which processes are Pawpad's: their Windows name from ps, their engine from the kernel; no
 * command lines or environments (a Wine program's arguments can carry the launcher's login data). The game is the program found beside UnityPlayer.dll (gamePath); the launcher is
 * any other program in the launcher's folder (Electron runs several copies of itself). Only
 * paths already kept in state.json are used here: the monitor runs without setup.lock and
 * never writes them. */
static NSString *capture(NSString *exe, NSArray *args) {
    NSTask *p=task(exe,args,@{@"PATH":@"/usr/bin:/bin:/usr/sbin:/sbin",@"LC_ALL":@"C"},[NSString stringWithFormat:@"session-query-%d.log",getpid()]);
    if(waitTask(p,5))return nil;
    NSString *path=join(join(root,@"logs"),[NSString stringWithFormat:@"session-query-%d.log",getpid()]);
    if([[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue]>(4ULL<<20))return nil;
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}
// What a process is, from the Windows path Wine gives it as its name: "game", "client",
// "installer" (Aniimo's launcher installer) or nil.
static NSString *processKind(NSString *name, NSString *game, NSString *launcher) {
    NSString *lower=name.lowercaseString;
    if([lower hasSuffix:[@"\\" stringByAppendingString:aniimoInstaller]])return @"installer";
    if([lower hasSuffix:[@"\\" stringByAppendingString:(game ? game.lastPathComponent : provisionalGameExecutable).lowercaseString]])return @"game";
    NSString *folder=launcher ? windowsPath(launcher.stringByDeletingLastPathComponent) : nil;
    if(folder && [lower hasPrefix:[folder.lowercaseString stringByAppendingString:@"\\"]] && [lower hasSuffix:@".exe"])return @"client";
    return nil;
}
static NSMutableDictionary *membershipCache;
static NSArray *sessionProcesses(void) {
    if(!membershipCache)membershipCache=[NSMutableDictionary dictionary];
    if(membershipCache.count>256)[membershipCache removeAllObjects];
    NSString *engine=[[runtime() stringByResolvingSymlinksInPath] stringByAppendingString:@"/"];
    NSString *shells=[[join(root,@"app-shell") stringByResolvingSymlinksInPath] stringByAppendingString:@"/"];
    // The game's and launcher's paths, read once per call (state.json used to be read twice for
    // every line ps printed).
    NSString *game=keptProgram(@"game_path"),*launcher=keptProgram(@"launcher_path");
    // Only Pawpad's own Wine processes go to ps: the kernel gives every process's executable path
    // (no arguments), and ps then reads just those processes' names. ps over every process on the
    // Mac took ~250 ms each time, every 2 s while recording.
    int capacity=proc_listallpids(NULL,0)+64;if(capacity<64)capacity=4096;
    pid_t *pids=calloc((size_t)capacity,sizeof(pid_t));
    int count=pids ? proc_listallpids(pids,capacity*(int)sizeof(pid_t)) : -1;
    NSMutableArray *candidates=[NSMutableArray array];
    for(int i=0;i<count;i++) {
        char executable[PROC_PIDPATHINFO_MAXSIZE];
        if(pids[i]<=0 || proc_pidpath(pids[i],executable,sizeof(executable))<=0)continue;
        NSString *path=@(executable);
        // Wine's loader is the executable of every Wine process: a prefix test is enough here; the
        // resolved path is checked again below.
        if([path hasPrefix:engine] || [path hasPrefix:shells] || [path containsString:@"/lib/wine/"] || [path containsString:@"/app-shell/"])
            [candidates addObject:[NSString stringWithFormat:@"%d",pids[i]]];
    }
    free(pids);
    if(count<0)fail(@"session_check_failed");
    if(!candidates.count)return @[];
    NSString *table=capture(@"/bin/ps",@[@"-o",@"pid=,lstart=,comm=",@"-p",[candidates componentsJoinedByString:@","]]);
    if(!table)fail(@"session_check_failed");
    NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d+)\\s+(\\S+\\s+\\S+\\s+\\d+\\s+\\S+\\s+\\d+)\\s+(.+)$" options:0 error:nil];
    NSMutableArray *found=[NSMutableArray array];
    for(NSString *line in [table componentsSeparatedByString:@"\n"]) {
        NSTextCheckingResult *m=[rx firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];if(!m)continue;
        NSString *name=[[line substringWithRange:[m rangeAtIndex:3]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *kind=processKind(name,game,launcher);
        if(!kind)continue;
        NSString *pid=[line substringWithRange:[m rangeAtIndex:1]],*start=[line substringWithRange:[m rangeAtIndex:2]];
        NSString *identity=[NSString stringWithFormat:@"%@|%@",pid,start];
        if(membershipCache[identity]) { if([membershipCache[identity] boolValue])[found addObject:@{@"pid":@(pid.intValue),@"identity":start,@"kind":kind,@"name":name}];continue; }
        // Pawpad's own Wine: the process runs this data folder's engine or its app bundle (its native executable,
        // one call to the kernel; lsof took seconds per process). Only Pawpad's environment uses it.
        char executable[PROC_PIDPATHINFO_MAXSIZE];
        // No path: it has just exited, or belongs to another user. Either way not Pawpad's.
        if(proc_pidpath(pid.intValue,executable,sizeof(executable))<=0)continue;
        NSString *resolved=[@(executable) stringByResolvingSymlinksInPath];
        BOOL member=[resolved hasPrefix:engine] || [resolved hasPrefix:shells];
        membershipCache[identity]=@(member);
        if(member)[found addObject:@{@"pid":@([pid intValue]),@"identity":start,@"kind":kind,@"name":name}];
    }
    [fm removeItemAtPath:join(join(root,@"logs"),[NSString stringWithFormat:@"session-query-%d.log",getpid()]) error:nil];
    return found;
}
static BOOL focusKinds(NSArray *processes, NSArray *kinds) {
    for(NSString *kind in kinds)for(NSDictionary *p in processes)if([p[@"kind"] isEqual:kind]) {
        NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:[p[@"pid"] intValue]];
        BOOL activated=app && [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        event(@"session_existing",@{@"kind":kind,@"activated":@(activated)});return YES;
    }
    return NO;
}
static BOOL focusSession(NSArray *processes) { return focusKinds(processes,@[@"game",@"client"]); }
static NSString *monitorPath(void) { return join(root,@"cache/monitor.pid"); }
// The session's monitor and flight recorder (watchClient) is in pawpad_recorder.h.
/* The displays as Wine takes them in when its session starts (Recall's displaySignature): Wine
 * keeps that layout for the whole session, so a game started in a session from before a display
 * change finds the wrong outputs. A launch ends such a session first. nil if unreadable. */
static NSString *displaySignature(void) {
    CGDirectDisplayID ids[16];uint32_t count=0;
    if(CGGetOnlineDisplayList(16,ids,&count)!=kCGErrorSuccess || !count)return nil;
    NSMutableArray *parts=[NSMutableArray array];
    for(uint32_t i=0;i<count;i++) {
        CGRect bounds=CGDisplayBounds(ids[i]);size_t pixelWidth=0,pixelHeight=0;
        CGDisplayModeRef mode=CGDisplayCopyDisplayMode(ids[i]);
        if(mode){pixelWidth=CGDisplayModeGetPixelWidth(mode);pixelHeight=CGDisplayModeGetPixelHeight(mode);CGDisplayModeRelease(mode);}
        [parts addObject:[NSString stringWithFormat:@"%u%@ %.0f,%.0f %.0fx%.0f %zux%zu m%u",ids[i],CGDisplayIsMain(ids[i])?@" main":@"",
            bounds.origin.x,bounds.origin.y,bounds.size.width,bounds.size.height,pixelWidth,pixelHeight,CGDisplayMirrorsDisplay(ids[i])]];
    }
    [parts sortUsingSelector:@selector(compare:)];
    return [parts componentsJoinedByString:@"; "];
}
