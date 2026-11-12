/* Host-side firmware mocks: no payload is executed. */
#include <assert.h>
#include <setjmp.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <efi.h>
static jmp_buf stopped;
static EFI_STATUS stopped_status;
static void __attribute__((noreturn)) launcher_test_stop(CHAR16 *where, EFI_STATUS status) {
    (void)where; stopped_status = status;
    if (getenv("LAUNCHER_TEST_VERBOSE")) {
        for (UINTN i = 0; where[i]; i++) fputc((char)where[i], stderr);
        fprintf(stderr, " status=%llx\n", (unsigned long long)status);
    }
    longjmp(stopped, 1);
}
#define LAUNCHER_TEST
#include "launcher.c"

#define HANDLE(n) ((EFI_HANDLE)(unsigned long)(n))
static struct { UINT8 hd[HD_NODE_SIZE]; EFI_DEVICE_PATH end; } disk;
static EFI_DEVICE_PATH esp_dp;
static EFI_LOADED_IMAGE infos[5];
static int loads, starts, fail_load, fail_start, duplicate, missing, insecure, wrong_volume;
static EFI_STATUS EFIAPI mock_variable(CHAR16 *name, EFI_GUID *guid, UINT32 *attrs, UINTN *n, void *data) {
    (void)guid; (void)attrs; assert(*n == 1);
    *(UINT8 *)data = name[2] == 'c' ? !insecure : 0;
    return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI mock_watchdog(UINTN timeout, UINT64 code, UINTN n, CHAR16 *data) {
    (void)code; (void)n; (void)data; assert(timeout == 0); return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI mock_protocol(EFI_HANDLE handle, EFI_GUID *guid, void **out) {
    if (same_bytes(guid, &loaded_guid, sizeof *guid)) {
        unsigned long i = (unsigned long)handle;
        assert(i >= 1 && i <= 4); *out = &infos[i];
    } else if (same_bytes(guid, &dp_guid, sizeof *guid)) {
        *out = handle == HANDLE(10) ? (void *)&esp_dp : (void *)&disk;
    } else { assert(same_bytes(guid, &fs_guid, sizeof *guid)); *out = HANDLE(99); }
    return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI mock_locate(EFI_LOCATE_SEARCH_TYPE type, EFI_GUID *guid, void *key, UINTN *n, EFI_HANDLE **out) {
    (void)type; (void)guid; (void)key;
    *n = duplicate ? 3 : 2; *out = malloc(*n * sizeof **out);
    (*out)[0] = HANDLE(10); (*out)[1] = HANDLE(20);
    if (duplicate) (*out)[2] = HANDLE(21);
    if (missing) memset(disk.hd + 24, 0, 16);
    return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI mock_alloc(EFI_MEMORY_TYPE type, UINTN n, void **out) {
    (void)type; *out = malloc(n); assert(*out); return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI mock_free(void *p) { free(p); return EFI_SUCCESS; }
static EFI_STATUS EFIAPI mock_load(BOOLEAN policy, EFI_HANDLE p, EFI_DEVICE_PATH *path, void *buf, UINTN n, EFI_HANDLE *out) {
    assert(!policy && p == HANDLE(1) && !buf && !n);
    ++loads; if (loads == fail_load) return EFI_SECURITY_VIOLATION;
    assert(starts == loads - 1); /* Drivers initialize before the next load. */
    EFI_DEVICE_PATH *node = path;
    while (DevicePathType(node) != MEDIA_DEVICE_PATH || node->SubType != MEDIA_FILEPATH_DP)
        node = NextDevicePathNode(node);
    CHAR16 *expected = loads == 1 ? QEBSPIL_PATH : loads == 2 ? SLBOUNCE_PATH : UKI_PATH;
    UINTN chars = 0; while (expected[chars]) chars++;
    assert(same_bytes(((FILEPATH_DEVICE_PATH *)node)->PathName, expected, (chars + 1) * 2));
    *out = HANDLE(loads + 1);
    EFI_LOADED_IMAGE *info = &infos[loads + 1];
    info->DeviceHandle = wrong_volume ? HANDLE(99) : loads == 3 ? HANDLE(20) : HANDLE(10);
    info->FilePath = node;
    info->ImageCodeType = loads == 3 ? EfiLoaderCode : EfiBootServicesCode;
    info->LoadOptions = HANDLE(99); info->LoadOptionsSize = 123;
    return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI mock_start(EFI_HANDLE handle, UINTN *n, CHAR16 **data) {
    assert(!n && !data); ++starts; assert(loads == starts);
    assert(handle == HANDLE(starts + 1));
    assert(!infos[starts + 1].LoadOptions && !infos[starts + 1].LoadOptionsSize);
    return starts == fail_start ? EFI_DEVICE_ERROR : EFI_SUCCESS;
}
static EFI_BOOT_SERVICES services = {
    .SetWatchdogTimer = mock_watchdog, .HandleProtocol = mock_protocol,
    .LocateHandleBuffer = mock_locate, .AllocatePool = mock_alloc,
    .FreePool = mock_free, .LoadImage = mock_load, .StartImage = mock_start,
};
static EFI_RUNTIME_SERVICES runtime = { .GetVariable = mock_variable };
static EFI_SYSTEM_TABLE table = { .BootServices = &services, .RuntimeServices = &runtime };
static void run(int expected_loads, int expected_starts, EFI_STATUS status) {
    loads = starts = 0; memset(infos, 0, sizeof infos);
    infos[1].DeviceHandle = HANDLE(10);
    memset(&disk, 0, sizeof disk);
    disk.hd[0] = MEDIA_DEVICE_PATH; disk.hd[1] = MEDIA_HARDDRIVE_DP;
    disk.hd[2] = HD_NODE_SIZE;
    disk.hd[40] = MBR_TYPE_EFI_PARTITION_TABLE_HEADER;
    disk.hd[41] = SIGNATURE_TYPE_GUID;
    copy_bytes(disk.hd + 24, &boot_partuuid, sizeof boot_partuuid);
    SetDevicePathEndNode(&disk.end); SetDevicePathEndNode(&esp_dp);
    if (!setjmp(stopped)) { efi_main(HANDLE(1), &table); assert(0 && "must not return"); }
    assert(loads == expected_loads && starts == expected_starts && stopped_status == status);
}
int main(void) {
    run(3, 3, EFI_SUCCESS); /* UKI return, even success, must stop. */
    for (fail_load = 1; fail_load <= 3; fail_load++) run(fail_load, fail_load - 1, EFI_SECURITY_VIOLATION);
    fail_load = 0;
    for (fail_start = 1; fail_start <= 3; fail_start++) run(fail_start, fail_start, EFI_DEVICE_ERROR);
    fail_start = 0;
    duplicate = 1; run(0, 0, EFI_SECURITY_VIOLATION); duplicate = 0;
    missing = 1; run(0, 0, EFI_NOT_FOUND); missing = 0;
    insecure = 1; run(0, 0, EFI_SECURITY_VIOLATION); insecure = 0;
    wrong_volume = 1; run(1, 0, EFI_SECURITY_VIOLATION); wrong_volume = 0;
    EFI_DEVICE_PATH malformed = { .Type = MEDIA_DEVICE_PATH, .SubType = MEDIA_HARDDRIVE_DP };
    UINTN size;
    assert(path_size(&malformed, &size) == EFI_COMPROMISED_DATA);
    puts("Firmware mock tests passed (12 paths, routing, options, halt-on-return)");
    return 0;
}
