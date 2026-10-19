#include "../tweak/NativePolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    struct {
        struct mach_header_64 header;
        struct uuid_command uuid;
        struct segment_command_64 data;
    } image = {0};
    image.header.magic = MH_MAGIC_64;
    image.header.cputype = CPU_TYPE_ARM64;
    image.header.cpusubtype = CPU_SUBTYPE_ARM64E;
    image.header.ncmds = 2;
    image.header.sizeofcmds = sizeof(image.uuid) + sizeof(image.data);
    image.uuid.cmd = LC_UUID;
    image.uuid.cmdsize = sizeof(image.uuid);
    memcpy(image.uuid.uuid, ML_IMAGE_UUID, 16);
    image.data.cmd = LC_SEGMENT_64;
    image.data.cmdsize = sizeof(image.data);
    memcpy(image.data.segname, "__DATA", 7);
    image.data.vmaddr = 0xe3c000;
    image.data.vmsize = 0x138000;
    image.data.initprot = VM_PROT_READ | VM_PROT_WRITE;
    assert(MLValidateImage(&image.header, sizeof(image)));
    image.uuid.uuid[0] ^= 1;
    assert(!MLValidateImage(&image.header, sizeof(image)));
    image.uuid.uuid[0] ^= 1;
    image.data.initprot = VM_PROT_READ;
    assert(!MLValidateImage(&image.header, sizeof(image)));
    image.data.initprot |= VM_PROT_WRITE;
    image.data.vmsize = 8;
    assert(!MLValidateImage(&image.header, sizeof(image)));
    image.data.vmsize = 0x138000;
    image.header.cpusubtype = CPU_SUBTYPE_ARM64_ALL;
    assert(!MLValidateImage(&image.header, sizeof(image)));
    image.header.cpusubtype = CPU_SUBTYPE_ARM64E;
    image.uuid.cmdsize = 0;
    assert(!MLValidateImage(&image.header, sizeof(image)));
    assert(MLDesiredWidth(667, 375) == 640); // SE 2 landscape enters the extended branch.
    assert(MLDesiredWidth(375, 667) == 1024); // Portrait restores Apple's original threshold.
    assert(MLDesiredWidth(0, 0) == 1024);
    assert(MLDesiredWidth(NAN, 375) == 1024);
    puts("PASS: UUID, architecture, writable segment, bounds, malformed commands, SE2 and portrait policies");
}
