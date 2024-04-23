#[test_only]
module minter::mint_stage_tests {
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::{String, utf8};
    use std::vector;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};
    use aptos_framework::timestamp;

    use minter::mint_stage;
    use minter::mint_stage::MintStageData;

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
        let (_, mint_stage_data) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            option::none()
        );

        assert!(mint_stage::start_time(mint_stage_data, category) == start_time, 0);
        assert!(mint_stage::end_time(mint_stage_data, category) == end_time, 0);
        assert!(vector::length(&mint_stage::stages(mint_stage_data)) == 1, 0);
        assert!(*vector::borrow(&mint_stage::stages(mint_stage_data), 0) == category, 0);
        assert!(mint_stage::is_active(mint_stage_data, category) == true, 0);
        // Assert there is no allowlist configured yet - meaning anyone can mint
        assert!(!mint_stage::is_allowlisted(mint_stage_data, category, signer::address_of(creator)), 0);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10001, location = minter::mint_stage)]
    fun exception_when_start_time_is_greater_than_end_time(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = timestamp::now_seconds() + 3600; // 1 hour post now
        let end_time = start_time - 7200; // 2 hours prior to now
        let category = utf8(b"Public sale");
        create_mint_stage_data_object(creator, start_time, end_time, category, option::none());
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10002, location = minter::mint_stage)]
    fun exception_when_end_time_is_less_than_current_time(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 10800 ; // 3 hours prior to now
        let end_time = now - 7200; // 2 hours prior to now
        let category = utf8(b"Public sale");
        create_mint_stage_data_object(creator, start_time, end_time, category, option::none());
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    fun test_assert_active_and_execute(creator: &signer, user: &signer, aptos_framework: &signer) {
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
            option::none()
        );

        let user_addr = signer::address_of(user);
        let amount = 1;
        mint_stage::add_to_allowlist(creator, mint_stage_data, category, user_addr, amount);
        assert!(mint_stage::is_allowlisted(mint_stage_data, category, user_addr) == true, 0);
        // Assert stage has allowlist configured
        assert!(mint_stage::is_stage_allowlisted(mint_stage_data, category), 0);
        assert!(mint_stage::allowlist_balance(mint_stage_data, category, user_addr) == amount, 0);

        // User mints 1 token
        mint_stage::assert_active_and_execute(user, mint_stage_data, category, amount);
        assert!(mint_stage::allowlist_balance(mint_stage_data, category, user_addr) == 0, 0);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x30006, location = minter::mint_stage)]
    fun exception_when_user_not_allowlisted(creator: &signer, user: &signer, aptos_framework: &signer) {
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
            option::none()
        );

        // Need to set allowlist before executing, empty allowlist means anyone can mint.
        mint_stage::add_to_allowlist(creator, mint_stage_data, category, signer::address_of(creator), 1);

        mint_stage::assert_active_and_execute(user, mint_stage_data, category, 1);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x40007, location = minter::mint_stage)]
    fun exception_when_not_owner_calling_authorized_method(creator: &signer, user: &signer, aptos_framework: &signer) {
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
            option::none()
        );

        // User tries calling instead of creator, this should fail.
        mint_stage::add_to_allowlist(user, mint_stage_data, category, signer::address_of(creator), 1);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    fun test_remove_from_allowlist(creator: &signer, user: &signer, aptos_framework: &signer) {
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
            option::none()
        );

        let user_addr = signer::address_of(user);
        let amount = 1;
        mint_stage::add_to_allowlist(creator, mint_stage_data, category, user_addr, amount);
        mint_stage::remove_from_allowlist(creator, mint_stage_data, category, user_addr);

        assert!(mint_stage::is_allowlisted(mint_stage_data, category, user_addr) == false, 0);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    fun test_set_start_and_end_time(creator: &signer, aptos_framework: &signer) {
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
            option::none()
        );

        let new_start_time = now - 7200; // 2 hours prior to now
        let new_end_time = now + 3600; // 1 hour post now
        mint_stage::set_start_and_end_time(creator, mint_stage_data, category, new_start_time, new_end_time);

        assert!(mint_stage::start_time(mint_stage_data, category) == new_start_time, 0);
        assert!(mint_stage::end_time(mint_stage_data, category) == new_end_time, 0);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    fun test_is_active(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = timestamp::now_seconds() + 3600; // 1 hour post now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, mint_stage_data) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            option::none()
        );
        assert!(mint_stage::is_active(mint_stage_data, category) == false, 0);

        let new_start_time = now - 3600; // Change start time to 1 hour prior to now
        let new_end_time = now + 3600; // Change end time to 1 hour post now
        mint_stage::set_start_and_end_time(creator, mint_stage_data, category, new_start_time, new_end_time);
        assert!(mint_stage::is_active(mint_stage_data, category) == true, 0);

        let new_end_time = timestamp::now_seconds() + 3600; // Change end time to 1 hour post now
        mint_stage::set_start_and_end_time(creator, mint_stage_data, category, new_start_time, new_end_time);
        assert!(mint_stage::is_active(mint_stage_data, category) == true, 0);
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
            option::none(),
        );
        mint_stage::create(&object_signer, presale_start_time, presale_end_time, presale, option::none());
        mint_stage::create(&object_signer, public_sale_start_time, public_sale_end_time, public_sale, option::none());

        let sorted_categories = mint_stage::stages(mint_stage_data);

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
        let (_, mint_stage_data) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            option::none()
        );
        assert!(mint_stage::mint_stage_data_exists(object::object_address(&mint_stage_data)), 0);

        mint_stage::destroy(creator, mint_stage_data);

        // Assert `MintStageData` resource has been destroyed.
        assert!(!mint_stage::mint_stage_data_exists(object::object_address(&mint_stage_data)), 0);
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
            option::none()
        );

        mint_stage::destroy(user, mint_stage_data);
    }

    // =========================== NoAllowlist Tests =========================== //

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    fun test_no_allowlist_execution(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let max_per_user = option::some(3);
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category, max_per_user);

        let user_addr = signer::address_of(user);
        let amount = 1;
        // Assert no_allowlist is configured with max per user limit
        assert!(mint_stage::no_allowlist_max_per_user(mint_stage_data, category) == max_per_user, 0);
        // User has not minted yet, so their no allowlist user balance should be `max_per_user`
        assert!(mint_stage::user_balance_in_no_allowlist(mint_stage_data, category, user_addr) == max_per_user, 0);

        // User tries to mint 1 token, should be successful
        mint_stage::assert_active_and_execute(user, mint_stage_data, category, amount);
        // Verify user balance in no_allowlist is updated to (max per user - amount minted)
        assert!(
            mint_stage::user_balance_in_no_allowlist(mint_stage_data, category, user_addr) == option::some(
                *option::borrow(&max_per_user) - amount
            ),
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
        let max_per_user = option::some(1);
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category, max_per_user);
        // User tries to mint 1 token, should be successful
        mint_stage::assert_active_and_execute(user, mint_stage_data, category, 1);

        // User tries to mint 1 more token, should fail since they have reached the max limit
        mint_stage::assert_active_and_execute(user, mint_stage_data, category, 1);
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
        let (_, mint_stage_data) = create_mint_stage_data_object(
            creator,
            start_time,
            end_time,
            category,
            option::none() // no max_per_user set
        );
        // Perform minting without restrictions
        mint_stage::assert_active_and_execute(user, mint_stage_data, category, 1);

        // Allow user to mint again since no max_per_user is set
        mint_stage::assert_active_and_execute(user, mint_stage_data, category, 1);
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
            option::none()
        );
        // Perform minting without restrictions
        mint_stage::assert_active_and_execute(user, mint_stage_data, category, 1);

        let new_max_per_user = option::some(1); // Update to 1
        mint_stage::set_no_allowlist_max_per_user(
            creator,
            mint_stage_data,
            category,
            new_max_per_user
        );
        // User tries to mint more than new `max_per_user`, should fail
        mint_stage::assert_active_and_execute(user, mint_stage_data, category, 2);
    }

    fun create_mint_stage_data_object(
        creator: &signer,
        start_time: u64,
        end_time: u64,
        category: String,
        no_allowlist_max_per_user: Option<u64>,
    ): (signer, Object<MintStageData>) {
        let constructor_ref = create_object(creator);
        let mint_stage_data = mint_stage::init(
            &constructor_ref,
            start_time,
            end_time,
            category,
            no_allowlist_max_per_user,
        );
        (object::generate_signer(&constructor_ref), mint_stage_data)
    }

    fun create_object(creator: &signer): ConstructorRef {
        object::create_object(signer::address_of(creator))
    }
}
