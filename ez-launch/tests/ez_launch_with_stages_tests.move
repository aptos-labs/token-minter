#[test_only]
module ez_launch::ez_launch_with_stages_tests {
    use std::option;
    use std::signer;
    use std::string::utf8;
    use std::vector;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use aptos_framework::signer::address_of;
    use aptos_framework::timestamp;

    use minter::coin_payment;
    use minter::coin_payment::CoinPayment;
    use minter::mint_stage;

    use ez_launch::ez_coin_utils;
    use ez_launch::ez_launch_with_stages;
    use ez_launch::ez_launch_with_stages::EZLaunchConfig;

    fun init_timestamp(aptos_framework: &signer, timestamp_seconds: u64) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test_secs(timestamp_seconds);
    }

    #[test(creator = @0x1, user = @0x2, aptos_framework = @0x1)]
    fun test_create_collection_with_stages(creator: &signer, user: &signer, aptos_framework: &signer) {
        let creator_addr = signer::address_of(creator);
        let user_addr = signer::address_of(user);
        ez_coin_utils::setup_user_and_creator_coin_balances(creator, user, aptos_framework, 1000, 1000);
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let ez_launch_config_obj = create_collection_helper(creator);
        ez_launch_with_stages::pre_mint_tokens_impl(
            creator,
            ez_launch_config_obj,
            vector[utf8(b"token 1")],
            vector[utf8(b"ezlaunch.token.com/1")],
            vector[utf8(b"ezlaunch token")],
            1,
        );

        let stage_category = utf8(b"Public Sale");
        let start_time = now - 3600;
        let end_time = now + 7200;
        let no_allowlist_max_mint = option::none();
        ez_launch_with_stages::add_stage(creator, ez_launch_config_obj, stage_category, start_time, end_time, no_allowlist_max_mint);

        let stages = mint_stage::stages(ez_launch_config_obj);
        assert!(vector::contains(&stages, &stage_category), 1);

        ez_launch_with_stages::add_to_allowlist(creator, ez_launch_config_obj, stage_category, vector[user_addr], vector[1]);

        let mint_fee = 100;
        ez_launch_with_stages::add_fee(creator, ez_launch_config_obj, mint_fee, creator_addr, stage_category);

        let token = ez_launch_with_stages::mint_impl(user, ez_launch_config_obj, 1);
        assert!(object::owner(token) == signer::address_of(user), 1);
    }

    #[test(creator = @0x1, user = @0x2, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 327686, location = ez_launch::ez_launch_with_stages)]
    fun test_mint_without_active_stage_fails(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let ez_launch_config_obj = create_collection_helper(creator);
        ez_launch_with_stages::mint_impl(user, ez_launch_config_obj, 1);
    }

    #[test(creator = @0x1, user = @0x2, aptos_framework = @0x1)]
    fun test_allowlist(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let ez_launch_config_obj = create_collection_helper(creator);

        let stage_category = utf8(b"Presale");
        let start_time = now + 3600;
        let end_time = now + 7200;
        let no_allowlist_max_mint = option::none();
        ez_launch_with_stages::add_stage(creator, ez_launch_config_obj, stage_category, start_time, end_time, no_allowlist_max_mint);

        let user_address = signer::address_of(user);
        ez_launch_with_stages::add_to_allowlist(creator, ez_launch_config_obj, stage_category, vector[user_address], vector[1]);

        assert!(mint_stage::is_allowlisted(ez_launch_config_obj, stage_category, user_address), 1);

        ez_launch_with_stages::remove_from_allowlist(creator, ez_launch_config_obj, stage_category, vector[user_address]);
        assert!(!mint_stage::is_allowlisted(ez_launch_config_obj, stage_category, user_address), 1);
    }

    #[test(creator = @0x1, user = @0x2, aptos_framework = @0x1)]
    fun test_mint_with_fee(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        ez_coin_utils::setup_user_and_creator_coin_balances(creator, user, aptos_framework, 1000, 1000);
        init_timestamp(aptos_framework, now);

        let ez_launch_config_obj = create_collection_helper(creator);

        // Pre-mint tokens
        ez_launch_with_stages::pre_mint_tokens(
            creator,
            ez_launch_config_obj,
            vector[utf8(b"token 1")],
            vector[utf8(b"ezlaunch.token.com/1")],
            vector[utf8(b"awesome token")],
            1,
        );

        // Add mint stage
        let stage_category = utf8(b"Public Sale");
        let start_time = now + 3600;
        let end_time = now + 7200;
        let no_allowlist_max_mint = option::some(2);
        ez_launch_with_stages::add_stage(creator, ez_launch_config_obj, stage_category, start_time, end_time, no_allowlist_max_mint);

        // Add fee
        let mint_fee = 100;
        ez_launch_with_stages::add_fee(creator, ez_launch_config_obj, mint_fee, address_of(creator), stage_category);

        // Advance time to within the mint stage
        timestamp::update_global_time_for_test_secs(start_time + 1);

        let user_address = address_of(user);
        let token = ez_launch_with_stages::mint_impl(user, ez_launch_config_obj, 1);
        assert!(object::owner(token) == user_address, 1);
    }

    fun create_collection_helper(creator: &signer): Object<EZLaunchConfig> {
        ez_launch_with_stages::create_collection_impl(
            creator,
            utf8(b"Default collection description"),
            utf8(b"Default collection name"),
            utf8(b"URI"),
            true, // mutable_collection_metadata
            true, // mutable_token_metadata
            false, // random_mint
            true, // is_soulbound
            true, // tokens_burnable_by_collection_owner
            true, // tokens_transferrable_by_collection_owner
            option::none(), // No max supply
            option::some(1), // royalty_numerator
            option::some(1), // royalty_denominator
        )
    }

    fun destroy_coin_payments(coin_payments: vector<CoinPayment<AptosCoin>>) {
        vector::destroy(coin_payments, |coin_payment| {
            coin_payment::destroy(coin_payment)
        });
    }
}
