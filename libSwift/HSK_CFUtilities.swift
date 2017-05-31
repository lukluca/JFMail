//
// Created by Tagliabue, L. on 26/05/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import Foundation

func CFWriteStreamWriteFullyUtf8Encoding(outputStream: CFWriteStream?, string: String) -> CFIndex {
    return CFWriteStreamWriteFully(outputStream: outputStream, utf8String: string.utf8, length: string.lengthOfBytes(using: .utf8))
}

func CFWriteStreamWriteFully(outputStream: CFWriteStream?, utf8String: String.UTF8View, length: CFIndex) -> CFIndex {

    var buffer = Array(utf8String)
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