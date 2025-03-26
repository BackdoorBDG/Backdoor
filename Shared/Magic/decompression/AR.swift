//
//  AR.swift
//  feather
//
//  Created by samara on 8/18/24.
//

import Foundation

public struct ARFile {
	var name: String
	var modificationDate: Date
	var ownerId: Int
	var groupId: Int
	var mode: Int
	var size: Int
	var content: Data
}

func removePadding(_ paddedString: String) -> String {
    guard let data = paddedString.data(using: .utf8) else {
        return paddedString
    }
        
    guard let firstNonSpaceIndex = data.firstIndex(of: UInt8(ascii: " ")) else {
        return paddedString
    }
    
    let actualData = data[..<firstNonSpaceIndex]
    return String(data: actualData, encoding: .utf8) ?? paddedString
}

enum ARError: Error {
    case badArchive(String)
    case invalidEncoding(String)
    case invalidInteger(String)
}

func getFileInfo(_ data: Data, _ offset: Int) throws -> ARFile {
    // Safely extract and parse size
    guard let sizeString = String(data: data.subdata(in: offset+48..<offset+48+10), encoding: .ascii) else {
        throw ARError.invalidEncoding("Could not decode size field")
    }
    
    let sizeStr = removePadding(sizeString)
    guard let size = Int(sizeStr) else {
        throw ARError.invalidInteger("Size is not a valid integer: \(sizeStr)")
    }
    
    if size < 1 {
        throw ARError.badArchive("Invalid size")
    }
    
    // Safely extract and parse name
    guard let nameString = String(data: data.subdata(in: offset..<offset+16), encoding: .ascii) else {
        throw ARError.invalidEncoding("Could not decode name field")
    }
    
    let name = removePadding(nameString)
    guard !name.isEmpty else {
        throw ARError.badArchive("Invalid name")
    }
    
    // Safely extract modification date
    guard let modDateString = String(data: data.subdata(in: offset+16..<offset+16+12), encoding: .ascii) else {
        throw ARError.invalidEncoding("Could not decode modification date field")
    }
    
    guard let modDateVal = Double(removePadding(modDateString)) else {
        throw ARError.invalidInteger("Modification date is not a valid number")
    }
    
    let modificationDate = Date(timeIntervalSince1970: modDateVal)
    
    // Safely extract owner ID
    guard let ownerIdString = String(data: data.subdata(in: offset+28..<offset+28+6), encoding: .ascii) else {
        throw ARError.invalidEncoding("Could not decode owner ID field")
    }
    
    guard let ownerId = Int(removePadding(ownerIdString)) else {
        throw ARError.invalidInteger("Owner ID is not a valid integer")
    }
    
    // Safely extract group ID
    guard let groupIdString = String(data: data.subdata(in: offset+34..<offset+34+6), encoding: .ascii) else {
        throw ARError.invalidEncoding("Could not decode group ID field")
    }
    
    guard let groupId = Int(removePadding(groupIdString)) else {
        throw ARError.invalidInteger("Group ID is not a valid integer")
    }
    
    // Safely extract mode
    guard let modeString = String(data: data.subdata(in: offset+40..<offset+40+8), encoding: .ascii) else {
        throw ARError.invalidEncoding("Could not decode mode field")
    }
    
    guard let mode = Int(removePadding(modeString)) else {
        throw ARError.invalidInteger("Mode is not a valid integer")
    }
    
    // Create file info
    return ARFile(
        name: name,
        modificationDate: modificationDate,
        ownerId: ownerId,
        groupId: groupId,
        mode: mode,
        size: size,
        content: data.subdata(in: offset+60..<offset+60+size)
    )
}

public func extractAR(_ rawData: Data) throws -> [ARFile] {
    guard rawData.count >= 8 else {
        throw ARError.badArchive("Data too short")
    }
    
    let magicBytes: [UInt8] = [0x21, 0x3c, 0x61, 0x72, 0x63, 0x68, 0x3e, 0x0a]
    let header = Array(rawData.prefix(8))
    
    guard header == magicBytes else {
        throw ARError.badArchive("Invalid magic")
    }

    let data = rawData.subdata(in: 8..<rawData.endIndex)
    
    var offset = 0
    var files: [ARFile] = []
    while offset < data.count {
        let fileInfo = try getFileInfo(data, offset)
        files.append(fileInfo)
        offset += fileInfo.size + 60
        offset += offset % 2
    }
    return files
}