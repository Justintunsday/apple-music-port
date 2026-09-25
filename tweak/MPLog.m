#import "MPLog.h"
#import <os/log.h>
#import <stdio.h>

static os_log_t MPLogger;
static BOOL MPFileEnabled = YES;
static NSString *MPCustomPath = nil;
static FILE *MPFile = NULL;

static NSString *MPResolveLogPath(void) {
    NSArray<NSString *> *candidates = @[
        @"/var/jb/var/mobile/Library/Logs/MusicPort.log",
        @"/var/mobile/Library/Logs/MusicPort.log",
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"MusicPort.log"],
    ];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *path in candidates) {
        NSString *dir = path.stringByDeletingLastPathComponent;
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        if ([fm isWritableFileAtPath:dir] || [fm isWritableFileAtPath:path]) return path;
    }
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"MusicPort.log"];
}

NSString *MPLogFilePath(void) {
    static NSString *defaultPath = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaultPath = MPResolveLogPath(); });
    return MPCustomPath ?: defaultPath;
}

void MPLogSetFileEnabled(BOOL enabled) {
    MPFileEnabled = enabled;
}

void MPLogSetLogPath(NSString *path) {
    NSString *next = path.length ? [path copy] : nil;
    if ((MPCustomPath == next) || [MPCustomPath isEqualToString:next]) return;
    if (MPFile) {
        fclose(MPFile);
        MPFile = NULL;
    }
    MPCustomPath = next;
}

static void MPEnsureLogger(void) {
    if (!MPLogger) MPLogger = os_log_create("com.justintunsday.musicport", "port");
}

static void MPEnsureFile(void) {
    if (MPFile || !MPFileEnabled) return;
    MPEnsureLogger();
    MPFile = fopen(MPLogFilePath().UTF8String, "a");
}

void MPLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    MPEnsureLogger();
    os_log(MPLogger, "%{public}s", message.UTF8String);

    if (MPFileEnabled) {
        MPEnsureFile();
        if (MPFile) {
            fprintf(MPFile, "[%s] %s\n", NSDate.date.description.UTF8String, message.UTF8String);
            fflush(MPFile);
        }
    }
}

void MPLogView(UIView *view, NSString *label) {
    if (!view) {
        MPLog(@"%@: <nil>", label);
        return;
    }
    SEL sel = NSSelectorFromString(@"recursiveDescription");
    NSString *desc = nil;
    if ([view respondsToSelector:sel]) {
        IMP imp = [view methodForSelector:sel];
        NSString *(*fn)(id, SEL) = (void *)imp;
        desc = fn(view, sel);
    }
    if (![desc isKindOfClass:NSString.class]) desc = view.description;
    if (desc.length > 120000) desc = [[desc substringToIndex:120000] stringByAppendingString:@"...<truncated>"];
    MPLog(@"==== %@ (%@) ====\n%@", label, NSStringFromClass(view.class), desc);
}
