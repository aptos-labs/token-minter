#[test_only]
module ez_launch::ez_launch_tests {
    use std::string::utf8;
    use std::option;
    use std::signer;

    use aptos_framework::object;
    use aptos_framework::object::Object;

    use ez_launch::ez_launch;
    use ez_launch::ez_launch::EZLaunchConfig;

    #[test(creator = @0x1)]
    fun test_create_collection(creator: &signer) {
        let ez_launch_config_obj = create_collection_helper(creator);
        let ez_launch_config_obj_address = object::object_address(&ez_launch_config_obj);
        let pre_minted_token = ez_launch::pre_mint_token(
            creator,
            ez_launch_config_obj,
            utf8(b"token 2"),
            utf8(b"ezlaunch.token.come/2"),
            utf8(b"awesome token"),
        );
        assert!(object::owner(pre_minted_token) == ez_launch_config_obj_address, 1);
    }

    #[test(creator = @0x1, user = @0x2)]
    fun test_mint_token(creator: &signer, user: &signer) {
        let user_address = signer::address_of(user);
        let ez_launch_config_obj = create_collection_helper(creator);
        ez_launch::pre_mint_tokens(
            creator,
            ez_launch_config_obj,
            vector[utf8(b"token 1")], // token_name_vec.
            vector[utf8(b"ezlaunch.token.come/1")], // token_uri_vec.
            vector[utf8(b"awesome token")], // token_description_vec.
            1,
        );
        ez_launch::set_minting_status(creator, ez_launch_config_obj, true /* ready_to_mint */);
        let minted_token = ez_launch::mint_impl(user, ez_launch_config_obj);
        assert!(object::owner(minted_token) == user_address, 1);
    }
    
    fun create_collection_helper(creator: &signer): Object<EZLaunchConfig> {
        ez_launch::create_collection_impl(
            creator,
            utf8(b"Default collection description"),
            utf8(b"Default collection name"),
            utf8(b"URI"),
            true, // mutable_collection_metadata
            true, // mutable_token_metadata
            false, // random_mint
            true, // is_soulbound
            true, // tokens_burnable_by_collection_owner,
            true, // tokens_transferrable_by_collection_owner,
            option::none(), // No max supply.
            option::none(), // mint_fee.
            option::some(1), // royalty_numerator.
            option::some(1), // royalty_denominator.
        )
    }

    // TODO(jill) add more edge cases to test
}
