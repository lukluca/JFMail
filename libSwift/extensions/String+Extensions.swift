//
//  String+Extensions.swift
//  JFMail
//
//  Created by Tagliabue, L. on 29/05/2017.
//  Copyright © 2017 jeffsss. All rights reserved.
//

import Foundation

extension String {

    init?(bytes: UnsafeMutableRawPointer, length: Int, encoding: String.Encoding){
        self.init(bytesNoCopy: bytes, length: length, encoding: encoding, freeWhenDone: true)
    }

    func nsRange(of: String) -> NSRange{
        let nsString = NSString(string: self)
        return nsString.range(of: of)
    }

}
