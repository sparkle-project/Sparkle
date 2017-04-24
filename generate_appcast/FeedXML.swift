//
//  Created by Kornel on 22/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

let maxVersionsInFeed = 5;

func findElement(name: String, parent: XMLElement) -> XMLElement? {
    if let found = try? parent.nodes(forXPath: name) {
        if found.count > 0 {
            if let element = found[0] as? XMLElement {
                return element;
            }
        }
    }
    return nil;
}

func findOrCreateElement(name: String, parent: XMLElement) -> XMLElement {
    if let element = findElement(name: name, parent: parent) {
        return element;
    }
    let element = XMLElement(name: name);
    linebreak(parent);
    parent.addChild(element);
    return element;
}

func text(_ text: String) -> XMLNode {
    return XMLNode.text(withStringValue: text) as! XMLNode
}

func linebreak(_ element: XMLElement) {
    element.addChild(text("\n"));
}


func writeAppcast(appcastDestPath: URL, updates: [ArchiveItem]) throws {
    let appBaseName = updates[0].appPath.deletingPathExtension().lastPathComponent;

    let sparkleNS = "http://www.andymatuschak.org/xml-namespaces/sparkle";

    var doc: XMLDocument;
    do {
        let options: XMLNode.Options = [
            XMLNode.Options.nodeLoadExternalEntitiesNever,
            XMLNode.Options.nodePreserveCDATA,
            XMLNode.Options.nodePreserveWhitespace,
        ];
        doc = try XMLDocument(contentsOf: appcastDestPath, options: Int(options.rawValue));
    } catch {
        let root = XMLElement(name: "rss");
        root.addAttribute(XMLNode.attribute(withName: "xmlns:sparkle", stringValue: sparkleNS) as! XMLNode);
        root.addAttribute(XMLNode.attribute(withName: "version", stringValue: "2.0") as! XMLNode);
        doc = XMLDocument(rootElement: root);
        doc.isStandalone = true;
    }

    var channel: XMLElement;

    let rootNodes = try doc.nodes(forXPath: "/rss");
    if rootNodes.count != 1 {
        throw makeError(code: .appcastError, "Weird XML? \(appcastDestPath.path)");
    }
    let root = rootNodes[0] as! XMLElement
    let channelNodes = try root.nodes(forXPath: "channel");
    if channelNodes.count > 0 {
        channel = channelNodes[0] as! XMLElement;
    } else {
        channel = XMLElement(name: "channel");
        linebreak(channel);
        channel.addChild(XMLElement.element(withName: "title", stringValue: appBaseName) as! XMLElement);
        linebreak(root);
        root.addChild(channel);
    }

    var numItems = 0;
    for update in updates {
        var item: XMLElement;
        let existingItems = try channel.nodes(forXPath: "item[enclosure[@sparkle:version=\"\(update.version)\"]]");
        let createNewItem = existingItems.count == 0;

        // Update all old items, but aim for less than 5 in new feeds
        if createNewItem && numItems >= maxVersionsInFeed {
            continue;
        }
        numItems += 1;

        if createNewItem {
            item = XMLElement.element(withName: "item") as! XMLElement;
            linebreak(channel);
            channel.addChild(item);
        } else {
            item = existingItems[0] as! XMLElement;
        }

        if nil == findElement(name: "title", parent: item) {
            linebreak(item);
            item.addChild(XMLElement.element(withName: "title", stringValue: update.shortVersion) as! XMLElement);
        }
        if nil == findElement(name: "pubDate", parent: item) {
            linebreak(item);
            item.addChild(XMLElement.element(withName: "pubDate", stringValue: update.pubDate) as! XMLElement);
        }

        if let html = update.releaseNotesHTML {
            let descElement = findOrCreateElement(name: "description", parent: item);
            let cdata = XMLNode(kind:.text, options:.nodeIsCDATA);
            cdata.stringValue = html;
            descElement.setChildren([cdata]);
        }

        var minVer = findElement(name: "sparkle:minimumSystemVersion", parent: item);
        if nil == minVer {
            minVer = XMLElement.element(withName: "sparkle:minimumSystemVersion", uri: sparkleNS) as? XMLElement;
            linebreak(item);
            item.addChild(minVer!);
        }
        minVer?.setChildren([text(update.minimumSystemVersion)]);

        let relElement = findElement(name: "sparkle:releaseNotesLink", parent: item);
        if let url = update.releaseNotesURL {
            if nil == relElement {
                linebreak(item);
                item.addChild(XMLElement.element(withName:"sparkle:releaseNotesLink", stringValue: url.absoluteString) as! XMLElement);
            }
        } else if let childIndex = relElement?.index {
            item.removeChild(at: childIndex);
        }
        
        var enclosure = findElement(name: "enclosure", parent: item);
        if nil == enclosure {
            enclosure = XMLElement.element(withName: "enclosure") as? XMLElement;
            linebreak(item);
            item.addChild(enclosure!);
        }

        guard let archiveURL = update.archiveURL?.absoluteString else {
            throw makeError(code: .appcastError, "Bad archive name or feed URL");
        };
        var attributes = [
            XMLNode.attribute(withName: "url", stringValue: archiveURL) as! XMLNode,
            XMLNode.attribute(withName: "sparkle:version", uri: sparkleNS, stringValue: update.version) as! XMLNode,
            XMLNode.attribute(withName: "sparkle:shortVersionString", uri: sparkleNS, stringValue: update.shortVersion) as! XMLNode,
            XMLNode.attribute(withName: "length", stringValue: String(update.fileSize)) as! XMLNode,
            XMLNode.attribute(withName: "type", stringValue: update.mimeType) as! XMLNode,
        ];
        if let sig = update.dsaSignature {
            attributes.append(XMLNode.attribute(withName: "sparkle:dsaSignature", uri: sparkleNS, stringValue: sig) as! XMLNode);
        }
        enclosure!.attributes = attributes;

        if update.deltas.count > 0 {
            var deltas = findElement(name: "sparkle:deltas", parent: item);
            if nil == deltas {
                deltas = XMLElement.element(withName: "sparkle:deltas", uri: sparkleNS) as? XMLElement;
                linebreak(item);
                item.addChild(deltas!);
            } else {
                deltas!.setChildren([]);
            }
            for delta in update.deltas {
                var attributes = [
                    XMLNode.attribute(withName: "url", stringValue: URL(string: delta.archivePath.lastPathComponent.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)!, relativeTo: update.archiveURL)!.absoluteString) as! XMLNode,
                    XMLNode.attribute(withName: "sparkle:version", uri: sparkleNS, stringValue: update.version) as! XMLNode,
                    XMLNode.attribute(withName: "sparkle:shortVersionString", uri: sparkleNS, stringValue: update.shortVersion) as! XMLNode,
                    XMLNode.attribute(withName: "sparkle:deltaFrom", uri: sparkleNS, stringValue: delta.fromVersion) as! XMLNode,
                    XMLNode.attribute(withName: "length", stringValue: String(delta.fileSize)) as! XMLNode,
                    XMLNode.attribute(withName: "type", stringValue: "application/octet-stream") as! XMLNode,
                    ];
                if let sig = delta.dsaSignature {
                    attributes.append(XMLNode.attribute(withName: "sparkle:dsaSignature", uri: sparkleNS, stringValue: sig) as! XMLNode);
                }
                linebreak(deltas!);
                deltas!.addChild(XMLNode.element(withName: "enclosure", children: nil, attributes: attributes) as! XMLElement);
            }
        }
        if createNewItem {
            linebreak(item);
            linebreak(channel);
        }
    }

    let options = XMLNode.Options.nodeCompactEmptyElement;
    let docData = doc.xmlData(withOptions:Int(options.rawValue));
    let _ = try XMLDocument(data: docData, options:0); // Verify that it was generated correctly, which does not always happen!
    try docData.write(to: appcastDestPath);
}
