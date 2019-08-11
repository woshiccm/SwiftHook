//
//  SwiftHook.m
//  SwiftHook
//
//  Created by roy.cao on 2019/8/11.
//  Copyright © 2019 roy. All rights reserved.
//
//
// https://github.com/johnno1962/SwiftTrace/blob/master/SwiftTrace/SwiftTrace.mm

#import "SwiftHook.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/arch.h>
#import <mach-o/getsect.h>
#import <mach-o/nlist.h>

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct nlist_64 nlist_t;
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct nlist nlist_t;
#endif

void findPureSwiftClasses(const char *path, void (^callback)(void *aClass)) {
    for (int32_t i = _dyld_image_count(); i >= 0 ; i--) {
        const mach_header_t *header = (const mach_header_t *)_dyld_get_image_header(i);
        const char *imageName = _dyld_get_image_name(i);
        if (imageName && (imageName == path || strcmp(imageName, path) == 0)) {
            segment_command_t *seg_linkedit = NULL;
            segment_command_t *seg_text = NULL;
            struct symtab_command *symtab = NULL;

            struct load_command *cmd = (struct load_command *)((intptr_t)header + sizeof(mach_header_t));
            for (uint32_t i = 0; i < header->ncmds; i++, cmd = (struct load_command *)((intptr_t)cmd + cmd->cmdsize))
            {
                switch(cmd->cmd)
                {
                    case LC_SEGMENT:
                    case LC_SEGMENT_64:
                        if (!strcmp(((segment_command_t *)cmd)->segname, SEG_TEXT))
                            seg_text = (segment_command_t *)cmd;
                        else if (!strcmp(((segment_command_t *)cmd)->segname, SEG_LINKEDIT))
                            seg_linkedit = (segment_command_t *)cmd;
                        break;

                    case LC_SYMTAB: {
                        symtab = (struct symtab_command *)cmd;
                        intptr_t file_slide = ((intptr_t)seg_linkedit->vmaddr - (intptr_t)seg_text->vmaddr) - seg_linkedit->fileoff;
                        const char *strings = (const char *)header + (symtab->stroff + file_slide);
                        nlist_t *sym = (nlist_t *)((intptr_t)header + (symtab->symoff + file_slide));

                        for (uint32_t i = 0; i < symtab->nsyms; i++, sym++) {
                            const char *sptr = strings + sym->n_un.n_strx;
                            void *aClass;
                            if (sym->n_type == 0xf &&
                                strncmp(sptr, "_$s", 3) == 0 &&
                                strcmp(sptr+strlen(sptr)-2, "CN") == 0 &&
                                (aClass = (void *)(sym->n_value + (intptr_t)header - (intptr_t)seg_text->vmaddr))) {
                                callback(aClass);
                            }
                        }

                        return;
                    }
                }
            }
        }
    }
}

#import <vector>
#import <algorithm>

using namespace std;

class Symbol {
public:
    nlist_t *sym;
    Symbol(nlist_t *sym) {
        this->sym = sym;
    }
};

static bool operator < (Symbol s1, Symbol s2) {
    return s1.sym->n_value < s2.sym->n_value;
}

class Dylib {
    const mach_header_t *header;
    segment_command_t *seg_linkedit = NULL;
    segment_command_t *seg_text = NULL;
    struct symtab_command *symtab = NULL;
    vector<Symbol> symbols;

public:
    char *start = nullptr, *stop = nullptr;
    const char *imageName;

    Dylib(int imageIndex) {
        imageName = _dyld_get_image_name(imageIndex);
        header = (const mach_header_t *)_dyld_get_image_header(imageIndex);
        struct load_command *cmd = (struct load_command *)((intptr_t)header + sizeof(mach_header_t));
        assert(header);

        for (uint32_t i = 0; i < header->ncmds; i++, cmd = (struct load_command *)((intptr_t)cmd + cmd->cmdsize))
        {
            switch(cmd->cmd)
            {
                case LC_SEGMENT:
                case LC_SEGMENT_64:
                    if (!strcmp(((segment_command_t *)cmd)->segname, SEG_TEXT))
                        seg_text = (segment_command_t *)cmd;
                    else if (!strcmp(((segment_command_t *)cmd)->segname, SEG_LINKEDIT))
                        seg_linkedit = (segment_command_t *)cmd;
                    break;

                case LC_SYMTAB:
                    symtab = (struct symtab_command *)cmd;
            }
        }

        const struct section_64 *section = getsectbynamefromheader_64( (const struct mach_header_64 *)header, SEG_TEXT, SECT_TEXT );
        if (section == 0) return;
        start = (char *)(section->addr + _dyld_get_image_vmaddr_slide( (uint32_t)imageIndex ));
        stop = start + section->size;
    }

    bool contains(const void *p) {
        return p >= start && p <= stop;
    }

    int dladdr(const void *ptr, Dl_info *info) {
        intptr_t file_slide = ((intptr_t)seg_linkedit->vmaddr - (intptr_t)seg_text->vmaddr) - seg_linkedit->fileoff;
        const char *strings = (const char *)header + (symtab->stroff + file_slide);

        if (symbols.empty()) {
            nlist_t *sym = (nlist_t *)((intptr_t)header + (symtab->symoff + file_slide));

            for (uint32_t i = 0; i < symtab->nsyms; i++, sym++)
                if (sym->n_type == 0xf)
                    symbols.push_back(Symbol(sym));

            sort(symbols.begin(), symbols.end());
        }

        nlist_t nlist;
        nlist.n_value = (intptr_t)ptr - ((intptr_t)header - (intptr_t)seg_text->vmaddr);

        auto it = lower_bound(symbols.begin(), symbols.end(), Symbol(&nlist));
        if (it != symbols.end()) {
            info->dli_fname = imageName;
            info->dli_sname = strings + it->sym->n_un.n_strx + 1;
            return 1;
        }

        return 0;
    }
};

class DylibPtr {
public:
    Dylib *dylib;
    const char *start;
    DylibPtr(Dylib *dylib) {
        if ((this->dylib = dylib))
            this->start = dylib->start;
    }
};

bool operator < (DylibPtr s1, DylibPtr s2) {
    return s1.start < s2.start;
}

int fast_dladdr(const void *ptr, Dl_info *info) {
#if !TRY_TO_OPTIMISE_DLADDR
    return dladdr(ptr, info);
#else
    static vector<DylibPtr> dylibs;

    if (dylibs.empty()) {
        for (int32_t i = 0; i < _dyld_image_count(); i++)
            dylibs.push_back(DylibPtr(new Dylib(i)));

        sort(dylibs.begin(), dylibs.end());
    }

    if (ptr < dylibs[0].dylib->start)
        return 0;

    DylibPtr dylibPtr(NULL);
    dylibPtr.start = (const char *)ptr;
    auto it = lower_bound(dylibs.begin(), dylibs.end(), dylibPtr);
    if (it != dylibs.end()) {
        Dylib *dylib = dylibs[distance(dylibs.begin(), it)-1].dylib;
        if (!dylib || !dylib->contains(ptr))
            return 0;
        return dylib->dladdr(ptr, info);
    }

    return 0;
#endif
}
