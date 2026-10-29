#include "TrackpadBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stddef.h>
#include <time.h>

// Undocumented Apple ABI, resolved at runtime; no third-party binary dependency.
// Interface references and limitations are recorded in README.md.
typedef struct { float x, y; } TFPoint;
typedef struct { TFPoint position, velocity; } TFVector;
typedef struct {
    int32_t frame; double timestamp;
    int32_t identifier, state, finger, hand;
    TFVector normalized;
    float size; int32_t reserved1;
    float angle, major, minor;
    TFVector absolute;
    int32_t reserved2, reserved3; float density;
} RawContact;
_Static_assert(sizeof(RawContact) == 96, "Unexpected multitouch contact ABI");
_Static_assert(offsetof(RawContact, normalized) == 32, "Unexpected coordinate ABI");
typedef int (*RawHandler)(void *, RawContact *, int, double, uint64_t);
static void *library;
static CFArrayRef devices;
static CFArrayRef (*createList)(void);
static void (*registerFrame)(void *, RawHandler);
static void (*unregisterFrame)(void *, RawHandler);
static void (*startDevice)(void *, int);
static void (*stopDevice)(void *);
static TFFrameHandler observer;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static TFContact recentSingle;
static double recentSingleTime;
static int recentSingleValid;
static void *sequenceDevice;
static int sequenceActive, sequenceRejected;
static double sequenceBegan;
static TFContact sequenceOrigin;
static double monotonicTime(void) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)now.tv_sec + (double)now.tv_nsec / 1e9;
}
int TFRecentSingleContact(TFContact *contact) {
    pthread_mutex_lock(&lock);
    int valid = recentSingleValid && monotonicTime() - recentSingleTime <= 0.12;
    if (valid && contact) *contact = recentSingle;
    pthread_mutex_unlock(&lock);
    return valid;
}

static int onFrame(void *device, RawContact *raw, int count, double time, uint64_t frame) {
    (void)frame;
    if (count < 0 || count > 32 || (count && !raw)) return 0;
    TFContact points[16];
    int n = 0;
    for (int i = 0; i < count && n < 16; i++) {
        // making/touching only: hover and lift-off frames must not shift the centroid.
        if (raw[i].state != 3 && raw[i].state != 4) continue;
        float x = raw[i].normalized.position.x, y = raw[i].normalized.position.y;
        if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) continue;
        points[n++] = (TFContact){raw[i].identifier, x, y};
    }
    pthread_mutex_lock(&lock);
    double arrival = monotonicTime();
    if (n > 0 && (!sequenceActive || sequenceDevice != device)) {
        sequenceDevice = device; sequenceActive = 1; sequenceRejected = 0;
        sequenceBegan = arrival; sequenceOrigin = points[0];
    }
    if (n > 1) { sequenceRejected = 1; recentSingleValid = 0; }
    else if (n == 1) {
        if (points[0].identifier != sequenceOrigin.identifier || arrival - sequenceBegan > 0.30 ||
            hypotf(points[0].x - sequenceOrigin.x, points[0].y - sequenceOrigin.y) > 0.025f) sequenceRejected = 1;
        recentSingleValid = !sequenceRejected;
        if (recentSingleValid) { recentSingle = sequenceOrigin; recentSingleTime = arrival; }
    } else if (sequenceDevice == device) { sequenceActive = 0; }
    TFFrameHandler target = observer;
    pthread_mutex_unlock(&lock);
    if (target) target((uint64_t)(uintptr_t)device, points, n, time);
    return 0;
}

int TFRefresh(void) {
    if (!createList) return -1;
    CFArrayRef next = createList();
    if (!next) return devices ? (int)CFArrayGetCount(devices) : 0;
    CFIndex oldCount = devices ? CFArrayGetCount(devices) : 0;
    CFIndex newCount = CFArrayGetCount(next);
    for (CFIndex i = 0; i < oldCount; i++) {
        void *device = (void *)CFArrayGetValueAtIndex(devices, i);
        if (!CFArrayContainsValue(next, CFRangeMake(0, newCount), device)) {
            unregisterFrame(device, onFrame);
            stopDevice(device);
        }
    }
    for (CFIndex i = 0; i < newCount; i++) {
        void *device = (void *)CFArrayGetValueAtIndex(next, i);
        if (!devices || !CFArrayContainsValue(devices, CFRangeMake(0, oldCount), device)) {
            registerFrame(device, onFrame);
            startDevice(device, 0);
        }
    }
    if (devices) CFRelease(devices);
    devices = next;
    return (int)newCount;
}

int TFStart(TFFrameHandler handler) {
    if (!library) library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    if (!library) return -1;
    createList = dlsym(library, "MTDeviceCreateList");
    registerFrame = dlsym(library, "MTRegisterContactFrameCallback");
    unregisterFrame = dlsym(library, "MTUnregisterContactFrameCallback");
    startDevice = dlsym(library, "MTDeviceStart");
    stopDevice = dlsym(library, "MTDeviceStop");
    if (!createList || !registerFrame || !unregisterFrame || !startDevice || !stopDevice) return -2;
    pthread_mutex_lock(&lock); observer = handler; pthread_mutex_unlock(&lock);
    return TFRefresh();
}

void TFStop(void) {
    pthread_mutex_lock(&lock); observer = NULL; recentSingleValid = 0; sequenceActive = 0; sequenceRejected = 0; pthread_mutex_unlock(&lock);
    if (!devices) return;
    for (CFIndex i = 0; i < CFArrayGetCount(devices); i++) {
        void *device = (void *)CFArrayGetValueAtIndex(devices, i);
        unregisterFrame(device, onFrame);
        stopDevice(device);
    }
    CFRelease(devices); devices = NULL;
    // Keep the dynamic library loaded: an in-flight callback may still be returning.
}
