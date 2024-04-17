#[test_only]
module airdrop_machine::airdrop_machine_tests {
    use std::option;
    use std::signer;
    use std::string::utf8;
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use airdrop_machine::airdrop_machine;
    use airdrop_machine::airdrop_machine::CollectionConfig;
    use aptos_framework::timestamp::set_time_has_started_for_testing;

    #[test(admin = @0x1, user = @0x2)]
    fun test_admin_minted_token(admin: &signer, user: &signer) {
        set_time_has_started_for_testing(admin);
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
        set_time_has_started_for_testing(admin);
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
    #[expected_failure(abort_code = 327684, location = airdrop_machine::airdrop_machine)]
    fun test_mint_fail(admin: &signer, user: &signer) {
        let user_address = signer::address_of(user);
        let collection = create_collection_helper(admin);

        airdrop_machine::mint_impl_for_testing(
            user,
            collection,
            user_address,
        );
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
            true, // mutable_collection_metadata
            true, // mutable_token_metadata
            true, // tokens_burnable_by_collection_owner,
            true, // tokens_transferrable_by_collection_owner,
            option::none(), // No max supply.
            option::none(), // royalty_numerator.
            option::none(), // royalty_denominator.
        )
    }
}
