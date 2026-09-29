//
//  m3_host_win32.h
//
//  The Win32 implementation of m3_host.h.
//
//  A header rather than a translation unit of its own, and included by m3_core.c
//  alone: a new .c would have to be added to every source list that names them one by
//  one, and most of those are in build scripts outside this repository.
//

#ifndef m3_host_win32_h
#define m3_host_win32_h

#include "m3_core.h"

#if !defined(_WIN32)
#  error "This file is for Windows only"
#endif

#include "m3_host.h"

#ifndef WIN32_LEAN_AND_MEAN
#  define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

// A thread's stack is one reservation, and any address inside it answers with the
// base of the whole thing - guard page included. That is what makes VirtualQuery
// enough here: no version check, no other library, and it describes a fibre's stack
// as readily as a thread's. GetCurrentThreadStackLimits would say the same, and only
// from Windows 8 on.
void* m3_HostStackBase (void)
{
    MEMORY_BASIC_INFORMATION mbi;

    // any address on the stack being asked about will do, and this one is on it
    volatile char            here = 0;

    if (VirtualQuery((LPCVOID)&here, &mbi, sizeof(mbi)) == 0) {
        return NULL;
    }

    return mbi.AllocationBase;
}

static IM3Runtime s_win32SuspendRuntime = NULL;

static
BOOL WINAPI m3_ConsoleCtrlHandler (DWORD dwCtrlType)
{
    if (dwCtrlType == CTRL_C_EVENT || dwCtrlType == CTRL_BREAK_EVENT) {
        if (s_win32SuspendRuntime && !s_win32SuspendRuntime->suspendRequested) {
            s_win32SuspendRuntime->suspendRequested = true;
            return TRUE;
        }
    }
    return FALSE;
}

void m3_HostInstallInterruptHandler (IM3Runtime io_runtime)
{
    s_win32SuspendRuntime = io_runtime;
    SetConsoleCtrlHandler(m3_ConsoleCtrlHandler, TRUE);
}

void m3_HostRemoveInterruptHandler (void)
{
    SetConsoleCtrlHandler(m3_ConsoleCtrlHandler, FALSE);
    s_win32SuspendRuntime = NULL;
}

// FILETIME counts 100ns intervals from 1601
u64 m3_HostTimeMs (void)
{
    static const u64 c_unixEpoch = 116444736000000000ULL;

    FILETIME         now;
    GetSystemTimeAsFileTime(&now);

    u64 ticks = ((u64)now.dwHighDateTime << 32) | now.dwLowDateTime;

    return (ticks > c_unixEpoch) ? (ticks - c_unixEpoch) / 10000 : 0;
}

// FILE_SHARE_READ and nothing else: another process may read the file, and one
// trying to write or delete it is refused for as long as the mapping lives. The
// kernel enforces that, so it is the real thing rather than the advisory lock POSIX
// has to make do with - see m3_host.h.
bool m3_HostMapFile (const char* i_path, size_t i_maxBytes, M3HostFile* o_file)
{
    HANDLE file = CreateFileA(i_path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                              FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) {
        return false;
    }

    LARGE_INTEGER size;

    // Anything with no size to map - a pipe, a console - is read instead, and so is
    // a file too large to address or larger than the caller wants
    if (not GetFileSizeEx(file, &size) or size.QuadPart <= 0 or
        (ULONGLONG) size.QuadPart > (ULONGLONG)SIZE_MAX or
        (i_maxBytes and (ULONGLONG) size.QuadPart > (ULONGLONG)i_maxBytes)) {
        CloseHandle(file);
        return m3_HostReadFile(i_path, i_maxBytes, o_file);
    }

    HANDLE mapping = CreateFileMappingA(file, NULL, PAGE_READONLY, 0, 0, NULL);
    CloseHandle(file);                   // the mapping holds the file open

    if (mapping == NULL) {
        return m3_HostReadFile(i_path, i_maxBytes, o_file);
    }

    void* base = MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
    CloseHandle(mapping);                // and the view holds the mapping

    if (base == NULL) {
        return m3_HostReadFile(i_path, i_maxBytes, o_file);
    }

    // Nothing left to keep: the view holds the mapping, which holds the file, and
    // the share mode with it
    o_file->data = base;
    o_file->size = (size_t)size.QuadPart;
    o_file->handle = d_m3HostNoHandle;
    o_file->mapped = true;
    return true;
}

void m3_HostUnmapFile (M3HostFile* io_file)
{
    if (io_file->mapped) {
        UnmapViewOfFile(io_file->data);  // the view knows how big it is
    } else {
        m3_Free(io_file->data);
    }

    io_file->data = NULL;
    io_file->size = 0;
    io_file->handle = d_m3HostNoHandle;
    io_file->mapped = false;
}

// rename refuses a target that exists; MoveFileEx replaces it, and within a
// volume does so by renaming, in one step
bool m3_HostReplaceFile (const char* i_from, const char* i_to)
{
    return MoveFileExA(i_from, i_to, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
}


#if d_m3GuardedMemory

size_t m3_HostPageSize (void)
{
    SYSTEM_INFO info;
    GetSystemInfo(&info);

    // dwAllocationGranularity, not dwPageSize: a reservation starts on the coarser
    // of the two, so that is the grain the whole scheme has to be cut in
    return info.dwAllocationGranularity ? info.dwAllocationGranularity : 65536;
}

void* m3_HostReserve (size_t i_bytes)
{
    return VirtualAlloc(NULL, i_bytes, MEM_RESERVE, PAGE_NOACCESS);
}

bool m3_HostCommit (void* i_address, size_t i_bytes)
{
    if (i_bytes == 0) {
        return true;
    }
    return VirtualAlloc(i_address, i_bytes, MEM_COMMIT, PAGE_READWRITE) != NULL;
}

bool m3_HostDecommit (void* i_address, size_t i_bytes)
{
    if (i_bytes == 0) {
        return true;
    }
    return VirtualFree(i_address, i_bytes, MEM_DECOMMIT) != 0;
}

void m3_HostRelease (void* i_address, size_t i_bytes)
{
    (void)i_bytes;                       // MEM_RELEASE frees the whole reservation
    VirtualFree(i_address, 0, MEM_RELEASE);
}

// Which faults are ours, for the handler below. Read from the exception record
// rather than from anything of ours, so nothing here depends on what the faulting
// code was in the middle of.
static
bool guard_fault (const EXCEPTION_POINTERS* i_info, const u8* i_low, size_t i_bytes)
{
    if (i_info == NULL or i_info->ExceptionRecord == NULL) {
        return false;
    }

    const EXCEPTION_RECORD* record = i_info->ExceptionRecord;

    if (record->ExceptionCode != EXCEPTION_ACCESS_VIOLATION or
        record->NumberParameters < 2) {
        return false;
    }

    // [0] says read or write, [1] is the address that could not be reached
    const u8* address = (const u8*)record->ExceptionInformation[1];

    return address >= i_low and address < i_low + i_bytes;
}

// One protected call on this thread: the region it guards, and the thread's context
// at the point m3_HostProtectedCall carries on from when the body faults - the Win32
// counterpart of the sigjmp_buf on POSIX. CONTEXT wants 16-byte alignment and
// declares it, which the struct inherits.
typedef struct M3GuardFrame {
    CONTEXT              resume;
    const u8*            low;
    size_t               bytes;
    struct M3GuardFrame* previous;
    volatile LONG        faulted;
} M3GuardFrame;

static M3_THREAD_LOCAL M3GuardFrame* g_guardFrame;

// 0 until the first ask, then 1 for a handler in place or 2 for none: settled once,
// as m3_host.h says, and by whichever thread asks first.
static volatile LONG                 g_guards;

// A vectored handler, first in line, rather than the __try/__except this used to be.
// Every vectored handler in the process runs before any frame's __except - and a
// process may well have one that was not ours: a test runner's or a crash reporter's,
// which takes a fault in our arena for a crash and ends the thread before the frame
// handler is ever asked. Registering first is what makes the fault ours to answer.
//
// The answer is to hand the thread back to m3_HostProtectedCall at the point it saved:
// the dispatcher restores the saved context on our behalf when this returns
// EXCEPTION_CONTINUE_EXECUTION with it in place of the faulting one. Nothing between
// is unwound, and nothing needs to be: what the body was doing is data on the heap,
// as the POSIX path's siglongjmp relies on too.
static
LONG CALLBACK guard_handler (EXCEPTION_POINTERS* i_info)
{
    M3GuardFrame* frame = g_guardFrame;

    if (frame and guard_fault(i_info, frame->low, frame->bytes)) {
        frame->faulted = 1;
        *i_info->ContextRecord = frame->resume;
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    return EXCEPTION_CONTINUE_SEARCH;
}

bool m3_HostGuardsActive (void)
{
    if (g_guards == 0) {
        PVOID handler = AddVectoredExceptionHandler(1 /* first */, guard_handler);
        LONG  state = handler ? 1 : 2;

        if (InterlockedCompareExchange(&g_guards, state, 0) != 0 and handler) {
            // another thread's handler went in first; one is enough
            RemoveVectoredExceptionHandler(handler);
        }
    }

    return g_guards == 1;
}

bool m3_HostProtectedCall (void (*i_body)(void*), void* i_context,
                           void* i_guardLow, size_t i_guardBytes)
{
    if (not m3_HostGuardsActive()) {
        return false;
    }

    M3GuardFrame frame;
    frame.low = (const u8*)i_guardLow;
    frame.bytes = i_guardBytes;
    frame.previous = g_guardFrame;
    frame.faulted = 0;

    g_guardFrame = &frame;

    // Returns once now, and once more from guard_handler if the body faults, with
    // faulted set; faulted is volatile so the second time is read from memory rather
    // than from a register the first time left behind.
    RtlCaptureContext(&frame.resume);

    if (frame.faulted) {
        g_guardFrame = frame.previous;
        return false;
    }

    i_body(i_context);

    g_guardFrame = frame.previous;
    return true;
}

#endif // d_m3GuardedMemory

#endif // m3_host_win32_h
