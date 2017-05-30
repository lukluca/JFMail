//
// Created by Tagliabue, L. on 26/05/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import Foundation

func CFWriteStreamWriteFully(outputStream: CFWriteStream, utf8String: String.UTF8View, length: CFIndex) -> CFIndex {

    var buffer: [UInt8] = Array(utf8String)
    var bufferOffset: CFIndex = 0
    var bytesWritten: CFIndex;

    while (bufferOffset < length)
    {
        if (CFWriteStreamCanAcceptBytes(outputStream))
        {
            bytesWritten = CFWriteStreamWrite(outputStream, &buffer[bufferOffset], length - bufferOffset);
            if (bytesWritten < 0)
            {
                // Bail!
                return bytesWritten;
            }
            bufferOffset += bytesWritten;
        }
        else if (CFWriteStreamGetStatus(outputStream) == .error)
        {
            return -1;
        }
        else
        {
            // Pump the runloop
            CFRunLoopRunInMode(.defaultMode, 0.0, true);
        }
    }

    return bufferOffset;

}