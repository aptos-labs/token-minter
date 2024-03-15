module example_composable::main {
    #[test_only]
    use std::option;
    #[test_only]
    use std::signer::address_of;
    #[test_only]
    use std::string::utf8;
    #[test_only]
    use aptos_framework::object;
    #[test_only]
    use aptos_token_objects::collection;
    #[test_only]
    use aptos_token_objects::collection::Collection;
    #[test_only]
    use aptos_token_objects::royalty;
    #[test_only]
    use aptos_token_objects::token;
    #[test_only]
    use aptos_token_objects::token::Token;
    #[test_only]
    use minter::collection_components;
    #[test_only]
    use minter::token_components;

    #[test(creator = @0x123, user = @0x456)]
    fun main(creator: &signer, user: &signer) {
        let creator_addr = address_of(creator);
        let user_addr = address_of(user);

        // First create the collection via the aptos-token-objects framework
        let sword_collection_construtor_ref = &collection::create_unlimited_collection(
            creator,
            utf8(b"sword collection"),
            utf8(b"swords"),
            option::none(),
            utf8(b"https://example.com/swords"),
        );
        collection_components::create_refs_and_properties(sword_collection_construtor_ref);
        let sword_collection = object::object_from_constructor_ref<Collection>(sword_collection_construtor_ref);

        let powerup_collection_constructor_ref = &collection::create_unlimited_collection(
            creator,
            utf8(b"powerup collection"),
            utf8(b"powerups"),
            option::none(),
            utf8(b"https://example.com/powerups"),
        );

        // Create and initialize collection properties
        collection_components::create_refs_and_properties(powerup_collection_constructor_ref);
        let powerup_collection = object::object_from_constructor_ref<Collection>(powerup_collection_constructor_ref);

        // Create Sword token from Sword collection
        let sword_token_constructor_ref = &token::create(
            creator,
            collection::name(sword_collection),
            utf8(b"A fancy sword"),
            utf8(b"Sword"),
            royalty::get(sword_collection),
            utf8(b"https://example.com/sword1.png"),
        );
        token_components::create_refs(sword_token_constructor_ref);

        let sword_token_obj = object::object_from_constructor_ref<Token>(sword_token_constructor_ref);
        let sword_token_addr = object::object_address(&sword_token_obj);
        assert!(object::owner(sword_token_obj) == creator_addr, 0);

        // Create Powerup token from Powerup collection
        let powerup_token_constructor_ref = &token::create(
            creator,
            collection::name(powerup_collection),
            utf8(b"A fancy powerup"),
            utf8(b"Powerup"),
            royalty::get(powerup_collection),
            utf8(b"https://example.com/powerup1.png"),
        );
        token_components::create_refs(powerup_token_constructor_ref);

        let powerup_token_obj = object::object_from_constructor_ref<Token>(powerup_token_constructor_ref);
        assert!(object::owner(powerup_token_obj) == creator_addr, 0);

        // Transfer powerup to the sword
        object::transfer(creator, powerup_token_obj, sword_token_addr);
        assert!(object::owner(powerup_token_obj) == sword_token_addr, 1);

        // Transfer powerup to a new user as the collection creator
        token_components::transfer_as_collection_owner(
            creator,
            powerup_token_obj,
            user_addr,
        );
        assert!(object::owner(powerup_token_obj) == user_addr, 2);

        // Transfer powerup to the sword
        object::transfer(user, powerup_token_obj, sword_token_addr);
        assert!(object::owner(powerup_token_obj) == sword_token_addr, 3);

        // Transfer powerup back to the user as the token owner/creator
        object::transfer(creator, powerup_token_obj, user_addr);
        assert!(object::owner(powerup_token_obj) == user_addr, 4);
    }
}
