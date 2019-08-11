//
//  SwiftHookTests.swift
//  SwiftHookTests
//
//  Created by roy.cao on 2019/8/11.
//  Copyright © 2019 roy. All rights reserved.
//

import XCTest
@testable import SwiftHook

public class TestClass {

    public func print(str: String) {

    }
}

typealias NewMethod = @convention(thin) (String) -> Void

func newPrinf(str: String) -> Void {
    string = str
}

var string = ""

class SwiftHookTests: XCTestCase {

    func testHooK() {

        print(SwiftHook.methodNames(ofClass: TestClass.self))

        SwiftHook.aspect(methodName: "SwiftHookTests.TestClass.print(str: Swift.String) -> ()", replacement: unsafeBitCast(newPrinf as NewMethod, to: UnsafeMutableRawPointer.self))

        let object = TestClass()
        object.print(str: "test")

        XCTAssertEqual(string, "test")
    }
}
