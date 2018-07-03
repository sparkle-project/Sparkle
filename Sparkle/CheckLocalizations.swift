#!/usr/bin/xcrun swift

import Foundation

func die(_ msg: String) {
    print("ERROR: \(msg)")
    exit(1)
}

extension XMLElement {
    convenience init(name: String, attributes: [String: String], stringValue string: String? = nil) {
        self.init(name: name, stringValue: string)
        setAttributesWith(attributes)
    }
}

let ud = UserDefaults.standard
let sparkleRoot = ud.object(forKey: "root") as? String
let htmlPath = ud.object(forKey: "htmlPath") as? String
if sparkleRoot == nil || htmlPath == nil {
    die("Missing arguments")
}

let enStringsPath = sparkleRoot! + "/Sparkle/en.lproj/Sparkle.strings"
let enStringsDict = NSDictionary(contentsOfFile: enStringsPath)
if enStringsDict == nil {
    die("Invalid English strings")
}
let enStringsDictKeys = enStringsDict!.allKeys

let dirPath = NSString(string: sparkleRoot! + "/Sparkle")
let dirContents = try! FileManager.default.contentsOfDirectory(atPath: dirPath as String)
let css =
    "body { font-family: sans-serif; font-size: 10pt; }" +
    "h1 { font-size: 12pt; }" +
    ".missing { background-color: #FFBABA; color: #D6010E; white-space: pre; }" +
    ".unused { background-color: #BDE5F8; color: #00529B; white-space: pre; }" +
    ".unlocalized { background-color: #FEEFB3; color: #9F6000; white-space: pre; }"
var html = XMLDocument(rootElement: XMLElement(name: "html"))
html.dtd = XMLDTD()
html.dtd!.name = html.rootElement()!.name
html.characterEncoding = "UTF-8"
html.documentContentKind = XMLDocument.ContentKind.xhtml
var body = XMLElement(name: "body")
var head = XMLElement(name: "head")
html.rootElement()!.addChild(head)
html.rootElement()!.addChild(body)
head.addChild(XMLElement(name: "meta", attributes: ["charset": html.characterEncoding!]))
head.addChild(XMLElement(name: "title", stringValue: "Sparkle Localizations Report"))
head.addChild(XMLElement(name: "style", stringValue: css))

let locale = Locale.current
for dirEntry in dirContents {
    if NSString(string: dirEntry).pathExtension != "lproj" || dirEntry == "en.lproj" {
        continue
    }

    let lang = (locale as NSLocale).displayName(forKey: NSLocale.Key.languageCode, value: NSString(string: dirEntry).deletingPathExtension)
    body.addChild(XMLElement(name: "h1", stringValue: "\(dirEntry) (\(lang!))"))

    let stringsPath = NSString(string: dirPath.appendingPathComponent(dirEntry)).appendingPathComponent("Sparkle.strings")
    let stringsDict = NSDictionary(contentsOfFile: stringsPath)
    if stringsDict == nil {
        die("Invalid strings file \(dirEntry)")
        continue
    }

    var missing: [String] = []
    var unlocalized: [String] = []
    var unused: [String] = []

    for key in enStringsDictKeys {
        let str = stringsDict?.object(forKey: key) as? String
        if str == nil {
            missing.append(key as! String)
        } else if let enStr = enStringsDict?.object(forKey: key) as? String {
            if enStr == str {
                unlocalized.append(key as! String)
            }
        }
    }

    let stringsDictKeys = stringsDict!.allKeys
    for key in stringsDictKeys {
        if enStringsDict?.object(forKey: key) == nil {
            unused.append(key as! String)
        }
    }

    let sorter = { (s1: String, s2: String) -> Bool in
        return s1 < s2
    }
    missing.sort(by: sorter)
    unlocalized.sort(by: sorter)
    unused.sort(by: sorter)

    let addRow = { (prefix: String, cssClass: String, key: String) -> Void in
        body.addChild(XMLElement(name: "span", attributes: ["class": cssClass], stringValue: [prefix, key].joined(separator: " ") + "\n"))
    }

    for key in missing {
        addRow("Missing", "missing", key)
    }
    for key in unlocalized {
        addRow("Unlocalized", "unlocalized", key)
    }
    for key in unused {
        addRow("Unused", "unused", key)
    }
}

var err: NSError?
if !((try? html.xmlData.write(to: URL(fileURLWithPath: htmlPath!), options: [.atomic])) != nil) {
    die("Can't write report: \(err!)")
}
