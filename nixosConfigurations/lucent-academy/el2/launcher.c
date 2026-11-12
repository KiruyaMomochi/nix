/* SPDX-License-Identifier: MIT
 * Entry-scoped EL2 preparation. No menu, config files or load options.
 * Use firmware LoadImage with complete on-disk paths, never buffer loading.
 */
#include <efi.h>
#include "launcher-config.h"

_Static_assert(sizeof(UINTN) == 8 && sizeof(CHAR16) == 2, "UEFI ABI width mismatch");
/* gnu-efi's HARDDRIVE_DEVICE_PATH is a native, unpacked structure (48 bytes).
 * The wire node is 42 bytes. Parse bytes rather than casting/sizeof that type. */
#define HD_NODE_SIZE 42
_Static_assert(SIZE_OF_FILEPATH_DEVICE_PATH == 4, "UEFI filepath layout mismatch");

static EFI_SYSTEM_TABLE *st;
static EFI_BOOT_SERVICES *bs;
static EFI_HANDLE parent;
static EFI_GUID loaded_guid = EFI_LOADED_IMAGE_PROTOCOL_GUID;
static EFI_GUID dp_guid = EFI_DEVICE_PATH_PROTOCOL_GUID;
static EFI_GUID fs_guid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;
static EFI_GUID global_guid = EFI_GLOBAL_VARIABLE;
static const EFI_GUID boot_partuuid = BOOT_PARTUUID;
/* Keep an absolute data reference so PE carries a relocation directory even
 * when LLVM otherwise emits only PC-relative AArch64 instructions. */
static CHAR16 * volatile banner = L"Entry-scoped EL2 launcher\r\n";

static void copy_bytes(void *to, const void *from, UINTN n) {
    UINT8 *d = to;
    const UINT8 *s = from;
    while (n--) *d++ = *s++;
}

static BOOLEAN same_bytes(const void *a, const void *b, UINTN n) {
    const UINT8 *x = a, *y = b;
    while (n--) if (*x++ != *y++) return FALSE;
    return TRUE;
}

static void say(CHAR16 *text) {
    if (st->ConOut) st->ConOut->OutputString(st->ConOut, text);
}

static void hex_status(EFI_STATUS status) {
    CHAR16 buf[19] = L"0x0000000000000000";
    CHAR16 *digits = L"0123456789abcdef";
    for (UINTN i = 0; i < 16; i++) {
        buf[17 - i] = digits[status & 15];
        status >>= 4;
    }
    say(buf);
}

static EFI_NORETURN void stop(CHAR16 *where, EFI_STATUS status) {
    /* A returning child might have armed the firmware watchdog again. */
    bs->SetWatchdogTimer(0, 0, 0, NULL);
    say(L"\r\nEL2 launcher STOP: "); say(where); say(L" (");
    hex_status(status); say(L")\r\nReset the machine before choosing another entry.\r\n");
#ifdef LAUNCHER_TEST
    launcher_test_stop(where, status);
#else
    /* Do not return/Exit/Unload: driver hooks may already be installed.
     * Keep firmware timers running, but disable its boot watchdog.
     */
    for (;;) bs->Stall(1000000);
#endif
}

static void require_ok(EFI_STATUS status, CHAR16 *where) {
    /* Warnings are not accepted as a successful preparation either. */
    if (status != EFI_SUCCESS) stop(where, status);
}

static void require_secure_boot(void) {
    UINT8 secure = 0, setup = 1;
    UINTN n = sizeof secure;
    require_ok(st->RuntimeServices->GetVariable(L"SecureBoot", &global_guid,
                                               NULL, &n, &secure), L"read SecureBoot");
    if (n != 1 || secure != 1) stop(L"Secure Boot is not active", EFI_SECURITY_VIOLATION);
    n = sizeof setup;
    require_ok(st->RuntimeServices->GetVariable(L"SetupMode", &global_guid,
                                               NULL, &n, &setup), L"read SetupMode");
    if (n != 1 || setup != 0) stop(L"firmware is in Setup Mode", EFI_SECURITY_VIOLATION);
}

/* Bound traversal even if a protocol exposes a malformed device path. */
static EFI_STATUS path_size(EFI_DEVICE_PATH *dp, UINTN *size) {
    UINTN offset = 0;
    while (offset < 65536) {
        EFI_DEVICE_PATH *node = (EFI_DEVICE_PATH *)((UINT8 *)dp + offset);
        UINTN len = DevicePathNodeLength(node);
        if (len < sizeof *node || len > 65536 - offset) return EFI_COMPROMISED_DATA;
        if (IsDevicePathEndType(node)) {
            if (!IsDevicePathEnd(node) || len != sizeof *node) return EFI_UNSUPPORTED;
            *size = offset + len;
            return EFI_SUCCESS;
        }
        offset += len;
    }
    return EFI_COMPROMISED_DATA;
}

static BOOLEAN has_partuuid(EFI_DEVICE_PATH *dp) {
    UINTN total;
    if (path_size(dp, &total) != EFI_SUCCESS) return FALSE;
    EFI_DEVICE_PATH *last_hd = NULL;
    for (UINTN offset = 0; offset < total - sizeof *dp;) {
        EFI_DEVICE_PATH *node = (EFI_DEVICE_PATH *)((UINT8 *)dp + offset);
        UINTN len = DevicePathNodeLength(node);
        if (DevicePathType(node) == MEDIA_DEVICE_PATH &&
            node->SubType == MEDIA_HARDDRIVE_DP) {
            if (len != HD_NODE_SIZE) return FALSE;
            last_hd = node;
        }
        offset += len;
    }
    if (!last_hd) return FALSE;
    const UINT8 *hd = (const UINT8 *)last_hd;
    return hd[40] == MBR_TYPE_EFI_PARTITION_TABLE_HEADER &&
           hd[41] == SIGNATURE_TYPE_GUID &&
           same_bytes(hd + 24, &boot_partuuid, sizeof boot_partuuid);
}

static EFI_HANDLE find_boot(void) {
    EFI_HANDLE *handles = NULL, found = NULL;
    UINTN count = 0;
    require_ok(bs->LocateHandleBuffer(ByProtocol, &fs_guid, NULL, &count, &handles),
               L"enumerate filesystems");
    for (UINTN i = 0; i < count; i++) {
        EFI_DEVICE_PATH *dp = NULL;
        EFI_STATUS status = bs->HandleProtocol(handles[i], &dp_guid, (void **)&dp);
        if (status != EFI_SUCCESS || !dp || !has_partuuid(dp)) continue;
        if (found) stop(L"duplicate XBOOTLDR PARTUUID", EFI_SECURITY_VIOLATION);
        found = handles[i];
    }
    require_ok(bs->FreePool(handles), L"free filesystem handles");
    if (!found) stop(L"XBOOTLDR PARTUUID not found", EFI_NOT_FOUND);
    return found;
}

static EFI_DEVICE_PATH *file_path(EFI_HANDLE volume, CHAR16 *path) {
    EFI_DEVICE_PATH *base = NULL, *result;
    UINTN base_size, chars = 0;
    require_ok(bs->HandleProtocol(volume, &dp_guid, (void **)&base), L"get volume device path");
    if (!base) stop(L"null volume device path", EFI_NOT_FOUND);
    require_ok(path_size(base, &base_size), L"validate volume device path");
    while (path[chars]) chars++;
    UINTN file_size = SIZE_OF_FILEPATH_DEVICE_PATH + (chars + 1) * sizeof(CHAR16);
    if (file_size > 65535) stop(L"file path too long", EFI_BAD_BUFFER_SIZE);
    UINTN prefix = base_size - sizeof(EFI_DEVICE_PATH);
    require_ok(bs->AllocatePool(EfiBootServicesData, prefix + file_size + sizeof(EFI_DEVICE_PATH),
                                (void **)&result), L"allocate file device path");
    copy_bytes(result, base, prefix);
    FILEPATH_DEVICE_PATH *file = (FILEPATH_DEVICE_PATH *)((UINT8 *)result + prefix);
    file->Header.Type = MEDIA_DEVICE_PATH;
    file->Header.SubType = MEDIA_FILEPATH_DP;
    SetDevicePathNodeLength(&file->Header, file_size);
    copy_bytes(file->PathName, path, (chars + 1) * sizeof(CHAR16));
    EFI_DEVICE_PATH *end = (EFI_DEVICE_PATH *)((UINT8 *)file + file_size);
    SetDevicePathEndNode(end);
    return result;
}

static EFI_HANDLE load(EFI_HANDLE volume, CHAR16 *path, BOOLEAN driver) {
    EFI_DEVICE_PATH *dp = file_path(volume, path);
    EFI_HANDLE image = NULL;
    say(L"Load "); say(path); say(L"\r\n");
    EFI_STATUS status = bs->LoadImage(FALSE, parent, dp, NULL, 0, &image);
    /* Keep the device path alive: driver LoadedImage/FilePath and hooks may use it. */
    require_ok(status, L"LoadImage (signature, path or image failure)");
    if (!image) stop(L"LoadImage returned no handle", EFI_LOAD_ERROR);
    EFI_LOADED_IMAGE *info = NULL;
    require_ok(bs->HandleProtocol(image, &loaded_guid, (void **)&info), L"get child LoadedImage");
    if (!info || info->DeviceHandle != volume || !info->FilePath)
        stop(L"child has no matching filesystem identity", EFI_SECURITY_VIOLATION);
    if (driver ? (info->ImageCodeType != EfiBootServicesCode && info->ImageCodeType != EfiRuntimeServicesCode)
               : info->ImageCodeType != EfiLoaderCode)
        stop(L"unexpected image subsystem", EFI_UNSUPPORTED);
    /* No caller-controlled command line reaches the UKI or either driver. */
    info->LoadOptions = NULL;
    info->LoadOptionsSize = 0;
    return image;
}

static void start_driver(EFI_HANDLE image, CHAR16 *name) {
    say(L"Start "); say(name); say(L"\r\n");
    require_ok(bs->StartImage(image, NULL, NULL), name);
    /* Successful drivers remain loaded; never UnloadImage them. */
}

EFI_STATUS EFIAPI efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *table) {
    parent = image; st = table; bs = st->BootServices;
    if (st->ConOut) st->ConOut->EnableCursor(st->ConOut, TRUE);
    say(banner);
    require_ok(bs->SetWatchdogTimer(0, 0, 0, NULL), L"disable boot watchdog");
    require_secure_boot();
    EFI_LOADED_IMAGE *self = NULL;
    require_ok(bs->HandleProtocol(parent, &loaded_guid, (void **)&self), L"get launcher LoadedImage");
    if (!self || !self->DeviceHandle) stop(L"launcher has no ESP device handle", EFI_NOT_FOUND);
    void *fs = NULL;
    require_ok(bs->HandleProtocol(self->DeviceHandle, &fs_guid, &fs), L"launcher is not on a filesystem");
    EFI_HANDLE boot = find_boot();
    if (boot == self->DeviceHandle) stop(L"XBOOTLDR must differ from ESP", EFI_SECURITY_VIOLATION);
    /* Preserve the usual driver-before-OS allocation and hook order. */
    EFI_HANDLE qebspil = load(self->DeviceHandle, QEBSPIL_PATH, TRUE);
    start_driver(qebspil, L"qebspil");
    EFI_HANDLE slbounce = load(self->DeviceHandle, SLBOUNCE_PATH, TRUE);
    start_driver(slbounce, L"slbounce");
    EFI_HANDLE uki = load(boot, UKI_PATH, FALSE);
    say(L"Start signed EL2 UKI\r\n");
    EFI_STATUS status = bs->StartImage(uki, NULL, NULL);
    /* Even EFI_SUCCESS means the OS returned; it is never a menu fallback. */
    stop(L"UKI returned", status);
}
