//
// Created by Tagliabue, L. on 30/05/2017.
// Copyright (c) 2017 jeffsss. All rights reserved.
//

import Foundation

extension Scanner {

    func scanUpToCharacters(from set: CharacterSet) -> String? {
        var value: NSString? = ""

        if scanUpToCharacters(from: set, into: &value) {
            if let value = value as String? {
                return value
            }
        }
        return nil
    }
}



