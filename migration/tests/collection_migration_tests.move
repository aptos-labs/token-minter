#[test_only]
module migration::collection_migration_tests {
    use std::option;
    use std::signer;
    use std::string::utf8;

    use aptos_token_objects::collection;
    use aptos_token_objects::royalty;
    use migration::migration;

    use minter::collection_components;
    use minter::collection_properties;
    use minter::collection_utils;
    use minter_v2::collection_components_v2;
    use minter_v2::collection_properties_v2;

    #[test_only]
    fun setup(creator: &signer) {
        migration::init_module_for_testing(creator);
    }

    #[test(creator = @0x123, migration = @migration)]
    /// Example of creating a v1 CollectionRefs extend ref and then migrating it to v2 CollectionRefs extend ref.
    fun test_collection_extend_ref_migration(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);

        // =============================== Test v1 refs =============================== //
        // We check to see all v1 refs working as expected.

        // extend_ref test - get collection_signer from v1 contract - this should not throw
        let _collection_signer = &collection_components::collection_object_signer(creator, collection);

        // mutator_ref test
        collection_components::set_collection_description(
            creator,
            collection,
            utf8(b"updated test collection description"),
        );
        assert!(collection::description(collection) == utf8(b"updated test collection description"), 0);

        // royalty_mutator_ref test
        let royalty = royalty::create(0, 100, signer::address_of(creator));
        collection_components::set_collection_royalties(creator, collection, royalty);
        assert!(royalty::get(collection) == option::some(royalty), 0);

        // // =============================== MIGRATION OCCURS HERE =============================== //
        // Call intermediary contract to migrate the collection refs from v1 to v2
        migration::migrate_vx_to_vy_collection_refs_and_properties(creator, collection);

        // =============================== Test v2 refs =============================== //

        // extend_ref test - get collection_signer from v2 contract - this should not throw
        let _collection_signer = collection_components_v2::collection_object_signer(creator, collection);

        // royalty_mutator_ref test
        let royalty_v2 = royalty::create(50, 100, signer::address_of(creator));
        collection_components_v2::set_collection_royalties(creator, collection, royalty_v2);
        assert!(royalty::get(collection) == option::some(royalty_v2), 0);

        // mutator_ref test
        collection_components_v2::set_collection_description(creator, collection, utf8(b"v2 collection description"));
        assert!(collection::description(collection) == utf8(b"v2 collection description"), 0);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393217, location = minter_v2::collection_properties_v2)]
    /// Example of trying to mutate a collection using v2 contract and CollectionRefs, but without migrating the CollectionRefs mutator ref.
    fun fails_to_mutate_when_mutator_ref_is_not_migrated(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        // let collection_signer = &collection_components::collection_object_signer(creator, collection);

        // We will call the v2 contract now, but should expect failure if user does not migrate the mutator ref.
        // We expect exception to be thrown here, as we are trying to use v2 contract without migrating the mutator ref.
        collection_components_v2::set_collection_description(creator, collection, utf8(b"v2 collection description"));
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393217, location = minter_v2::collection_components_v2)]
    /// Example of trying to mutate a collection using v2 contract and CollectionRefs, but without migrating the CollectionRefs extend ref.
    fun fails_to_get_signer_when_extend_ref_is_not_migrated(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        // Now get collection_signer from v2 contract, this throws as the extend ref was not migrated
        let _collection_signer = collection_components_v2::collection_object_signer(creator, collection);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393217, location = minter_v2::collection_properties_v2)]
    /// Example of trying to change collection's royalty, but without migrating the CollectionRefs royalty mutator ref.
    fun fails_to_mutate_when_royalty_mutator_ref_is_not_migrated(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);
        // let collection_signer = &collection_components::collection_object_signer(creator, collection);
        let royalty = royalty::create(0, 100, signer::address_of(creator));

        // This throws
        collection_components_v2::set_collection_royalties(creator, collection, royalty);
    }

    // =============================== CollectionProperties Migration =============================== //

    #[test(creator = @0x123, migration = @migration)]
    /// Example of creating a v1 CollectionProperties and then migrating it to v2 CollectionProperties.
    /// This test will create a collection with v1 CollectionProperties and then migrate it to v2 CollectionProperties.
    fun test_collection_properties_migration(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);

        // Use the v1 contract and CollectionProperties to set collection properties
        collection_properties::set_mutable_description(creator, collection, false);
        assert!(collection_properties::is_mutable_description(collection) == false, 0);

        // =============================== MIGRATION OCCURS HERE =============================== //

        // We will call the v2 contract now, as we will simulate a migration from v1 to v2.
        // First, we must migrate the properties that belong to the collection.
        // This will create the new CollectionProperties defined in v2 contract.
        migration::migrate_vx_to_vy_collection_refs_and_properties(creator, collection);

        // Now try setting the collection properties again, but using the v2 CollectionProperties and v2 contract.
        collection_properties_v2::set_mutable_token_name(creator, collection, false);
        assert!(collection_properties_v2::is_mutable_token_name(collection) == false, 0);

        collection_properties_v2::set_tokens_burnable_by_collection_owner(creator, collection, false);
        assert!(collection_properties_v2::is_tokens_burnable_by_collection_owner(collection) == false, 0);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393217, location = minter_v2::collection_properties_v2)]
    /// Example of trying to mutate a collection using v2 contract and CollectionProperties, but without migrating the CollectionProperties.
    fun fails_to_mutate_when_collection_properties_are_not_migrated(creator: &signer, migration: &signer) {
        setup(migration);
        let collection = collection_utils::create_collection_with_refs(creator);

        // We will call the v2 contract now, but should expect failure if user does not migrate the properties.
        // We expect exception to be thrown here, as we are trying to use v2 contract without migrating the properties.
        collection_properties_v2::set_mutable_token_name(creator, collection, false);
    }
}
