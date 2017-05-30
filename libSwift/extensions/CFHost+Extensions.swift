//
// Created by Tagliabue, L. on 29/05/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import Foundation

extension CFHost {

    static func Start(theHost: CFHost, CFHostInfoType info: CFHostInfoType , error: inout CFStreamError?) -> Bool {
        var err = ((error == nil) ? CFStreamError.init() : error!)
        let uns = UnsafeMutablePointer<CFStreamError>(&err)
        return CFHostStartInfoResolution(theHost, info, uns)
    }

    static func GetAddressing(theHost: CFHost, hasBeenResolved: inout Bool?){
        var darwin = DarwinBoolean((hasBeenResolved == nil) ? false : hasBeenResolved!)
        let pointer = UnsafeMutablePointer<DarwinBoolean>(&darwin)
        CFHostGetAddressing(theHost, pointer)
    }

}
