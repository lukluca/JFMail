//
// Created by Tagliabue, L. on 26/05/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import Foundation

protocol JFMailSenderDelegate {
    func mailSent(sender: JFMailSender)
    func mailFailed(sender: JFMailSender, error: NSError)
}

class JFMailSender: NSObject {

    public var hostConfiguration: MailHostConfiguration
    public var user: MailUser
    public var mail: Mail?

    public var validateSSLChain = true
    public var ccEmail: String?
    public var cnEmail: String?
    public var connectTimeout: TimeInterval = 8.0
    public var delegate: JFMailSenderDelegate?
    public var relayPorts: Array<Int>?

    fileprivate var sendState: SmtpState?
    fileprivate var inputString: String?

    private var watchdogTimer: Timer?
    private var connectTimer: Timer?
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var relayHost: String!
    private var isSecure: Bool?


    //MARK: Initialisation & Deinitialisation

    init(hostConfiguration: MailHostConfiguration, user: MailUser) {
        self.hostConfiguration = hostConfiguration
        self.user = user
    }

    deinit {
        debugPrint("deinit", self)
        connectTimer?.invalidate()
        stopWatchdog()
    }

    //MARK: Connection Timers

    private func startShortWatchdog() {
        debugPrint("*** starting short watchdog ***")
        watchdogTimer = Timer.scheduledTimer(timeInterval: Timeout.SHORT_LIVENESS.rawValue, target: self, selector: #selector(connectionWatchdog), userInfo: nil, repeats: false)
    }

    private func startLongWatchdog() {
        debugPrint("*** starting long watchdog ***")
        watchdogTimer = Timer.scheduledTimer(timeInterval: Timeout.LONG_LIVENESS.rawValue, target: self, selector: #selector(connectionWatchdog), userInfo: nil, repeats: false)
    }

    fileprivate func stopWatchdog() {
        debugPrint("*** stopping watchdog ***")
        watchdogTimer?.invalidate();
        watchdogTimer = nil;
    }

    @objc func connectionConnectedCheck(aTimer: Timer) {
        if sendState == .connecting {
            cleanUpStreams()

            // Try the next port - if we don't have another one to try, this will fail
            sendState = .idle
            sendMail()
        }
        connectTimer = nil

    }

    //MARK: Watchdog Callback
    @objc func connectionWatchdog(aTimer: Timer) {
        cleanUpStreams()

        // No hard error if we're waiting on a reply
        if sendState != .waitingQuitReply {
            let error = NSError(domain: "SKPSMTPMessageError", code: SmtpError.connectionTimeout.rawValue, userInfo:
            [
                    NSLocalizedDescriptionKey: NSLocalizedString("Timeout sending message.", comment: "server timeout fail error description"),
                    NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Try sending your message again later.", comment: "server generic error recovery")
            ])

            delegate?.mailFailed(sender: self, error: error)
        } else {
            delegate?.mailSent(sender: self)
        }
    }

    private func cleanUpStreams() {
        inputStream?.close()
        inputStream?.remove(from: .current, forMode: .defaultRunLoopMode)
        inputStream = nil;
        outputStream?.close()
        outputStream?.remove(from: .current, forMode: .defaultRunLoopMode)
        outputStream = nil;
    }

    //MARK: Connection

    private func checkRelayHost(error: inout NSError?) -> Bool {

        let host = CFHostCreateWithName(nil, relayHost as CFString).takeRetainedValue()
        var streamError: CFStreamError?

        if !CFHost.Start(theHost: host, CFHostInfoType: .addresses , error: &streamError) {
            var errorDomainName: String
            if let strErr = streamError {
                switch (strErr.domain) {
                case CFStreamErrorDomain.custom.rawValue:
                    errorDomainName = "kCFStreamErrorDomainCustom";
                case CFStreamErrorDomain.POSIX.rawValue:
                    errorDomainName = "kCFStreamErrorDomainPOSIX";
                case CFStreamErrorDomain.macOSStatus.rawValue:
                    errorDomainName = "kCFStreamErrorDomainMacOSStatus";
                default:
                    errorDomainName = "Generic CFStream Error Domain \(strErr.domain)";
                }

                if error != nil {
                    error = NSError(domain: errorDomainName, code: Int(strErr.error), userInfo: [NSLocalizedDescriptionKey: "Error resolving address.", NSLocalizedRecoverySuggestionErrorKey: "Check your SMTP Host name"])
                }

                return false

            }
        }

        var hasBeenResolved: Bool?
        CFHost.GetAddressing(theHost: host, hasBeenResolved: &hasBeenResolved)
        if let hBR = hasBeenResolved, hBR {
            if error != nil {
                error = NSError(domain: "SKPSMTPMessageError", code: SmtpError.nonExistentDomain.rawValue, userInfo: [NSLocalizedDescriptionKey: "Error resolving host.", NSLocalizedRecoverySuggestionErrorKey: "Check your SMTP Host name"])
            }
            return false
        }

        return true
    }

    private func sendMail() {

        assert((hostConfiguration.requiresAuth != nil), "send requires hostConfiguration requiresAuth set")
        assert((mail != nil), "send requires mail set")
        assert(sendState == .idle, "Message has already been sent!")
        assert((user.email != nil), "send requires mail toEmail")
        if let reqAuth = hostConfiguration.requiresAuth, reqAuth {
            assert((user.login != nil), "auth requires login")
            assert((user.password != nil), "auth requires pass")
        }
        assert((relayHost != nil), "send requires relayHost")
        if let mailVal = mail {
            assert((mailVal.subject != nil), "send requires mail subject")
            assert((mailVal.address != nil), "send requires mail address")
            assert((mailVal.contentType != nil), "send requires mail contentType")
            assert((mailVal.contentTransferEncoding != nil), "send requires mail contentTransferEncoding")
        }

        var error: NSError?

        if !checkRelayHost(error: &error) {
            if let err = error {
                delegate?.mailFailed(sender: self, error: err)
            }
            return
        }

        if let ports = relayPorts, ports.count == 0 {
            DispatchQueue.global().async {
                self.delegate?.mailFailed(sender: self, error: NSError.init(domain: "SKPSMTPMessageError", code: SmtpError.connectionFailed.rawValue, userInfo:
                [NSLocalizedDescriptionKey: NSLocalizedString("Unable to connect to the server.", comment: "server connection fail error description"),
                 NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Try sending your message again later.", comment: "server generic error recovery")]))
            }
            return
        }

        // Grab the next relay port
        if let ports = relayPorts, let port = ports.first {
            // Pop this off the head of the queue.
            relayPorts = ports.count > 1 ? Array(ports[1..<ports.count]) : []
            debugPrint("C: Attempting to connect to server at:", relayHost, port)
            connectTimer = Timer(timeInterval: connectTimeout, target: self, selector: #selector(connectionConnectedCheck), userInfo: nil, repeats: false)
            if let timer = connectTimer {
                RunLoop.current.add(timer, forMode: .defaultRunLoopMode)
            }

            getStreams(hostName: relayHost, port: port)

            if let input = inputStream, let output = outputStream {
                sendState = .connecting
                isSecure = false
                input.delegate = self
                output.delegate = self
                input.schedule(in: .current, forMode: .defaultRunLoopMode)
                output.schedule(in: .current, forMode: .defaultRunLoopMode)
                input.open()
                output.open()
                inputString = ""
                if !RunLoop.current.isEqual(RunLoop.main) {
                    RunLoop.current.run()
                }
                return
            } else {
                connectTimer?.invalidate()
                connectTimer = nil
                delegate?.mailFailed(sender: self, error: NSError(domain: "SKPSMTPMessageError", code: SmtpError.connectionFailed.rawValue, userInfo:
                [NSLocalizedDescriptionKey: NSLocalizedString("Unable to connect to the server.", comment: "server connection fail error description"),
                 NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Try sending your message again later.", comment: "server generic error recovery")]
                ))
            }

        }
    }

    //iOS NSStream doesn't support NSHost.This is a defect know to Apple (http://developer.apple.com/library/ios/#qa/qa1652/_index.html).
    //Next lines of code are the same workaround, wrote in Swift language.
    private func getStreams(hostName: String, port: Int) {
        let host: CFHost? = CFHostCreateWithName(nil, hostName as CFString).takeUnretainedValue()
        var readStream: CFReadStream? = nil
        var writeStream: CFWriteStream? = nil

        if let hos = host {
            CFStream.CreatePair(theHost: hos, port: port, readStream: &readStream, writeStream: &writeStream)
        }

        self.inputStream = readStream
        self.outputStream = writeStream
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

//MARK: StreamDelegate
extension JFMailSender: StreamDelegate {

    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {

        switch eventCode {
        case Stream.Event.hasBytesAvailable:
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            memset(buf, 0, MemoryLayout<UInt8>.size * 1024);
            var len = 0
            if let inputStream = aStream as? InputStream {
                len = inputStream.read(buf, maxLength: MemoryLayout<UInt8>.size * 1024)
            }
            if len > 0 {
                if let tmpString = String(bytes: buf, length: len, encoding: String.Encoding.utf8){
                    inputString?.append(tmpString)
                    parseBuffer()
                }
            }
        case Stream.Event.endEncountered:
            stopWatchdog()
            aStream.close()
            aStream.remove(from: RunLoop.current, forMode: .defaultRunLoopMode)
            if(sendState != SmtpState.messageSent){
                self.delegate?.mailFailed(sender: self, error: NSError(domain: "SKPSMTPMessageError", code: SmtpError.connectionInterrupted.rawValue, userInfo:
                    [NSLocalizedDescriptionKey: NSLocalizedString("The connection to the server was interrupted.", comment: "server connection interrupted error description"),
                 NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Try sending your message again later.", comment: "server generic error recovery")]))
            }

        default:
            ()
        }
    }

    private func parseBuffer(){

    }

}
