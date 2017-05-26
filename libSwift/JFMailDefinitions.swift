//
// Created by Tagliabue, L. on 26/05/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import Foundation

//MARK: enums

enum SmtpState {
    case idle
    case connecting
    case waitingEHLOReply
    case waitingTLSReply
    case waitingLOGINUsernameReply
    case waitingLOGINPasswordReply
    case waitingAuthSuccess
    case waitingFromReply
    case waitingToReply
    case waitingForEnterMail
    case waitingSendSuccess
    case waitingQuitReply
    case messageSent
}

enum PartType {
    case filePart
    case plainPart
}

enum SmtpError: Int, Error {
    case connectionTimeout = -5
    case connectionFailed = -3
    case connectionInterrupted = -4
    case unsupportedLogin = -2
    case nonExistentDomain = 1
    case invalidUserPass = 535
    case invalidMessage = 550
    case noRelay = 530
}

enum Timeout: Double {
    case SHORT_LIVENESS = 20.0
    case LONG_LIVENESS = 60.0
}

//MARK: structs

struct SmtpKey {
    static let partContentDisposition = "smtpPartContentDispositionKey"
    static let partContentType = "smtpPartContentTypeKey"
    static let partMessage = "smtpPartMessageKey"
    static let partContentTransferEncoding = "smtpPartContentTransferEncodingKey"
}



