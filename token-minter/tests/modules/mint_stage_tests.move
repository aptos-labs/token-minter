#[test_only]
module minter::mint_stage_tests {
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
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category);

        assert!(mint_stage::start_time(mint_stage_data, category) == start_time, 0);
        assert!(mint_stage::end_time(mint_stage_data, category) == end_time, 0);
        assert!(vector::length(&mint_stage::categories(mint_stage_data)) == 1, 0);
        assert!(*vector::borrow(&mint_stage::categories(mint_stage_data), 0) == category, 0);
        assert!(mint_stage::is_active(mint_stage_data, category) == true, 0);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10001, location = minter::mint_stage)]
    fun exception_when_start_time_is_greater_than_end_time(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = timestamp::now_seconds() + 3600; // 1 hour post now
        let end_time = start_time - 7200; // 2 hours prior to now
        let category = utf8(b"Public sale");
        create_mint_stage_data_object(creator, start_time, end_time, category);
    }

    #[test(creator = @0x123, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10002, location = minter::mint_stage)]
    fun exception_when_end_time_is_less_than_current_time(creator: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 10800 ; // 3 hours prior to now
        let end_time = now - 7200; // 2 hours prior to now
        let category = utf8(b"Public sale");
        create_mint_stage_data_object(creator, start_time, end_time, category);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    fun test_assert_active_and_execute(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category);

        let user_addr = signer::address_of(user);
        let amount = 1;
        mint_stage::add_to_allowlist(creator, mint_stage_data, category, user_addr, amount);
        assert!(mint_stage::is_allowlisted(mint_stage_data, category, user_addr) == true, 0);
        assert!(mint_stage::balance(mint_stage_data, category, user_addr) == amount, 0);

        mint_stage::assert_active_and_execute(creator, mint_stage_data, category, user_addr, amount);
        assert!(mint_stage::balance(mint_stage_data, category, user_addr) == 0, 0);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x30006, location = minter::mint_stage)]
    fun exception_when_user_not_allowlisted(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category);

        // Need to set allowlist before executing, empty allowlist means anyone can mint.
        mint_stage::add_to_allowlist(creator, mint_stage_data, category, signer::address_of(creator), 1);

        mint_stage::assert_active_and_execute(creator, mint_stage_data, category, signer::address_of(user), 1);
    }

    #[test(creator = @0x123, user = @0x456, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x40007, location = minter::mint_stage)]
    fun exception_when_not_owner_calling_authorized_method(creator: &signer, user: &signer, aptos_framework: &signer) {
        let now = 100000;
        init_timestamp(aptos_framework, now);

        let start_time = now - 3600; // 1 hour prior to now
        let end_time = start_time + 7200; // 2 hours post now
        let category = utf8(b"Public sale");
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category);

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
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category);

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
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category);

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
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category);
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
            private_sale
        );
        mint_stage::create(&object_signer, presale_start_time, presale_end_time, presale);
        mint_stage::create(&object_signer, public_sale_start_time, public_sale_end_time, public_sale);

        let sorted_categories = mint_stage::categories(mint_stage_data);

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
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category);
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
        let (_, mint_stage_data) = create_mint_stage_data_object(creator, start_time, end_time, category);

        mint_stage::destroy(user, mint_stage_data);
    }

    fun create_mint_stage_data_object(
        creator: &signer,
        start_time: u64,
        end_time: u64,
        category: String,
    ): (signer, Object<MintStageData>) {
        let constructor_ref = create_object(creator);
        let mint_stage_data = mint_stage::init(&constructor_ref, start_time, end_time, category);
        (object::generate_signer(&constructor_ref), mint_stage_data)
    }

    fun create_object(creator: &signer): ConstructorRef {
        object::create_object(signer::address_of(creator))
    }
}
