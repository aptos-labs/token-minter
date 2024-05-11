#[test_only]
module minter::token_components_tests {
    use std::string;
    use std::string::utf8;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::signer;

    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

    use minter::collection_properties::Self;
    use minter::collection_utils;
    use minter::migration_utils::create_migration_object_signer;
    use minter::token_components::Self;
    use minter::token_utils;

    #[test(creator = @0x123)]
    fun test_create_token_refs(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        assert!(token_components::token_refs_exist(object::object_address(&token)), 0);
    }

    #[test(creator = @0x123)]
    fun test_set_token_description(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        assert!(token_components::is_mutable_description(token), 0);

        let new_description = utf8(b"Updated Sword Description");
        token_components::set_description(creator, token, new_description);

        assert!(token::description(token) == new_description, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_set_token_description_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let new_description = utf8(b"User Sword Description");
        token_components::set_description(user, token, new_description);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327683, location = minter::token_components)]
    fun test_set_non_mutable_token_description_fails(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        collection_properties::set_mutable_token_description(creator, token::collection_object(token), false);

        let new_description = utf8(b"Non-Mutable Sword Description");
        token_components::set_description(creator, token, new_description);
    }

    #[test(creator = @0x123)]
    fun test_set_token_name(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let new_name = utf8(b"Legendary Sword");

        assert!(token_components::is_mutable_name(token), 0);

        token_components::set_name(creator, token, new_name);

        assert!(token::name(token) == new_name, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_set_token_name_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let new_name = utf8(b"Non-Mutable Legendary Sword");
        token_components::set_name(user, token, new_name);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327683, location = minter::token_components)]
    fun test_set_non_mutable_token_name_fails(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);

        // Set the name property to non-mutable
        collection_properties::set_mutable_token_name(creator, token::collection_object(token), false);

        let new_name = utf8(b"Non-Mutable Legendary Sword");
        token_components::set_name(creator, token, new_name);
    }

    #[test(creator = @0x123)]
    fun test_set_token_uri(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let new_uri = utf8(b"https://set-token-uri/legendary-sword.png");
        assert!(token_components::is_mutable_uri(token), 0);

        token_components::set_uri(creator, token, new_uri);
        assert!(token::uri(token) == new_uri, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_set_token_uri_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let new_uri = utf8(b"https://non-mutable.com/legendary-sword.png");
        token_components::set_uri(user, token, new_uri);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327683, location = minter::token_components)]
    fun test_set_non_mutable_token_uri_fails(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        collection_properties::set_mutable_token_uri(creator, token::collection_object(token), false);
        let new_uri = utf8(b"https://non-mutable.com/legendary-sword.png");
        token_components::set_uri(creator, token, new_uri);
    }

    #[test(creator = @0x123, user = @456)]
    fun test_transfer_token_as_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let user_addr = signer::address_of(user);
        token_components::transfer_as_collection_owner(creator, token, user_addr);

        assert!(object::owner(token) == user_addr, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_transfer_token_as_collection_owner_fails_when_not_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        token_components::transfer_as_collection_owner(user, token, signer::address_of(user));
    }

    #[test(creator = @0x123, user = @456)]
    #[expected_failure(abort_code = 327686, location = minter::token_components)]
    fun test_transfer_token_as_collection_owner_fails_when_property_disasbled(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);

        collection_properties::set_tokens_transferable_by_collection_owner(
            creator,
            token::collection_object(token),
            false,
        );

        token_components::transfer_as_collection_owner(creator, token, signer::address_of(user));
    }

    #[test(creator = @0x123, user = @456, migration = @migration)]
    #[expected_failure(abort_code = 393222, location = minter::token_components)]
    fun test_transfer_token_as_collection_owner_fails_when_transfer_ref_dropped(
        creator: &signer,
        user: &signer,
        migration: &signer,
    ) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove transfer ref from `TokenRefs`
        token_components::migrate_out_transfer_ref(&migration_object_signer, creator, token);

        token_components::transfer_as_collection_owner(creator, token, signer::address_of(user));
    }

    #[test(creator = @0x123, user = @456)]
    #[expected_failure(abort_code = 327683, location = aptos_framework::object)]
    fun transfer_fails_when_token_is_soulbound(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        token_components::freeze_transfer(creator, token);

        // Attempting to transfer the token should fail, as transfers are frozen
        object::transfer(creator, token, signer::address_of(user));
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_freeze_transfer_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        token_components::freeze_transfer(user, token);
    }

    #[test(creator = @0x123, user = @456)]
    fun test_unfreeze_transfer(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);

        token_components::freeze_transfer(creator, token);
        token_components::unfreeze_transfer(creator, token);

        let user_addr = signer::address_of(user);
        object::transfer(creator, token, user_addr);

        assert!(object::owner(token) == user_addr, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_unfreeze_transfer_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        token_components::unfreeze_transfer(user, token);
    }

    #[test(creator = @0x123)]
    fun test_burn_token_as_collection_owner(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        token_components::burn(creator, token);

        assert!(!object::object_exists<Token>(object::object_address(&token)), 0);
    }

    #[test(creator = @0x123, user = @456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_burn_token_as_non_collection_owner_fails(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        token_components::burn(user, token);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327684, location = minter::token_components)]
    fun test_burn_token_as_collection_owner_fails_when_property_disabled(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        collection_properties::set_tokens_burnable_by_collection_owner(creator, token::collection_object(token), false);

        token_components::burn(creator, token);
    }

    #[test(creator = @0x123)]
    fun test_add_property(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        assert!(token_components::are_properties_mutable(token), 0);

        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        token_components::add_property(creator, token, property_name, property_type, vector [10]);

        assert!(property_map::read_u8(&token, &property_name) == 10, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_add_property_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        token_components::add_property(user, token, property_name, property_type, vector [10]);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327685, location = minter::token_components)]
    fun test_set_non_mutable_add_property_fails(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        collection_properties::set_mutable_token_properties(creator, token::collection_object(token), false);

        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        token_components::add_property(creator, token, property_name, property_type, vector [10]);
    }

    #[test(creator = @0x123)]
    fun test_add_typed_property(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        assert!(token_components::are_properties_mutable(token), 0);

        let property_name = string::utf8(b"u8");
        token_components::add_typed_property<u8>(creator, token, property_name, 10);

        assert!(property_map::read_u8(&token, &property_name) == 10, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_add_typed_property_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let property_name = string::utf8(b"u8");
        token_components::add_typed_property<u8>(user, token, property_name, 10);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327685, location = minter::token_components)]
    fun test_set_non_mutable_add_typed_property_fails(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        collection_properties::set_mutable_token_properties(creator, token::collection_object(token), false);

        let property_name = string::utf8(b"u8");
        token_components::add_typed_property<u8>(creator, token, property_name, 10);
    }

    #[test(creator = @0x123)]
    fun test_remove_property(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let property_name = string::utf8(b"u8");
        token_components::add_typed_property<u8>(creator, token, property_name, 10);
        token_components::remove_property(creator, token, property_name);

        assert!(!property_map::contains_key(&token, &property_name), 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_remove_property_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let property_name = string::utf8(b"u8");
        token_components::add_typed_property<u8>(creator, token, property_name, 10);

        token_components::remove_property(user, token, property_name);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327685, location = minter::token_components)]
    fun test_set_non_mutable_remove_property_fails(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);

        collection_properties::set_mutable_token_properties(creator, token::collection_object(token), false);
        let property_name = string::utf8(b"u8");
        token_components::add_typed_property<u8>(creator, token, property_name, 10);
        token_components::remove_property(creator, token, property_name);
    }

    #[test(creator = @0x123)]
    fun test_update_property(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        token_components::add_property(creator, token, property_name, property_type, vector[10]);

        let new_value = 20;
        token_components::update_property(creator, token, property_name, property_type, vector[new_value]);

        assert!(property_map::read_u8(&token, &property_name) == new_value, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_update_property_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        token_components::add_property(creator, token, property_name, property_type, vector[10]);

        let new_value = 20;
        token_components::update_property(user, token, property_name, property_type, vector[new_value]);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327685, location = minter::token_components)]
    fun test_set_non_mutable_update_property_fails(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        collection_properties::set_mutable_token_properties(creator, token::collection_object(token), false);

        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        token_components::add_property(creator, token, property_name, property_type, vector[10]);

        let new_value = 20;
        token_components::update_property(creator, token, property_name, property_type, vector[new_value]);
    }

    #[test(creator = @0x123)]
    fun test_update_typed_property(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let property_name = string::utf8(b"u8");
        token_components::add_typed_property<u8>(creator, token, property_name, 10);

        let new_value = 20;
        token_components::update_typed_property<u8>(creator, token, property_name, new_value);

        assert!(property_map::read_u8(&token, &property_name) == new_value, 0);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_update_typed_property_fails_as_non_collection_owner(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let property_name = string::utf8(b"u8");
        token_components::add_typed_property<u8>(creator, token, property_name, 10);

        let new_value = 20;
        token_components::update_typed_property<u8>(user, token, property_name, new_value);
    }

    #[test(creator = @0x123)]
    #[expected_failure(abort_code = 327685, location = minter::token_components)]
    fun test_set_non_mutable_update_typed_property_fails(creator: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        collection_properties::set_mutable_token_properties(creator, token::collection_object(token), false);

        let property_name = string::utf8(b"u8");
        token_components::add_typed_property<u8>(creator, token, property_name, 10);

        let new_value = 20;
        token_components::update_typed_property<u8>(creator, token, property_name, new_value);
    }

    #[test(creator = @0x123, user = @456)]
    #[expected_failure(abort_code = 327682, location = minter::token_components)]
    fun test_new_token_owner_cannot_update_token(creator: &signer, user: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let user_addr = signer::address_of(user);
        let property_name = string::utf8(b"u8");
        let property_type = string::utf8(b"u8");
        let initial_value = vector[10];

        // Collection owner adds a property
        token_components::add_property(creator, token, property_name, property_type, initial_value);
        token_components::transfer_as_collection_owner(creator, token, user_addr);

        // New owner updates the property
        // This should fail as only `collection owner` can update token
        let new_value = vector[50];
        token_components::update_property(user, token, property_name, property_type, new_value);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393219, location = minter::token_components)]
    fun test_set_description_fails_when_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove mutator ref from `TokenRefs`
        token_components::migrate_out_mutator_ref(&migration_object_signer, creator, token);

        let new_description = utf8(b"Updated Sword Description");
        token_components::set_description(creator, token, new_description);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393219, location = minter::token_components)]
    fun test_set_name_fails_when_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove mutator ref from `TokenRefs`
        token_components::migrate_out_mutator_ref(&migration_object_signer, creator, token);

        let new_name = utf8(b"Updated Sword Name");
        token_components::set_name(creator, token, new_name);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393219, location = minter::token_components)]
    fun test_set_uri_fails_when_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove mutator ref from `TokenRefs`
        token_components::migrate_out_mutator_ref(&migration_object_signer, creator, token);

        let new_uri = utf8(b"https://new-uri-for-token.com");
        token_components::set_uri(creator, token, new_uri);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393221, location = minter::token_components)]
    fun test_add_property_fails_when_property_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove property mutator ref from `TokenRefs`
        token_components::migrate_out_property_mutator_ref(&migration_object_signer, creator, token);

        let property_name = utf8(b"u8");
        let property_type = utf8(b"u8");
        let value = vector[10];
        token_components::add_property(creator, token, property_name, property_type, value);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393221, location = minter::token_components)]
    fun test_update_property_fails_when_property_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove property mutator ref from `TokenRefs`
        token_components::migrate_out_property_mutator_ref(&migration_object_signer, creator, token);

        let property_name = utf8(b"u8");
        let property_type = utf8(b"u8");
        let initial_value = vector[10];
        // Add property before dropping the ref
        token_components::add_property(creator, token, property_name, property_type, initial_value);

        let new_value = vector[50];
        token_components::update_property(creator, token, property_name, property_type, new_value);
    }

    #[test(creator = @0x123, migration = @migration)]
    #[expected_failure(abort_code = 393221, location = minter::token_components)]
    fun test_remove_property_fails_when_property_mutator_ref_dropped(creator: &signer, migration: &signer) {
        let (_, token) = create_test_token_with_refs_and_collection(creator);
        let migration_object_signer = create_migration_object_signer(migration);

        // Remove property mutator ref from `TokenRefs`
        token_components::migrate_out_property_mutator_ref(&migration_object_signer, creator, token);

        let property_name = utf8(b"u8");
        let property_type = utf8(b"u8");
        let value = vector[10];
        token_components::add_property(creator, token, property_name, property_type, value);
        token_components::remove_property(creator, token, property_name);
    }

    fun create_test_token_with_refs_and_collection(
        creator: &signer,
    ): (Object<Collection>, Object<Token>) {
        let collection = collection_utils::create_collection_with_refs(creator);
        let token = token_utils::create_token_with_refs(creator, collection);
        (collection, token)
    }
}
