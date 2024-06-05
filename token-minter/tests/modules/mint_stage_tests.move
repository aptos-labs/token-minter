#[test_only]
module minter::mint_stage_tests {
    use std::signer;
    use std::string::{String, utf8};
    use std::vector;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};
    use aptos_framework::timestamp;

    use aptos_token_objects::collection::Collection;

    use minter::collection_components;
    use minter::collection_utils;
    use minter::mint_stage;

    fun init_timestamp(aptos_framework: &signer, timestamp_seconds: u64) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test_secs(timestamp_seconds);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    fun test_create_mint_stage_data(creator: &signer, aptos_framework: &signer) {
        init_timestamp(aptos_framework, 100000);

        let start_time = timestamp::now_seconds() - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);

        assert!(mint_stage::start_time(collection, index) == start_time, 0);
        assert!(mint_stage::end_time(collection, index) == end_time, 0);
        assert!(vector::length(&mint_stage::stages(collection)) == 1, 0);
        assert!(*vector::borrow(&mint_stage::stages(collection), 0) == category, 0);
        assert!(mint_stage::is_active(collection, index) == true, 0);
        // Assert there is no allowlist configured yet - meaning anyone can mint
        let mint_stage = mint_stage::find_mint_stage_by_index(collection, 0);
        assert!(!mint_stage::allowlist_exists(mint_stage), 0);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10001, location = minter::mint_stage)]
    fun exception_when_start_time_is_greater_than_end_time(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = timestamp::now_seconds() + 3600; // 1 hour post now
        let end_time = start_time - 7200; // 2 hours prior to now
        let category = utf8(b"Public sale");
        create_mint_stage_data_object(creator, start_time, end_time, category, 0);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10002, location = minter::mint_stage)]
    fun exception_when_end_time_is_less_than_current_time(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 10800 ; // 3 hours prior to now
        let end_time = now - 7200; // 2 hours prior to now
        let category = utf8(b"Public sale");
        create_mint_stage_data_object(creator, start_time, end_time, category, 0);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    fun test_assert_active_and_execute(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);

        let user_addr = signer::address_of(user);
        let amount = 1;
        mint_stage::add_to_allowlist(creator, collection, index, user_addr, amount);
        assert!(mint_stage::is_allowlisted(collection, index, user_addr) == true, 0);
        // Assert stage has allowlist configured
        assert!(mint_stage::is_stage_allowlisted(collection, index), 0);
        assert!(mint_stage::allowlist_balance(collection, index, user_addr) == amount, 0);

        // User mints 1 token
        mint_stage::assert_active_and_execute(user, collection, index, amount);
        assert!(mint_stage::allowlist_balance(collection, index, user_addr) == 0, 0);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    fun test_remove_stage(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);
        let presale = utf8(b"Presale");
        let presale_start_time = now + 3600; // Starts 2 hours from now
        let presale_end_time = presale_start_time + 3600; // Ends 3 hours from now
        let (_, collection) = create_mint_stage_data_object(
            creator,
            presale_start_time,
            presale_end_time,
            presale,
            0,
        );
        let presale_index = mint_stage::find_mint_stage_index_by_name(collection, presale);
        mint_stage::remove_stage(creator, collection, presale_index);

        assert!(vector::is_empty(&mint_stage::stages(collection)), 0);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x1000b, location = minter::mint_stage)]
    fun exception_when_amount_is_zero(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = timestamp::now_seconds() + 3600;
        let end_time = start_time + 7200;
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);
        mint_stage::assert_active_and_execute(user, collection, index, 0);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x30006, location = minter::mint_stage)]
    fun exception_when_user_not_allowlisted(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);

        // Need to set allowlist before executing, empty allowlist means anyone can mint.
        mint_stage::add_to_allowlist(creator, collection, index, signer::address_of(creator), 1);

        mint_stage::assert_active_and_execute(user, collection, index, 1);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x40007, location = minter::mint_stage)]
    fun exception_when_not_owner_calling_authorized_method(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);
        // User tries calling instead of creator, this should fail.
        mint_stage::add_to_allowlist(user, collection, index, signer::address_of(creator), 1);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    fun test_remove_from_allowlist(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);

        let user_addr = signer::address_of(user);
        let amount = 1;
        mint_stage::add_to_allowlist(creator, collection, index, user_addr, amount);
        mint_stage::remove_from_allowlist(creator, collection, index, user_addr);

        assert!(mint_stage::is_allowlisted(collection, index, user_addr) == false, 0);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    fun test_remove_all_from_allowlist(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);

        let user_addr = signer::address_of(user);
        let creator_addr = signer::address_of(creator);
        let amount = 1;
        mint_stage::add_to_allowlist(creator, collection, index, user_addr, amount);
        mint_stage::add_to_allowlist(creator, collection, index, creator_addr, amount);
        mint_stage::clear_allowlist(creator, collection, index);

        // Assert no one is allowlisted
        assert!(!mint_stage::is_allowlisted(collection, index, user_addr), 0);
        assert!(!mint_stage::is_allowlisted(collection, index, creator_addr), 0);
        assert!(mint_stage::allowlist_count(collection, index) == 0, 0);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    fun test_set_start_and_end_time(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);

        let new_start_time = now - 7200; // 2 hours prior to now
        let new_end_time = now + 3600; // 1 hour post now
        mint_stage::set_start_and_end_time(creator, collection, index, new_start_time, new_end_time);

        assert!(mint_stage::start_time(collection, index) == new_start_time, 0);
        assert!(mint_stage::end_time(collection, index) == new_end_time, 0);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    fun test_is_active(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = timestamp::now_seconds() + 3600; // 1 hour post now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);
        assert!(mint_stage::is_active(collection, index) == false, 0);

        let new_start_time = now - 3600; // Change start time to 1 hour prior to now
        let new_end_time = now + 3600; // Change end time to 1 hour post now
        mint_stage::set_start_and_end_time(creator, collection, index, new_start_time, new_end_time);
        assert!(mint_stage::is_active(collection, index) == true, 0);

        let new_end_time = timestamp::now_seconds() + 3600; // Change end time to 1 hour post now
        mint_stage::set_start_and_end_time(creator, collection, index, new_start_time, new_end_time);
        assert!(mint_stage::is_active(collection, index) == true, 0);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    fun test_sorted_categories(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        // Initialize different categories
        let private_sale = utf8(b"Private Sale");
        let presale = utf8(b"Presale");
        let public_sale = utf8(b"Public Sale");

        // Set start and end times for Private Sale
        let private_sale_start_time = now + 3600; // Starts 1 hour from now
        let private_sale_end_time = private_sale_start_time + 1800; // Ends 1.5 hours from now

        // Set start and end times for Presale, starting 1 hour after Private Sale starts
        let presale_start_time = private_sale_start_time + 3600; // Starts 2 hours from now
        let presale_end_time = presale_start_time + 3600; // Ends 3 hours from now

        // Set start and end times for Public Sale
        let public_sale_start_time = now + 7200; // Starts 2 hours from now
        let public_sale_end_time = public_sale_start_time + 3600; // Ends 3 hours from now

        // Create a MintStageData object and add all three sales to it
        let (object_signer, mint_stage_data) = create_mint_stage_data_object(
            creator,
            private_sale_start_time,
            private_sale_end_time,
            private_sale,
            0,
        );
        let collection = object::convert(mint_stage_data);
        mint_stage::create(&object_signer, presale, presale_start_time, presale_end_time);
        mint_stage::create(&object_signer, public_sale, public_sale_start_time, public_sale_end_time);

        let sorted_categories = mint_stage::stages(collection);

        // Order should be (Private Sale, Presale, Public Sale)
        assert!(*vector::borrow(&sorted_categories, 0) == private_sale, 0); // Private Sale ends first
        assert!(*vector::borrow(&sorted_categories, 1) == presale, 0); // Then Presale
        assert!(*vector::borrow(&sorted_categories, 2) == public_sale, 0); // Finally Public Sale
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    fun test_destroy_mint_data_object(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        assert!(mint_stage::mint_stage_data_exists(collection), 0);

        mint_stage::destroy(creator, collection);

        // Assert `MintStageData` resource has been destroyed.
        assert!(!mint_stage::mint_stage_data_exists(collection), 0);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x40007, location = minter::mint_stage)]
    fun exception_when_not_owner_calling_destroy(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, mint_stage_data) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let collection = object::convert(mint_stage_data);

        mint_stage::destroy(user, collection);
    }

    // =========================== NoAllowlist Tests =========================== //

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    fun test_public_sale_with_limit_execution(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let max_per_user = 3;
        let (_, collection) = create_mint_stage_data_object(creator, start_time, end_time, category, max_per_user);
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);

        let user_addr = signer::address_of(user);
        let amount = 1;
        // Assert no_allowlist is configured with max per user limit
        assert!(mint_stage::public_stage_max_per_user(collection, index) == max_per_user, 0);
        // User has not minted yet, so their no allowlist user balance should be `max_per_user`
        assert!(
            mint_stage::public_stage_with_limit_user_balance(collection, index, user_addr) == max_per_user,
            0,
        );

        // User tries to mint 1 token, should be successful
        mint_stage::assert_active_and_execute(user, collection, index, amount);
        // Verify user balance in no_allowlist is updated to (max per user - amount minted)
        assert!(
            mint_stage::public_stage_with_limit_user_balance(
                collection,
                index,
                user_addr
            ) == max_per_user - amount,
            0,
        );
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x3000A, location = minter::mint_stage)]
    fun exception_when_user_mints_more_than_max_per_user(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let max_per_user = 1;
        let (_, collection) = create_mint_stage_data_object(creator, start_time, end_time, category, max_per_user);
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);
        // User tries to mint 1 token, should be successful
        mint_stage::assert_active_and_execute(user, collection, index, 1);

        // User tries to mint 1 more token, should fail since they have reached the max limit
        mint_stage::assert_active_and_execute(user, collection, index, 1);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    fun test_no_allowlist_unlimited_mints_when_max_per_user_not_set(
        creator: &signer,
        user: &signer,
        aptos_framework: &signer,
    ) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, collection) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0, // No public sale with limit set
        );
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);
        // Perform minting without restrictions
        mint_stage::assert_active_and_execute(user, collection, index, 1);

        // Allow user to mint again since no max_per_user is set
        mint_stage::assert_active_and_execute(user, collection, index, 1);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x3000A, location = minter::mint_stage)]
    fun test_set_max_per_user(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        // Max per user is none.
        let (_, mint_stage_data) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            0,
        );
        let collection = object::convert(mint_stage_data);
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);
        // Perform minting without restrictions
        mint_stage::assert_active_and_execute(user, collection, index, 1);

        let new_max_per_user = 1; // Update to 1
        mint_stage::set_public_stage_max_per_user(
            creator,
            collection,
            index,
            new_max_per_user
        );
        // User tries to mint more than new `max_per_user`, should fail
        mint_stage::assert_active_and_execute(user, collection, index, 2);
    }

    fun create_mint_stage_data_object(
        creator: &signer,
        start_time: u64,
        end_time: u64,
        category: String,
        public_stage_max_per_user: u64, // 0 means no public stage should be created
    ): (signer, Object<Collection>) {
        let constructor_ref = collection_utils::create_unlimited_collection(creator);
        collection_components::create_refs_and_properties(&constructor_ref);
        let mint_stage_data = mint_stage::init(
            &constructor_ref,
            category,
            start_time,
            end_time,
        );
        let collection = object::convert(mint_stage_data);
        let index = mint_stage::find_mint_stage_index_by_name(collection, category);
        if (public_stage_max_per_user > 0) {
            mint_stage::set_public_stage_max_per_user(creator, collection, index, public_stage_max_per_user);
        };
        (object::generate_signer(&constructor_ref), collection)
    }

    fun create_object(creator: &signer): ConstructorRef {
        object::create_object(signer::address_of(creator))
    }
}
