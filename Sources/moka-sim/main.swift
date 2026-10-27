import MokaCore
import MokaStore

let db = try MokaDatabase.inMemory()
print("core=\(Health.check()) store=\(try MokaDatabase.healthCheck(db))")
