module minter::migration_helper {

    use aptos_framework::object;

    // The seed for the migration contract
    const MIGRATION_CONTRACT_SEED: vector<u8> = b"migration::migration_contract";

    #[view]
    /// Helper function to get the address of the migration object signer.
    public fun migration_object_address(): address {
        object::create_object_address(&@migration, MIGRATION_CONTRACT_SEED)
    }
}
