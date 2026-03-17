import Foundation
import SwiftData

// SwiftData handles lightweight migrations (adding/removing optional columns)
// automatically without needing versioned schemas. Explicit VersionedSchema
// with nested @Model types is only needed for complex/custom migrations.
