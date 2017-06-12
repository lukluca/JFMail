//
// Created by Tagliabue, L. on 12/06/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import UIKit

@objc class SwiftViewController: UIViewController {

    var mailSender: JFMailSender?

    override func viewDidLoad() {
        super.viewDidLoad()
        debugPrint("view did load")

        let button = UIButton(frame: CGRect(x: 100, y: 100, width: 100, height: 50))
        button.backgroundColor = .green
        button.setTitle("Send Email", for: .normal)
        button.addTarget(self, action: #selector(sendButtonAction), for: .touchUpInside)
        
        button.center = view.center

        self.view.addSubview(button)

        var user = MailUser()
        user.email = "er@mail.com"
        user.password = ""
        user.login = ""
        user.name = ""
       
        mailSender = JFMailSender(hostConfiguration: Host.Gmail.info, user: user)

        let plainPart = [SmtpKey.partContentType: "text/plain; charset=UTF-8",
                         SmtpKey.partMessage: "ceshiceshiceshi 测试测试测试.<br><h1>天气不错</h1>", SmtpKey.partContentTransferEncoding: "8bit"]


        if let vcfPath = Bundle.main.path(forResource: "test", ofType: "vcf"), let vcfData = NSData(contentsOfFile: vcfPath) {
            let encoding = vcfData.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))

            let vcfPart = [SmtpKey.partContentType: "text/directory;\r\n\tx-unix-mode=0644;\r\n\tname=\"test.vcf\"",
                           SmtpKey.partContentDisposition: "attachment;\r\n\tfilename=\"test.vcf\"", SmtpKey.partMessage: encoding, SmtpKey.partContentTransferEncoding: "base64"]
            let fileName = JFMailSender.chineseCharacterEncodingFileName(fileName: "测试.vcf")

            let vcfPart2 = JFMailSender.part(type: PartType.filePart, message: encoding,
                    contentType: String(format: "text/directory;\r\n\tx-unix-mode=0644;\r\n\tname=\"%@\"", [fileName]),
                    contentTransferEncoding: "base64", fileName: fileName)

            mailSender?.parts = [plainPart, vcfPart, vcfPart2];
            mailSender?.delegate = self
        }
    }

    func sendButtonAction(sender: UIButton!) {
        let mail = Mail()
        mailSender?.sendMail(mail: mail)
    }
}


extension SwiftViewController: JFMailSenderDelegate {

    func mailSent(sender: JFMailSender) {
        debugPrint("Yay! Message was sent!")
    }

    func mailFailed(sender: JFMailSender, error: Error?) {
        if let err = error as NSError? {
            debugPrint(String(format: "Darn! Error!\n%li: %@\n%@", err.code, err.localizedDescription, err.localizedRecoverySuggestion ?? "nil"))
        }

    }
}


