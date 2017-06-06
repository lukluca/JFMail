//
// Created by Tagliabue, L. on 26/05/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import Foundation

//MARK: protocols

protocol MailService {
    func send(mail: Mail, completion: @escaping MailResponseCompletion)
    func send(mail: Mail, to: [String], completion: @escaping MailResponseCompletion)
}

protocol Copyable {
    func copy() -> Self
}

typealias MailResponseCompletion = (MailResponseState) -> Void

//MARK: enums

enum MailResponseState {
    case success(Mail, MailHostConfiguration, MailUser)
    case fail(Mail, MailHostConfiguration, MailUser, Error)
}

enum Host  {
    case Gmail

    var info: MailHostConfiguration {
        switch self {
        case .Gmail:
            var host = MailHostConfiguration()
            host.relayHost = "smtp.gmail.com"
            host.requiresAuth = true
            host.wantsSecure = true
            host.relayPort = 465
            return host
        }
    }
}

//MARK: structs

struct Mail: CustomDebugStringConvertible {
    var toAddress: String?
    var ccAddress: String?
    var subject: String?
    var body: String?
    var contentType: String?
    var contentTransferEncoding: String?

    var debugDescription: String {
        return "toAddress: \(toAddress ?? "nil"), ccAddress: \(ccAddress ?? "nil"), subject: \(subject ?? "nil"), body: \(body ?? "nil"), parts -> contentType: \(contentType ?? "nil"), contentTransferEncoding: \(contentTransferEncoding ?? "nil" )"
    }
}

struct MailHostConfiguration: CustomDebugStringConvertible {
    var relayHost: String?
    var requiresAuth: Bool?
    var wantsSecure: Bool?
    var relayPort: Int = 0

    var debugDescription: String {
        return "relayHost: \(relayHost ?? "nil"), requiresAuth: \(requiresAuth ?? false), wantsSecure: \(wantsSecure ?? false), relayPort: \(relayPort)"
    }

}

extension MailHostConfiguration: Copyable {
    func copy() -> MailHostConfiguration {
        var host = MailHostConfiguration()
        host.relayHost = self.relayHost
        host.requiresAuth = self.requiresAuth
        host.relayPort = self.relayPort
        host.wantsSecure = self.wantsSecure
        return host
    }
}

struct MailUser: CustomDebugStringConvertible {
    var name: String?
    var email: String?
    var password: String?
    var login: String?

    var debugDescription: String {
        return "name: \(name ?? "nil"), email: \(email ?? "nil"), password: \(password ?? "nil"), relayPort: \(login ?? "nil")"
    }
}

extension MailUser: Copyable {
    func copy() -> MailUser {
        var user = MailUser()
        user.name = self.name
        user.email = self.email
        user.password = self.password
        user.login = self.login
        return user
    }
}