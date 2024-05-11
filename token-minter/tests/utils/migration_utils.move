#[test_only]
module minter::migration_utils {
    use aptos_framework::object;

    const MIGRATION_CONTRACT_SEED: vector<u8> = b"minter::migration_contract";

    public fun create_migration_object_signer(migration: &signer): signer {
        let constructor_ref = object::create_named_object(migration, MIGRATION_CONTRACT_SEED);
        object::generate_signer(&constructor_ref)
    }
}
