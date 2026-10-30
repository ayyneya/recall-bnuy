/* Pawpad's setup worker: Recall's native worker (scripts/portable_setup.m, by Joshua Asher
 * Nelson) for Aniimo. Original project contributions: Apache-2.0.
 *
 * The same engine (Wine and DXMT with Recall's changes), the same Windows environment and the
 * same safety rules: one data folder Pawpad owns (marked), a runtime archive and an installer
 * checked against the app's pinned SHA-256, extraction that refuses anything outside the
 * runtime, one worker at a time, uninstall to the Trash. Aniimo's own launcher takes
 * Battle.net's place. The app runs one command per worker and reads its JSON events.
 */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreAudio/CoreAudio.h>
#import <IOKit/IOKitLib.h>
#include <CommonCrypto/CommonDigest.h>
#include <archive.h>
#include <archive_entry.h>
#include <sys/file.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <fcntl.h>
#include <errno.h>
#include <libproc.h>
#include <signal.h>
#include <unistd.h>

static NSFileManager *fm;
static NSString *root;
static int lockFD = -1;
static BOOL monitorMode;
// The launcher start a launch's monitor watches (watch --session), whose record it adds to.
static NSString *monitorSession;
static BOOL ownedPreparation;
static volatile sig_atomic_t childPID;
static volatile sig_atomic_t cancelRequested;
static void cancelled(int sig) { cancelRequested=sig; if (childPID > 0) kill(childPID, SIGTERM); }
static void fail(NSString *code) { @throw [NSException exceptionWithName:@"SetupError" reason:code userInfo:nil]; }
static NSString *join(NSString *a, NSString *b) { return [a stringByAppendingPathComponent:b]; }
static void event(NSString *stage, NSDictionary *details) {
    NSMutableDictionary *value = [@{@"stage":stage} mutableCopy];
    [value addEntriesFromDictionary:details ?: @{}];
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
    fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); fflush(stdout);
}
static void mkdirs(NSString *path) {
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES
                       attributes:@{NSFilePosixPermissions:@0700} error:nil]) fail(@"directory_creation_failed");
}
static void writeJSON(id object, NSString *path) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:nil];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:nil]) fail(@"state_write_failed");
}
static NSDictionary *readJSON(NSString *path) {
    if([[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue]>(8ULL<<20))fail(@"manifest_size_limit");
    NSData *data = [NSData dataWithContentsOfFile:path];
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![value isKindOfClass:NSDictionary.class]) fail(@"invalid_manifest");
    return value;
}
static BOOL matches(NSString *s, NSString *pattern) {
    if (!s || ![s isKindOfClass:NSString.class]) return NO;
    NSRange range = [s rangeOfString:pattern options:NSRegularExpressionSearch];
    return range.location == 0 && range.length == s.length;
}
static BOOL safePath(NSString *s) {
    if (!s.length || [s hasPrefix:@"/"] || [s containsString:@"\\"] || [s containsString:@"\n"] ||
        [s containsString:@"\r"] || [s containsString:@"\t"]) return NO;
    for (NSString *part in [s componentsSeparatedByString:@"/"])
        if (!part.length || [part isEqual:@"."] || [part isEqual:@".."]) return NO;
    return YES;
}
static NSString *hashFile(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) fail(@"file_read_failed");
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode)) { close(fd); fail(@"file_not_regular"); }
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    unsigned char buffer[1024*128], digest[CC_SHA256_DIGEST_LENGTH]; ssize_t count;
    while ((count = read(fd, buffer, sizeof(buffer))) > 0) CC_SHA256_Update(&context, buffer, (CC_LONG)count);
    close(fd); if (count < 0) fail(@"file_read_failed");
    CC_SHA256_Final(digest, &context);
    NSMutableString *result = [NSMutableString string];
    for (unsigned int i=0; i<sizeof(digest); i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}
static uint64_t freeBytes(void) {
    return [[fm attributesOfFileSystemForPath:root error:nil][NSFileSystemFreeSize] unsignedLongLongValue];
}
static void space(uint64_t needed) { if (freeBytes() < needed) fail(@"insufficient_disk_space"); }
static void supportedVolume(NSString *path) {
    // Wine needs POSIX symlinks and Windows games expect case-insensitive
    // names: only APFS or Mac OS Extended, never case-sensitive or read-only.
    struct statfs fs;
    if (statfs(path.fileSystemRepresentation,&fs)) fail(@"install_location_unavailable");
    if (strcmp(fs.f_fstypename,"apfs") && strcmp(fs.f_fstypename,"hfs")) fail(@"unsupported_volume_format");
    if (fs.f_flags & MNT_RDONLY) fail(@"read_only_volume");
    if (pathconf(path.fileSystemRepresentation,_PC_CASE_SENSITIVE) == 1) fail(@"case_sensitive_volume");
}
static void ownRoot(NSString *requested) {
    root = [[requested stringByStandardizingPath] stringByResolvingSymlinksInPath];
    if (![root isAbsolutePath] || [root isEqual:@"/"] || [root isEqual:NSHomeDirectory()]) fail(@"unsafe_install_directory");
    NSString *parent = [root stringByDeletingLastPathComponent];
    BOOL parentIsDirectory = NO;
    if (![fm fileExistsAtPath:root] && !([fm fileExistsAtPath:parent isDirectory:&parentIsDirectory] && parentIsDirectory))
        fail(@"install_location_unavailable");
    NSString *marker = join(root,@".pawpad-owner");
    if ([fm fileExistsAtPath:root] && ![fm fileExistsAtPath:marker] &&
        [fm contentsOfDirectoryAtPath:root error:nil].count) fail(@"directory_not_owned_by_app");
    if (![fm fileExistsAtPath:marker]) supportedVolume([fm fileExistsAtPath:root] ? root : parent);
    mkdirs(root);
    struct stat st;
    if (lstat(root.fileSystemRepresentation,&st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid()) fail(@"directory_not_owned_by_user");
    if (chmod(root.fileSystemRepresentation,0700)) fail(@"private_directory_permissions_failed");
    int markerFD = open(marker.fileSystemRepresentation,O_RDWR|O_CREAT|O_NOFOLLOW,0600);
    if (markerFD < 0) fail(@"invalid_ownership_marker");
    char bytes[32] = {0}; ssize_t n=read(markerFD,bytes,sizeof(bytes));
    if (n==0) { if(write(markerFD,"pawpad-setup-v1\n",16)!=16) {close(markerFD);fail(@"ownership_write_failed");} }
    else if(n!=16 || memcmp(bytes,"pawpad-setup-v1\n",16)) {close(markerFD);fail(@"invalid_ownership_marker");}
    close(markerFD);
    lockFD=open(join(root,@"setup.lock").fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(lockFD<0)fail(@"setup_lock_failed");
    NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+(monitorMode ? 180.0 : 5.0);
    BOOL announced=NO;
    while(YES) {
        if(cancelRequested)fail(@"cancelled");
        if(flock(lockFD,LOCK_EX|LOCK_NB)==0)break;
        if(errno!=EWOULDBLOCK && errno!=EAGAIN && errno!=EINTR)fail(@"setup_lock_failed");
        if(NSProcessInfo.processInfo.systemUptime>=deadline)fail(@"setup_already_running");
        if(!announced) {event(@"waiting_for_setup",nil);announced=YES;}
        [NSThread sleepForTimeInterval:0.05];
    }
    if(cancelRequested)fail(@"cancelled");
    for (NSString *directory in @[@"runtimes",@"downloads",@"logs",@"home",@"tmp",@"cache"])
        mkdirs(join(root,directory));
}
static NSMutableDictionary *state(void) {
    NSString *p=join(root,@"state.json");
    return [fm fileExistsAtPath:p] ? [readJSON(p) mutableCopy] : [@{@"schema":@1,@"stage":@"not_installed"} mutableCopy];
}
static void saveStage(NSString *stage) {
    NSMutableDictionary *s=state();s[@"stage"]=stage;writeJSON(s,join(root,@"state.json"));event(stage,nil);
}
static NSString *runtime(void) {
    NSString *version=state()[@"active_runtime"];
    if(!matches(version,@"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")) fail(@"runtime_not_installed");
    NSString *p=join(join(root,@"runtimes"),version);
    if (![fm fileExistsAtPath:join(p,@"runtime.json")]) fail(@"runtime_missing");
    return p;
}
static NSString *gameExecutable(void);
#include "pawpad_profile.h"
/* Aniimo's environment (pawpad_profile.h) plus the data folder's paths. Never the player's HOME,
 * account state or caches. */
static NSMutableDictionary *wineEnv(NSString *engine) {
    NSString *game=gameExecutable();
    NSMutableDictionary *env=[aniimoEnvironment(game) mutableCopy];
    [env addEntriesFromDictionary:@{@"PATH":@"/usr/bin:/bin:/usr/sbin:/sbin",@"HOME":join(root,@"home"),@"USER":@"player",
        @"TMPDIR":join(root,@"tmp"),@"WINEPREFIX":join(root,@"environment"),@"WINEARCH":@"win64",
        @"WINESERVER":join(engine,@"bin/wineserver"),@"WINELOADER":join(engine,@"bin/wine"),
        @"WINEDEBUG":@"-all",
        @"CX_APPLEGPTK_LIBD3DSHARED_PATH":join(engine,@"lib/external/libd3dshared.dylib"),
        @"DXMT_SHADER_CACHE_PATH":join(root,@"cache/shaders"),@"DXMT_LOG_LEVEL":@"error",@"DXMT_LOG_PATH":@"none",
        @"DXMT_CONFIG_FILE":[@"Z:" stringByAppendingString:[([fm fileExistsAtPath:join(root,@"dxmt.conf")]?join(root,@"dxmt.conf"):join(engine,@"config/dxmt.conf")) stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]],
        @"DXMT_PIPELINE_CACHE_PATH":join(root,@"cache/pipelines")}];
    return env;
}
// DIRECTORY is the working directory (the data folder unless given): Wine names it the
// program's current directory, so a program started inside drive C sees a C: path.
static NSTask *taskIn(NSString *executable, NSArray *args, NSDictionary *env, NSString *logname, NSString *directory) {
    NSTask *p=[NSTask new];p.executableURL=[NSURL fileURLWithPath:executable];p.arguments=args;
    if(env)p.environment=env;
    p.currentDirectoryURL=[NSURL fileURLWithPath:directory ?: root];
    NSString *log=join(join(root,@"logs"),logname);
    mkdirs(log.stringByDeletingLastPathComponent);
    if(![fm fileExistsAtPath:log]) [fm createFileAtPath:log contents:nil attributes:@{NSFilePosixPermissions:@0600}];
    NSFileHandle *out=[NSFileHandle fileHandleForWritingAtPath:log];[out truncateFileAtOffset:0];
    p.standardOutput=out;p.standardError=out;
    if(![p launchAndReturnError:nil]) fail(@"process_launch_failed");
    // The child has its own copy; this one would stay open for the worker's life (the recorder
    // runs ps every 2 s: one descriptor each, until the 256-descriptor limit stopped it).
    [out closeFile];
    return p;
}
static NSTask *task(NSString *executable, NSArray *args, NSDictionary *env, NSString *logname) {
    return taskIn(executable,args,env,logname,nil);
}
static int waitTask(NSTask *p, double seconds) {
    childPID=p.processIdentifier;
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(p.running && deadline.timeIntervalSinceNow>0 && !cancelRequested) [NSThread sleepForTimeInterval:0.05];
    if(p.running) {
        kill(p.processIdentifier,SIGTERM);
        NSDate *grace=[NSDate dateWithTimeIntervalSinceNow:2];
        while(p.running && grace.timeIntervalSinceNow>0) [NSThread sleepForTimeInterval:0.05];
        if(p.running)kill(p.processIdentifier,SIGKILL);
        [p waitUntilExit];childPID=0;if(cancelRequested)fail(@"cancelled");return 124;
    }
    [p waitUntilExit];childPID=0;if(cancelRequested)fail(@"cancelled");return p.terminationStatus;
}
static BOOL busy(NSString *engine) {
    if(![fm fileExistsAtPath:join(root,@"environment")]) return NO;
    NSTask *p=task(join(engine,@"bin/wineserver"),@[@"-w"],wineEnv(engine),@"server-check.log");
    int result=waitTask(p,5);
    if(result!=0 && result!=124)fail(@"server_check_failed");
    return result==124;
}
#define GAME_EXECUTABLE gameExecutable()
#include "pawpad_aniimo.h"
#include "pawpad_shell.h"
#include "portable_logs.h"
#include "pawpad_session.h"
#include "portable_voice.h"
#include "portable_network.h"
#include "pawpad_display.h"
#include "pawpad_recorder.h"
#ifndef ROSETTA_PROBE
#define ROSETTA_PROBE @"/usr/bin/arch"
#endif
// The launcher, the game and Wine are Intel programs. Upgrading macOS doesn't keep Rosetta
// (Recall issue #15), so launches check too, before anything starts Wine.
static void requireRosetta(void) {
    if(waitTask(task(ROSETTA_PROBE,@[@"-x86_64",@"/usr/bin/true"],nil,@"rosetta-check.log"),10))fail(@"rosetta_required");
}
static void preflight(void) {
    int silicon=0;size_t size=sizeof(silicon);
    sysctlbyname("hw.optional.arm64",&silicon,&size,NULL,0);
    if(!silicon)fail(@"apple_silicon_required");
    // Recall's engine needs Rosetta's fixes in macOS 26.5.
    if(![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){26,5,0}])fail(@"macos_26_5_required");
    requireRosetta();
    event(@"preflight_ok",@{@"free_bytes":@(freeBytes())});
}
static NSString *download(NSString *url, NSString *expected) {
    if(!matches(expected,@"^[a-f0-9]{64}$"))fail(@"invalid_download_hash");
    NSURL *u=[NSURL URLWithString:url];
    if(![u.scheme isEqual:@"https"] || !u.host.length || u.user || u.password)fail(@"https_download_required");
    NSString *dest=join(join(root,@"downloads"),expected);
    if([fm fileExistsAtPath:dest]) {
        if(![hashFile(dest) isEqual:expected])fail(@"cached_download_hash_mismatch");return dest;
    }
    space(1ULL<<30);
    NSString *part=[dest stringByAppendingString:@".part"];
    struct stat st;
    if(!lstat(part.fileSystemRepresentation,&st) && !S_ISREG(st.st_mode))fail(@"unsafe_partial_download");
    event(@"downloading",nil);
    NSArray *args=@[@"--fail",@"--location",@"--proto",@"=https",@"--proto-redir",@"=https",
        @"--retry",@"2",@"--connect-timeout",@"20",@"--max-time",@"1800",@"--max-filesize",@"1073741824",
        @"--continue-at",@"-",@"--output",part,url];
    int code=waitTask(task(@"/usr/bin/curl",args,nil,@"download.log"),1810);
    if(code==33 || code==36) {
        [fm removeItemAtPath:part error:nil];
        code=waitTask(task(@"/usr/bin/curl",args,nil,@"download.log"),1810);
    }
    if(code)fail(@"download_interrupted_retry_to_resume");
    if(![hashFile(part) isEqual:expected]) { [fm removeItemAtPath:part error:nil];fail(@"download_hash_mismatch"); }
    if(![fm moveItemAtPath:part toPath:dest error:nil])fail(@"download_commit_failed");
    event(@"download_verified",nil);return dest;
}
static void extract(NSString *archivePath, NSString *destination) {
    struct archive *a=archive_read_new();archive_read_support_filter_gzip(a);archive_read_support_format_tar(a);
    if(archive_read_open_filename(a,archivePath.fileSystemRepresentation,131072)!=ARCHIVE_OK)fail(@"archive_open_failed");
    NSMutableSet *seen=[NSMutableSet set];NSMutableArray *links=[NSMutableArray array];
    struct archive_entry *entry;uint64_t total=0;int result;
    @try {
        while((result=archive_read_next_header(a,&entry))==ARCHIVE_OK) {
            if(cancelRequested)fail(@"cancelled");
            NSString *name=[NSString stringWithUTF8String:archive_entry_pathname(entry)];
            if([name hasSuffix:@"/"])name=[name substringToIndex:name.length-1];
            if(!safePath(name) || [seen containsObject:name.lowercaseString] || seen.count>20000)fail(@"unsafe_archive_path");
            [seen addObject:name.lowercaseString];
            if(archive_entry_hardlink(entry))fail(@"archive_hardlink_rejected");
            mode_t type=archive_entry_filetype(entry);NSString *dest=join(destination,name);
            if(type==AE_IFLNK) {
                const char *raw=archive_entry_symlink(entry);NSString *link=raw?[NSString stringWithUTF8String:raw]:nil;
                if(!link.length || [link hasPrefix:@"/"] || [link containsString:@"\\"])fail(@"unsafe_archive_symlink");
                NSString *resolved=[[name.stringByDeletingLastPathComponent stringByAppendingPathComponent:link] stringByStandardizingPath];
                if(!safePath(resolved))fail(@"archive_symlink_escapes_runtime");
                [links addObject:@[dest,link]];continue;
            }
            if(type!=AE_IFREG && type!=AE_IFDIR)fail(@"archive_special_file_rejected");
            mkdirs(dest.stringByDeletingLastPathComponent);
            if(type==AE_IFDIR) {mkdirs(dest);continue;}
            la_int64_t length=archive_entry_size(entry);
            if(length<0 || length>(2LL<<30) || total+(uint64_t)length>(8ULL<<30))fail(@"archive_size_limit");
            total+=(uint64_t)length;
            int fd=open(dest.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,
                        archive_entry_perm(entry)&0111 ? 0755:0644);
            if(fd<0)fail(@"archive_file_creation_failed");
            char buffer[131072];la_ssize_t n;uint64_t wrote=0;
            while((n=archive_read_data(a,buffer,sizeof(buffer)))>0) {
                ssize_t offset=0;
                while(offset<n) {ssize_t count=write(fd,buffer+offset,(size_t)(n-offset));if(count<=0){close(fd);fail(@"archive_write_failed");}offset+=count;}
                wrote+=(uint64_t)n;
            }
            close(fd);if(n<0 || wrote!=(uint64_t)length)fail(@"archive_truncated");
        }
        if(result!=ARCHIVE_EOF)fail(@"archive_corrupt");
        // No symlink can be traversed during extraction: create all of them last.
        for(NSArray *link in links) {
            NSString *parent=[link[0] stringByDeletingLastPathComponent];
            NSString *relative=[parent substringFromIndex:destination.length];
            NSString *cursor=destination;
            for(NSString *part in [relative componentsSeparatedByString:@"/"]) {
                if(!part.length)continue;cursor=join(cursor,part);struct stat st;
                if(!lstat(cursor.fileSystemRepresentation,&st) && !S_ISDIR(st.st_mode))fail(@"archive_symlink_parent_rejected");
                mkdirs(cursor);
            }
            if(symlink([link[1] fileSystemRepresentation],[link[0] fileSystemRepresentation]))fail(@"archive_symlink_failed");
        }
        for(NSArray *link in links) {
            NSString *resolved=[link[0] stringByResolvingSymlinksInPath];
            if(![resolved hasPrefix:[destination stringByAppendingString:@"/"]])fail(@"archive_symlink_escapes_runtime");
        }
    } @finally {archive_read_free(a);}
}
static void verifyRuntime(NSString *engine, NSString *version) {
    NSDictionary *manifest=readJSON(join(engine,@"runtime.json"));
    if(![manifest[@"version"] isEqual:version] || ![manifest[@"files"] isKindOfClass:NSDictionary.class])fail(@"runtime_identity_mismatch");
    NSDictionary *files=manifest[@"files"];
    for(NSString *name in files) {
        if(cancelRequested)fail(@"cancelled");
        if(!safePath(name))fail(@"unsafe_manifest_path");
        NSDictionary *spec=files[name];NSString *p=join(engine,name);struct stat st;
        if(lstat(p.fileSystemRepresentation,&st))fail(@"runtime_file_missing");
        if(spec[@"symlink"]) {
            if(!S_ISLNK(st.st_mode) || ![[fm destinationOfSymbolicLinkAtPath:p error:nil] isEqual:spec[@"symlink"]])fail(@"runtime_link_mismatch");
        } else if(!S_ISREG(st.st_mode) || ![hashFile(p) isEqual:spec[@"sha256"]])fail(@"runtime_file_hash_mismatch");
    }
    NSDirectoryEnumerator *enumerator=[fm enumeratorAtPath:engine];NSString *name;
    while((name=[enumerator nextObject])) {
        struct stat st;if(lstat(join(engine,name).fileSystemRepresentation,&st))fail(@"runtime_file_missing");
        if(S_ISREG(st.st_mode) && [name.lastPathComponent isEqual:@".DS_Store"])continue;
        if(!S_ISDIR(st.st_mode) && ![name isEqual:@"runtime.json"] && !files[name])fail(@"runtime_unlisted_file");
    }
    for(NSString *required in @[@"bin/wine",@"bin/wineserver",@"config/dxmt.conf",@"lib/external/libd3dshared.dylib",
                              @"lib/wine/x86_64-unix/winemetal.so",@"lib/wine/x86_64-unix/winemac.so"])
        if(!files[required])fail(@"runtime_required_component_missing");
}
// Keep the active and the previous runtime; older ones this worker installed are removed.
static void pruneRuntimes(NSString *active, NSString *previous) {
    NSString *directory=join(root,@"runtimes");
    for(NSString *name in [fm contentsOfDirectoryAtPath:directory error:nil]) {
        if([name isEqual:active] || [name isEqual:previous] || !matches(name,@"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"))continue;
        NSString *path=join(directory,name);struct stat st;
        if(lstat(path.fileSystemRepresentation,&st) || !S_ISDIR(st.st_mode) || ![fm fileExistsAtPath:join(path,@"runtime.json")])continue;
        [fm removeItemAtPath:path error:nil];
        // and the engine's app shell (pawpad_shell.h), whose links pointed into it
        [fm removeItemAtPath:join(join(root,@"app-shell"),name) error:nil];
    }
}
static void installRuntime(NSString *archivePath, NSString *expected, NSString *version, BOOL repair) {
    if(!matches(version,@"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") || !matches(expected,@"^[a-f0-9]{64}$"))fail(@"invalid_runtime_identity");
    if(state()[@"active_runtime"] && busy(runtime()))fail(@"close_game_before_maintenance");
    if(![hashFile(archivePath) isEqual:expected])fail(@"archive_hash_mismatch");
    space(3ULL<<30);
    NSString *target=join(join(root,@"runtimes"),version),*stage=join(root,@"incoming-runtime");
    saveStage(@"installing_runtime");
    if([fm fileExistsAtPath:target] && !repair)verifyRuntime(target,version);
    else {
        if([fm fileExistsAtPath:stage] && ![fm removeItemAtPath:stage error:nil])fail(@"staging_cleanup_failed");
        mkdirs(stage);extract(archivePath,stage);verifyRuntime(stage,version);
        NSString *replaced=join(root,@"replaced-runtime");
        if([fm fileExistsAtPath:replaced] && ![fm removeItemAtPath:replaced error:nil])fail(@"staging_cleanup_failed");
        if([fm fileExistsAtPath:target] && ![fm moveItemAtPath:target toPath:replaced error:nil])fail(@"runtime_commit_failed");
        if(![fm moveItemAtPath:stage toPath:target error:nil])fail(@"runtime_commit_failed");
        [fm removeItemAtPath:replaced error:nil];
    }
    NSMutableDictionary *s=state();NSString *previous=s[@"active_runtime"];
    if(previous && ![previous isEqual:version])s[@"previous_runtime"]=previous;
    if(repair)[s removeObjectForKey:@"prepared_runtime"];
    s[@"active_runtime"]=version;s[@"stage"]=@"runtime_ready";writeJSON(s,join(root,@"state.json"));
    pruneRuntimes(version,s[@"previous_runtime"]);
    event(@"runtime_ready",@{@"version":version});
}
static void prepare(void) {
    preflight();NSString *engine=runtime();verifyRuntime(engine,state()[@"active_runtime"]);
    if(busy(engine))fail(@"close_game_before_setup");space(2ULL<<30);
    NSString *prefix=join(root,@"environment");
    NSString *marker=join(root,@"environment-owned.json");
    if([fm fileExistsAtPath:prefix] && ![fm fileExistsAtPath:marker])fail(@"existing_environment_not_owned");
    if(![fm fileExistsAtPath:marker])writeJSON(@{@"schema":@1,@"runtime":state()[@"active_runtime"]},marker);
    saveStage(@"preparing_environment");ownedPreparation=YES;
    // Update the registry and drivers without running installed programs' login startup entries.
    if(waitTask(task(join(engine,@"bin/wine"),@[@"wineboot.exe",@"-u",@"-r"],wineEnv(engine),@"wineboot.log"),180))fail(@"environment_initialization_failed");
    if(waitTask(task(join(engine,@"bin/wineserver"),@[@"-w"],wineEnv(engine),@"wineboot-wait.log"),60))fail(@"environment_initialization_busy");
    if(![fm fileExistsAtPath:join(prefix,@"system.reg")])fail(@"environment_registry_missing");
    configureRetinaMode(engine);
    // Before the launcher first goes online. None stops setup; launches retry.
    configureProxy(engine,proxyDetectionChosen());
    configureOptionKey(engine);
    configureCryptoProvider(engine);
    configureDrives(engine);
    if(!registrySaved(engine,60))fail(@"environment_initialization_busy");
    NSMutableDictionary *s=state();s[@"prepared_runtime"]=s[@"active_runtime"];writeJSON(s,join(root,@"state.json"));
    saveStage(@"environment_ready");ownedPreparation=NO;
}
/* In Retina mode (a Retina main display) each Windows pixel is half a point, so programs laid out
 * for 96 DPI come out half size. The engine's WINE_APP_DPI (patches/wine-win32u-display-log.patch)
 * gives the programs it names 192 DPI, Windows' 200%, while the game keeps 96 and draws at its own
 * resolution: the installer, and the launcher once found. Without Retina mode they need nothing. */
static NSMutableDictionary *launcherSize(NSMutableDictionary *env) {
    if(!retinaModeOn())return env;
    NSMutableArray *names=[NSMutableArray arrayWithObject:aniimoInstaller];
    NSString *launcher=launcherPath();
    if(launcher)[names addObject:launcher.lastPathComponent];
    env[@"WINE_APP_DPI"]=[@"192:" stringByAppendingString:[names componentsJoinedByString:@";"]];
    return env;
}
static void endSession(NSString *engine);
static void installLauncher(NSString *installer, NSString *expected) {
    requireRosetta();
    NSString *engine=runtime();
    if(![fm fileExistsAtPath:join(root,@"environment/system.reg")])fail(@"prepare_environment_first");
    // Open already: brought forward, never a second copy. The game or launcher running: wait.
    NSArray *running=sessionProcesses();
    if(focusKinds(running,@[@"installer"])) {event(@"launcher_installer_open",@{@"existing":@YES});return;}
    if(running.count)fail(@"close_game_before_setup");
    // Only Wine's own services left (from an installer that was closed): end them.
    if(busy(engine))endSession(engine);
    if(!matches(expected,@"^[a-f0-9]{64}$") || ![hashFile(installer) isEqual:expected])fail(@"client_installer_hash_mismatch");
    configureProxy(engine,proxyDetectionChosen());
    configureCryptoProvider(engine);
    // Z: as a network drive, so the installer offers C:\PawPrint\Aniimo; the mount manager
    // reads drive types when the session starts, so let the registry tool's session end first.
    if(configureDrives(engine) && !registrySaved(engine,30))fail(@"environment_initialization_busy");
    // Run from inside drive C, as on Windows from a Downloads folder.
    NSString *folder=join(driveC(),@"users/Public/Downloads"),*copy=join(folder,aniimoInstaller);
    mkdirs(folder);[fm removeItemAtPath:copy error:nil];
    if(![fm copyItemAtPath:installer toPath:copy error:nil] || ![hashFile(copy) isEqual:expected])fail(@"client_installer_copy_failed");
    saveStage(@"installing_launcher");
    // Wine's errors and any crash go to the installer's log (logs/launcher-installer.log): it
    // runs once, so the cost doesn't matter, and a window that vanishes leaves a reason.
    NSMutableDictionary *env=launcherSize(wineEnv(engine));env[@"WINEDEBUG"]=@"-all,err+all,+seh,+timestamp,+pid";
    NSTask *p=taskIn(join(engine,@"bin/wine"),@[windowsPath(copy)],env,@"launcher-installer.log",folder);
    event(@"launcher_installer_open",@{@"pid":@(p.processIdentifier)});
}
// Ends whatever is left of the Wine session.
static void endSession(NSString *engine) {
    waitTask(task(join(engine,@"bin/wineserver"),@[@"-k"],wineEnv(engine),@"session-end.log"),15);
    if(waitTask(task(join(engine,@"bin/wineserver"),@[@"-w"],wineEnv(engine),@"session-end-wait.log"),15))fail(@"client_close_failed");
}
/* Apple's Metal Performance HUD (Settings, launch --metal-hud 1) reaches the game through the
 * launcher, which starts it with its own environment, as Battle.net does for Overwatch.
 * Metal validation (launch --metal-validation 1|2) goes the same way, for finding GPU faults:
 * 1 checks the API calls, 2 also checks every shader's memory access (much slower). Errors are
 * logged and the game carries on, rather than stopping at the first one. */
#include "pawpad_metalfx.h"
static NSMutableDictionary *clientEnvironment(NSMutableDictionary *env, BOOL hud, int validation) {
    launcherSize(env);
    if(hud)[env addEntriesFromDictionary:@{@"MTL_HUD_ENABLED":@"1",@"MTL_HUD_DISABLE_MENU_BAR":@"1",
        @"MTL_HUD_ELEMENTS":@"device,rosetta,layersize,memory,gamemode,fps,gputime,frameinterval,frameintervalgraph,shaders"}];
    // Warnings stay off: in Aniimo they are millions of "redundant"/"unused binding" notes a session.
    if(validation>=1)[env addEntriesFromDictionary:@{@"MTL_DEBUG_LAYER":@"1",@"MTL_DEBUG_LAYER_ERROR_MODE":@"nslog"}];
    if(validation>=2)[env addEntriesFromDictionary:@{@"MTL_SHADER_VALIDATION":@"1",@"MTL_SHADER_VALIDATION_REPORT_TO_STDERR":@"1"}];
    return env;
}
static void closeClient(NSString *gameRunning);
/* --env "KEY=VALUE;KEY=VALUE": extra environment for one launch (a test's switches, e.g.
 * DXMT_CONFIG or DXMT_RECORD_*), applied last and kept in the session record. Only DXMT_, MTL_,
 * WINENCPU (CrossOver's processor count) and WINEMSYNC_QLIMIT names are taken: nothing here may
 * reach Wine's own paths or the account. DXMT_CONFIG separates its own options with ';' too, so a
 * piece after it that doesn't start another allowed name is one of its options:
 * "DXMT_CONFIG=dxgi.presentPacing=True;dxgi.presentPacingMode=3;DXMT_LOG_LEVEL=info". */
static NSDictionary *extraEnvironment(NSString *spec) {
    NSMutableDictionary *extra=[NSMutableDictionary dictionary];NSString *key=nil;
    for(NSString *piece in [spec ?: @"" componentsSeparatedByString:@";"]) {
        NSRange eq=[piece rangeOfString:@"="];
        NSString *name=eq.location==NSNotFound ? nil : [[piece substringToIndex:eq.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        BOOL allowed=name && matches(name,@"^(DXMT_[A-Z0-9_]+|MTL_[A-Z0-9_]+|WINENCPU|WINEMSYNC_QLIMIT)$");
        if(!allowed && [key isEqual:@"DXMT_CONFIG"]) {extra[key]=[extra[key] stringByAppendingFormat:@";%@",piece];continue;}
        if(!name)continue;
        if(!allowed)fail(@"launch_env_rejected");
        key=name;extra[key]=[piece substringFromIndex:eq.location+1];
    }
    return extra;
}
static void launchClient(BOOL hud, int validation, BOOL shell, BOOL recording, NSString *logging, NSString *loggingCustom, NSString *extraSpec, BOOL metalfx, NSString *sharpening) {
    // Both checked before anything changes: a rejected --env leaves the session and settings alone.
    NSDictionary *logs=loggingEnvironment(logging,loggingCustom),*extra=extraEnvironment(extraSpec);
    requireRosetta();
    NSString *engine=runtime(),*launcher=launcherPath();
    if(!launcher)fail(@"launcher_not_installed");
    NSArray *existing=sessionProcesses();
    // A game must start in a Wine session that began with the displays as they are now. A
    // launcher open from before a display change is closed and opened again; a running game
    // is left alone.
    NSString *displays=displaySignature(),*sessionDisplays=state()[@"session_displays"];
    BOOL displaysChanged=displays && ![displays isEqual:sessionDisplays];
    BOOL game=NO;for(NSDictionary *p in existing)game|=[p[@"kind"] isEqual:@"game"];
    if(existing.count && !game && sessionDisplays && displaysChanged) {
        event(@"displays_changed",nil);closeClient(@"close_game_before_maintenance");existing=@[];
    }
    if(focusSession(existing)) {
        if(!game)task(NSProcessInfo.processInfo.arguments[0],@[@"watch",@"--root",root],nil,[NSString stringWithFormat:@"client-monitor-%d.log",getpid()]);
        return;
    }
    if(displaysChanged)endSession(engine);
    configureRetinaMode(engine);
    // MetalFX upscaling (pawpad_metalfx.h): the DLSS stand-in in system32 or put back, sharpening.
    NSString *sharpness=nil;metalfx=configureAniimoMetalFX(engine,metalfx,sharpening,&sharpness);
    if(![aniimoSharpeningProfile(aniimoRendererProfile(gameExecutable()),gameExecutable(),sharpness) writeToFile:join(root,@"dxmt.conf") atomically:YES encoding:NSUTF8StringEncoding error:nil])fail(@"settings_write_failed");
    event(@"display",@{@"retina_mode":@(retinaModeOn()),@"game":gameExecutable()});
    // Setup applies these; a launch puts back any that went missing.
    configureProxy(engine,proxyDetectionChosen());
    configureOptionKey(engine);
    configureCryptoProvider(engine);
    configureVoiceMicrophone(engine,nil,YES,YES);
    if(displays) {NSMutableDictionary *s=state();s[@"session_displays"]=displays;writeJSON(s,join(root,@"state.json"));}
    NSMutableDictionary *env=clientEnvironment(wineEnv(engine),hud,validation);
    if(metalfx)[env addEntriesFromDictionary:aniimoMetalFXEnvironment()];
    // The launcher, and the game it starts, run inside the game's app bundle (pawpad_shell.h).
    NSString *loader=shell ? ensureShell(engine) : join(engine,@"bin/wine");
    env[@"WINELOADER"]=loader;
    // Recording keeps Wine's errors (timestamped, with the Windows process), which the recorder
    // reads; a logging preset chosen for a problem still wins.
    if(recording)env[@"WINEDEBUG"]=@"-all,err+all,+timestamp,+pid";
    [env addEntriesFromDictionary:logs];
    NSMutableDictionary *record=[@{@"logging":logs.count ? logging : @"off",@"winedebug":env[@"WINEDEBUG"],@"dxmt_log_level":env[@"DXMT_LOG_LEVEL"],
        @"runtime":state()[@"active_runtime"],@"game":gameExecutable(),@"metal_hud":@(hud),@"metal_validation":@(validation),@"app_shell":@(shell),@"profile":pawpadProfileVersion,@"retina_mode":@(retinaModeOn()),
        @"recording":@(recording),@"metalfx":@(metalfx)} mutableCopy];
    if(sharpness)record[@"metalfx_sharpness"]=sharpness;
    if([logging isEqual:@"custom"])record[@"logging_custom"]=loggingCustom;
    if(extra.count)record[@"extra_env"]=extra;
    if(recording)record[@"machine"]=machineRecord();
    stopMonitor();
    NSString *session=startSessionLog(record);
    if(recording)[env addEntriesFromDictionary:recorderEnvironment(sessionFolder(session))];
    [env addEntriesFromDictionary:extra];
    NSTask *p=taskIn(loader,@[windowsPath(launcher)],env,[NSString stringWithFormat:@"sessions/%@/wine.log",session],launcher.stringByDeletingLastPathComponent);
    saveStage(@"launcher_started");event(@"launcher_open",@{@"pid":@(p.processIdentifier),@"session":session,@"recording":@(recording)});
    task(NSProcessInfo.processInfo.arguments[0],@[@"watch",@"--root",root,@"--session",session,@"--record",recording ? @"1" : @"0"],nil,[NSString stringWithFormat:@"client-monitor-%d.log",getpid()]);
}
// Refuses while the game runs (failing with gameRunning). The launcher is closed with SIGTERM,
// then wineserver -k.
static void closeClient(NSString *gameRunning) {
    if(!(matches(state()[@"active_runtime"],@"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") && [fm fileExistsAtPath:join(join(join(root,@"runtimes"),state()[@"active_runtime"]),@"runtime.json")]))return;
    NSString *engine=runtime();BOOL closed=NO;
    for(int attempt=0;attempt<20 && !closed;attempt++) {
        if(membershipCache)[membershipCache removeAllObjects];
        NSArray *rows=sessionProcesses();NSMutableArray *clients=[NSMutableArray array];
        for(NSDictionary *p in rows) {if([p[@"kind"] isEqual:@"game"])fail(gameRunning);[clients addObject:p];}
        if(!clients.count) {closed=YES;break;}
        // Only the launcher's own program is asked to quit. The other programs in its folder (its
        // repair tool, the anti-cheat's cleaner) end with it or with the session, never by a signal
        // aimed at them.
        if(attempt==0) {
            event(@"closing_client",nil);
            // Launcher.exe (the stub kept in state.json) and <version>\PC-Launcher.exe (what it starts),
            // by exact name: UacLauncher.exe, in the same folder, is one of the helpers.
            for(NSDictionary *p in clients) {
                NSString *program=[[[p[@"name"] lowercaseString] componentsSeparatedByString:@"\\"] lastObject];
                if([program isEqual:@"launcher.exe"] || [program isEqual:@"pc-launcher.exe"])kill([p[@"pid"] intValue],SIGTERM);
            }
        }
        else if(attempt==10)waitTask(task(join(engine,@"bin/wineserver"),@[@"-k"],wineEnv(engine),@"client-stop.log"),15);
        [NSThread sleepForTimeInterval:1];
    }
    if(!closed)fail(@"client_close_failed");
}
static void uninstall(void) {
    // Everything Pawpad created lives under the owned root. Move, never delete: the folder is
    // recoverable from the Trash with Put Back, and on the same volume this is a rename.
    closeClient(@"close_game_before_uninstall");
    if(state()[@"active_runtime"])waitTask(task(join(runtime(),@"bin/wineserver"),@[@"-k"],wineEnv(runtime()),@"uninstall-stop.log"),15);
    NSURL *trashed=nil;NSError *error=nil;
    if(![fm trashItemAtURL:[NSURL fileURLWithPath:root] resultingItemURL:&trashed error:&error])fail(@"uninstall_move_failed");
    event(@"uninstalled",@{@"trashed":trashed.path ?: @""});
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    fm=NSFileManager.defaultManager;signal(SIGTERM,cancelled);signal(SIGINT,cancelled);
    @try {
        if(argc<2)fail(@"command_required");NSString *command=@(argv[1]);NSMutableDictionary *options=[NSMutableDictionary dictionary];
        for(int i=2;i<argc;i+=2) {if(i+1>=argc || strncmp(argv[i],"--",2))fail(@"invalid_arguments");options[@(argv[i]+2)]=@(argv[i+1]);}
        NSString *defaultRoot=join([fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject.path,@"Pawpad");
        monitorMode=[command isEqual:@"watch"];
        ownRoot(options[@"root"] ?: defaultRoot);
        if(monitorMode && validSessionName(options[@"session"]))monitorSession=options[@"session"];
        if([command isEqual:@"preflight"])preflight();
        else if([command isEqual:@"status"]) {
            BOOL environment=[fm fileExistsAtPath:join(root,@"environment/system.reg")];
            NSString *launcher=environment ? launcherPath() : nil,*game=environment ? gamePath() : nil;
            NSMutableDictionary *details=[@{@"state":state(),@"retina_display":@(mainDisplayIsRetina()),@"launcher_installed":@((BOOL)(launcher!=nil)),
                @"game_installed":@((BOOL)(game!=nil)),@"game_executable":gameExecutable(),@"free_bytes":@(freeBytes())} mutableCopy];
            if(launcher)details[@"launcher_path"]=windowsPath(launcher);
            if(game)details[@"game_path"]=windowsPath(game);
            event(@"status",details);
        }
        else if([command isEqual:@"onboarded"]) { NSMutableDictionary *s=state();s[@"onboarding_complete"]=@YES;writeJSON(s,join(root,@"state.json"));event(@"onboarding_complete",nil); }
        else if([command isEqual:@"session"])event(@"session",@{@"processes":sessionProcesses()});
        else if([command isEqual:@"watch"])watchClient([options[@"record"] isEqual:@"1"]);
        else if([command isEqual:@"repair-retina"])configureRetinaMode(runtime());
        // Builds the active engine's app bundle (pawpad_shell.h) without starting anything.
        else if([command isEqual:@"app-shell"])event(@"app_shell_ready",@{@"loader":ensureShell(runtime())});
        else if([command isEqual:@"download"])event(@"download_complete",@{@"file":[download(options[@"url"],options[@"sha256"]) lastPathComponent]});
        else if([command isEqual:@"install-runtime"])installRuntime(options[@"archive"] ?: download(options[@"url"],options[@"sha256"]),options[@"sha256"],options[@"version"],[options[@"repair"] isEqual:@"1"]);
        else if([command isEqual:@"verify"]) {verifyRuntime(runtime(),state()[@"active_runtime"]);event(@"runtime_verified",nil);}
        else if([command isEqual:@"prepare"])prepare();
        else if([command isEqual:@"install-launcher"])installLauncher(options[@"installer"] ?: download(options[@"url"],options[@"sha256"]),options[@"sha256"]);
        // --metal-hud 1 shows Apple's Metal Performance HUD over the game; --metal-validation 1|2 turns on
        // Metal's error checking (clientEnvironment); --app-shell 0 runs Wine's bare loader instead of
        // the game's app bundle (pawpad_shell.h); --env "KEY=VALUE;…" adds a test's switches
        // (extraEnvironment); --logging off|crashes|graphics|custom.
        // --record 1 records the session (Settings › Record performance): the flight recorder in
        // pawpad_recorder.h, and pawpad-perf's report when it ends.
        // --metalfx 1 offers DLSS on MetalFX, with --sharpening off|low|high (pawpad_metalfx.h); off by
        // default, and a launch without it puts back what an earlier one changed.
        else if([command isEqual:@"launch"])launchClient([options[@"metal-hud"] isEqual:@"1"],[options[@"metal-validation"] intValue],![options[@"app-shell"] isEqual:@"0"],[options[@"record"] isEqual:@"1"],options[@"logging"] ?: @"off",options[@"logging-custom"],options[@"env"],[options[@"metalfx"] isEqual:@"1"],options[@"sharpening"] ?: @"off");
        // A marker on the current session's timeline (--label: what is about to happen, e.g. "entering world").
        else if([command isEqual:@"mark"])markSession(options[@"label"]);
        else if([command isEqual:@"logging"])event(@"logging",@{@"setting":options[@"setting"] ?: @"off",@"environment":loggingEnvironment(options[@"setting"] ?: @"off",options[@"custom"])});
        else if([command isEqual:@"close-client"]) {closeClient(@"close_game_before_update");event(@"client_closed",nil);}
        else if([command isEqual:@"uninstall"])uninstall();
        else if([command isEqual:@"stop"]) {noteForceQuit();NSString *engine=runtime();int code=waitTask(task(join(engine,@"bin/wineserver"),@[@"-k"],wineEnv(engine),@"stop.log"),15);if(code!=0 && code!=1)fail(@"stop_failed");event(@"environment_stopped",nil);}
        else fail(@"unknown_command");
        if(lockFD>=0)close(lockFD);return 0;
    } @catch(NSException *exception) {
        if(cancelRequested && ownedPreparation) {
            cancelRequested=0;
            @try { NSString *engine=runtime();waitTask(task(join(engine,@"bin/wineserver"),@[@"-k"],wineEnv(engine),@"cancel-prepare.log"),15);waitTask(task(join(engine,@"bin/wineserver"),@[@"-w"],wineEnv(engine),@"cancel-wait.log"),15); } @catch(NSException *ignored) { (void)ignored; }
        }
        event(@"error",@{@"code":[exception.name isEqual:@"SetupError"]?exception.reason:@"unexpected_setup_error"});
        if(lockFD>=0)close(lockFD);return 1;
    }
}}
