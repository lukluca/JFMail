//
// Created by Tagliabue, L. on 29/05/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import Foundation

class CFStream {
}

extension CFStream {

    static func CreatePair(theHost: CFHost, port: Int, readStream: inout CFReadStream?, writeStream: inout CFWriteStream?){

        var unReadStream: Unmanaged<CFReadStream>?
        if let read = readStream {
            unReadStream = Unmanaged.passRetained(read)
        }

        var unWriteStream: Unmanaged<CFWriteStream>?
        if let write = writeStream {
            unWriteStream = Unmanaged.passRetained(write)
        }

        CFStreamCreatePairWithSocketToCFHost(nil, theHost, Int32(port), &unReadStream, &unWriteStream)

    }

}