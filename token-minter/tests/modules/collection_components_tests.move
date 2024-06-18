#[test_only]
module minter::collection_components_tests {
    use std::option::Self;
    use std::string;
    use std::string::utf8;
    use aptos_framework::object::{Self, ConstructorRef, Object};
    use aptos_framework::signer;

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::royalty;
    use minter::migration_utils::create_migration_object_signer;

    use minter::collection_components::{Self, CollectionRefs};
    use minter::collection_properties;
    use minter::collection_utils;

    #[test(creator = @0x123)]
    fun test_create_refs_and_properties(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);

        assert!(collection_components::collection_refs_exist(object::object_address(&collection)), 0);
        assert!(collection_properties::collection_properties_exists(collection), 0);
    }

    #[test(creator = @0x123)]
    fun test_set_collection_name(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let new_name = utf8(b"Updated Name");
        assert!(collection_components::is_mutable_name(collection), 0);

        collection_components::set_collection_name(creator, collection, new_name);
        assert!(collection::name(collection) == new_name, 0);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327683, location = minter::collection_components)]
    fun test_set_non_mutable_collection_name_fails(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);

        // Set the name property to non-mutable
        collection_properties::set_mutable_name(creator, collection, false);

        // Attempt to update the collection name, should fail
        let new_name = utf8(b"Non-Mutable Name");
        collection_components::set_collection_name(creator, collection, new_name);
    }

    #[test(creator = @0x123)]
    fun test_set_collection_description(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let new_description = utf8(b"Updated Description");
        assert!(collection_components::is_mutable_description(collection), 0);

        collection_components::set_collection_description(creator, collection, new_description);
        assert!(collection::description(collection) == new_description, 0);
    }

    #[test(creator = @0x123)]
    fun test_set_collection_max_supply(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let new_max_supply = 100;
        assert!(collection_components::is_mutable_max_supply(collection), 0);

        collection_components::set_collection_max_supply(creator, collection, new_max_supply);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327683, location = minter::collection_components)]
    fun test_set_non_mutable_collection_max_supply_fails(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);

        // Set the max supply property to non-mutable
        collection_properties::set_mutable_max_supply(creator, collection, false);

        // Attempt to update the collection max supply, should fail
        collection_components::set_collection_max_supply(creator, collection, 100);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327683, location = minter::collection_components)]
    fun test_set_non_mutable_collection_description_fails(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);

        // Set the description property to non-mutable
        collection_properties::set_mutable_description(creator, collection, false);

        // Attempt to update the collection description, should fail
        let new_description = utf8(b"Non-Mutable Description");
        collection_components::set_collection_description(creator, collection, new_description);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 196611, location = minter::collection_properties)]
    fun exception_when_setting_collection_properties_more_than_once(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);

        collection_properties::set_mutable_description(creator, collection, false);

        // This should fail, as it has already then set once,
        collection_properties::set_mutable_description(creator, collection, true);
    }

    #[test(creator = @0x123)]
    fun test_set_collection_uri(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let new_uri = utf8(b"https://new-example.com");
        assert!(collection_components::is_mutable_uri(collection), 0);

        collection_components::set_collection_uri(creator, collection, new_uri);
        assert!(collection::uri(collection) == new_uri, 0);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327683, location = minter::collection_components)]
    fun test_set_non_mutable_collection_uri_fails(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);

        collection_properties::set_mutable_uri(creator, collection, false);

        let new_uri = utf8(b"https://non-mutable.com");
        collection_components::set_collection_uri(creator, collection, new_uri);
    }

    #[test(creator = @0x123)]
    fun test_set_collection_royalties(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        assert!(collection_components::is_mutable_royalty(collection), 0);

        let new_royalty = royalty::create(5, 100, signer::address_of(creator));
        collection_components::set_collection_royalties(creator, collection, new_royalty);
        let royalty_info = royalty::get(collection);

        // Verify collection now has royalties (previously is was not set)
        assert!(option::is_some(&royalty_info), 0);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327683, location = minter::collection_components)]
    fun test_set_non_mutable_collection_royalties_fails(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        collection_properties::set_mutable_royalty(creator, collection, false);
        let new_royalty = royalty::create(5, 100, signer::address_of(creator));
        collection_components::set_collection_royalties(creator, collection, new_royalty);
    }

    #[test(creator = @0x123, user = @456)]
    fun test_transfer_as_owner(creator: &signer, user: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let user_addr = signer::address_of(user);
        collection_components::transfer_as_owner(creator, collection, user_addr);

        assert!(object::owner(collection) == user_addr, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::collection_components)]
    fun test_set_collection_description_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let new_description = utf8(b"Unauthorized Description Change Attempt");
        collection_components::set_collection_description(user, collection, new_description);
    }

    #[test(creator = @0x123, user = @456)]
    #[expected_failure(abort_code = 327682, location = minter::collection_components)]
    fun test_set_collection_uri_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let new_uri = utf8(b"https://unauthorized-uri-change.com");
        collection_components::set_collection_uri(user, collection, new_uri);
    }

    #[test(creator = @0x123, user = @456)]
    #[expected_failure(abort_code = 327682, location = minter::collection_components)]
    fun test_set_collection_royalties_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let new_royalty = royalty::create(10, 100, signer::address_of(user));
        collection_components::set_collection_royalties(user, collection, new_royalty);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393219, location = minter::collection_components)]
    fun test_set_description_fails_when_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove mutator ref from `CollectionRefs`
        collection_components::migrate_out_mutator_ref(&migration_object_signer, creator, collection);

        let new_description = utf8(b"Description after migration");
        collection_components::set_collection_description(creator, collection, new_description);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393219, location = minter::collection_components)]
    fun test_set_royalties_fails_when_royalty_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove royalty mutator ref from `CollectionRefs`
        collection_components::migrate_out_royalty_mutator_ref(&migration_object_signer, creator, collection);

        let new_royalty = royalty::create(10, 100, signer::address_of(creator));
        collection_components::set_collection_royalties(creator, collection, new_royalty);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393219, location = minter::collection_components)]
    fun test_set_uri_fails_when_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove mutator ref from `CollectionRefs`
        collection_components::migrate_out_mutator_ref(&migration_object_signer, creator, collection);

        let new_uri = utf8(b"https://new-uri-after-migration.com");
        collection_components::set_collection_uri(creator, collection, new_uri);
    }

    #[test(creator = @0x123, user = @456, migration = @migration)]
    #[expected_failure(abort_code = 393221, location = minter::collection_components)]
    fun test_transfer_as_owner_fails_when_transfer_ref_dropped(creator: &signer, user: &signer, migration: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove transfer ref from `CollectionRefs`
        collection_components::migrate_out_transfer_ref(&migration_object_signer, creator, collection);

        collection_components::transfer_as_owner(creator, collection, signer::address_of(user));
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393220, location = minter::collection_components)]
    fun test_extend_ref_fails_when_extend_ref_dropped(creator: &signer, migration: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove extend ref from `CollectionRefs`
        collection_components::migrate_out_extend_ref(&migration_object_signer, creator, collection);
        let _collection_signer = collection_components::collection_object_signer(creator, collection);
    }


    #[test(creator = @0x123, user = @456, migration = @migration)]
    #[expected_failure(abort_code = 393221, location = minter::collection_components)]
    fun test_transfer_as_owner_fails_without_transfer_ref(creator: &signer, user: &signer, migration: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        collection_properties::set_tokens_transferable_by_collection_owner(creator, collection, false);

        let migration_object_signer = create_migration_object_signer(migration);

        // Remove transfer ref from `CollectionRefs`
        collection_components::migrate_out_transfer_ref(&migration_object_signer, creator, collection);

        // This should fail as we removed the transfer ref
        collection_components::transfer_as_owner(creator, collection, signer::address_of(user));
    }

    #[test(creator = @0x123)]
    fun test_add_remove_update_property_map_functions(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        assert!(collection_components::is_mutable_properties(collection), 0);

        let property_name = utf8(b"u8");
        let property_type = utf8(b"u8");
        collection_components::add_property(creator, collection, property_name, property_type, vector [10]);
        assert!(property_map::read_u8(&collection, &property_name) == 10, 0);

        collection_components::remove_property(creator, collection, property_name);
        assert!(!property_map::contains_key(&collection, &property_name), 0);

        collection_components::add_typed_property<u8>(creator, collection, property_name, 20);
        assert!(property_map::read_u8(&collection, &property_name) == 20, 0);

        collection_components::update_property(creator, collection, property_name, property_type, vector[30]);
        assert!(property_map::read_u8(&collection, &property_name) == 30, 0);

        collection_components::update_typed_property<u8>(creator, collection, property_name, 40);
        assert!(property_map::read_u8(&collection, &property_name) == 40, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::collection_components)]
    fun test_add_property_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        collection_components::add_property(user, collection, property_name, property_type, vector [10]);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327686, location = minter::collection_components)]
    fun test_set_non_mutable_add_property_fails(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        collection_properties::set_mutable_properties(creator, collection, false);

        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        collection_components::add_property(creator, collection, property_name, property_type, vector [10]);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::collection_components)]
    fun test_add_typed_property_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let property_name = string::utf8(b"u8");
        collection_components::add_typed_property<u8>(user, collection, property_name, 10);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327686, location = minter::collection_components)]
    fun test_set_non_mutable_add_typed_property_fails(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        collection_properties::set_mutable_properties(creator, collection, false);

        let property_name = string::utf8(b"u8");
        collection_components::add_typed_property<u8>(creator, collection, property_name, 10);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::collection_components)]
    fun test_remove_property_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let property_name = string::utf8(b"u8");
        collection_components::add_typed_property<u8>(creator, collection, property_name, 10);

        collection_components::remove_property(user, collection, property_name);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327686, location = minter::collection_components)]
    fun test_set_non_mutable_remove_property_fails(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);

        collection_properties::set_mutable_properties(creator, collection, false);
        let property_name = string::utf8(b"u8");
        collection_components::add_typed_property<u8>(creator, collection, property_name, 10);
        collection_components::remove_property(creator, collection, property_name);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::collection_components)]
    fun test_update_property_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        collection_components::add_property(creator, collection, property_name, property_type, vector[10]);

        let new_value = 20;
        collection_components::update_property(user, collection, property_name, property_type, vector[new_value]);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327686, location = minter::collection_components)]
    fun test_set_non_mutable_update_property_fails(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        collection_properties::set_mutable_properties(creator, collection, false);

        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        collection_components::add_property(creator, collection, property_name, property_type, vector[10]);

        let new_value = 20;
        collection_components::update_property(creator, collection, property_name, property_type, vector[new_value]);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::collection_components)]
    fun test_update_typed_property_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let property_name = string::utf8(b"u8");
        collection_components::add_typed_property<u8>(creator, collection, property_name, 10);

        let new_value = 20;
        collection_components::update_typed_property<u8>(user, collection, property_name, new_value);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327686, location = minter::collection_components)]
    fun test_set_non_mutable_update_typed_property_fails(creator: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        collection_properties::set_mutable_properties(creator, collection, false);

        let property_name = string::utf8(b"u8");
        collection_components::add_typed_property<u8>(creator, collection, property_name, 10);

        let new_value = 20;
        collection_components::update_typed_property<u8>(creator, collection, property_name, new_value);
    }

    #[test(creator = @0x123, user = @456)]
    #[expected_failure(abort_code = 327682, location = minter::collection_components)]
    fun test_non_collection_owner_can_update_collection(creator: &signer, user: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let user_addr = signer::address_of(user);
        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        let initial_value = vector[10];

        // Collection owner adds a property
        collection_components::add_property(creator, collection, property_name, property_type, initial_value);
        collection_components::transfer_as_owner(creator, collection, user_addr);

        // This should fail as only `collection owner` can update token - which is the user as it got transferred above.
        let new_value = vector[50];
        collection_components::update_property(creator, collection, property_name, property_type, new_value);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393223, location = minter::collection_components)]
    fun test_add_property_fails_when_property_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove property mutator ref from `CollectionRefs`
        collection_components::migrate_out_property_mutator_ref(&migration_object_signer, creator, collection);

        let property_name = utf8(b"u8");
        let property_type = utf8(b"u8");
        let value = vector[10];
        collection_components::add_property(creator, collection, property_name, property_type, value);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393223, location = minter::collection_components)]
    fun test_update_property_fails_when_property_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        let property_name = utf8(b"u8");
        let property_type = utf8(b"u8");
        let initial_value = vector[10];
        // Add property before dropping the ref
        collection_components::add_property(creator, collection, property_name, property_type, initial_value);

        // Remove property mutator ref from `CollectionRefs`
        collection_components::migrate_out_property_mutator_ref(&migration_object_signer, creator, collection);

        let new_value = vector[50];
        collection_components::update_property(creator, collection, property_name, property_type, new_value);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393223, location = minter::collection_components)]
    fun test_remove_property_fails_when_property_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, _, collection) = create_test_collection_with_refs_and_properties(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        let property_name = utf8(b"u8");
        let property_type = utf8(b"u8");
        let value = vector[10];
        collection_components::add_property(creator, collection, property_name, property_type, value);

        // Remove property mutator ref from `CollectionRefs`
        collection_components::migrate_out_property_mutator_ref(&migration_object_signer, creator, collection);

        collection_components::remove_property(creator, collection, property_name);
    }

    #[test_only]
    fun create_test_collection_with_refs_and_properties(
        creator: &signer,
    ): (ConstructorRef, Object<CollectionRefs>, Object<Collection>) {
        let collection_constructor = collection_utils::create_unlimited_collection(creator);
        let refs = minter::collection_components::create_refs_and_properties(&collection_constructor);
        property_map::init(&collection_constructor, property_map::prepare_input(vector[], vector[], vector[]));
        let collection = object::object_from_constructor_ref(&collection_constructor);
        (collection_constructor, refs, collection)
    }
}
