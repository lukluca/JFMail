//
// Created by Tagliabue, L. on 26/05/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import Foundation

protocol JFMailSenderDelegate {
    func mailSent(sender: JFMailSender)
    func mailFailed(sender: JFMailSender, error: NSError)
}

class JFMailSender {

    public var hostConfiguration: MailHostConfiguration
    public var user: MailUser
    public var mail: Mail?

    public var validateSSLChain = true
    public var ccEmail: String?
    public var cnEmail: String?
    public var connectTimeout: TimeInterval = 8.0
    public var delegate: JFMailSenderDelegate?

    private var watchdogTimer: Timer?
    private var connectTimer: Timer?
    private var sendState: SmtpState?
    private var inputStream: InputStream?
    private var outputStream: OutputStream?

    //MARK: Initialisation & Deinitialisation

    init(hostConfiguration: MailHostConfiguration, user: MailUser){
        self.hostConfiguration = hostConfiguration
        self.user = user
    }

    deinit {
        debugPrint("deinit", self)
        connectTimer?.invalidate()
        stopWatchdog()
    }

    //MARK: Connection Timers

    func startShortWatchdog() {
        debugPrint("*** starting short watchdog ***")
        watchdogTimer = Timer.scheduledTimer(timeInterval: Timeout.SHORT_LIVENESS.rawValue, target: self, selector: #selector(connectionWatchdog), userInfo: nil, repeats: false)
    }

    func startLongWatchdog() {
        debugPrint("*** starting long watchdog ***")
        watchdogTimer = Timer.scheduledTimer(timeInterval: Timeout.LONG_LIVENESS.rawValue, target: self, selector: #selector(connectionWatchdog), userInfo: nil, repeats: false)
    }

    func stopWatchdog() {
        debugPrint("*** stopping watchdog ***")
        watchdogTimer?.invalidate();
        watchdogTimer = nil;
    }

    //Mark: Watchdog Callback
    @objc func connectionWatchdog(aTimer: Timer) {
        cleanUpStreams()

        // No hard error if we're waiting on a reply
        if (sendState != .waitingQuitReply) {
            let error = NSError(domain: "SKPSMTPMessageError", code: SmtpError.connectionTimeout.rawValue, userInfo:
            [
                    NSLocalizedDescriptionKey : NSLocalizedString("Timeout sending message.", comment: "server timeout fail error description"),
                    NSLocalizedRecoverySuggestionErrorKey : NSLocalizedString("Try sending your message again later.", comment: "server generic error recovery")
            ])

            delegate?.mailFailed(sender: self, error: error)
        }
        else {
            delegate?.mailSent(sender: self)
        }
    }

    func cleanUpStreams() {
        inputStream?.close()
        inputStream?.remove(from: .current, forMode: .defaultRunLoopMode)
        inputStream = nil;
        outputStream?.close()
        outputStream?.remove(from: .current, forMode: .defaultRunLoopMode)
        outputStream = nil;
    }
}

//MARK: NSCopying protocol
extension JFMailSender: NSCopying {

    public func copy(with zone: NSZone? = nil) -> Any {

        let mailSenderCopy =  JFMailSender(hostConfiguration: self.hostConfiguration.copy(), user: self.user.copy())
        mailSenderCopy.delegate = self.delegate
        mailSenderCopy.ccEmail = self.ccEmail
        mailSenderCopy.cnEmail = self.cnEmail
        return mailSenderCopy;

    }

}
