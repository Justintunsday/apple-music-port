#pragma once
#include <mach-o/loader.h>
#include <mach/machine.h>
#include <mach/vm_prot.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <math.h>

// Observed in the 20B101 arm64e MusicApplication image, not a guessed ivar offset.
#define ML_WIDTH_VADDR UINT64_C(0xf6eaa8)
static const uint8_t ML_IMAGE_UUID[16] = {0xac,0x7a,0xfb,0xa5,0xdd,0x53,0x3c,0xb8,0xa1,0x46,0x5d,0x97,0x5b,0xb3,0xad,0x1b};

static inline bool MLValidateImage(const struct mach_header_64 *header, size_t available) {
    if (!header || available < sizeof(*header) || header->magic != MH_MAGIC_64 ||
        header->cputype != CPU_TYPE_ARM64 || (header->cpusubtype & ~CPU_SUBTYPE_MASK) != CPU_SUBTYPE_ARM64E ||
        header->sizeofcmds > available - sizeof(*header) || header->ncmds > 512) return false;
    bool uuid = false, writable = false;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if ((size_t)(end - cursor) < sizeof(struct load_command)) return false;
        const struct load_command *command = (const void *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end - cursor)) return false;
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            uuid = memcmp(((const struct uuid_command *)command)->uuid, ML_IMAGE_UUID, 16) == 0;
        }
        if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *segment = (const void *)command;
            if (strncmp(segment->segname, "__DATA", 16) == 0 && (segment->initprot & VM_PROT_WRITE) &&
                segment->vmaddr <= ML_WIDTH_VADDR && segment->vmsize >= sizeof(double) &&
                ML_WIDTH_VADDR - segment->vmaddr <= segment->vmsize - sizeof(double)) writable = true;
        }
        cursor += command->cmdsize;
    }
    return uuid && writable;
}
static inline double MLDesiredWidth(double width, double height) {
    return isfinite(width) && isfinite(height) && width > height && width >= 480 && height >= 240 ? fmin(640, width) : 1024;
}
