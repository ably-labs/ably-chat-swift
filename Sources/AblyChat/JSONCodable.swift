internal protocol JSONEncodable {
    var toJSONValue: JSONValue { get }
}

internal protocol JSONDecodable {
    init(jsonValue: JSONValue) throws
}

internal typealias JSONCodable = JSONDecodable & JSONEncodable

internal protocol JSONObjectEncodable: JSONEncodable {
    var toJSONObject: [String: JSONValue] { get }
}

// Default implementation of `JSONEncodable` conformance for `JSONObjectEncodable`
internal extension JSONObjectEncodable {
    var toJSONValue: JSONValue {
        .object(toJSONObject)
    }
}

internal protocol JSONObjectDecodable: JSONDecodable {
    init(jsonObject: [String: JSONValue]) throws
}

internal enum JSONValueDecodingError: Error {
    case valueIsNotObject
    case noValueForKey(String)
    case wrongTypeForKey(String, actualValue: JSONValue)
}

// Default implementation of `JSONDecodable` conformance for `JSONObjectDecodable`
internal extension JSONObjectDecodable {
    init(jsonValue: JSONValue) throws {
        guard case let .object(jsonObject) = jsonValue else {
            throw JSONValueDecodingError.valueIsNotObject
        }

        self = try .init(jsonObject: jsonObject)
    }
}

internal typealias JSONObjectCodable = JSONObjectDecodable & JSONObjectEncodable

// MARK: - Extracting values from a dictionary

/// This extension adds some helper methods for extracting values from a dictionary of `JSONValue` values; you may find them helpful when implementing `JSONCodable`.
internal extension [String: JSONValue] {
    /// If this dictionary contains a value for `key`, and this value has case `object`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `JSONValueDecodingError.noValueForKey` if the key is absent
    ///   - `JSONValueDecodingError.wrongTypeForKey` if the value does not have case `object`
    func objectValueForKey(_ key: String) throws -> [String: JSONValue] {
        guard let value = self[key] else {
            throw JSONValueDecodingError.noValueForKey(key)
        }

        guard case let .object(objectValue) = value else {
            throw JSONValueDecodingError.wrongTypeForKey(key, actualValue: value)
        }

        return objectValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `object`, this returns the associated value. If this dictionary does not contain a value for `key`, or if the value for key has case `null`, it returns `nil`.
    ///
    /// - Throws: `JSONValueDecodingError.wrongTypeForKey` if the value does not have case `object` or `null`
    func optionalObjectValueForKey(_ key: String) throws -> [String: JSONValue]? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .object(objectValue) = value else {
            throw JSONValueDecodingError.wrongTypeForKey(key, actualValue: value)
        }

        return objectValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `array`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `JSONValueDecodingError.noValueForKey` if the key is absent
    ///   - `JSONValueDecodingError.wrongTypeForKey` if the value does not have case `array`
    func arrayValueForKey(_ key: String) throws -> [JSONValue] {
        guard let value = self[key] else {
            throw JSONValueDecodingError.noValueForKey(key)
        }

        guard case let .array(arrayValue) = value else {
            throw JSONValueDecodingError.wrongTypeForKey(key, actualValue: value)
        }

        return arrayValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `array`, this returns the associated value. If this dictionary does not contain a value for `key`, or if the value for key has case `null`, it returns `nil`.
    ///
    /// - Throws: `JSONValueDecodingError.wrongTypeForKey` if the value does not have case `array` or `null`
    func optionalArrayValueForKey(_ key: String) throws -> [JSONValue]? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .array(arrayValue) = value else {
            throw JSONValueDecodingError.wrongTypeForKey(key, actualValue: value)
        }

        return arrayValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `string`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `JSONValueDecodingError.noValueForKey` if the key is absent
    ///   - `JSONValueDecodingError.wrongTypeForKey` if the value does not have case `string`
    func stringValueForKey(_ key: String) throws -> String {
        guard let value = self[key] else {
            throw JSONValueDecodingError.noValueForKey(key)
        }

        guard case let .string(stringValue) = value else {
            throw JSONValueDecodingError.wrongTypeForKey(key, actualValue: value)
        }

        return stringValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `string`, this returns the associated value. If this dictionary does not contain a value for `key`, or if the value for key has case `null`, it returns `nil`.
    ///
    /// - Throws: `JSONValueDecodingError.wrongTypeForKey` if the value does not have case `string` or `null`
    func optionalStringValueForKey(_ key: String) throws -> String? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .string(stringValue) = value else {
            throw JSONValueDecodingError.wrongTypeForKey(key, actualValue: value)
        }

        return stringValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `number`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `JSONValueDecodingError.noValueForKey` if the key is absent
    ///   - `JSONValueDecodingError.wrongTypeForKey` if the value does not have case `number`
    func numberValueForKey(_ key: String) throws -> Double {
        guard let value = self[key] else {
            throw JSONValueDecodingError.noValueForKey(key)
        }

        guard case let .number(numberValue) = value else {
            throw JSONValueDecodingError.wrongTypeForKey(key, actualValue: value)
        }

        return numberValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `number`, this returns the associated value. If this dictionary does not contain a value for `key`, or if the value for key has case `null`, it returns `nil`.
    ///
    /// - Throws: `JSONValueDecodingError.wrongTypeForKey` if the value does not have case `number` or `null`
    func optionalNumberValueForKey(_ key: String) throws -> Double? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .number(numberValue) = value else {
            throw JSONValueDecodingError.wrongTypeForKey(key, actualValue: value)
        }

        return numberValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `bool`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `JSONValueDecodingError.noValueForKey` if the key is absent
    ///   - `JSONValueDecodingError.wrongTypeForKey` if the value does not have case `bool`
    func boolValueForKey(_ key: String) throws -> Bool {
        guard let value = self[key] else {
            throw JSONValueDecodingError.noValueForKey(key)
        }

        guard case let .bool(boolValue) = value else {
            throw JSONValueDecodingError.wrongTypeForKey(key, actualValue: value)
        }

        return boolValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `bool`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `JSONValueDecodingError.noValueForKey` if the key is absent
    ///   - `JSONValueDecodingError.wrongTypeForKey` if the value does not have case `bool`
    func optionalBoolValueForKey(_ key: String) throws -> Bool? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .bool(boolValue) = value else {
            throw JSONValueDecodingError.wrongTypeForKey(key, actualValue: value)
        }

        return boolValue
    }
}