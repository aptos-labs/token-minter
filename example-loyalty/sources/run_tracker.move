module example_loyalty::main {
    use aptos_framework::object::{Self, Object};
    use minter::token_minter::{Self, TokenMinter, init_token_minter_object, mint_tokens_object};
    use std::option;
    use std::signer::{address_of};
    use std::string::{utf8};
    use std::vector;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct RunTracker has key {
        total_miles: u64,
        miles_left: u64,
    }
    
    struct AdminConfig has key {
        token_minter: Object<TokenMinter>,
    }

    fun init_module(admin: &signer) {
        let minter_obj = init_token_minter_object(
            admin,
            utf8(b"loyalty collection"),
            option::none(),
            utf8(b"run tracker"),
            utf8(b"soulbound"),
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            option::none(), // royalty
            false, // creator_mint_only
            true,
        );
        move_to(admin, AdminConfig {
            token_minter: minter_obj,
        });
    }

    /// The user will mint a soulbound NFT that tracks their run and reward based on total miles ran
    /// They can use their miles as points to redeem for rewards
    entry fun mint(user: &signer) acquires AdminConfig {
        let admin_config = borrow_global<AdminConfig>(@example_loyalty);
        let token_minter = admin_config.token_minter;
        let user_addr = address_of(user);
        let tokens = mint_tokens_object(
            user,
            token_minter,
            utf8(b"Run Run Run"),
            utf8(b"Tracks your runs"),
            utf8(b"https://static.wikia.nocookie.net/onepiece/images/2/27/RUN%21_RUN%21_RUN%21.png/revision/latest?cb=20131010064322"),
            1,
            vector[vector[]],
            vector[vector[]],
            vector[vector[]],
            vector[user_addr],
        );
        let token = vector::borrow(&tokens, 0);
        let minter_signer = token_minter::token_minter_signer(token_minter);
        move_to(&minter_signer, RunTracker {
            total_miles: 0,
            miles_left: 0,
        });
    }

    entry fun add_miles(user: &signer) acquires AdminConfig {
        // mutate the run tracker for the user, but...how do I get back the token from the user?
    }
}