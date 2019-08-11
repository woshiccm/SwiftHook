//
//  SwiftHook.swift
//  SwiftHook
//
//  Created by roy.cao on 2019/8/11.
//  Copyright © 2019 roy. All rights reserved.
//

import Foundation

struct SwiftClassMetada {
    let metaClass: uintptr_t
    let superClass: uintptr_t
    let reserved1: uintptr_t
    let reserved2: uintptr_t
    let rodataPointer: uintptr_t
    let flags: UInt32
    let instanceAddressPoint: UInt32
    let instanceSize: UInt32
    let instanceAlignmentMask: UInt16
    let reserved: UInt16

    let classSize: UInt32
    let classAddressOffset: UInt32
    let descriptor: uintptr_t
    var ivarDestroyer: UnsafeMutableRawPointer? = nil
}

public class SwiftHook {

    public static func methodNames(ofClass: AnyClass) -> [String] {
        var names = [String]()
        iterateMethods(ofClass: ofClass) {
            (name, vtableSlot, stop) in
            names.append(name)
        }
        return names
    }

    @discardableResult
    public static func aspect(methodName: String, replacement: UnsafeMutableRawPointer) -> Bool {
        return forAllClasses {
            (aClass, stop) in
            stop = aspect(aClass: aClass, methodName: methodName, replacement: replacement)
        }
    }

    @discardableResult
    public static func aspect(aClass: AnyClass, methodName: String, replacement: UnsafeMutableRawPointer) -> Bool {
        return iterateMethods(ofClass: aClass) {
            (name, vtableSlot, stop) in
            if name == methodName {
                vtableSlot.pointee = replacement
                stop = true
            }
        }
    }
}

extension SwiftHook {

    @discardableResult
    class func iterateMethods(ofClass aClass: AnyClass,
                              callback: (_ name: String, _ vtableSlot: UnsafeMutablePointer<UnsafeMutableRawPointer>, _ stop: inout Bool) -> Void) -> Bool {
        let swiftMeta: UnsafeMutablePointer<SwiftClassMetada> = autoBitCast(aClass)
        let className = NSStringFromClass(aClass)
        var stop = false

        guard (className.hasPrefix("_Tt") || className.contains(".")) && !className.hasPrefix("Swift.") else {
            return false
        }

        withUnsafeMutablePointer(to: &swiftMeta.pointee.ivarDestroyer) {
            (vtableStart) in
            swiftMeta.withMemoryRebound(to: UnsafeMutableRawPointer.self, capacity: 1) {
                let endMeta = ($0 - Int(swiftMeta.pointee.classAddressOffset) + Int(swiftMeta.pointee.classSize))
                endMeta.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) {
                    (vtableEnd) in

                    var info = Dl_info()
                    for i in 0..<(vtableEnd - vtableStart) {
                        if let impl: IMP = autoBitCast(vtableStart[i]) {
                            let voidPtr: UnsafeMutableRawPointer = autoBitCast(impl)
                            if fast_dladdr(voidPtr, &info) != 0 && info.dli_sname != nil,
                                let demangled = demangle(symbol: info.dli_sname) {
                                callback(demangled, &vtableStart[i]!, &stop)
                                if stop {
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        return stop
    }

    @discardableResult
    class func forAllClasses(callback: (_ aClass: AnyClass, _ stop: inout Bool) -> Void ) -> Bool {
        var stopped = false
        var nc: UInt32 = 0

        if let classes = objc_copyClassList(&nc) {
            for aClass in (0..<Int(nc)).map({ classes[$0] }) {
                callback(aClass, &stopped)
                if stopped {
                    break
                }
            }
            free(UnsafeMutableRawPointer(classes))
        }

        return stopped
    }

    @objc class func demangle(symbol: UnsafePointer<Int8>) -> String? {
        if let demangledNamePtr = _stdlib_demangleImpl(
            symbol, mangledNameLength: UInt(strlen(symbol)),
            outputBuffer: nil, outputBufferSize: nil, flags: 0) {
            let demangledName = String(cString: demangledNamePtr)
            free(demangledNamePtr)
            return demangledName
        }
        return nil
    }
}

private func autoBitCast<IN,OUT>(_ arg: IN) -> OUT {
    return unsafeBitCast(arg, to: OUT.self)
}

@_silgen_name("swift_demangle")
private
func _stdlib_demangleImpl(
    _ mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<UInt8>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
    ) -> UnsafeMutablePointer<CChar>?
