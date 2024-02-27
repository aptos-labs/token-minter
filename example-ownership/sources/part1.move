module example_ownership::part1 {
    #[test_only]
    use aptos_framework::object;
    #[test_only]
    use aptos_token_objects::collection;
    #[test_only]
    use aptos_token_objects::token;
    #[test_only]
    use minter::token_minter;
    #[test_only]
    use std::option;
    #[test_only]
    use std::string::{utf8};
    #[test_only]
    use std::signer::{address_of};
    #[test_only]
    use std::vector;
    #[test_only]
    use minter::collection_refs::{set_collection_description};

    #[test_only]
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinterDetails has key {
        object_addr: address,
    }

    #[test(creator = @0x123, minter = @0x456)]
    fun part1(creator: &signer, minter: &signer) {
        let minter_addr = address_of(minter);

        let token_minter_obj = token_minter::init_token_minter_object(
            creator,
            utf8(b"test collection description"),
            option::none(),
            utf8(b"test collection name"),
            utf8(b"https://www.google.com"),
            true, // mutable_description
            true, // mutable_royalty
            true, // mutable_uri
            true, // mutable_token_description
            true, // mutable_token_name
            true, // mutable_token_properties
            true, // mutable_token_uri
            true, // tokens_burnable_by_creator
            true, // tokens_freezable_by_creator
            option::none(), // royalty
            false, // creator_mint_only
            false, // soulbound
        );

        let collection = token_minter::collection(token_minter_obj);
        set_collection_description(creator, collection, utf8(b"updated test collection description"));
        assert!(collection::description(collection) == utf8(b"updated test collection description"), 0);

        // lets say now i don't have token minter object handy, lets see how easy to retrieve it
        // it will require off chain passing in the object address and then we generate the object from address for mutation.

        token_minter::set_version(creator, token_minter_obj, 1);
        assert!(token_minter::version(token_minter_obj) == 1, 0);

        let minted_tokens_object = token_minter::mint_tokens_object(
            minter,
            token_minter_obj,
            utf8(b"test token"),
            utf8(b"test token description"),
            utf8(b"https://www.google.com"),
            1,
            vector[vector[]],
            vector[vector[]],
            vector[vector[]],
            vector[minter_addr],
        );
        let minted_token = *vector::borrow(&minted_tokens_object, 0);
        assert!(token_minter::tokens_minted(token_minter_obj) == 1, 0);

        token_minter::set_token_description<token::Token>(creator, minted_token, utf8(b"updated test token description"));
        assert!(token::description(minted_token) == utf8(b"updated test token description"), 0);

        // lets say i wanna add additional struct to tokenminter, need to get tokenminter object address first
        let token_minter_object_address = object::object_address<token_minter::TokenMinter>(&token_minter_obj);
        let token_minter_signer = token_minter::token_minter_signer(creator, token_minter_obj);
        move_to(&token_minter_signer, TokenMinterDetails {
            object_addr: token_minter_object_address
        });

        // then verify TokenMinterDetails exist in the same object account
        assert!(object::object_exists<TokenMinterDetails>(token_minter_object_address), 0);
        assert!(object::object_exists<token_minter::TokenMinter>(token_minter_object_address), 0);
    }
}
