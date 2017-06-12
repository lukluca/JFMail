//
// Created by Tagliabue, L. on 26/05/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import Foundation

protocol JFMailSenderDelegate {
    func mailSent(sender: JFMailSender)
    func mailFailed(sender: JFMailSender, error: Error?)
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
    fileprivate var inputStream: InputStream?
    fileprivate var outputStream: OutputStream?
    fileprivate var relayHost: String!
    fileprivate var isSecure = false

    // Auth support flags
    fileprivate var serverAuthPLAIN = false
    fileprivate var serverAuthLOGIN = false

    // Content support flags
    fileprivate var server8bitMessages = false

    fileprivate var parts: Array<Dictionary<String,String>>?



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

    fileprivate func startShortWatchdog() {
        debugPrint("*** starting short watchdog ***")
        watchdogTimer = Timer.scheduledTimer(timeInterval: Timeout.SHORT_LIVENESS.rawValue, target: self, selector: #selector(connectionWatchdog), userInfo: nil, repeats: false)
    }

    fileprivate func startLongWatchdog() {
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

    fileprivate func cleanUpStreams() {
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
            assert((mailVal.toAddress != nil), "send requires mail address")
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
        // Pull out the next line

        var error: Error?
        var encounteredError = false
        var tmpLine: NSString?
        var messageSent = false

        if let str = inputString {
            let scanner = Scanner(string: str)

            while (!scanner.isAtEnd){

                if scanner.scanUpToCharacters(from: .newlines, into: &tmpLine), let tmp = tmpLine {
                    stopWatchdog()
                    debugPrint("S: \(tmp)");

                    if let state = sendState {
                        switch state {
                        case SmtpState.connecting:
                            if tmp.hasPrefix("220 ") {
                                sendState = .waitingEHLOReply
                                let ehlo = String(format: "EHLO %@\r\n", arguments: ["localhost"])
                                debugPrint("C: \(ehlo)")
                                if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: ehlo) < 0 {
                                    error = outputStream?.streamError
                                    encounteredError = true

                                }
                            } else {
                                startShortWatchdog()
                            }
                        case SmtpState.waitingEHLOReply:
                            if tmp.hasPrefix("250-AUTH") {
                                var testRange = (tmp as String).nsRange(of: "PLAIN")

                                if  testRange.location != NSNotFound{
                                    serverAuthPLAIN = true;
                                }

                                testRange = (tmp as String).nsRange(of:"LOGIN")
                                if (testRange.location != NSNotFound){
                                    serverAuthLOGIN = true;
                                }

                            }
                            else if tmp.hasPrefix("250-8BITMIME") {
                                server8bitMessages = true;

                            }
                            else if tmp.hasPrefix("250-STARTTLS"), !isSecure, let want = hostConfiguration.wantsSecure, want {
                                // if we're not already using TLS, start it up
                                sendState = .waitingTLSReply
                                let startTLS = "STARTTLS\r\n"
                                debugPrint("C: %@ \(startTLS)")
                                if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: startTLS) < 0 {
                                    error =  outputStream?.streamError
                                    encounteredError = true
                                }
                                else{
                                    startShortWatchdog()
                                }

                            }
                            else if tmp.hasPrefix("250 ") {
                                if let req = hostConfiguration.requiresAuth, req {
                                    // Start up auth
                                    if serverAuthPLAIN {
                                        sendState = .waitingAuthSuccess
                                        if let login = user.login, let password = user.password {
                                            let loginString = String(format: "\000%@\000%@", arguments: [login, password])
                                            if let argString = loginString.data(using: .utf8)?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0)) {
                                                let authString = String(format: "AUTH PLAIN %@\r\n", arguments: [argString])
                                                debugPrint("C: \(authString)")
                                                if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: authString) < 0 {
                                                    error = outputStream?.streamError
                                                    encounteredError = true
                                                } else {
                                                    startShortWatchdog()
                                                }
                                            }

                                        }

                                    }
                                    else if serverAuthLOGIN {
                                        sendState = .waitingLOGINUsernameReply
                                        let authString = "AUTH LOGIN\r\n"
                                        debugPrint("C: \(authString)")
                                        if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: authString) < 0 {
                                            error = outputStream?.streamError
                                            encounteredError = true
                                        } else {
                                            startShortWatchdog()
                                        }
                                    }
                                    else {
                                        error =  NSError(domain: "SKPSMTPMessageError", code: SmtpError.unsupportedLogin.rawValue, userInfo:
                                        [NSLocalizedDescriptionKey: NSLocalizedString("Unsupported login mechanism.", comment: "server unsupported login fail error description"),
                                         NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Your server's security setup is not supported, please contact your system administrator or use a supported email account like MobileMe.", comment: "server security fail error recovery")])
                                        encounteredError = true
                                    }
                                }

                            }

                            else {
                                // Start up send from
                                sendState = .waitingFromReply
                                if let from = user.email {
                                    let mailFrom = String(format: "MAIL FROM:<%@>\r\n", arguments: [from])
                                    debugPrint("C: \(mailFrom)")
                                    if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: mailFrom) < 0 {
                                        error = outputStream?.streamError
                                        encounteredError = true
                                    } else {
                                        startShortWatchdog()
                                    }
                                }
                            }

                        case .waitingTLSReply:
                            if tmp.hasPrefix("220 ") {
                                // Attempt to use TLSv1
                                var sslOptions: [String: Any] = [kCFStreamSSLLevel as String : kCFStreamSocketSecurityLevelTLSv1 as String ]
                                if !validateSSLChain {
                                    // Don't validate SSL certs. This is terrible, please complain loudly to your BOFH.
                                    debugPrint("WARNING: Will not validate SSL chain!!!")
                                    sslOptions[kCFStreamSSLValidatesCertificateChain as String] = kCFBooleanFalse as CFBoolean
                                }
                                debugPrint("Beginning TLSv1...")
                                CFReadStreamSetProperty(inputStream, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings), sslOptions as CFTypeRef)
                                CFWriteStreamSetProperty(outputStream, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings), sslOptions as CFTypeRef)
                                // restart the connection
                                sendState = .waitingEHLOReply
                                isSecure = true;
                                let ehlo = String(format: "EHLO %@\r\n", ["localhost"])
                                debugPrint("C: \(ehlo)")
                                if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: ehlo) < 0 {
                                    error = outputStream?.streamError
                                    encounteredError = true
                                }
                                else {
                                    startShortWatchdog()
                                }
                            }
                        case .waitingLOGINUsernameReply:
                            if tmp.hasPrefix("334 VXNlcm5hbWU6") {
                                sendState = .waitingLOGINPasswordReply
                                if let arg = user.login?.data(using: .utf8)?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0)) {
                                    let authString = String(format: "%@\r\n", arguments: [arg])
                                    debugPrint("C: \(authString)")
                                    if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: authString) < 0 {
                                        error = outputStream?.streamError
                                        encounteredError = true
                                    } else {
                                        startShortWatchdog()
                                    }

                                }
                            }
                        case .waitingLOGINPasswordReply:
                            if tmp.hasPrefix("334 UGFzc3dvcmQ6"){
                                sendState = .waitingAuthSuccess
                                if let arg = user.password?.data(using: .utf8)?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0)) {
                                    let authString = String(format: "%@\r\n", arguments: [arg])
                                    debugPrint("C: \(authString)")
                                    if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: authString) < 0 {
                                        error = outputStream?.streamError
                                        encounteredError = true
                                    } else {
                                        startShortWatchdog()
                                    }
                                }
                            }
                        case .waitingAuthSuccess:
                            if tmp.hasPrefix("235 ") {
                                self.sendState = .waitingFromReply
                                let format = server8bitMessages ? "MAIL FROM:<%@> BODY=8BITMIME\r\n" : "MAIL FROM:<%@>\r\n"
                                if let addr = mail?.toAddress {
                                    let mailFrom = String(format: format, arguments: [addr])
                                    debugPrint("C: \(mailFrom)")
                                    if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: mailFrom) < 0 {
                                        error = outputStream?.streamError
                                        encounteredError = true
                                    } else {
                                        startShortWatchdog()
                                    }
                                }
                            }
                            else if tmp.hasPrefix("535 "){
                                error = NSError(domain: "SKPSMTPMessageError", code: SmtpError.unsupportedLogin.rawValue, userInfo:
                                [NSLocalizedDescriptionKey: NSLocalizedString("Invalid username or password.", comment: "server login fail error description"),
                                 NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Go to Email Preferences in the application and re-enter your username and password.", comment: "server login error recovery")])
                                encounteredError = true
                            }
                        case .waitingFromReply:
                            // toc 2009-02-18 begin changes per mdesaro issue 18 - http://code.google.com/p/skpsmtpmessage/issues/detail?id=18
                            // toc 2009-02-18 begin changes to support cc & bcc
                            if tmp.hasPrefix("250 "){
                                self.sendState = .waitingToReply
                                if var multipleRcptTo = format(addresses: mail?.toAddress){
                                    if let form = format(addresses: mail?.ccAddress) {
                                        multipleRcptTo.append(form)
                                    }
                                    debugPrint("C: \(multipleRcptTo)")
                                    if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: multipleRcptTo) < 0 {
                                        error = outputStream?.streamError
                                        encounteredError = true
                                    } else {
                                        startShortWatchdog()
                                    }

                                }
                            }
                        case .waitingToReply:
                            if tmp.hasPrefix("250 "){
                                self.sendState = .waitingForEnterMail
                                let dataString = "DATA\r\n"
                                debugPrint("C: \(dataString)")
                                if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: dataString) < 0 {
                                    error = outputStream?.streamError
                                    encounteredError = true
                                } else {
                                    startShortWatchdog()
                                }
                            }
                            else if tmp.hasPrefix("530 "){
                                error = NSError(domain:"SKPSMTPMessageError",
                                        code:SmtpError.noRelay.rawValue,
                                        userInfo:[NSLocalizedDescriptionKey: NSLocalizedString("Relay rejected.", comment: "server relay fail error description"), NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Your server probably requires a username and password.", comment: "server relay fail error recovery")])
                                encounteredError = true
                            }
                            else if tmp.hasPrefix("550 "){
                                error = NSError(domain:"SKPSMTPMessageError",
                                        code:SmtpError.invalidMessage.rawValue,
                                        userInfo:[NSLocalizedDescriptionKey: NSLocalizedString("To address rejected.", comment: "server to address fail error description"), NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Please re-enter the To: address.", comment: "server to address fail error recovery")])
                                encounteredError = true
                            }
                        case .waitingForEnterMail:
                            if tmp.hasPrefix("354 "){
                                sendState = .waitingSendSuccess

                                if sendParts() {
                                    error =  outputStream?.streamError
                                    encounteredError = true
                                }
                            }

                        case .waitingSendSuccess:
                            if tmp.hasPrefix("250 "){
                                self.sendState = .waitingQuitReply
                                let quitString = "QUIT\r\n"
                                debugPrint("C: \(quitString)")
                                if CFWriteStreamWriteFullyUtf8Encoding(outputStream: self.outputStream, string: quitString) < 0 {
                                    error = outputStream?.streamError
                                    encounteredError = true
                                }  else{
                                    startShortWatchdog()
                                }
                            }
                            else if tmp.hasPrefix("550 ") {
                                error = NSError(domain: "SKPSMTPMessageError",
                                        code: SmtpError.invalidMessage.rawValue,
                                        userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Failed to logout.", comment: "server logout fail error description"), NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Try sending your message again later.", comment: "server generic error recovery")])
                                encounteredError = true;
                            }
                        case .waitingQuitReply:
                            if tmp.hasPrefix("221 ") {
                                sendState = .messageSent
                                messageSent = true
                            }
                        default:
                            ()
                        }
                    }

                } else {
                    break
                }

                inputString = inputString?.substring(from: scanner.scanLocation)

                if (messageSent) {
                    cleanUpStreams()
                    delegate?.mailSent(sender: self)
                }
                else if (encounteredError) {
                    cleanUpStreams()
                    delegate?.mailFailed(sender: self, error: error)
                }
            }
        }
    }

    private func format(addresses: String?) -> String? {
        let splitSet = CharacterSet(charactersIn: ";,")
        var multipleRcptTo: String?
        if let add = addresses, !add.isEmpty {
            multipleRcptTo = ""
            if add.nsRange(of: ";").location != NSNotFound || add.nsRange(of: ",").location != NSNotFound {
                multipleRcptTo = add.components(separatedBy: splitSet).map {
                    (value: String) -> String? in
                    return format(anAddress:value)}.removeNils().joined()
            } else {
                if let form = format(anAddress:add) {
                    multipleRcptTo?.append(form)
                }
            }
        }
        return multipleRcptTo
    }

    private func format(anAddress: String?) -> String? {
        var formattedAddress: String?
        let whitespaceCharSet = CharacterSet.whitespaces
        if let add = anAddress {
            if add.nsRange(of: "<").location == NSNotFound || add.nsRange(of: ">").location == NSNotFound {
                formattedAddress = String(format: "RCPT TO:<%@>\r\n", arguments: [add.trimmingCharacters(in: whitespaceCharSet)])
            } else {
                formattedAddress = String(format: "RCPT TO:%@\r\n", arguments: [add.trimmingCharacters(in: whitespaceCharSet)])
            }
        }
        return formattedAddress
    }

    private func sendParts() -> Bool {
        let separatorString = "--JFMailSender--Separator--Delimiter\r\n"
        let uuidRef = CFUUIDCreate(kCFAllocatorDefault)
        let uuid = CFUUIDCreateString(kCFAllocatorDefault, uuidRef) as String
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        var message = String(format: "Date: %@\r\n", arguments: [dateFormatter.string(from: now)])
        message = message.appendingFormat("Message-id: <%@@%@>\r\n", [uuid.replacingOccurrences(of: "-", with: ""), self.relayHost])
        if let name = user.name, let email = user.email {
            message = message.appendingFormat("From:\"%@\"%@\r\n", JFMailSender.chineseCharacterEncodingFileName(fileName: name), email)
        } else if let email = user.email {
            message  = message.appendingFormat("From:%@\r\n", [email])
        }

        if let toAddress = mail?.toAddress, !toAddress.isEmpty {
            message = message.appendingFormat("To:%@\r\n", [toAddress])
        }

        if let ccAddress = mail?.ccAddress, !ccAddress.isEmpty {
            message = message.appendingFormat("Cc:%@\r\n", [ccAddress])
        }

        message.append("Content-Type: multipart/mixed; boundary=JFMailSender--Separator--Delimiter\r\n")
        message.append("Mime-Version: 1.0 (JFMailSender 1.0)\r\n")
        message.append("Subject:%@\r\n\r\n")
        message.append(separatorString)
        var intPointee: Int32?
        if let messageData = message.data(using: .utf8, allowLossyConversion: true) {
            messageData.withUnsafeBytes { (pointer: UnsafePointer<Int32>) -> Void in
                debugPrint("C: %@ \(pointer)")
                intPointee = pointer.pointee
            }
        }

        if let pointee = intPointee, CFWriteStreamWriteFullyUtf8Encoding(outputStream: self.outputStream, string: String(pointee)) < 0 {
            return false
        }

        parts = parts?.map ({ (part: Dictionary<String, String>) -> Dictionary<String, String> in
            if let disposition = part[SmtpKey.partContentDisposition], !disposition.isEmpty {
                message = message.appendingFormat("Content-Disposition: %@\r\n", disposition)
            }
            if let type = part[SmtpKey.partContentType], !type.isEmpty {
                message = message.appendingFormat("Content-Type: %@\r\n", type)
            }
            if let encoding = part[SmtpKey.partContentTransferEncoding], !encoding.isEmpty {
                message = message.appendingFormat("Content-Transfer-Encoding: %@\r\n\r\n", encoding)
            }
            if let partMessage = part[SmtpKey.partMessage], !partMessage.isEmpty {
                message = message.appendingFormat(partMessage);
            }

            message = message.appendingFormat("\r\n")
            message = message.appendingFormat(separatorString)

            return part
        })

        message.append("\r\n.\r\n")
        debugPrint("C: %@ \(message)")
        if CFWriteStreamWriteFullyUtf8Encoding(outputStream: outputStream, string: message) < 0 {
            return false
        }

        startLongWatchdog()
        return true
    }

    static func part(type: PartType, message: String, contentType: String, contentTransferEncoding: String, fileName: String) -> Dictionary<String, String>{
        if(type == PartType.plainPart){
            return [SmtpKey.partContentType: contentType, SmtpKey.partMessage: message, SmtpKey.partContentTransferEncoding: contentTransferEncoding]
        } else {
            return [SmtpKey.partContentDisposition: String(format: "attachment;\r\n\tfilename=\"%@\"", arguments: [fileName]), SmtpKey.partMessage: message, SmtpKey.partContentTransferEncoding: contentTransferEncoding]
        }
    }

    static func chineseCharacterEncodingFileName(fileName: String) -> String {
        return String(format: "=?UTF-8?B?%@?=", arguments: [(fileName.data(using: .utf8)?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0)))!])
    }

}
