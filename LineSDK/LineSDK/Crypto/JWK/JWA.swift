//
//  JWA.swift
//
//  Copyright (c) 2016-present, LINE Corporation. All rights reserved.
//
//  You are hereby granted a non-exclusive, worldwide, royalty-free license to use,
//  copy and distribute this software in source code or binary form for use
//  in connection with the web services and APIs provided by LINE Corporation.
//
//  As with any software that integrates with the LINE Corporation platform, your use of this software
//  is subject to the LINE Developers Agreement [http://terms2.line.me/LINE_Developers_Agreement].
//  This copyright notice shall be included in all copies or substantial portions of the software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation

// A partitial implementation for JSON Web Algorithms (JWA) RFC 7518
// Only RSA related algorithms are required for LineSDK, ref:  https://tools.ietf.org/html/rfc7518
struct JWA {
    enum Algorithm: String, Decodable {
        case RS256
        case RS384
        case RS512
        
        var rsaAlgorithm: RSA.Algorithm {
            switch self {
            case .RS256: return .sha256
            case .RS384: return .sha384
            case .RS512: return .sha512
            }
        }
    }
}

extension JWA {
    // A wrapper (container) for parameters for a certain key type.
    // If we need to support other types of signing key, we should add it here.
    enum KeyParameters: Decodable {
        
        enum CodingKeys: String, CodingKey {
            case keyType = "kty"
        }
        
        case rsa(RSAParameters)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let keyType = try container.decode(JWK.KeyType.self, forKey: .keyType)
            switch keyType {
            case .rsa:
                self = .rsa(try RSAParameters(from: decoder))
            }
        }
        
        var asRSA: RSAParameters? {
            if case .rsa(let parameters) = self { return parameters }
            return nil
        }
    }
}

extension JWA {
    
    struct RSAParameters: Decodable {
        // Private RSA key is not used in LineSDK, so we only support public key for now.
        let modulus: String
        let exponent: String
        
        enum CodingKeys: String, CodingKey {
            case modulus = "n"
            case exponent = "e"
        }
        
        // Get public key DER data from modulus and exponent.
        // It follows the ASN.1 encoding to create data under distinguished encoding rules.
        func getKeyData() throws -> Data {
            
            guard let decodedModulusData = modulus.base64URLDecoded else {
                throw CryptoError.generalError(reason: .base64ConversionFailed(string: modulus))
            }
            guard let decodedExponentData = exponent.base64URLDecoded else {
                throw CryptoError.generalError(reason: .base64ConversionFailed(string: exponent))
            }
            
            var modulusBytes = [UInt8](decodedModulusData)
            
            // Make sure the modulusBytes starts with 0x00. If not, append it.
            if let firstByte = modulusBytes.first, firstByte != 0x00 {
                modulusBytes.insert(0x00, at: 0)
            }
            
            let modulusEncoded = modulusBytes.encode(as: .integer)
            
            let exponentBytes = [UInt8](decodedExponentData)
            let exponentEncoded = exponentBytes.encode(as: .integer)
            
            let sequenceEncoded = (modulusEncoded + exponentEncoded).encode(as: .sequence)
            
            return Data(bytes: sequenceEncoded)
        }
    }
}

// MARK: Array Extension for Encoding
// Inspired by: https://github.com/henrinormak/Heimdall/blob/master/Heimdall/Heimdall.swift
extension Array where Element == UInt8 {
    
    func encode(as type: ASN1Type) -> [UInt8] {
        var tlvTriplet: [UInt8] = []
        tlvTriplet.append(type.byte)
        tlvTriplet.append(contentsOf: lengthField(of: self))
        tlvTriplet.append(contentsOf: self)
        
        return tlvTriplet
    }
    
}

// MARK: Freestanding Helper Function
private func lengthField(of valueField: [UInt8]) -> [UInt8] {
    var count = valueField.count
    
    if count < 128 {
        return [ UInt8(count) ]
    }
    
    // The number of bytes needed to encode count.
    let lengthBytesCount = Int((log2(Double(count)) / 8) + 1)
    
    // The first byte in the length field encoding the number of remaining bytes.
    let firstLengthFieldByte = UInt8(128 + lengthBytesCount)
    
    var lengthField: [UInt8] = []
    for _ in 0..<lengthBytesCount {
        // Take the last 8 bits of count.
        let lengthByte = UInt8(count & 0xff)
        // Add them to the length field.
        lengthField.insert(lengthByte, at: 0)
        // Delete the last 8 bits of count.
        count = count >> 8
    }
    
    // Include the first byte.
    lengthField.insert(firstLengthFieldByte, at: 0)
    
    return lengthField
}