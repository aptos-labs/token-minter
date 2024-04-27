#[test_only]
module airdrop_machine::airdrop_machine_tests {
    use std::option;
    use std::signer;
    use std::string::utf8;
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use airdrop_machine::airdrop_machine;
    use airdrop_machine::airdrop_machine::CollectionConfig;

    #[test(admin = @0x1, user = @0x2)]
    fun test_admin_minted_token(admin: &signer, user: &signer) {
        let user_address = signer::address_of(user);
        let collection_config = create_collection_helper(admin);
        airdrop_machine::set_minting_status(admin, collection_config, true);
        let admin_minted_token = airdrop_machine::mint_with_admin_impl(
            admin,
            collection_config,
            user_address,
        );
        assert!(object::owner(admin_minted_token) == user_address, 1);
    }

    #[test(admin = @0x1, user = @0x2)]
    fun test_user_minted_token(admin: &signer, user: &signer) {
        let user_address = signer::address_of(user);
        let collection_config = create_collection_helper(admin);
        airdrop_machine::set_minting_status(admin, collection_config, true);
        let user_minted_token = airdrop_machine::mint_impl_for_testing(
            user,
            collection_config,
            user_address,
        );
        assert!(object::owner(user_minted_token) == user_address, 1);
    }

    #[test(admin = @0x1, user = @0x2)]
    #[expected_failure(abort_code = 327683, location = airdrop_machine::airdrop_machine)]
    fun test_mint_fail(admin: &signer, user: &signer) {
        let user_address = signer::address_of(user);
        let collection = create_collection_helper(admin);

        airdrop_machine::mint_impl_for_testing(
            user,
            collection,
            user_address,
        );
    }

    #[test(admin = @0x1, user = @0x2)]
    fun test_admin_burn(admin: &signer, user: &signer) {
        let user_address = signer::address_of(user);
        let collection_config = create_collection_helper(admin);
        airdrop_machine::set_minting_status(admin, collection_config, true);
        let user_minted_token = airdrop_machine::mint_impl_for_testing(
            user,
            collection_config,
            user_address,
        );
        assert!(object::owner(user_minted_token) == user_address, 1);

        airdrop_machine::burn_with_admin(admin, collection_config, user_minted_token);

        let token_addr = object::object_address(&user_minted_token);
        // Assert `ObjectCore` does not exist, as it's been burned.
        assert!(!object::is_object(token_addr), 1);
    }

    #[test(admin = @0x1, user = @0x2)]
    #[expected_failure(abort_code = 327681, location = airdrop_machine::airdrop_machine)]
    fun exception_when_non_admin_burns(admin: &signer, user: &signer) {
        let user_address = signer::address_of(user);
        let collection_config = create_collection_helper(admin);
        airdrop_machine::set_minting_status(admin, collection_config, true);
        let user_minted_token = airdrop_machine::mint_impl_for_testing(
            user,
            collection_config,
            user_address,
        );
        assert!(object::owner(user_minted_token) == user_address, 1);

        // Should revert as `user` is not the admin.
        airdrop_machine::burn_with_admin(user, collection_config, user_minted_token);
    }

    fun create_collection_helper(admin: &signer): Object<CollectionConfig> {
        airdrop_machine::create_collection_impl(
            admin,
            utf8(b"Airdrop collection description"),
            utf8(b"Airdrop collection name"),
            utf8(b"Airdrop collection URI"),
            utf8(b"Airdrop token description"),
            utf8(b"Airdrop token name"),
            vector[utf8(b"Airdrop token URI 1"), utf8(b"Airdrop token URI 2")],
            vector[20, 80],
            true, // mutable_collection_metadata
            true, // mutable_token_metadata
            true, // tokens_burnable_by_collection_owner,
            true, // tokens_transferrable_by_collection_owner,
            option::none(), // No max supply.
            option::none(), // royalty_numerator.
            option::some(1), // royalty_denominator.
        )
    }
}
