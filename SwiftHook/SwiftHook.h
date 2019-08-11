//
//  SwiftHook.h
//  SwiftHook
//
//  Created by roy.cao on 2019/8/11.
//  Copyright © 2019 roy. All rights reserved.
//

#import <UIKit/UIKit.h>

//! Project version number for SwiftHook.
FOUNDATION_EXPORT double SwiftHookVersionNumber;

//! Project version string for SwiftHook.
FOUNDATION_EXPORT const unsigned char SwiftHookVersionString[];

#import <dlfcn.h>

#ifdef __cplusplus
extern "C" {
#endif
    int fast_dladdr(const void * _Nonnull, Dl_info * _Nonnull);
#ifdef __cplusplus
}
#endif
