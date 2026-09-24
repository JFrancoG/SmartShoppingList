import FluentKit
import FluentSQL

/// PostgreSQL constraints are a second boundary after route authorization and validation.
struct CreateSharedShopping: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let sql = try shoppingSQL(database)
        for statement in Self.statements {
            try await sql.raw(SQLQueryString(stringLiteral: statement)).run()
        }
    }

    func revert(on database: any Database) async throws {
        let sql = try shoppingSQL(database)
        try await sql.raw("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_group_id_fkey").run()
        for table in ["mutation_receipts", "invitations", "items", "stores", "groups", "users"] {
            try await sql.raw("DROP TABLE \(ident: table)").run()
        }
    }

    private static let statements = [
        """
        CREATE TABLE users (
            id UUID PRIMARY KEY, apple_subject TEXT UNIQUE NOT NULL, display_name TEXT,
            group_id UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
        )
        """,
        """
        CREATE TABLE groups (
            id UUID PRIMARY KEY, name TEXT NOT NULL, creator_user_id UUID UNIQUE NOT NULL REFERENCES users(id),
            created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
        )
        """,
        "ALTER TABLE users ADD CONSTRAINT users_group_id_fkey FOREIGN KEY (group_id) REFERENCES groups(id)",
        "CREATE INDEX users_group_idx ON users(group_id)",
        """
        CREATE TABLE stores (
            id UUID PRIMARY KEY, group_id UUID NOT NULL REFERENCES groups(id), name TEXT NOT NULL,
            normalized_key TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
            UNIQUE(group_id, normalized_key), UNIQUE(group_id, id)
        )
        """,
        "CREATE INDEX stores_page_idx ON stores(group_id, created_at, id)",
        """
        CREATE TABLE items (
            id UUID PRIMARY KEY, group_id UUID NOT NULL REFERENCES groups(id), store_id UUID NOT NULL,
            name TEXT NOT NULL, quantity TEXT, status TEXT NOT NULL CHECK(status IN ('pending','purchased','cancelled')),
            version BIGINT NOT NULL CHECK(version BETWEEN 1 AND 9007199254740991),
            created_by UUID NOT NULL REFERENCES users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
            purchased_by UUID REFERENCES users(id), purchased_at TIMESTAMPTZ,
            FOREIGN KEY(group_id, store_id) REFERENCES stores(group_id, id),
            CHECK((status = 'purchased' AND purchased_by IS NOT NULL AND purchased_at IS NOT NULL)
                OR (status <> 'purchased' AND purchased_by IS NULL AND purchased_at IS NULL))
        )
        """,
        "CREATE INDEX items_page_idx ON items(group_id, store_id, status, created_at, id)",
        "CREATE INDEX items_created_by_idx ON items(created_by)",
        "CREATE INDEX items_purchased_by_idx ON items(purchased_by)",
        """
        CREATE TABLE invitations (
            id UUID PRIMARY KEY, group_id UUID NOT NULL REFERENCES groups(id), secret_hash TEXT UNIQUE NOT NULL,
            created_at TIMESTAMPTZ NOT NULL, expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ,
            accepted_by UUID REFERENCES users(id), accepted_at TIMESTAMPTZ,
            CHECK((accepted_by IS NULL) = (accepted_at IS NULL)),
            CHECK(revoked_at IS NULL OR accepted_by IS NULL), CHECK(expires_at > created_at)
        )
        """,
        "CREATE INDEX invitations_page_idx ON invitations(group_id, created_at, id)",
        "CREATE INDEX invitations_accepted_by_idx ON invitations(accepted_by)",
        """
        CREATE TABLE mutation_receipts (
            user_id UUID NOT NULL REFERENCES users(id), operation_id UUID NOT NULL, operation_type TEXT NOT NULL,
            group_id UUID REFERENCES groups(id), fingerprint TEXT NOT NULL, status INTEGER, body TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), PRIMARY KEY(user_id, operation_id),
            CHECK((status IS NULL) = (body IS NULL))
        )
        """,
        "CREATE INDEX receipts_group_idx ON mutation_receipts(group_id)"
    ]
}
