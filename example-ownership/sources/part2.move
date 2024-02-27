module example_ownership::part2 {
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use aptos_token_objects::token;
    use minter::token_minter;
    use std::option;
    use std::string::{utf8};
    use std::signer::{address_of};
    use std::vector;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinterPoints has key {
        loyalty: u64,
    }

    /// verify that:
    /// 1. user mint is controlled by whitelist
    /// 2. after launching token minter, we could extend the module by moving resources into the signer
    /// 3. we could easily edit extended struct
    /// 4. after launching token minter, we could add, edit, remove the extension/feature
    public fun mint_with_extensions_and_external_structs(creator: &signer, minter: &signer): (Object<token_minter::TokenMinter>, Object<token::Token>) acquires TokenMinterPoints {
        let token_minter_obj = create_token_minter_helper(creator);

        let token_minter_signer = token_minter::token_minter_signer(creator, token_minter_obj);
        move_to(&token_minter_signer, TokenMinterPoints {
            loyalty: 0
        });

        let token_minter_address = object::object_address<token_minter::TokenMinter>(&token_minter_obj);
        let points = borrow_global_mut<TokenMinterPoints>(token_minter_address);
        points.loyalty = 1;

        let whitelisted_address = vector[address_of(minter)];
        let max_mint_per_whitelists = vector[1];
        token_minter::add_or_update_whitelist(creator, token_minter_obj, whitelisted_address, max_mint_per_whitelists);
        let minted_token = create_token_helper(minter, token_minter_obj);

        object::transfer<token::Token>(minter, minted_token, address_of(creator));

        (token_minter_obj, minted_token)
    }

    fun create_token_minter_helper(creator: &signer): Object<token_minter::TokenMinter> {
        token_minter::init_token_minter_object(
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
        )
    }

    fun create_token_helper(minter: &signer, token_minter_obj: Object<token_minter::TokenMinter>): Object<token::Token> {
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
            vector[address_of(minter)],
        );
        *vector::borrow(&minted_tokens_object, 0)
    }

    #[test(creator = @0x123, minter = @0x456)]
    fun part2(creator: &signer, minter: &signer) acquires TokenMinterPoints {
        let (token_minter_obj, minted_token) = mint_with_extensions_and_external_structs(creator, minter);
        assert!(object::owner(token_minter_obj) == address_of(creator), 0);
        // verify that token owner transfer works after minting with whitelisted address
        assert!(object::owner(minted_token) == address_of(creator), 0);

        let token_minter_object_address = object::object_address<token_minter::TokenMinter>(&token_minter_obj);
        assert!(object::object_exists<TokenMinterPoints>(token_minter_object_address), 0);
        
        let points = borrow_global_mut<TokenMinterPoints>(token_minter_object_address);
        assert!(points.loyalty == 1, 0);
    }
}

