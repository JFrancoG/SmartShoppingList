import FluentKit
import FluentSQL

/// Records authorship of new content without guessing who supplied legacy names or quantities.
struct AddContentProvenance: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("""
                ALTER TABLE stores ADD COLUMN created_by UUID REFERENCES users(id)
                """).run()
            try await sql.raw("""
                ALTER TABLE items
                    ADD COLUMN name_author_user_id UUID REFERENCES users(id),
                    ADD COLUMN quantity_author_user_id UUID REFERENCES users(id),
                    ADD CONSTRAINT items_quantity_author_requires_content
                        CHECK(quantity IS NOT NULL OR quantity_author_user_id IS NULL)
                """).run()
            try await sql.raw("CREATE INDEX stores_created_by_idx ON stores(created_by)").run()
            try await sql.raw("CREATE INDEX items_name_author_idx ON items(name_author_user_id)").run()
            try await sql.raw("CREATE INDEX items_quantity_author_idx ON items(quantity_author_user_id)").run()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("LOCK TABLE stores, items IN ACCESS EXCLUSIVE MODE").run()
            guard try await sql.raw("""
                SELECT 1 FROM stores WHERE created_by IS NOT NULL
                UNION ALL SELECT 1 FROM items
                    WHERE name_author_user_id IS NOT NULL OR quantity_author_user_id IS NOT NULL
                LIMIT 1
                """).first() == nil else { throw ReversionError.contentProvenanceCannotBeDiscarded }
            try await sql.raw("ALTER TABLE stores DROP COLUMN created_by").run()
            try await sql.raw("""
                ALTER TABLE items DROP CONSTRAINT items_quantity_author_requires_content,
                    DROP COLUMN name_author_user_id, DROP COLUMN quantity_author_user_id
                """).run()
        }
    }

    enum ReversionError: Error, Equatable {
        case contentProvenanceCannotBeDiscarded
    }
}
