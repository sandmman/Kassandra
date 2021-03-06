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

import XCTest
@testable import Kassandra
import Foundation

#if os(OSX) || os(iOS)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif

class KassandraTests: XCTestCase {
    
    private var connection: Kassandra!
    
    public var t: TodoItem!
    
    var tokens = [String]()

    public let useKeyspace: String = "test;"
    
    static var allTests: [(String, (KassandraTests) -> () throws -> Void)] {
        return [
            ("testConnectAndCreateKeyspace", testConnectAndCreateKeyspace),
            ("testKeyspaceWithCreateABreadShopTable", testKeyspaceWithCreateABreadShopTable),
            ("testKeyspaceWithCreateABreadShopTableInsertAndSelect", testKeyspaceWithCreateABreadShopTableInsertAndSelect),
            ("testKeyspaceWithCreateATable", testKeyspaceWithCreateATable),
            ("testKeyspaceWithFetchCompletedTodoItems", testKeyspaceWithFetchCompletedTodoItems),
            ("testModel", testModel),
            ("testPreparedQuery", testPreparedQuery),
            ("testZBatch", testZBatch),
            ("testZDropTableAndDeleteKeyspace", testZDropTableAndDeleteKeyspace)
        ]
    }
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        connection = Kassandra()//host: "ec2-54-224-86-166.compute-1.amazonaws.com")
        t = TodoItem()
    }
    
    func testConnectAndCreateKeyspace() throws {
        let expectation1 = expectation(description: "Keyspace Created")
        let expectation2 = expectation(description: "Keyspace Not Created")
        
        try connection.connect() { result in

            XCTAssertTrue(result.success, "Connected to Cassandra")

            self.connection.create(keyspace: "test", with: .simple(numberOfReplicas: 3), ifNotExists: true) {
                result in
                
                if result.success { expectation1.fulfill() }
                
                self.connection.create(keyspace: "test", with: .simple(numberOfReplicas: 3), ifNotExists: false) {
                    result in
                    
                    if result.asError != nil { expectation2.fulfill() }
                    
                }
            
            }
            
        }
        waitForExpectations(timeout: 5, handler: { _ in  })
    }
    
    func testKeyspaceWithCreateABreadShopTable() throws {
        
        let expectation1 = expectation(description: "Create a table in the keyspace or table exist in the keyspace")
        
        try connection.connect(with: self.useKeyspace) { result in
            XCTAssertTrue(result.success, "Connected to Cassandra")
            self.connection.execute("CREATE TABLE IF NOT EXISTS breadshop (userID uuid primary key, type text, bread map<text, int>, cost float, rate double, time timestamp);") {
                result in
                XCTAssertEqual(result.asSchema?.type, "CREATED", "Created Table \(BreadShop.tableName)")
                if result.success { expectation1.fulfill() }
            }
        }
        waitForExpectations(timeout: 5, handler: { _ in  })
    }
    
    func testKeyspaceWithCreateABreadShopTableInsertAndSelect() throws {
        
        let expectation1 = expectation(description: "Insert and select the row")
        
        let bread: [BreadShop.Field: Any] = [.userID: UUID(), .type: "Sandwich", .bread: ["Chicken Roller": 3, "Steak Roller": 7, "Spicy Chicken Roller": 9], .cost: 2.1, .rate: 9.1, .time : Date()]
        
        try connection.connect(with: self.useKeyspace) { result in
            XCTAssertTrue(result.success, "Connected to Cassandra")
            
            BreadShop.insert(bread).execute() { result in
                BreadShop.select().execute() {
                    result in

                    XCTAssertEqual(result.asRows?.count, 1)
                    if result.asRows != nil { expectation1.fulfill() }
                }
            }
        }
        waitForExpectations(timeout: 5, handler: { _ in  })
        
    }
    
    func testKeyspaceWithCreateATable() throws {
        
        let expectation1 = expectation(description: "Create a table in the keyspace or table exist in the keyspace")
        
        try connection.connect(with: self.useKeyspace) { result in
            XCTAssertTrue(result.success, "Connected to Cassandra")
            
            self.connection.execute("CREATE TABLE IF NOT EXISTS todoitem(userID uuid primary key, type text, title text, pos int, completed boolean);") { result in

                XCTAssertEqual(result.asSchema?.type, "CREATED", "Created Table \(TodoItem.tableName)")
                if result.success { expectation1.fulfill() }
            }
        }
        waitForExpectations(timeout: 5, handler: { _ in  })
    }
    
    
    func testKeyspaceWithFetchCompletedTodoItems() throws {
        
        let expectation1 = expectation(description: "Select first two completed item and check their row count")
        let expectation2 = expectation(description: "Truncate the table to get 0 completed items")
        
        let userID1 = UUID()
        let god: [TodoItem.Field: Any] = [.type: "todo", .userID: userID1, .title: "God Among God", .pos: 1, .completed: true]
        let ares: [TodoItem.Field: Any] = [.type: "todo", .userID: UUID(), .title: "Ares", .pos: 2, .completed: true]
        let thor: [TodoItem.Field: Any] = [.type: "todo", .userID: UUID(), .title: "Thor", .pos: 3, .completed: true]
        let apollo: [TodoItem.Field: Any] = [.type: "todo", .userID: UUID(), .title: "Apollo", .pos: 4, .completed: true]
        let cass: [TodoItem.Field: Any] = [.type: "todo", .userID: UUID(), .title: "Cassandra", .pos: 5, .completed: true]
        let hades: [TodoItem.Field: Any] = [.type: "todo", .userID: UUID(), .title: "Hades", .pos: 6, .completed: true]
        let athena: [TodoItem.Field: Any] =  [.type: "todo", .userID: UUID(), .title: "Athena", .pos: 7, .completed: true]
        
        try connection.connect(with: self.useKeyspace) { result in
            XCTAssertTrue(result.success, "Connected to Cassandra")
            
            TodoItem.insert(god).execute() { result in
                TodoItem.insert(ares).execute() { result in
                    TodoItem.insert(thor).execute() { result in
                        TodoItem.insert(apollo).execute() { result in
                            TodoItem.insert(cass).execute() { result in
                                TodoItem.insert(hades).execute() { result in
                                    TodoItem.insert(athena).execute() { result in
                                        TodoItem.update([.title: "Zeus"], conditions: "userID" == userID1).execute {
                                            result in
                                            
                                            TodoItem.select().limit(to: 2).filter(by: "userID" == userID1).execute() {
                                                result in
                                                
                                                if let rows = result.asRows {
                                                    if let _ = rows[0]["title"] as? String, rows.count == 1 {
                                                        expectation1.fulfill()
                                                    }
                                                } else {
                                                    print("\n",result,"\n")
                                                }
                                            }
                                            
                                            TodoItem.truncate().execute() { result in
                                                
                                                TodoItem.count().execute() { result in
                                                    if let rows = result.asRows {
                                                        if let count = rows[0]["count"] as? Int64, count == 0 {
                                                            expectation2.fulfill()
                                                        }
                                                        
                                                    } else {
                                                        print("\n",result,"\n")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        waitForExpectations(timeout: 5, handler: { _ in  })
    }
    
    
    func testZDropTableAndDeleteKeyspace() throws {
        
        let expectation1 = expectation(description: "Drop the table and delete the keyspace")
        
        try connection.connect(with: self.useKeyspace) { result in
            XCTAssertTrue(result.success, "Connected to Cassandra")
            
            TodoItem.drop().execute() { result in

                self.connection.execute("DROP KEYSPACE test") { result in

                    XCTAssertTrue(result.success)
                    expectation1.fulfill()
                }
                expectation1.fulfill()
            }
        }

        waitForExpectations(timeout: 5, handler: { _ in  })
    }
    
    func testPreparedQuery() throws {
        
        let expectation1 = expectation(description: "Execute a prepared query")
        
        var query: Query = Raw(query: "SELECT userID FROM todoitem WHERE completed = true allow filtering;")
        
        try connection.connect(with: self.useKeyspace) { result in
            XCTAssertTrue(result.success, "Connected to Cassandra")
            
            query.prepare() { result in
                if let id = result.asPrepared {
                    
                    query.preparedID = id
                    
                    query.execute() { result in
                        
                        if result.asRows?.count == 0 {
                            expectation1.fulfill()
                        }
                        else { print("\n",result,"\n") }
                    }
                } else {
                    print("\n","Prepare",result,"\n")
                }
            }
        }
        waitForExpectations(timeout: 5, handler: { _ in  })
    }
    
    public func testZBatch() throws {
        let expectation1 = expectation(description: "Execute a batch query")
        
        let insert1 = TodoItem.insert([.type: "todo", .userID: NSUUID(), .title: "Water Plants", .pos: 15, .completed: false])
        let insert2 = TodoItem.insert([.type: "todo", .userID: NSUUID(),.title: "Make Dinner", .pos: 14, .completed: true])
        let insert3 = TodoItem.insert([.type: "todo", .userID: NSUUID(),.title: "Excercise", .pos: 13, .completed: true])
        let insert4 = TodoItem.insert([.type: "todo", .userID: NSUUID(),.title: "Sprint Plannning", .pos: 12, .completed: false])
        
        try connection.connect(with: self.useKeyspace) { result in
            XCTAssertTrue(result.success, "Connected to Cassandra")
            
                insert1.execute() { result in
                    [insert1,insert2,insert3,insert4].execute(with: .logged, consis: .any) { result in
                        TodoItem.select().execute() { result in
                            
                            XCTAssertEqual(result.asRows?.count, 4)
                            if result.success { expectation1.fulfill() }
                            else { print("\n",result,"\n") }
                        }
                    }
                }
        }
        waitForExpectations(timeout: 5, handler: { _ in  })
    }
    
    func testModel() throws {
        
        let expectation1 = expectation(description: "Execute a prepared query")

        try connection.connect(with: self.useKeyspace) { result in
            XCTAssertTrue(result.success, "Connected to Cassandra")
            
            Student.create(ifNotExists: true) { result in
                
                let uuid = UUID()
                let s = Student(id: uuid, name: "Chia", school: "UC")

                s.save { result in
                    
                    assert(result.success)

                    Student.fetch(predicate: "id" == uuid) { result, error in
                        
                        if let res = result {
                            
                            XCTAssertEqual(res[0].id, uuid)

                            s.delete { result in
                                
                                assert(result.success)
                                expectation1.fulfill()
                            }
                        }
                    }
                }
            }
        }
        waitForExpectations(timeout: 5, handler: { _ in  })
    }
}

