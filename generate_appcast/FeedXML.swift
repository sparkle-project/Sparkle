//
//  Created by Kornel on 22/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

func findElement(name: String, parent: XMLElement) -> XMLElement? {
    if let found = try? parent.nodes(forXPath: name) {
        if found.count > 0 {
            if let element = found[0] as? XMLElement {
                return element
            }
        }
    }
    return nil
}

func createElement(name: String, parent: XMLElement) -> XMLElement {
    let element = XMLElement(name: name)
    parent.addChild(element)
    return element
}

func findOrCreateElement(name: String, parent: XMLElement) -> XMLElement {
    if let element = findElement(name: name, parent: parent) {
        return element
    }
    return createElement(name: name, parent: parent)
}

func text(_ text: String) -> XMLNode {
    return XMLNode.text(withStringValue: text) as! XMLNode
}

func extractVersion(parent: XMLNode) -> String? {
    guard let itemElement = parent as? XMLElement else {
        return nil
    }
    
    // Look for version attribute in enclosure
    if let enclosure = findElement(name: "enclosure", parent: itemElement) {
        if let versionAttribute = enclosure.attribute(forName: SUAppcastAttributeVersion) {
            return versionAttribute.stringValue
        }
    }

    // Look for top level version element
    if let versionElement = findElement(name: SUAppcastElementVersion, parent: itemElement) {
        return versionElement.stringValue
    }

    return nil
}

func readAppcast(archives: [String: ArchiveItem], appcastURL: URL) throws -> [String: UpdateBranch] {
    let options: XMLNode.Options = [
        XMLNode.Options.nodeLoadExternalEntitiesNever,
        XMLNode.Options.nodePreserveCDATA,
        XMLNode.Options.nodePreserveWhitespace,
    ]
    let doc = try XMLDocument(contentsOf: appcastURL, options: options)
    
    let rootNodes = try doc.nodes(forXPath: "/rss")
    if rootNodes.count != 1 {
        throw makeError(code: .appcastError, "Weird XML? \(appcastURL.path)")
    }
    
    let root = rootNodes[0] as! XMLElement
    
    let channelNodes = try root.nodes(forXPath: "channel")
    if channelNodes.count == 0 {
        throw makeError(code: .appcastError, "Weird Feed? No channels: \(appcastURL.path)")
    }
    
    let channel = channelNodes[0] as! XMLElement
    
    guard let itemNodes = try? channel.nodes(forXPath: "item") else {
        return [:]
    }
    
    var updateBranches: [String: UpdateBranch] = [:]
    for item in itemNodes {
        guard let item = item as? XMLElement else {
            continue
        }
        
        let version: String?
        if let versionElement = findElement(name: SUAppcastElementVersion, parent: item) {
            version = versionElement.stringValue
        } else if let enclosure = findElement(name: "enclosure", parent: item), let versionAttribute = enclosure.attribute(forName: SUAppcastAttributeVersion) {
            version = versionAttribute.stringValue
        } else {
            version = nil
        }
        
        guard let version = version else {
            continue
        }
        
        let minimumSystemVersion: String?
        if let minVer = findElement(name: SUAppcastElementMinimumSystemVersion, parent: item) {
            minimumSystemVersion = minVer.stringValue
        } else if let archive = archives[version] {
            minimumSystemVersion = archive.minimumSystemVersion
        } else {
            minimumSystemVersion = nil
        }
        
        let maximumSystemVersion: String?
        if let maxVer = findElement(name: SUAppcastElementMaximumSystemVersion, parent: item) {
            maximumSystemVersion = maxVer.stringValue
        } else {
            maximumSystemVersion = nil
        }
        
        let minimumAutoupdateVersion: String?
        if let minimumAutoupdateVersionElement = findElement(name: SUAppcastElementMinimumAutoupdateVersion, parent: item) {
            minimumAutoupdateVersion = minimumAutoupdateVersionElement.stringValue
        } else {
            minimumAutoupdateVersion = nil
        }
        
        let sparkleChannel: String?
        if let sparkleChannelElement = findElement(name: SUAppcastElementChannel, parent: item) {
            sparkleChannel = sparkleChannelElement.stringValue
        } else {
            sparkleChannel = nil
        }
        
        let updateBranch = UpdateBranch(minimumSystemVersion: minimumSystemVersion, maximumSystemVersion: maximumSystemVersion, minimumAutoupdateVersion: minimumAutoupdateVersion, channel: sparkleChannel)
        
        updateBranches[version] = updateBranch
    }
    
    return updateBranches
}

func writeAppcast(appcastDestPath: URL, appcast: Appcast, fullReleaseNotesLink: String?, preferToEmbedReleaseNotes: Bool, link: String?, newChannel: String?, majorVersion: String?, ignoreSkippedUpgradesBelowVersion: String?, phasedRolloutInterval: Int?, criticalUpdateVersion: String?, informationalUpdateVersions: [String]?) throws -> (numNewUpdates: Int, numExistingUpdates: Int, numUpdatesRemoved: Int) {
    let appBaseName = appcast.inferredAppName

    let sparkleNS = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    var doc: XMLDocument
    do {
        let options: XMLNode.Options = [
            XMLNode.Options.nodeLoadExternalEntitiesNever,
            XMLNode.Options.nodePreserveCDATA,
            XMLNode.Options.nodePreserveWhitespace,
        ]
        doc = try XMLDocument(contentsOf: appcastDestPath, options: options)
    } catch {
        let root = XMLElement(name: "rss")
        root.addAttribute(XMLNode.attribute(withName: "xmlns:sparkle", stringValue: sparkleNS) as! XMLNode)
        root.addAttribute(XMLNode.attribute(withName: "version", stringValue: "2.0") as! XMLNode)
        doc = XMLDocument(rootElement: root)
        doc.isStandalone = true
    }

    var channel: XMLElement

    let rootNodes = try doc.nodes(forXPath: "/rss")
    if rootNodes.count != 1 {
        throw makeError(code: .appcastError, "Weird XML? \(appcastDestPath.path)")
    }
    let root = rootNodes[0] as! XMLElement
    let channelNodes = try root.nodes(forXPath: "channel")
    var numUpdatesRemoved: Int = 0
    
    if channelNodes.count > 0 {
        channel = channelNodes[0] as! XMLElement
        
        // Enumerate through all existing update items and remove any that we aren't going to keep
        let versionsInFeedSet = Set(appcast.versionsInFeed)
        var nodesToRemove: [XMLElement] = []
        if let itemNodes = try? channel.nodes(forXPath: "item") {
            for item in itemNodes {
                guard let item = item as? XMLElement else {
                    continue
                }
                
                let version: String?
                if let versionElement = findElement(name: SUAppcastElementVersion, parent: item) {
                    version = versionElement.stringValue
                } else if let enclosure = findElement(name: "enclosure", parent: item), let versionAttribute = enclosure.attribute(forName: SUAppcastAttributeVersion) {
                    version = versionAttribute.stringValue
                } else {
                    version = nil
                }
                
                guard let version = version else {
                    continue
                }
                
                if !versionsInFeedSet.contains(version) {
                    nodesToRemove.append(item)
                }
            }
            
            // Remove old nodes from highest-to-lowest index order
            for node in nodesToRemove.reversed() {
                channel.removeChild(at: node.index)
            }
            
            numUpdatesRemoved = nodesToRemove.count
        }
    } else {
        channel = XMLElement(name: "channel")
        channel.addChild(XMLElement.element(withName: "title", stringValue: appBaseName) as! XMLElement)
        root.addChild(channel)
    }
    
    var numNewUpdates = 0
    var numExistingUpdates = 0
    
    let versionComparator = SUStandardVersionComparator()

    var numItems = 0
    for version in appcast.versionsInFeed {
        guard let update = appcast.archives[version] else {
            continue
        }
        
        var item: XMLElement
        
        var existingItems = try channel.nodes(forXPath: "item[enclosure[@\(SUAppcastAttributeVersion)=\"\(update.version)\"]]")
        if existingItems.count == 0 {
            // Fall back to see if any items are using the element version variant
            existingItems = try channel.nodes(forXPath: "item[\(SUAppcastElementVersion)=\"\(update.version)\"]")
        }
        
        let createNewItem = (existingItems.count == 0)
        
        if createNewItem {
            numNewUpdates += 1
        } else {
            numExistingUpdates += 1
        }
        numItems += 1

        if createNewItem {
            item = XMLElement.element(withName: "item") as! XMLElement
            
            // When we insert a new item, find the best place to insert the new update item in
            // This takes account of existing items and even ones that we don't have existing info on
            var foundBestUpdateInsertion = false
            if let itemNodes = try? channel.nodes(forXPath: "item") {
                for childItemNode in itemNodes {
                    guard let childItemNode = childItemNode as? XMLElement else {
                        continue
                    }
                    
                    guard let childItemVersion = extractVersion(parent: childItemNode) else {
                        continue
                    }

                    if versionComparator.compareVersion(update.version, toVersion: childItemVersion) == .orderedDescending {
                        channel.insertChild(item, at: childItemNode.index)
                        foundBestUpdateInsertion = true
                        break
                    }
                }
            }

            if !foundBestUpdateInsertion {
                channel.addChild(item)
            }
        } else {
            item = existingItems[0] as! XMLElement
        }

        if nil == findElement(name: "title", parent: item) {
            item.addChild(XMLElement.element(withName: "title", stringValue: update.shortVersion) as! XMLElement)
        }
        if nil == findElement(name: "pubDate", parent: item) {
            item.addChild(XMLElement.element(withName: "pubDate", stringValue: update.pubDate) as! XMLElement)
        }
        
        if createNewItem {
            // Set link
            if let link = link,
               let linkElement = XMLElement.element(withName: SURSSElementLink, uri: sparkleNS) as? XMLElement {
                linkElement.setChildren([text(link)])
                item.addChild(linkElement)
            }
            
            if let fullReleaseNotesLink = fullReleaseNotesLink,
               let fullReleaseNotesElement = XMLElement.element(withName: SUAppcastElementFullReleaseNotesLink, uri: sparkleNS) as? XMLElement {
                fullReleaseNotesElement.setChildren([text(fullReleaseNotesLink)])
                item.addChild(fullReleaseNotesElement)
            }
            
            // Set new channel name
            if let newChannelName = newChannel,
               let channelNameElement = XMLElement.element(withName: SUAppcastElementChannel, uri: sparkleNS) as? XMLElement {
                channelNameElement.setChildren([text(newChannelName)])
                item.addChild(channelNameElement)
            }
            
            // Set last major version
            if let minimumAutoupdateVersion = majorVersion,
               let minimumAutoupdateVersionElement = XMLElement.element(withName: SUAppcastElementMinimumAutoupdateVersion, uri: sparkleNS) as? XMLElement {
                minimumAutoupdateVersionElement.setChildren([text(minimumAutoupdateVersion)])
                item.addChild(minimumAutoupdateVersionElement)
            }
            
            // Set ignore skipped upgrades below version
            if let ignoreSkippedUpgradesBelowVersion = ignoreSkippedUpgradesBelowVersion, let ignoreSkippedUpgradesBelowVersionElement = XMLElement.element(withName: SUAppcastElementIgnoreSkippedUpgradesBelowVersion, uri: sparkleNS) as? XMLElement {
                ignoreSkippedUpgradesBelowVersionElement.setChildren([text(ignoreSkippedUpgradesBelowVersion)])
                item.addChild(ignoreSkippedUpgradesBelowVersionElement)
            }
            
            // Set phased rollout interval
            if let phasedRolloutInterval = phasedRolloutInterval,
               let phasedRolloutIntervalElement = XMLElement.element(withName: SUAppcastElementPhasedRolloutInterval, uri: sparkleNS) as? XMLElement {
                phasedRolloutIntervalElement.setChildren([text(String(phasedRolloutInterval))])
                item.addChild(phasedRolloutIntervalElement)
            }
            
            // Set last critical update version
            if let criticalUpdateVersion = criticalUpdateVersion,
               let criticalUpdateElement = XMLElement.element(withName: SUAppcastElementCriticalUpdate, uri: sparkleNS) as? XMLElement {
                if criticalUpdateVersion.count > 0 {
                    criticalUpdateElement.setAttributesWith([SUAppcastAttributeVersion: criticalUpdateVersion])
                }
                item.addChild(criticalUpdateElement)
            }
            
            // Set informational update versions
            if let informationalUpdateVersions = informationalUpdateVersions,
               let informationalUpdateElement = XMLElement.element(withName: SUAppcastElementInformationalUpdate, uri: sparkleNS) as? XMLElement {
                let versionElements: [XMLElement] = informationalUpdateVersions.compactMap({ informationalUpdateVersion in
                    let element: XMLElement?
                    let informationalVersionText: String
                    if informationalUpdateVersion.hasPrefix("<") {
                        element = XMLElement.element(withName: SUAppcastElementBelowVersion, uri: sparkleNS) as? XMLElement
                        informationalVersionText = String(informationalUpdateVersion.dropFirst())
                    } else {
                        element = XMLElement.element(withName: SUAppcastElementVersion, uri: sparkleNS) as? XMLElement
                        informationalVersionText = informationalUpdateVersion
                    }
                    
                    element?.setChildren([text(informationalVersionText)])
                    return element
                })
                
                informationalUpdateElement.setChildren(versionElements)
                item.addChild(informationalUpdateElement)
            }
        }
        
        var versionElement = findElement(name: SUAppcastElementVersion, parent: item)
        if nil == versionElement {
            versionElement = XMLElement.element(withName: SUAppcastElementVersion, uri: sparkleNS) as? XMLElement
            item.addChild(versionElement!)
        }
        versionElement?.setChildren([text(update.version)])
        
        var shortVersionElement = findElement(name: SUAppcastElementShortVersionString, parent: item)
        if nil == shortVersionElement {
            shortVersionElement = XMLElement.element(withName: SUAppcastElementShortVersionString, uri: sparkleNS) as? XMLElement
            item.addChild(shortVersionElement!)
        }
        shortVersionElement?.setChildren([text(update.shortVersion)])
        
        // Override the minimum system version with the version from the archive,
        // only if an existing item doesn't specify one
        let minimumSystemVersion: String
        var minVer = findElement(name: SUAppcastElementMinimumSystemVersion, parent: item)
        if let minVer = minVer {
            minimumSystemVersion = minVer.stringValue ?? update.minimumSystemVersion
        } else {
            minVer = XMLElement.element(withName: SUAppcastElementMinimumSystemVersion, uri: sparkleNS) as? XMLElement
            item.addChild(minVer!)
            
            minimumSystemVersion = update.minimumSystemVersion
        }
        minVer?.setChildren([text(minimumSystemVersion)])
        
        // Look for an existing release notes element
        let releaseNotesXpath = "\(SUAppcastElementReleaseNotesLink)"
        let results = ((try? item.nodes(forXPath: releaseNotesXpath)) as? [XMLElement])?
            .filter { !($0.attributes ?? [])
            .contains(where: { $0.name == SUXMLLanguage }) }
        let relElement = results?.first
        
        // If an existing item has a release notes item, don't automatically embed release notes even if the user
        // prefers to embed release notes (we only respect this choice for updates without a release notes item or a new item)
        let embedReleaseNotesAlways = preferToEmbedReleaseNotes && (relElement == nil)
        if let (descriptionContents, descriptionFormat) = update.releaseNotesContent(embedReleaseNotesAlways: embedReleaseNotesAlways) {
            let descElement = findOrCreateElement(name: "description", parent: item)
            let cdata = XMLNode(kind: .text, options: .nodeIsCDATA)
            cdata.stringValue = descriptionContents
            descElement.setChildren([cdata])
            if descriptionFormat != "html" {
                descElement.addAttribute(XMLNode.attribute(withName: SUAppcastAttributeFormat, stringValue: descriptionFormat) as! XMLNode)
            }
        } else if let existingDescriptionElement = findElement(name: "description", parent: item) {
            // The update doesn't include embedded release notes. Remove it.
            item.removeChild(at: existingDescriptionElement.index)
        }
        
        if let url = update.releaseNotesURL(embedReleaseNotesAlways: embedReleaseNotesAlways) {
            // The update includes a valid release notes URL
            if let existingReleaseNotesElement = relElement {
                // The existing item includes a release notes element. Update it.
                existingReleaseNotesElement.stringValue = url.absoluteString
            } else {
                // The existing item doesn't have a release notes element. Add one.
                item.addChild(XMLElement.element(withName: SUAppcastElementReleaseNotesLink, stringValue: url.absoluteString) as! XMLElement)
            }
        } else if let childIndex = relElement?.index {
            // The update doesn't include a release notes URL. Remove it.
            item.removeChild(at: childIndex)
        }

        let languageNotesNodes = ((try? item.nodes(forXPath: releaseNotesXpath)) as? [XMLElement])?
            .map { ($0, $0.attribute(forName: SUXMLLanguage)?.stringValue )}
            .filter { $0.1 != nil } ?? []
        for (node, language) in languageNotesNodes.reversed()
            where !update.localizedReleaseNotes().contains(where: { $0.0 == language }) {
            item.removeChild(at: node.index)
        }
        for (language, url) in update.localizedReleaseNotes() {
            if !languageNotesNodes.contains(where: { $0.1 == language }) {
                let localizedNode = XMLNode.element(
                    withName: SUAppcastElementReleaseNotesLink,
                    children: [XMLNode.text(withStringValue: url.absoluteString) as! XMLNode],
                    attributes: [XMLNode.attribute(withName: SUXMLLanguage, stringValue: language) as! XMLNode])
                item.addChild(localizedNode as! XMLNode)
            }
        }

        var enclosure = findElement(name: "enclosure", parent: item)
        if nil == enclosure {
            enclosure = XMLElement.element(withName: "enclosure") as? XMLElement
            item.addChild(enclosure!)
        }

        guard let archiveURL = update.archiveURL?.absoluteString else {
            throw makeError(code: .appcastError, "Bad archive name or feed URL")
        }
        var attributes = [
            XMLNode.attribute(withName: "url", stringValue: archiveURL) as! XMLNode,
            XMLNode.attribute(withName: "length", stringValue: String(update.fileSize)) as! XMLNode,
            XMLNode.attribute(withName: "type", stringValue: update.mimeType) as! XMLNode,
        ]
        if let sig = update.edSignature {
            attributes.append(XMLNode.attribute(withName: SUAppcastAttributeEDSignature, uri: sparkleNS, stringValue: sig) as! XMLNode)
        }
#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
        if let sig = update.dsaSignature {
            attributes.append(XMLNode.attribute(withName: SUAppcastAttributeDSASignature, uri: sparkleNS, stringValue: sig) as! XMLNode)
        }
#endif
        enclosure!.attributes = attributes

        if update.deltas.count > 0 {
            var deltas = findElement(name: SUAppcastElementDeltas, parent: item)
            if nil == deltas {
                deltas = XMLElement.element(withName: SUAppcastElementDeltas, uri: sparkleNS) as? XMLElement
                item.addChild(deltas!)
            } else {
                deltas!.setChildren([])
            }
            for delta in update.deltas {
                var attributes = [
                    XMLNode.attribute(withName: "url", stringValue: URL(string: delta.archivePath.lastPathComponent.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)!, relativeTo: update.archiveURL)!.absoluteString) as! XMLNode,
                    XMLNode.attribute(withName: SUAppcastAttributeDeltaFrom, uri: sparkleNS, stringValue: delta.fromVersion) as! XMLNode,
                    XMLNode.attribute(withName: "length", stringValue: String(delta.fileSize)) as! XMLNode,
                    XMLNode.attribute(withName: "type", stringValue: "application/octet-stream") as! XMLNode,
                    ]
                
                if let sparkleExecutableFileSize = delta.sparkleExecutableFileSize {
                    attributes.append(XMLNode.attribute(withName: SUAppcastAttributeDeltaFromSparkleExecutableSize, stringValue: String(sparkleExecutableFileSize)) as! XMLNode)
                }
                
                if let sparkleLocales = delta.sparkleLocales {
                    attributes.append(XMLNode.attribute(withName: SUAppcastAttributeDeltaFromSparkleLocales, stringValue: sparkleLocales) as! XMLNode)
                }
                
                if let sig = delta.edSignature {
                    attributes.append(XMLNode.attribute(withName: SUAppcastAttributeEDSignature, uri: sparkleNS, stringValue: sig) as! XMLNode)
                }
#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
                if let sig = delta.dsaSignature {
                    attributes.append(XMLNode.attribute(withName: SUAppcastAttributeDSASignature, uri: sparkleNS, stringValue: sig) as! XMLNode)
                }
#endif
                deltas!.addChild(XMLNode.element(withName: "enclosure", children: nil, attributes: attributes) as! XMLElement)
            }
        }
    }

    let options: XMLNode.Options = [.nodeCompactEmptyElement, .nodePrettyPrint]
    let docData = doc.xmlData(options: options)
    _ = try XMLDocument(data: docData, options: XMLNode.Options()); // Verify that it was generated correctly, which does not always happen!
    try docData.write(to: appcastDestPath)
    
    return (numNewUpdates, numExistingUpdates, numUpdatesRemoved)
}
