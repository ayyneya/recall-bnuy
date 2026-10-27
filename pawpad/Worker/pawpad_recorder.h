/* Pawpad's flight recorder: what happened in a play session, cheap enough to leave on.
 *
 * One folder per launch (logs/sessions/<UTC start>), holding:
 *   session.json      what the session started with: settings, engine, Mac, displays
 *   wine.log          everything Wine, the launcher and the game print (stdout/stderr)
 *   frames-<winpid>*  the engine's present loop, one row per frame the game finished
 *                     (DXMT_FRAME_LOG: frame time, GPU wait, pacing sleep, shader compiles)
 *   display-<pid>*    what macOS put on screen and when (DXMT_DISPLAY_LOG: Metal's
 *                     presentedTime per drawable; .hitches.csv lists gaps over 25 ms)
 *   shaders-<winpid>* each shader translation and pipeline build, with timings (DXMT_SHADER_LOG)
 *   pipeline-cache-*  the pipeline cache's own log (DXMT_PIPELINE_CACHE_LOG)
 *   system.csv        this recorder, once a second: the game's CPU, threads and memory, the GPU's
 *                     load and memory, frames shown that second, heat, memory pressure, swap
 *   timeline.jsonl    one line per notable event, from every source, on one clock (unix ms):
 *                     launcher/game start and end, first frame, freezes, crashes, GPU pipeline
 *                     failures, Wine errors, heat and memory-pressure changes, markers
 *   freezes/          a stack sample of the game (Apple's sample tool) for each freeze
 *   report.md/.json   pawpad-perf's summary, written when the session ends
 *
 * The engine's logs are written off the game's threads (ring buffers, writer threads); this
 * recorder is a separate process that reads files and system counters once a second.
 * A freeze is the game's window on screen with no new frame shown for 3 s. */
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>

static NSString *sessionFolder(NSString *name) { return join(sessionsFolder(),name); }
static uint64_t unixMs(void) { return (uint64_t)([NSDate date].timeIntervalSince1970*1000); }
// The timeline is appended to by the recorder and by `mark`, so each event is one write to a
// file opened for appending (atomic on the local disk).
static int timelineFD=-1;
static void appendTimeline(int fd, NSString *kind, NSDictionary *details) {
    if(fd<0)return;
    NSMutableDictionary *value=[@{@"t":@(unixMs()),@"kind":kind} mutableCopy];
    [value addEntriesFromDictionary:details ?: @{}];
    NSMutableData *data=[[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil] mutableCopy];
    if(!data)return;
    [data appendBytes:"\n" length:1];
    if(write(fd,data.bytes,data.length)<0) { /* a full disk loses the event, never the session */ }
}
static void timeline(NSString *kind, NSDictionary *details) { appendTimeline(timelineFD,kind,details); }
static int openTimeline(NSString *folder) { return open(join(folder,@"timeline.jsonl").fileSystemRepresentation,O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW,0600); }
// Pawpad's Force Quit, noted before anything is closed, so the report says the session was ended by hand.
static void noteForceQuit(void) {
    NSString *name=state()[@"log_session"];
    if(!validSessionName(name) || ![fm fileExistsAtPath:join(sessionFolder(name),@"timeline.jsonl")])return;
    int fd=openTimeline(sessionFolder(name));
    appendTimeline(fd,@"force_quit",@{@"src":@"user"});
    if(fd>=0)close(fd);
}
// `mark --label <text>`: a marker on the current session's timeline, for timing a part of play.
static void markSession(NSString *label) {
    NSString *name=state()[@"log_session"];
    if(!validSessionName(name) || ![fm fileExistsAtPath:join(sessionFolder(name),@"timeline.jsonl")])fail(@"no_recorded_session");
    if(!matches(label,@"^[A-Za-z0-9 ._:()-]{1,80}$"))fail(@"invalid_arguments");
    int fd=openTimeline(sessionFolder(name));
    appendTimeline(fd,@"marker",@{@"label":label,@"src":@"user"});
    if(fd>=0)close(fd);
    event(@"marked",@{@"session":name,@"label":label});
}
static NSFileHandle *appendHandle(NSString *path, NSString *header) {
    if(![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:[header dataUsingEncoding:NSUTF8StringEncoding] attributes:@{NSFilePosixPermissions:@0600}];
    NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:path];[h seekToEndOfFile];return h;
}
// "Z:\Users\...": the same folder as a Windows program sees it, for the engine's Windows-side logs.
static NSString *zPath(NSString *path) { return [@"Z:" stringByAppendingString:[path stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]]; }

/* What a launch adds to the environment to record a session into FOLDER. MoltenVK (used by
 * Wine's Vulkan, not by the game's graphics) prints 110 lines of extensions per process at its
 * default level; errors only. */
static NSDictionary *recorderEnvironment(NSString *folder) {
    return @{@"DXMT_FRAME_LOG":zPath(join(folder,@"frames")),@"DXMT_SHADER_LOG":zPath(join(folder,@"shaders")),
             @"DXMT_DISPLAY_LOG":join(folder,@"display"),@"DXMT_PIPELINE_CACHE_LOG":join(folder,@"pipeline-cache"),
             @"MVK_CONFIG_LOG_LEVEL":@"1"};
}

/* The Mac and its displays as the session starts, for comparing sessions fairly. */
static NSString *sysctlString(const char *name) {
    char value[256]={0};size_t size=sizeof(value);
    return sysctlbyname(name,value,&size,NULL,0) ? @"" : @(value);
}
static NSDictionary *machineRecord(void) {
    uint64_t memory=0;size_t size=sizeof(memory);sysctlbyname("hw.memsize",&memory,&size,NULL,0);
    NSMutableArray *displays=[NSMutableArray array];
    for(NSScreen *screen in NSScreen.screens) {
        NSDictionary *d=screen.deviceDescription;
        CGDirectDisplayID id=(CGDirectDisplayID)[d[@"NSScreenNumber"] unsignedIntValue];
        CGDisplayModeRef mode=CGDisplayCopyDisplayMode(id);
        NSMutableDictionary *entry=[@{@"main":@(CGDisplayIsMain(id)!=0),@"points":@[@(screen.frame.size.width),@(screen.frame.size.height)],
            @"scale":@(screen.backingScaleFactor),@"max_fps":@(screen.maximumFramesPerSecond),@"name":screen.localizedName ?: @""} mutableCopy];
        if(mode) {entry[@"pixels"]=@[@(CGDisplayModeGetPixelWidth(mode)),@(CGDisplayModeGetPixelHeight(mode))];entry[@"refresh_hz"]=@(CGDisplayModeGetRefreshRate(mode));CGDisplayModeRelease(mode);}
        [displays addObject:entry];
    }
    NSOperatingSystemVersion v=NSProcessInfo.processInfo.operatingSystemVersion;
    return @{@"model":sysctlString("hw.model"),@"chip":sysctlString("machdep.cpu.brand_string"),@"memory_gb":@(memory>>30),
             @"macos":[NSString stringWithFormat:@"%ld.%ld.%ld",(long)v.majorVersion,(long)v.minorVersion,(long)v.patchVersion],
             @"low_power_mode":@(NSProcessInfo.processInfo.lowPowerModeEnabled),@"thermal_state":@(NSProcessInfo.processInfo.thermalState),
             @"displays":displays};
}

/* The game process's own counters (rusage v6, as Activity Monitor reads them), without any
 * permission: CPU time (all cores and P-cores), time its threads were ready to run but waited
 * for a core (runnable), memory footprint, energy in nanojoules, wakeups (a part of Activity
 * Monitor's Energy Impact), disk I/O, instructions and cycles. */
typedef struct { uint64_t cpuNs, pcoreNs, runnableNs, footprint, energyNj, wakeups, diskRead, diskWrite, instructions, cycles; int threads; BOOL ok; } ProcessSample;
static uint64_t ticksToNs(uint64_t ticks) {
    static mach_timebase_info_data_t base;if(!base.denom)mach_timebase_info(&base);
    return ticks*base.numer/base.denom;
}
static ProcessSample sampleProcess(pid_t pid) {
    ProcessSample s={0};
    struct rusage_info_v6 ri;
    if(proc_pid_rusage(pid,RUSAGE_INFO_V6,(rusage_info_t *)&ri))return s;
    // Apple Silicon reports times in Mach ticks, not nanoseconds.
    s.cpuNs=ticksToNs(ri.ri_user_time+ri.ri_system_time);s.pcoreNs=ticksToNs(ri.ri_user_ptime+ri.ri_system_ptime);
    s.runnableNs=ticksToNs(ri.ri_runnable_time);s.footprint=ri.ri_phys_footprint;s.energyNj=ri.ri_energy_nj;
    s.wakeups=ri.ri_pkg_idle_wkups+ri.ri_interrupt_wkups;s.diskRead=ri.ri_diskio_bytesread;s.diskWrite=ri.ri_diskio_byteswritten;
    s.instructions=ri.ri_instructions;s.cycles=ri.ri_cycles;
    struct proc_taskinfo ti;
    if(proc_pidinfo(pid,PROC_PIDTASKINFO,0,&ti,sizeof(ti))==sizeof(ti))s.threads=ti.pti_threadnum;
    s.ok=YES;return s;
}
// The whole Mac's memory as Activity Monitor's Memory tab splits it: used (app + wired +
// compressed) and compressed, in bytes.
static void systemMemory(uint64_t *used, uint64_t *compressed) {
    vm_statistics64_data_t vm;mach_msg_type_number_t count=HOST_VM_INFO64_COUNT;
    *used=*compressed=0;
    if(host_statistics64(mach_host_self(),HOST_VM_INFO64,(host_info64_t)&vm,&count)!=KERN_SUCCESS)return;
    uint64_t page=vm_kernel_page_size;
    uint64_t app=(uint64_t)(vm.internal_page_count>vm.purgeable_count ? vm.internal_page_count-vm.purgeable_count : 0);
    *compressed=(uint64_t)vm.compressor_page_count*page;
    *used=(app+vm.wire_count+vm.compressor_page_count)*page;
}

/* Temperatures, power and clock speeds for the whole Mac come from macmon (MIT,
 * github.com/vladkens/macmon; brew install macmon), which reads Apple's IOReport and sensors
 * without administrator rights, as powermetrics can't. It runs beside the recorder, printing a
 * JSON line each second; the recorder keeps the values below in system.csv. Without macmon those
 * columns stay empty. */
static NSString *macmonPath(void) {
    for(NSString *path in @[@"/opt/homebrew/bin/macmon",@"/usr/local/bin/macmon"])if([fm isExecutableFileAtPath:path])return path;
    return nil;
}
typedef struct { NSTask *task; int fd; NSMutableData *pending; NSDictionary *latest; } Macmon;
static void startMacmon(Macmon *m) {
    NSString *path=macmonPath();if(!path)return;
    NSTask *p=[NSTask new];NSPipe *pipe=[NSPipe pipe];
    p.executableURL=[NSURL fileURLWithPath:path];p.arguments=@[@"pipe",@"-i",@"1000"];
    p.standardOutput=pipe;p.standardError=[NSFileHandle fileHandleWithNullDevice];
    if(![p launchAndReturnError:nil])return;
    m->task=p;m->fd=pipe.fileHandleForReading.fileDescriptor;m->pending=[NSMutableData data];
    fcntl(m->fd,F_SETFL,fcntl(m->fd,F_GETFL)|O_NONBLOCK);
}
static void readMacmon(Macmon *m) {
    if(!m->task)return;
    char buffer[65536];ssize_t n;
    while((n=read(m->fd,buffer,sizeof(buffer)))>0)[m->pending appendBytes:buffer length:(NSUInteger)n];
    const char *bytes=m->pending.bytes;NSUInteger start=0;
    for(NSUInteger i=0;i<m->pending.length;i++) if(bytes[i]=='\n') {
        NSDictionary *value=[NSJSONSerialization JSONObjectWithData:[m->pending subdataWithRange:NSMakeRange(start,i-start)] options:0 error:nil];
        if([value isKindOfClass:NSDictionary.class])m->latest=value;
        start=i+1;
    }
    [m->pending replaceBytesInRange:NSMakeRange(0,start) withBytes:NULL length:0];
    if(m->pending.length>(1<<20))[m->pending setLength:0];
}
static void stopMacmon(Macmon *m) { if(m->task.running)[m->task terminate];m->task=nil; }
// macmon's values as CSV fields: temperatures, power, clocks and the fastest fan.
static NSString *macmonFields(NSDictionary *v) {
    if(!v)return @",,,,,,,,,";
    double fan=0;for(NSDictionary *f in [v[@"fans"] isKindOfClass:NSArray.class] ? v[@"fans"] : @[])fan=MAX(fan,[f[@"rpm"] doubleValue]);
    NSString *(^num)(id,NSString *)=^NSString *(id x,NSString *format){ return [x isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:format,[x doubleValue]] : @""; };
    return [@[num(v[@"temp"][@"cpu_temp_avg"],@"%.1f"),num(v[@"temp"][@"gpu_temp_avg"],@"%.1f"),num(v[@"cpu_power"],@"%.2f"),num(v[@"gpu_power"],@"%.2f"),
              num(v[@"all_power"],@"%.2f"),num(v[@"sys_power"],@"%.2f"),num(v[@"ecpu_freq_mhz"],@"%.0f"),num(v[@"pcpu_freq_mhz"],@"%.0f"),
              num(v[@"gpu_freq_mhz"],@"%.0f"),v[@"fans"] ? [NSString stringWithFormat:@"%.0f",fan] : @""] componentsJoinedByString:@","];
}
// The GPU's own counters (IOAccelerator PerformanceStatistics), as Activity Monitor shows them.
static NSDictionary *gpuStatistics(void) {
    io_iterator_t iterator=0;NSMutableDictionary *result=[NSMutableDictionary dictionary];
    if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOAccelerator"),&iterator)!=KERN_SUCCESS)return result;
    io_object_t service;
    while((service=IOIteratorNext(iterator))) {
        CFTypeRef value=IORegistryEntryCreateCFProperty(service,CFSTR("PerformanceStatistics"),kCFAllocatorDefault,0);
        if(value && CFGetTypeID(value)==CFDictionaryGetTypeID()) {
            NSDictionary *stats=(__bridge NSDictionary *)value;
            for(NSString *key in @[@"Device Utilization %",@"Renderer Utilization %",@"Tiler Utilization %",@"In use system memory"])
                if([stats[key] isKindOfClass:NSNumber.class])result[key]=stats[key];
        }
        if(value)CFRelease(value);
        IOObjectRelease(service);
        if(result.count)break;
    }
    IOObjectRelease(iterator);
    return result;
}
static int memoryPressure(void) { int level=0;size_t size=sizeof(level);sysctlbyname("kern.memorystatus_vm_pressure_level",&level,&size,NULL,0);return level; }
static uint64_t swapUsed(void) { struct xsw_usage swap;size_t size=sizeof(swap);return sysctlbyname("vm.swapusage",&swap,&size,NULL,0) ? 0 : swap.xsu_used; }
// The game's window is on screen: then it should be showing frames.
static BOOL windowOnScreen(pid_t pid) {
    CFArrayRef list=CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements,kCGNullWindowID);
    BOOL found=NO;
    for(NSDictionary *window in (__bridge NSArray *)list) {
        if([window[(id)kCGWindowOwnerPID] intValue]!=pid || [window[(id)kCGWindowLayer] intValue]!=0)continue;
        NSDictionary *bounds=window[(id)kCGWindowBounds];
        if([bounds[@"Width"] doubleValue]>=320 && [bounds[@"Height"] doubleValue]>=240) {found=YES;break;}
    }
    if(list)CFRelease(list);
    return found;
}

/* Reads what a file gained since the last call, a whole line at a time. A file that shrank was
 * rotated (the engine keeps .1/.2 copies): reading starts again from its top. */
typedef struct { unsigned long long offset; NSMutableData *pending; } Tail;
static NSArray *tailLines(NSString *path, Tail *t) {
    if(!t->pending)t->pending=[NSMutableData data];
    unsigned long long size=[[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue];
    if(size<t->offset) {t->offset=0;[t->pending setLength:0];}
    if(size==t->offset)return @[];
    NSFileHandle *h=[NSFileHandle fileHandleForReadingAtPath:path];if(!h)return @[];
    [h seekToFileOffset:t->offset];
    NSData *data=[h readDataOfLength:(NSUInteger)MIN(size-t->offset,(unsigned long long)(8<<20))];[h closeFile];
    t->offset+=data.length;[t->pending appendData:data];
    NSMutableArray *lines=[NSMutableArray array];
    const char *bytes=t->pending.bytes;NSUInteger start=0;
    for(NSUInteger i=0;i<t->pending.length;i++) if(bytes[i]=='\n') {
        NSString *line=[[NSString alloc] initWithBytes:bytes+start length:i-start encoding:NSUTF8StringEncoding];
        if(line)[lines addObject:line];
        start=i+1;
    }
    [t->pending replaceBytesInRange:NSMakeRange(0,start) withBytes:NULL length:0];
    if(t->pending.length>(1<<20))[t->pending setLength:0];
    return lines;
}

/* Wine's output, turned into timeline events. Lines with +timestamp,+pid look like
 * "791252.512:0090:009c:err:channel:function message"; MESSAGE() lines ("wine: Unhandled ...")
 * have no prefix. Each distinct error message reaches the timeline 3 times; all are counted. */
static NSMutableDictionary *wineErrorCounts;
static NSUInteger wineEvents;
static void readWineLine(NSString *line) {
    if(!wineErrorCounts)wineErrorCounts=[NSMutableDictionary dictionary];
    if(!line.length || [line hasPrefix:@"[mvk-"] || [line hasPrefix:@"\t"])return;
    NSString *pid=nil,*text=line;
    NSArray *parts=[line componentsSeparatedByString:@":"];
    if(parts.count>=5 && matches(parts[0],@"^[0-9]+\\.[0-9]+$") && matches(parts[1],@"^[0-9a-f]{4}$")) {
        pid=parts[1];text=[[parts subarrayWithRange:NSMakeRange(3,parts.count-3)] componentsJoinedByString:@":"];
    }
    NSString *kind=nil;
    if([text containsString:@"Unhandled"] || [text containsString:@"unhandled exception"])kind=@"crash";
    else if([text containsString:@"PSO"] || [text containsString:@"materializeAll"] || [text containsString:@"pipeline state"])kind=@"gpu_pipeline_failure";
    else if([text hasPrefix:@"err:"] || [text hasPrefix:@"err "])kind=@"wine_error";
    if(!kind)return;
    // The same message from different threads or addresses counts as one: digits don't matter.
    NSString *key=[[NSRegularExpression regularExpressionWithPattern:@"[0-9a-fA-F]{4,}|[0-9]+" options:0 error:nil]
        stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0,text.length) withTemplate:@"#"];
    NSUInteger count=[wineErrorCounts[key] unsignedIntegerValue]+1;wineErrorCounts[key]=@(count);
    if(count<=3 && wineEvents<1000) {
        wineEvents++;
        NSMutableDictionary *details=[@{@"text":text.length>400 ? [text substringToIndex:400] : text,@"src":@"wine"} mutableCopy];
        if(pid)details[@"wine_pid"]=pid;
        timeline(kind,details);
    }
}

/* The game's frames shown since the last call, from its display log (one per native pid):
 * the count, and the longest gap between them in ms. */
typedef struct { NSUInteger frames; double maxGapMs; double lastPresented; BOOL any; } DisplayRead;
static DisplayRead readDisplay(NSString *folder, pid_t pid, Tail *t, double lastPresented, NSMutableArray *gaps) {
    DisplayRead r={0,0,lastPresented,NO};
    for(NSString *line in tailLines(join(folder,[NSString stringWithFormat:@"display-%d.csv",pid]),t)) {
        // schema_version,event,unix_ms,native_pid,sequence,layer_ptr,drawable_id,command_ptr,request_host_s,
        // event_host_s,minimum_duration_s,presented_s,presented_state,...
        NSArray *f=[line componentsSeparatedByString:@","];
        if(f.count<13 || ![f[1] isEqual:@"presented"] || ![f[12] isEqual:@"valid"])continue;
        double presented=[f[11] doubleValue];if(presented<=0)continue;
        if(r.lastPresented>0 && presented>r.lastPresented) {
            double gap=(presented-r.lastPresented)*1000;
            r.maxGapMs=MAX(r.maxGapMs,gap);[gaps addObject:@[@(presented),@(gap)]];
        }
        r.lastPresented=MAX(r.lastPresented,presented);r.frames++;r.any=YES;
    }
    return r;
}

static NSString *helperPath(NSString *name) { return join([NSProcessInfo.processInfo.arguments[0] stringByDeletingLastPathComponent],name); }

/* live.json: the recorder's view of the last seconds, for Pawpad's overlay. Rewritten each
 * second (a whole new file, so a reader never sees half of one). */
static double lowOf(NSArray *gaps, double fraction) {
    if(!gaps.count)return 0;
    NSMutableArray *times=[NSMutableArray arrayWithCapacity:gaps.count];
    for(NSArray *g in gaps)[times addObject:g[1]];
    [times sortUsingSelector:@selector(compare:)];
    NSUInteger n=MAX((NSUInteger)1,(NSUInteger)lround(times.count*fraction));double sum=0;
    for(NSUInteger i=0;i<n;i++)sum+=[times[times.count-1-i] doubleValue];
    return sum>0 ? 1000/(sum/n) : 0;
}
static void writeLive(NSString *folder, NSDictionary *value) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
    [data writeToFile:join(folder,@"live.json") options:NSDataWritingAtomic error:nil];
}

/* A launch ends the monitor of an earlier session that is still running (its launcher closed less
 * than two minutes ago, or still open), so the new session is the one recorded; the old one
 * finishes its own report. Only a pawpad-setup process named in cache/monitor.pid is stopped. */
static void stopMonitor(void) {
    pid_t pid=[[NSString stringWithContentsOfFile:monitorPath() encoding:NSUTF8StringEncoding error:nil] intValue];
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if(pid<=0 || pid==getpid() || proc_pidpath(pid,path,sizeof(path))<=0 || ![@(path) hasSuffix:@"/pawpad-setup"])return;
    kill(pid,SIGTERM);
    int fd=open(join(root,@"launch-monitor.lock").fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(fd<0)return;
    // Its report can take a few seconds; the new monitor waits for the lock in any case.
    for(int i=0;i<300 && flock(fd,LOCK_EX|LOCK_NB);i++)[NSThread sleepForTimeInterval:0.05];
    close(fd);
    event(@"previous_monitor_stopped",@{@"pid":@(pid)});
}

static NSString *const systemHeader=@"unix_ms,game_pid,window_on_screen,frames_shown,max_gap_ms,"
    "game_cpu_pct,game_pcore_pct,game_runnable_pct,game_threads,game_footprint_mb,game_power_w,game_wakeups_per_s,game_disk_read_mb_s,game_disk_write_mb_s,game_ipc,"
    "gpu_device_pct,gpu_renderer_pct,gpu_tiler_pct,gpu_memory_mb,ram_used_mb,ram_compressed_mb,swap_mb,memory_pressure,thermal_state,"
    "cpu_temp_c,gpu_temp_c,cpu_power_w,gpu_power_w,package_power_w,system_power_w,ecpu_mhz,pcpu_mhz,gpu_mhz,fan_rpm\n";

/* The session's monitor. It waits as long as the launcher stays open (until two minutes after it
 * closes), up to half a day, and never closes the launcher: Aniimo's may still be needed while
 * the game runs. With RECORD (Settings › Record performance) it is also the flight recorder:
 * once a second it samples the game and the Mac into system.csv, reads what the game showed
 * and what Wine printed, notes events in timeline.jsonl, samples a freeze, and writes the
 * session's report when it ends. Without it, it only notes when the game ran. */
static void watchClient(BOOL record) {
    int fd=open(join(root,@"launch-monitor.lock").fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(fd<0)fail(@"monitor_lock_failed");
    flock(lockFD,LOCK_UN);close(lockFD);lockFD=-1;
    BOOL locked=NO;for(int i=0;i<200 && !cancelRequested && !(locked=flock(fd,LOCK_EX|LOCK_NB)==0);i++)[NSThread sleepForTimeInterval:0.1];
    if(!locked){close(fd);return;}
    [[NSString stringWithFormat:@"%d",getpid()] writeToFile:monitorPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *folder=record && validSessionName(monitorSession) ? sessionFolder(monitorSession) : nil;
    NSFileHandle *system=nil;Macmon macmon={nil,-1,nil,nil};
    if(folder) {
        timelineFD=openTimeline(folder);
        system=appendHandle(join(folder,@"system.csv"),systemHeader);
        startMacmon(&macmon);
        timeline(@"recorder_started",@{@"macmon":@(macmon.task!=nil),@"src":@"recorder"});
    }
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:12*3600],*clientSeen=[NSDate date],*lastSeen=[NSDate date],*checked=[NSDate distantPast];
    pid_t gamePid=0,launcherPid=0;ProcessSample previous={0};NSTimeInterval previousAt=0;
    Tail wine={0,nil},display={0,nil};double lastPresented=0;
    NSDate *lastFrame=nil,*freezeStart=nil;NSUInteger freezes=0,samples=0,gameFrames=0,stutters=0;int thermal=-1,pressure=-1;
    NSMutableArray *recent=[NSMutableArray array];  // [presented_s, gap_ms] of the last 30 s on screen
    NSUInteger recorderErrors=0;
    while(deadline.timeIntervalSinceNow>0 && !cancelRequested) {
        NSDate *tick=[NSDate date];
        // One bad second (a file mid-rotation, a process gone mid-read) never ends the recording:
        // it is noted and the next second goes on.
        @try {
        if(-checked.timeIntervalSinceNow>=2) {
            checked=[NSDate date];NSArray *rows=sessionProcesses();
            pid_t game=0,launcher=0;
            for(NSDictionary *p in rows) {if([p[@"kind"] isEqual:@"game"])game=[p[@"pid"] intValue];else if([p[@"kind"] isEqual:@"client"] && !launcher)launcher=[p[@"pid"] intValue];}
            if(launcher && !launcherPid)timeline(@"launcher_seen",@{@"pid":@(launcher),@"src":@"recorder"});
            if(!launcher && launcherPid)timeline(@"launcher_closed",@{@"pid":@(launcherPid),@"src":@"recorder"});
            launcherPid=launcher;
            if(game!=gamePid) {
                if(gamePid) {
                    recordGameEnded(monitorSession);timeline(@"game_ended",@{@"pid":@(gamePid),@"frames_shown":@(gameFrames),@"src":@"recorder"});
                    // A report as soon as the game closes; the session's end writes it again.
                    NSString *perf=helperPath(@"pawpad-perf");
                    if(folder && [fm isExecutableFileAtPath:perf])task(perf,@[@"report",folder],nil,@"perf-report.log");
                }
                if(game) {recordGameStarted(monitorSession);timeline(@"game_started",@{@"pid":@(game),@"executable":gameExecutable(),@"src":@"recorder"});}
                gamePid=game;previous=(ProcessSample){0};display=(Tail){0,nil};lastPresented=0;lastFrame=nil;freezeStart=nil;gameFrames=0;[recent removeAllObjects];
            }
            if(rows.count) {lastSeen=[NSDate date];clientSeen=[NSDate date];}
        }
        if(folder) {
            for(NSString *line in tailLines(join(folder,@"wine.log"),&wine))readWineLine(line);
            readMacmon(&macmon);
            ProcessSample now=gamePid ? sampleProcess(gamePid) : (ProcessSample){0};
            NSTimeInterval at=NSProcessInfo.processInfo.systemUptime,dt=at-previousAt;
            BOOL rate=now.ok && previous.ok && dt>0.2;
            double (^per)(uint64_t,uint64_t)=^double(uint64_t a,uint64_t b){ return rate && a>=b ? (double)(a-b)/dt : 0; };
            double cpu=per(now.cpuNs,previous.cpuNs)/1e7,pcore=per(now.pcoreNs,previous.pcoreNs)/1e7,runnable=per(now.runnableNs,previous.runnableNs)/1e7;
            double watts=per(now.energyNj,previous.energyNj)/1e9,wakeups=per(now.wakeups,previous.wakeups);
            double readMB=per(now.diskRead,previous.diskRead)/1048576,writeMB=per(now.diskWrite,previous.diskWrite)/1048576;
            double ipc=rate && now.cycles>previous.cycles ? (double)(now.instructions-previous.instructions)/(double)(now.cycles-previous.cycles) : 0;
            previous=now;previousAt=at;
            NSMutableArray *gaps=[NSMutableArray array];
            DisplayRead shown=gamePid ? readDisplay(folder,gamePid,&display,lastPresented,gaps) : (DisplayRead){0,0,0,NO};
            if(gamePid)lastPresented=shown.lastPresented;
            BOOL visible=gamePid && windowOnScreen(gamePid);
            // Gaps while the window wasn't on screen (minimized, another Space) are not stutters.
            if(visible) {
                [recent addObjectsFromArray:gaps];
                for(NSArray *g in gaps)stutters+=[g[1] doubleValue]>50;
            }
            while(recent.count && [recent[0][0] doubleValue]<shown.lastPresented-30)[recent removeObjectAtIndex:0];
            if(shown.any) {
                if(!gameFrames)timeline(@"first_frame",@{@"pid":@(gamePid),@"src":@"recorder"});
                gameFrames+=shown.frames;lastFrame=[NSDate date];
                if(shown.maxGapMs>=250)timeline(@"hitch",@{@"pid":@(gamePid),@"gap_ms":@(round(shown.maxGapMs)),@"src":@"display"});
            }
            // A freeze: the window on screen and nothing new shown for 3 s, after the game had shown frames.
            if(gamePid && visible && lastFrame && -lastFrame.timeIntervalSinceNow>=3 && !freezeStart) {
                freezeStart=lastFrame;freezes++;
                NSMutableDictionary *details=[@{@"pid":@(gamePid),@"cpu_pct":@(round(cpu)),@"runnable_pct":@(round(runnable)),@"threads":@(now.threads),@"src":@"recorder"} mutableCopy];
                if(samples<5) {
                    NSString *file=join(folder,[NSString stringWithFormat:@"freezes/freeze-%lu-%d.txt",(unsigned long)freezes,gamePid]);
                    mkdirs(file.stringByDeletingLastPathComponent);
                    @try { task(@"/usr/bin/sample",@[[NSString stringWithFormat:@"%d",gamePid],@"3",@"-mayDie",@"-file",file],nil,@"freeze-sample.log");samples++;details[@"sample"]=[file substringFromIndex:folder.length+1]; }
                    @catch(NSException *ignored) { (void)ignored; }
                }
                timeline(@"freeze_started",details);
            }
            if(freezeStart && shown.any) {
                timeline(@"freeze_ended",@{@"pid":@(gamePid),@"duration_ms":@(round(-freezeStart.timeIntervalSinceNow*1000)),@"src":@"recorder"});freezeStart=nil;
            }
            NSDictionary *gpu=gpuStatistics();uint64_t used,compressed;systemMemory(&used,&compressed);
            int t=(int)NSProcessInfo.processInfo.thermalState,p=memoryPressure();
            if(t!=thermal) {if(thermal>=0)timeline(@"thermal_state",@{@"state":@(t),@"src":@"system"});thermal=t;}
            if(p!=pressure) {if(pressure>=0)timeline(@"memory_pressure",@{@"level":@(p),@"src":@"system"});pressure=p;}
            NSString *row=[NSString stringWithFormat:@"%llu,%d,%d,%lu,%.1f,%.1f,%.1f,%.1f,%d,%.0f,%.2f,%.0f,%.2f,%.2f,%.2f,%@,%@,%@,%.0f,%.0f,%.0f,%.0f,%d,%d,%@\n",
                unixMs(),gamePid,visible,(unsigned long)shown.frames,shown.maxGapMs,
                cpu,pcore,runnable,now.threads,now.footprint/1048576.0,watts,wakeups,readMB,writeMB,ipc,
                gpu[@"Device Utilization %"] ?: @"",gpu[@"Renderer Utilization %"] ?: @"",gpu[@"Tiler Utilization %"] ?: @"",[gpu[@"In use system memory"] doubleValue]/1048576.0,
                used/1048576.0,compressed/1048576.0,swapUsed()/1048576.0,p,t,macmonFields(macmon.latest)];
            @try { [system writeData:[row dataUsingEncoding:NSUTF8StringEncoding]]; } @catch(NSException *ignored) { (void)ignored; }
            NSMutableArray *last10=[NSMutableArray array];double sum10=0,worst10=0;
            for(NSArray *g in recent)if([g[0] doubleValue]>=shown.lastPresented-10) {[last10 addObject:g];sum10+=[g[1] doubleValue];worst10=MAX(worst10,[g[1] doubleValue]);}
            NSDictionary *m=macmon.latest;
            NSMutableDictionary *live=[@{@"t":@(unixMs()),@"game":@(gamePid!=0),@"visible":@(visible),@"frozen":@(freezeStart!=nil),
                @"fps":@(shown.frames),@"fps_10s":@(sum10>0 ? last10.count*1000.0/sum10 : 0),@"low_1pct_30s":@(lowOf(recent,0.01)),@"worst_ms_10s":@(worst10),
                @"stutters":@(stutters),@"freezes":@(freezes),@"cpu_pct":@(cpu),@"runnable_pct":@(runnable),@"game_mb":@(now.footprint/1048576.0),
                @"ram_used_mb":@(used/1048576.0),@"swap_mb":@(swapUsed()/1048576.0),@"thermal":@(t),@"pressure":@(p)} mutableCopy];
            if(gpu[@"Device Utilization %"])live[@"gpu_pct"]=gpu[@"Device Utilization %"];
            if([m[@"temp"] isKindOfClass:NSDictionary.class]) {live[@"cpu_c"]=m[@"temp"][@"cpu_temp_avg"] ?: @0;live[@"gpu_c"]=m[@"temp"][@"gpu_temp_avg"] ?: @0;}
            if(m[@"all_power"])live[@"package_w"]=m[@"all_power"];
            writeLive(folder,live);
        }
        } @catch(NSException *exception) {
            if(++recorderErrors<=20)timeline(@"recorder_error",@{@"reason":[NSString stringWithFormat:@"%@: %@",exception.name,exception.reason ?: @""],@"src":@"recorder"});
        }
        if(-clientSeen.timeIntervalSinceNow>120)break;
        NSTimeInterval rest=(folder ? 1.0 : 2.0)+tick.timeIntervalSinceNow;
        if(rest>0)[NSThread sleepForTimeInterval:rest];
    }
    // Stopped by a new launch (SIGTERM): finish this session's record and report all the same.
    BOOL stopped=cancelRequested!=0;cancelRequested=0;
    if(gamePid) {recordGameEnded(monitorSession);timeline(@"game_ended",@{@"pid":@(gamePid),@"frames_shown":@(gameFrames),@"src":@"recorder"});}
    if(stopped)timeline(@"recorder_stopped_by_new_launch",@{@"src":@"recorder"});
    recordSessionEnded(monitorSession,lastSeen);
    if(folder) {
        writeLive(folder,@{@"t":@(unixMs()),@"game":@NO,@"ended":@YES});
        stopMacmon(&macmon);
        NSMutableArray *errors=[NSMutableArray array];
        for(NSString *key in [wineErrorCounts keysSortedByValueUsingSelector:@selector(compare:)].reverseObjectEnumerator) {
            if(errors.count>=25)break;
            [errors addObject:@{@"message":key,@"count":wineErrorCounts[key]}];
        }
        timeline(@"recorder_finished",@{@"freezes":@(freezes),@"freeze_samples":@(samples),@"wine_messages":errors,@"src":@"recorder"});
        if(timelineFD>=0)close(timelineFD);timelineFD=-1;[system closeFile];
        // The session's report (pawpad-perf, beside this worker). Bounded; never fatal.
        NSString *perf=helperPath(@"pawpad-perf");
        if([fm isExecutableFileAtPath:perf])waitTask(task(perf,@[@"report",folder],nil,@"perf-report.log"),120);
    }
    [fm removeItemAtPath:monitorPath() error:nil];
    close(fd);
}
