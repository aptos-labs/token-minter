module minter::migration_helper {

    use std::signer;
    use aptos_framework::object;

    /// Caller not authorized to call migration functions.
    const ENOT_MIGRATION_SIGNER: u64 = 1;

    // The seed for the migration contract
    const MIGRATION_CONTRACT_SEED: vector<u8> = b"minter::migration_contract";

    #[view]
    /// Helper function to get the address of the migration object signer.
    public fun migration_object_address(): address {
        object::create_object_address(&@migration, MIGRATION_CONTRACT_SEED)
    }

    public fun assert_migration_object_signer(migration_signer: &signer) {
        let migration_object_signer = migration_object_address();
        assert!(signer::address_of(migration_signer) == migration_object_signer, ENOT_MIGRATION_SIGNER);
    }
}
