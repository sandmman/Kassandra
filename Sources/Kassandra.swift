/**
 Copyright IBM Corporation 2016
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Foundation
import Socket

public class Kassandra {
    
    private var socket: Socket?
    
    public var host: String = "localhost"
    public var port: Int32 = 9042
    
    private var readQueue: DispatchQueue
    private var writeQueue: DispatchQueue
    
    private var buffer: Data
    
    var map            = [UInt16: (TableObj?, Error?) -> Void]()
    var awaitingResult = [UInt16: (Error?) -> Void]()

    public init(host: String = "localhost", port: Int32 = 9042) {
        self.host = host
        self.port = port

        socket = nil
        
        buffer = Data()

        readQueue = DispatchQueue(label: "read queue", attributes: .concurrent)
        writeQueue = DispatchQueue(label: "write queue", attributes: .concurrent)
    }
    
    public func connect(oncompletion: (Error?) -> Void) throws {
        
        if socket == nil {
            socket = try! Socket.create(family: .inet6, type: .stream, proto: .tcp)
        }

        guard let sock = socket else {
            throw RCErrorType.GenericError("Could not create a socket")

        }

        do {
            try sock.connect(to: host, port: port)

            try RequestPacket.startup(options: [:]).write(id: 10, writer: sock)
            
            config.connection = self

        } catch {
            oncompletion(RCErrorType.ConnectionError)
            return
        }
        
        read()
        
        oncompletion(nil)
    }

    public func execute(_ request: RequestPacket, oncompletion: (Error?) -> Void) throws {
        guard let sock = socket else {
            throw RCErrorType.GenericError("Could not create a socket")
            
        }
        writeQueue.async {
            do {
                let id = UInt16(random: true)
                
                self.awaitingResult[id] = oncompletion

                try request.write(id: id, writer: sock)
                
            } catch {
                oncompletion(RCErrorType.ConnectionError)
            }
        }
    }

    public func execute(_ request: RequestPacket, oncompletion: (TableObj?, Error?) -> Void) throws {
        guard let sock = socket else {
            throw RCErrorType.GenericError("Could not create a socket")
            
        }
        writeQueue.async {
            do {
                
                let id = UInt16(random: true)

                self.map[id] = oncompletion

                try request.write(id: id, writer: sock)

            } catch {
                oncompletion(nil, RCErrorType.ConnectionError)
            }
        }
    }
}

extension Kassandra {
    
    public func read() {
        
        guard let sock = socket else {
            return
        }
        
        let iochannel = DispatchIO(type: DispatchIO.StreamType.stream, fileDescriptor: sock.socketfd, queue: readQueue, cleanupHandler: {
            error in
        })
        
        iochannel.read(offset: off_t(0), length: 1, queue: readQueue) {
            done, data, error in
            
            let bytes: [Byte]? = data?.map {
                byte in
                return byte
            }
            
            if let d = bytes {
                
                self.buffer.append(d, count: d.count)

                if self.buffer.count >= 9 {
                    self.unpack()
                }
                
                self.read()
            }
        }
    }

    public func unpack() {
        while buffer.count >= 9 {
            
            //Unpack header
            let flags       = UInt8(buffer[1])    // flags
            let streamID    = UInt16(msb: buffer[3], lsb: buffer[2])
            let opcode      = UInt8(buffer[4])
            let bodyLength  = Int(data: buffer.subdata(in: Range(5...8)))
            
            // Do we have all the bytes we need for the full packet?
            let bytesNeeded = buffer.count - bodyLength - 9
            
            if bytesNeeded < 0 {
                return
            }

            let body = buffer.subdata(in: Range(9..<9 + bodyLength))
            
            buffer = buffer.subdata(in: Range(9 + bodyLength..<buffer.count))

            handle(id: streamID, flags: flags, ResponsePacket(opcode: opcode, body: body))
        
        }
    }
    public func handle(id: UInt16, flags: Byte, _ response: ResponsePacket) {
        switch response {
        case .ready                     : awaitingResult[id]?(nil)
        case .authSuccess               : awaitingResult[id]?(nil)
        case .event                     : print(response)
        case .error                     : print(response)
        case .authChallenge(let token)  : authResponse(token: token)
        case .authenticate(_)           : authResponse(token: 1)
        case .supported                 : print(response)
        case .result(let resultKind)    :
            switch resultKind {
            case .void                  : break
            case .schema                : print(response)
            case .keyspace              : print(response)
            case .prepared              : print(response)
            case .rows(_, let c, let r) : map[id]?(TableObj(rows: r, headers: c),nil)
            }
        }
    }
}













//// Struct Implementation
extension Kassandra {
    private func authResponse(token: Int) {
        
        guard let sock = socket else {
            print(RCErrorType.GenericError("Could not create a socket"))
            return
        }
        
        writeQueue.async {
            do {
                try AuthResponse(token: token).write(writer: sock)
                
            } catch {
                print("error")
            }
        }
    }
    
    public func options(oncompletion: (Error?) -> Void) throws {
        
        guard let sock = socket else {
            throw RCErrorType.GenericError("Could not create a socket")
            
        }
        
        writeQueue.async {
            do {
                try OptionsRequest().write(writer: sock)
                
            } catch {
                oncompletion(RCErrorType.ConnectionError)
            }
        }
    }
    
    public func query(query: String, oncompletion: (TableObj?, Error?) -> Void) throws {
        
        guard let sock = socket else {
            throw RCErrorType.GenericError("Could not create a socket")
            
        }
        writeQueue.async {
            do {
                let val = UInt16(random: true)
                
                self.map[val] = oncompletion
                
                //try RequestPacket.query(id: val, query: Query(query)).write(writer: sock)
                try QueryRequest(query: Query(query)).write(writer: sock)
                
            } catch {
                oncompletion(nil,RCErrorType.ConnectionError)
            }
        }
    }
    
    public func prepare(query: String, oncompletion: (Error?) -> Void) throws {
        guard let sock = socket else {
            throw RCErrorType.GenericError("Could not create a socket")
            
        }
        writeQueue.async {
            do {
                try Prepare(query: Query(query)).write(writer: sock)
                
            } catch {
                oncompletion(RCErrorType.ConnectionError)
                
            }
        }
    }
    
    public func execute(id: UInt16, parameters: String, oncompletion: (Error?) -> Void) throws {
        
        guard let sock = socket else {
            throw RCErrorType.GenericError("Could not create a socket")
            
        }
        
        writeQueue.async {
            do {
                try Execute(id: id, parameters: parameters).write(writer: sock)
                
            } catch {
                oncompletion(RCErrorType.ConnectionError)
            }
        }
    }
    
    public func batch(query: [String], oncompletion: (Error?) -> Void) throws {
        
        guard let sock = socket else {
            throw RCErrorType.GenericError("Could not create a socket")
            
        }
        
        let queries = query.map {
            str in
            
            return Query(str)
        }
        
        writeQueue.async {
            do {
                try Batch(queries: queries).write(writer: sock)
                
            } catch {
                oncompletion(RCErrorType.ConnectionError)
            }
        }
    }
    
    public func register(events: [String], oncompletion: (Error?) -> Void) throws {
        
        guard let sock = socket else {
            throw RCErrorType.GenericError("Could not create a socket")
            
        }
        
        writeQueue.async {
            do {
                try Register(events: events).write(writer: sock)
                
            } catch {
                oncompletion(RCErrorType.ConnectionError)
            }
        }
    }
}

// Struct version
extension Kassandra {
    public func createResponseMessage(opcode: UInt8, data: Data) -> Response? {
        let opcode = Opcode(rawValue: opcode)!
        switch opcode {
        case .error:        return ErrorPacket(body: data)
        case .ready:        return Ready(body: data)
        case .authenticate: return Authenticate(body: data)
        case .supported:    return Supported(body: data)
        case .result:       return Result(body: data)
        case .authSuccess:  return AuthSuccess(body: data)
        case .event:        return Event(body: data)
        case .authChallenge:return AuthChallenge(body: data)
        default: return nil
        }
    }
    public func handle(_ response: Response) {
        switch response {
        case let r as ErrorPacket   : print(r.description)
        case _ as Authenticate      : authResponse(token: 1)
        case let r as Supported     : print(r.description)
        case let r as Event         : print(r.description)
        case let r as AuthChallenge : self.authResponse(token: r.token)
        case let r as Result        :
            switch r.message {
            case .void              : break
            case .rows(_, _, _)     : print("rows")
            case .schema            : print(r.message)
            case .keyspace          : print(r.message)
            case .prepared          : print(r.message)
            }
        default                     : print(response.description)
        }
    }
}

// Custom operators for database
extension Kassandra {
    subscript(_ database: String) -> Bool {
        do {
            try query(query: "USE \(database);") { _ in
                
            }
        } catch {
            return false
        }
        return true
    }
    
}

public struct TableObj {
    
    var rows = [[String: Data]]()

    init(rows: [[Data]], headers: [(name: String, type: DataType)]){
        for row in rows {
            var map = [String: Data]()
            for i in 0..<headers.count {
                map[headers[i].name] = row[i]
            }
            self.rows.append(map)
        }
    }
    
    subscript(_ index: String) -> String {
        return ""
    }
}
