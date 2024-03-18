#[test_only]
module migration::token_migration_tests {
    use std::bcs;
    use std::signer;
    use std::string;
    use std::string::utf8;

    use aptos_token_objects::token;
    use minter::collection_utils;
    use minter::token_components;
    use minter::token_utils;
    use minter_v2::token_components_v2;

    use migration::migration;

    #[test_only]
    fun setup(migration: &signer) {
        migration::init_module_for_testing(migration);
    }

    #[test(creator = @0x123, migration = @migration)]
    /// Example of creating a v1 TokenRefs extend ref and then migrating it to v2 TokenRefs extend ref.
    fun test_token_extend_ref_migration(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);

        // This should not throw when getting collection signer from v1 contract
        let _token_signer = token_components::token_object_signer(creator, token);

        // =============================== MIGRATION OCCURS HERE =============================== //
        migration::migrate_vx_to_vy_token_refs_and_properties(creator, token);

        // Now get collection_signer from v2 contract, this should not throw as we migrated the extend ref
        let _token_signer = token_components_v2::token_object_signer(creator, token);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393217, location = minter_v2::token_components_v2)]
    /// Example of trying to mutate a token using v2 contract and TokenRefs, but without migrating the TokenRefs extend ref.
    fun fails_to_get_signer_when_extend_ref_is_not_migrated(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);

        // Now get collection_signer from v2 contract, this throws as the extend ref was not migrated
        let _token_signer = token_components_v2::token_object_signer(creator, token);
    }

    #[test(creator = @0x123, migration = @migration)]
    /// Example of creating a v1 TokenRefs burn_ref and then migrating it to v2 TokenRefs burn_ref.
    fun test_burn_ref_migration(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);
        token_components::burn(creator, token);

        // Create new token as we burnt the previous one
        let new_token = token_utils::create_token_with_refs(creator, collection);

        // Must migrate collection properties as well, as we are burning the token.
        migration::migrate_vx_to_vy_collection_refs_and_properties(creator, collection);
        migration::migrate_vx_to_vy_token_refs_and_properties(creator, new_token);

        // Now try burning a new token, but using the v2 TokenRefs burn ref and v2 contract.
        token_components_v2::burn(creator, new_token);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393217, location = minter_v2::collection_properties_v2)]
    fun fails_to_burn_when_burn_ref_is_not_migrated(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);

        // We will call the v2 contract now, but should expect failure as user does not migrate refs.
        token_components_v2::burn(creator, token);
    }

    #[test(creator = @0x123, user = @0x456, migration = @migration)]
    /// Example of creating a v1 TokenRefs transfer_ref and then migrating it to v2 TokenRefs transfer_ref.
    fun test_transfer_ref_migration(creator: &signer, user: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);
        let user_address = signer::address_of(user);
        token_components::transfer_as_collection_owner(creator, token, user_address);

        // Create new token as we transferred the previous one
        let new_token = token_utils::create_token_with_refs(creator, collection);

        // Must migrate collection properties as well, as we are transferring to a new token.
        migration::migrate_vx_to_vy_collection_refs_and_properties(creator, collection);
        migration::migrate_vx_to_vy_token_refs_and_properties(creator, new_token);

        // Now try transferring a new token, but using the v2 TokenRefs burn ref and v2 contract.
        token_components_v2::transfer_as_collection_owner(creator, new_token, user_address);
    }

    #[test(creator = @0x123, user = @0x456, migration = @migration)]
    #[expected_failure(abort_code = 393217, location = minter_v2::token_components_v2)]
    fun fails_to_transfer_when_transfer_ref_is_not_migrated(creator: &signer, user: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);

        // Must migrate collection properties as well, as we are transferring to a new token.
        migration::migrate_vx_to_vy_collection_refs_and_properties(creator, collection);

        // We will call the v2 contract now, but should expect failure if user does not migrate refs.
        token_components_v2::transfer_as_collection_owner(creator, token, signer::address_of(user));
    }

    #[test(creator = @0x123, migration = @migration)]
    /// Example of creating a v1 TokenRefs mutator_ref and then migrating it to v2 TokenRefs mutator_ref.
    fun test_mutator_ref_migration(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);

        // Use the v1 contract and TokenRefs mutator_ref to mutate collection description
        token_components::set_description(creator, token, utf8(b"updated test token description"));
        assert!(token::description(token) == utf8(b"updated test token description"), 0);

        // =============================== MIGRATION OCCURS HERE =============================== //

        // Must migrate collection properties as well, as we are setting the description for token.
        migration::migrate_vx_to_vy_collection_refs_and_properties(creator, collection);

        // We will call the v2 contract now, as we will simulate a migration from v1 to v2.
        // First, we must migrate the TokenRefs mutator ref that belong to the token.
        // This will create the new TokenRefs mutator ref defined in v2 contract.
        migration::migrate_vx_to_vy_token_refs_and_properties(creator, token);

        // Now try mutating the token again, but using the v2 TokenRefs mutator_ref and v2 contract.
        token_components_v2::set_description(creator, token, utf8(b"v2 token description"));
        assert!(token::description(token) == utf8(b"v2 token description"), 0);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393217, location = minter_v2::token_components_v2)]
    /// Example of trying to mutate a token using v2 contract and TokenRefs, but without migrating the TokenRefs mutator ref.
    fun fails_to_mutate_when_mutator_ref_is_not_migrated(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);
        migration::migrate_vx_to_vy_collection_refs_and_properties(creator, collection);

        // We will call the v2 contract now, but should expect failure if user does not migrate refs.
        // We expect exception to be thrown here, as we are trying to use v2 contract without migrating refs.
        token_components_v2::set_description(creator, token, utf8(b"v2 token description"));
    }

    #[test(creator = @0x123, migration = @migration)]
    /// Example of creating a v1 TokenRefs property_mutator_ref and then migrating it to v2 TokenRefs property_mutator_ref.
    fun test_property_mutator_ref_migration(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);
        token_components::add_property(
            creator,
            token,
            string::utf8(b"u8"),
            string::utf8(b"u8"),
            bcs::to_bytes<u8>(&0x12),
        );

        migration::migrate_vx_to_vy_collection_refs_and_properties(creator, collection);
        migration::migrate_vx_to_vy_token_refs_and_properties(creator, token);

        // Now try updating properties for the token.
        token_components_v2::update_property(
            creator,
            token,
            string::utf8(b"u8"),
            string::utf8(b"u8"),
            bcs::to_bytes<u8>(&0x45),
        );
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393217, location = minter_v2::token_components_v2)]
    fun fails_to_transfer_when_property_mutator_ref_is_not_migrated(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);
        token_components::add_property(
            creator,
            token,
            string::utf8(b"u8"),
            string::utf8(b"u8"),
            bcs::to_bytes<u8>(&0x12),
        );
        migration::migrate_vx_to_vy_collection_refs_and_properties(creator, collection);

        // Now try updating properties for the token, this will fail as we did not migrate the property mutator ref.
        token_components_v2::update_property(
            creator,
            token,
            string::utf8(b"u8"),
            string::utf8(b"u8"),
            bcs::to_bytes<u8>(&0x45),
        );
    }
}
