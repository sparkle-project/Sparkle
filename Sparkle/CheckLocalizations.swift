import Foundation

func die(msg: String) {
    println("ERROR: \(msg)")
    exit(1)
}

func escapeHTML(str: String) -> String {
    if let node = NSXMLNode.textWithStringValue(str) as? NSXMLNode {
        return node.XMLString
    }
    die("NSXMLNode failure"); return ""
}

let ud = NSUserDefaults.standardUserDefaults()
let sparkleRoot = ud.objectForKey("root") as? String
let htmlPath = ud.objectForKey("htmlPath") as? String
if sparkleRoot == nil || htmlPath == nil {
    die("Missing arguments")
}

let enStringsPath = sparkleRoot! + "/Sparkle/en.lproj/Sparkle.strings"
let enStringsDict = NSDictionary(contentsOfFile: enStringsPath)
if enStringsDict == nil {
    die("Invalid English strings")
}
let enStringsDictKeys = enStringsDict!.allKeys

let dirPath = sparkleRoot! + "/Sparkle"
let dirContents = NSFileManager.defaultManager().contentsOfDirectoryAtPath(dirPath, error: nil) as! [String]
let css =
    "body { font-family: sans-serif; font-size: 10pt; }" +
    "h1 { font-size: 12pt; }"  +
    ".missing { background-color: #FFBABA; color: #D6010E; }"  +
    ".unused { background-color: #BDE5F8; color: #00529B; }" +
    ".unlocalized { background-color: #FEEFB3; color: #9F6000; }"
var html = "<!DOCTYPE html>\n<html><head><meta charset=\"UTF-8\">\n<title>Localizations</title>\n<style>\(css)</style>\n</head><body>\n"
let locale = NSLocale.currentLocale()
for dirEntry in dirContents {
    if dirEntry.pathExtension != "lproj" || dirEntry == "en.lproj" {
        continue
    }
    
    let lang = locale.displayNameForKey(NSLocaleLanguageCode, value: dirEntry.stringByDeletingPathExtension)
    html += "<h1>\(dirEntry) (\(lang!))</h1>\n"
    
    let stringsPath = dirPath.stringByAppendingPathComponent(dirEntry).stringByAppendingPathComponent("Sparkle.strings")
    let stringsDict = NSDictionary(contentsOfFile: stringsPath)
    if stringsDict == nil {
        die("Invalid strings file \(dirEntry)")
        continue
    }
    
    var missing: [String] = []
    var unlocalized: [String] = []
    var unused: [String] = []
    
    for key in enStringsDictKeys {
        let str = stringsDict?.objectForKey(key) as? String
        if str == nil {
            missing.append(key as! String)
        } else if let enStr = enStringsDict?.objectForKey(key) as? String {
            if enStr == str {
                unlocalized.append(key as! String)
            }
        }
    }

    let stringsDictKeys = stringsDict!.allKeys
    for key in stringsDictKeys {
        if enStringsDict?.objectForKey(key) == nil {
            unused.append(key as! String)
        }
    }
    
    let sorter = { (s1: String, s2: String) -> Bool in
        return s1 < s2
    }
    missing.sort(sorter)
    unlocalized.sort(sorter)
    unused.sort(sorter)
    
    for key in missing {
        html += "<span class=\"missing\">Missing \"\(escapeHTML(key))\"</span><br/>\n"
    }
    for key in unlocalized {
        html += "<span class=\"unlocalized\">Unlocalized \"\(escapeHTML(key))\"</span><br/>\n"
    }
    for key in unused {
        html += "<span class=\"unused\">Unused \"\(escapeHTML(key))\"</span><br/>\n"
    }
}
html += "</body></html>"

var err: NSError?
if !html.writeToFile(htmlPath!, atomically: true, encoding: NSUTF8StringEncoding, error: &err) {
    die("Can't write report: \(err)")
}
