//
//  SandboxBookmarks.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 7/28/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

class SandboxBookmark {
    static var instance: SandboxBookmark? = nil

    private let bookmarksKey = "SecurityBookmarks"
    private var defaults = UserDefaults.init(suiteName: "group.fsnotes-manager")
    private var bookmarks = [URL: Data]()

    public static func sharedInstance() -> SandboxBookmark {
        guard let sandbox = self.instance else {
            self.instance = SandboxBookmark()
            return self.instance!
        }
        
        return sandbox
    }

    public func load() -> [URL] {
        if let bookmarks = defaults?.object(forKey: bookmarksKey) as? [Data] {
            for bookmarkData in bookmarks {
                do {
                    var isStale = false
                    let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale).resolvingSymlinksInPath()

                    if !isStale {
                        self.bookmarks[url] = bookmarkData
                        print("URL loaded from security scope: \(url)")
                    } else {
                        remove(url: url)
                    }
                }
                catch let error {
                    print(error)
                }
            }
        }

        return bookmarks.map({ $0.key })
    }

    public func save(data: Data) {
        var bookmarks = [Data]()

        if let bookmarksData = defaults?.object(forKey: bookmarksKey) as? [Data] {
            bookmarks = bookmarksData
        }

        bookmarks.append(data)
        save(data: bookmarks)
    }

    public func save(data: [Data]) {
        defaults?.set(data, forKey: bookmarksKey)
    }

    public func remove(url: URL) {
        self.bookmarks.removeValue(forKey: url)

        print(url)
        print(url.resolvingSymlinksInPath())

        print(self.bookmarks)

        let values = bookmarks.map({ $0.value })
        save(data: values)
    }
}
