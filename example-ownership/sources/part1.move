module example_ownership::part1 {
    #[test_only]
    use std::option;
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

    #[test_only]
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinterDetails has key {
        object_addr: address,
    }

    #[test_only]
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenDetails has key {
        object_addr: address,
    }

    #[test(creator = @0x123, _minter = @0x456)]
    fun part1(creator: &signer, _minter: &signer) {
        // First create the collection via the aptos-token-objects framework
        let collection_construtor_ref = &collection::create_unlimited_collection(
            creator,
            utf8(b"test collection description"),
            utf8(b"test collection name"),
            option::none(),
            utf8(b"https://www.google.com"),
        );

        // Create and initialize collection properties
        collection_components::create_refs_and_properties(collection_construtor_ref);
        let collection = object::object_from_constructor_ref<Collection>(collection_construtor_ref);

        collection_components::set_collection_description(creator, collection, utf8(b"updated test collection description"));
        assert!(collection::description(collection) == utf8(b"updated test collection description"), 0);

        // lets say now i don't have token minter object handy, lets see how easy to retrieve it
        // it will require off chain passing in the object address and then we generate the object from address for mutation.
        let token_constructor_ref = &token::create(
            creator,
            collection::name(collection),
            utf8(b"test token description"),
            utf8(b"test token"),
            royalty::get(collection),
            utf8(b"https://www.google.com"),
        );
        token_components::create_refs(token_constructor_ref);
        let minted_token = object::object_from_constructor_ref<Token>(token_constructor_ref);

        token_components::set_description(creator, minted_token, utf8(b"updated test token description"));
        assert!(token::description(minted_token) == utf8(b"updated test token description"), 0);

        // lets say i wanna add additional struct to token, need to get token signer.
        let token_signer = token_components::token_object_signer(creator, minted_token);
        let token_addr = object::object_address(&minted_token);
        move_to(&token_signer, TokenDetails { object_addr: token_addr });

        // then verify TokenDetails exist in the same object account as token
        assert!(object::object_exists<TokenDetails>(token_addr), 0);
        assert!(object::object_exists<Token>(token_addr), 0);
    }
}
