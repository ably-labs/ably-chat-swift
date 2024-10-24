import Foundation

/**
 * Unified Test Suite adapter generator for swift Chat SDK
 */
class ChatAdapterGenerator {
    
    var generatedFileContent = "// GENERATED CONTENT BEGIN\n\n"
    
    func generate() {
        Schema.json.forEach { generateSchema($0) }
        generatedFileContent += "// GENERATED CONTENT END"
        print(generatedFileContent)
    }
    
    func generateSchema(_ schema: JSON) {
        guard let objectType = schema.name else {
            return print("Schema should have a name.")
        }
        if let constructor = schema.constructor {
            generateConstructorForType(objectType, schema: constructor, isAsync: false, throwing: false)
        }
        for method in schema.syncMethods?.sortedByKey() ?? [] {
            generateMethodForType(objectType, methodName: method.key, methodSchema: method.value as! JSON, isAsync: false, throwing: true)
        }
        for method in schema.asyncMethods?.sortedByKey() ?? [] {
            generateMethodForType(objectType, methodName: method.key, methodSchema: method.value as! JSON, isAsync: true, throwing: true)
        }
        for field in schema.fields?.sortedByKey() ?? [] {
            generateFieldForType(objectType, fieldName: field.key, fieldSchema: field.value as! JSON)
        }
        for method in schema.listeners?.sortedByKey() ?? [] {
            generateMethodWithCallbackForType(objectType, methodName: method.key, methodSchema: method.value as! JSON, isAsync: true, throwing: true)
        }
    }
    
    func generateConstructorForType(_ objectType: String, schema: JSON, isAsync: Bool, throwing: Bool) {
        let implPath = "\(objectType)"
        if Schema.skipPaths.contains([implPath]) {
            return print("\(implPath) was not yet implemented or requires custom implementation.")
        }
        let methodArgs = schema.args ?? [:]
        let paramsDeclarations = methodArgs.map {
            let argSchema = $0.value as! JSON
            return "    let \($0.key.bigD()) = \(altTypeName(argSchema.type!)).from(rpcParams[\"\($0.key)\"])"
        }
        let callParams = methodArgs.map { "\($0.key.bigD()): \($0.key.bigD())" }.joined(separator: ", ")
        generatedFileContent +=
            """
            case "\(objectType)":
            """
        if !paramsDeclarations.isEmpty {
            generatedFileContent += paramsDeclarations.joined(separator: "\n") + "\n"
        }
        generatedFileContent +=
            """
                let \(altTypeName(objectType).firstLowercased()) = \(altTypeName(objectType))(\(callParams))
                let instanceId = generateId()
                idTo\(altTypeName(objectType))[instanceId] = \(altTypeName(objectType).firstLowercased())
                return jsonRpcResult(rpcParams.callbackId, "{\\"instanceId\\":\\"\\(instanceId)\\"}")
            \n
            """
    }
    
    func generateMethodForType(_ objectType: String, methodName: String, methodSchema: JSON, isAsync: Bool, throwing: Bool) {
        let implPath = "\(objectType).\(methodName)"
        if Schema.skipPaths.contains([implPath]) {
            return print("\(implPath) was not yet implemented or requires custom implementation.")
        }
        let methodArgs = methodSchema.args ?? [:]
        let paramsDeclarations = methodArgs.map {
            let argSchema = $0.value as! JSON
            return "    let \($0.key.bigD()) = \(altTypeName(argSchema.type!)).from(rpcParams[\"\($0.key)\"])"
        }
        let callParams = methodArgs.map { "\($0.key.bigD()): \($0.key.bigD())" }.joined(separator: ", ")
        let hasResult = methodSchema.result.type != nil && methodSchema.result.type != "void"
        let resultType = altTypeName(methodSchema.result.type ?? "void")
        generatedFileContent +=
            """
            case "\(objectType).\(methodName)":\n
            """
        if !paramsDeclarations.isEmpty {
            generatedFileContent += paramsDeclarations.joined(separator: "\n") + "\n"
        }
        generatedFileContent +=
            """
                guard let \(altTypeName(objectType).firstLowercased())Ref = idTo\(altTypeName(objectType))[rpcParams.refId] else {
                    print("\(altTypeName(objectType)) with `refId == \\(rpcParams.refId)` doesn't exist.")
                    return nil
                }
                \(hasResult ? "let \(resultType.firstLowercased()) = " : "")\(throwing ? "try " : "")\(isAsync ? "await " : "")\(altTypeName(objectType).firstLowercased())Ref.\(methodName)(\(callParams)) // \(resultType)\n
            """
        if hasResult {
            if isJsonPrimitiveType(methodSchema.result.type!) {
                generatedFileContent +=
                    """
                        return jsonRpcResult(rpcParams.callbackId, "{\\"response\\": \\"\\(\(resultType.firstLowercased()))\\"}")
                    \n
                    """
            } else if methodSchema.result.isSerializable {
                generatedFileContent +=
                    """
                        return jsonRpcResult(rpcParams.callbackId, "{\\"response\\": \\"\\(JSON.from(\(resultType.firstLowercased())))\\"}")
                    \n
                    """
            } else {
                generatedFileContent +=
                    """
                        let resultRefId = generateId()
                        idTo\(altTypeName(methodSchema.result.type!))[resultRefId] = \(resultType.firstLowercased())
                        return jsonRpcResult(rpcParams.callbackId, "{\\"refId\\":\\"\\(resultRefId)\\"}")
                    \n
                    """
            }
        }
        else {
            generatedFileContent +=
                """
                    return jsonRpcResult(rpcParams.callbackId, "{}")
                \n
                """
        }
    }
    
    func generateFieldForType(_ objectType: String, fieldName: String, fieldSchema: JSON) {
        guard let fieldType = fieldSchema.type else {
            return print("Type information for '\(fieldName)' field is incorrect.")
        }
        let implPath = "\(objectType)#\(fieldName)"
        if Schema.skipPaths.contains([implPath]) {
            return print("\(implPath) was not yet implemented or requires custom implementation.")
        }
        generatedFileContent +=
            """
            case "\(implPath)":
                guard let \(altTypeName(objectType).firstLowercased())Ref = idTo\(altTypeName(objectType))[rpcParams.refId] else {
                    print("\(altTypeName(objectType)) with `refId == \\(rpcParams.refId)` doesn't exist.")
                    return nil
                }
                let \(fieldName.bigD()) = \(altTypeName(objectType).firstLowercased())Ref.\(fieldName.bigD()) // \(fieldType)\n
            """
        
        if fieldSchema.isSerializable {
            if isJsonPrimitiveType(fieldType) {
                generatedFileContent +=
                    """
                        return jsonRpcResult(rpcParams.callbackId, "{\\"response\\": \\"\\(\(fieldName.bigD()))\\"}")
                    \n
                    """
            } else {
                generatedFileContent +=
                    """
                        return jsonRpcResult(rpcParams.callbackId, "{\\"response\\": \\"\\(JSON.from(\(fieldName.bigD())))\\"}")
                    \n
                    """
            }
        } else {
            generatedFileContent +=
                """
                    let fieldRefId = generateId()
                    idTo\(fieldType)[fieldRefId] = \(fieldName.bigD())
                    return jsonRpcResult(rpcParams.callbackId, "{\\"refId\\":\\"\\(fieldRefId)\\"}")
                \n
                """
        }
    }
    
    func generateMethodWithCallbackForType(_ objectType: String, methodName: String, methodSchema: JSON, isAsync: Bool, throwing: Bool) {
        let implPath = "\(objectType).\(methodName)"
        if Schema.skipPaths.contains([implPath]) {
            return print("\(implPath) was not yet implemented or requires custom implementation.")
        }
        let methodArgs = methodSchema.args ?? [:]
        let paramsSignatures = methodArgs.compactMap {
            let argName = $0.key
            let argType = ($0.value as! JSON).type!
            if argType != "callback" {
                return (declaration: "    let \(argName.bigD()) = \(altTypeName(argType)).from(rpcParams[\"\(argName)\"])",
                        usage: "\(argName.bigD()): \(argName.bigD())")
            } else {
                return nil
            }
        }
        let callParams = (paramsSignatures.map { $0.usage } + ["bufferingPolicy: .unbounded"]).joined(separator: ", ")
        generatedFileContent +=
            """
            case "\(objectType).\(methodName)":\n
            """
        if !paramsSignatures.isEmpty {
            generatedFileContent += paramsSignatures.map { $0.declaration }.joined(separator: "\n") + "\n"
        }
        generatedFileContent +=
            """
                guard let \(altTypeName(objectType).firstLowercased())Ref = idTo\(altTypeName(objectType))[rpcParams.refId] else {
                    print("\(altTypeName(objectType)) with `refId == \\(rpcParams.refId)` doesn't exist.")
                    return nil
                }
                let subscription = \(throwing ? "try " : "")\(isAsync ? "await " : "")\(altTypeName(objectType).firstLowercased())Ref.\(altMethodName(methodName))(\(callParams))\n
            """
        generatedFileContent += generateCallback(methodSchema.callback!, isAsync: false, throwing: false)
        generatedFileContent +=
            """
                let resultRefId = generateId()
                idTo\(altTypeName(methodSchema.result.type!))[resultRefId] = subscription
                return jsonRpcResult(rpcParams.requestId, "{\\"refId\\":\\"\\(resultRefId)\\"}")
                \n
            """
    }
    
    func generateCallback(_ callbackSchema: JSON, isAsync: Bool, throwing: Bool) -> String {
        let callbackArgs = callbackSchema.args ?? [:]
        let paramsSignatures = callbackArgs.prefix(1).compactMap { // code below simplifies it to just one callback parameter
            let argName = $0.key
            let argType = ($0.value as! JSON).type!
            let isOptional = ($0.value as! JSON).isOptional
            return (declaration: "\(altTypeName(argType))" + (isOptional ? "?" : ""), usage: "\(argName.bigD())")
        }
        let paramsDeclaration = paramsSignatures.map { $0.declaration }.joined(separator: ", ")
        let paramsUsage = paramsSignatures.map { $0.usage }.joined(separator: ", ")
        var result =
            """
                let callback: (\(paramsDeclaration)) -> \(altTypeName(callbackSchema.result.type!)) = {\n
            """
        if (callbackArgs.first?.value as? JSON)?.isOptional ?? false {
            result +=
                """
                        if let param = $0 {
                            self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\\(param.json())"))
                        } else {
                            self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "{}"))
                        }\n
                """
        } else {
            result +=
                """
                        self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\\($0.json())"))\n
                """
        }
        result +=
            """
                }
                Task {
                    for await \(paramsUsage) in subscription {
                        callback(\(paramsUsage))
                    }
                }\n
            """
        return result
    }
}
