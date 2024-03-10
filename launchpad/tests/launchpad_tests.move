module minter::launchpad_tests {
    #[test_only]
    use std::option;
    #[test_only]
    use std::signer;
    #[test_only]
    use std::string;
    #[test_only]
    use std::string::utf8;
    #[test_only]
    use aptos_framework::aptos_coin::AptosCoin;
    #[test_only]
    use aptos_framework::coin;
    #[test_only]
    use launchpad::launchpad;
    #[test_only]
    use minter::coin_utils::setup_user_and_creator_coin_balances;
    #[test_only]
    use minter::collection_components;

    #[test_only]
    fun initialize_balances(
        creator: &signer,
        minter: &signer,
        launchpad_admin: &signer,
        fx: &signer,
        user_initial_balance: u64,
    ) {
        let creator_initial_balance = 0;
        let launchpad_admin_initial_balance = 0;

        setup_user_and_creator_coin_balances(
            fx,
            minter,
            creator,
            launchpad_admin,
            user_initial_balance,
            creator_initial_balance,
            launchpad_admin_initial_balance,
        );
    }

    // ========================================= Tests =======================================================//

    #[test(creator = @0x123, minter = @0x456, launchpad_admin = @launchpad_admin, fx = @0x1)]
    /// Example of how to use the token minter extensions to create collection and mint tokens
    /// The admin object will hold the `AdminData`, `FeeExtensions`, `Launchpad` resources.
    fun test_create_launchpad_and_mint(
        creator: &signer,
        minter: &signer,
        launchpad_admin: &signer,
        fx: &signer,
    ) {
        let minter_addr = signer::address_of(minter);
        let launchpad_admin_addr = signer::address_of(launchpad_admin);

        let user_initial_balance = 1000000;
        initialize_balances(creator, minter, launchpad_admin, fx, user_initial_balance);

        // When calling this function, the `creator` will be have ownership of the collection.
        // But the `launchpad_admin` will need to sign this transaction. This is because
        // they are approving that the creator is allowed to create the collection on it's platform.
        //
        // The creator owns the Launchpad created, the launchpad owns the collection.
        let collection_properties = collection_components::create_properties(
            true,  // mutable_description
            true, // mutable_uri
            true, // mutable_token_description
            true, // mutable_token_name
            true, // mutable_token_properties
            true, // mutable_token_uri
            true, // mutable_royalty
            true, // tokens_burnable_by_creator
            true, // tokens_transferable_by_creator
        );
        let launchpad = launchpad::create_launchpad_for_collection(
            creator,
            launchpad_admin, // Launchpad admin must sign this transaction
            utf8(b"test collection description"),
            option::none(), // unlimited supply
            utf8(b"test collection name"),
            utf8(b"https://www.google.com"),
            option::some(collection_properties),
            option::none(), // royalty
            true, // soulbound
        );

        let mint_fee = 100000;
        // Now add AptosCoin Mint fees to the launchpad. We will send the fees to the launchpad admin for now.
        // Launchpad fees are autoamtically created and take a 0.3% cut of all fees added.
        launchpad::add_coin_payment_to_fees<AptosCoin>(
            creator,
            launchpad,
            mint_fee,
            launchpad_admin_addr,
            string::utf8(b"Mint fee"),
        );

        // Create token with custom extension logic - example mint function
        // First execute all extensions with user as minter
        let _token = launchpad::mint(
            minter,
            launchpad,
            utf8(b"test token"),
            utf8(b"test token description"),
            utf8(b"https://www.google.com"),
            minter_addr, // recipient_addr
        );

        let launchpad_fee = 300;
        let total_cost = mint_fee + launchpad_fee;
        let minter_balance = coin::balance<AptosCoin>(minter_addr);
        // Assert minter has paid the fees.
        assert!(minter_balance == user_initial_balance - total_cost, 0);

        let launchpad_admin_balance = coin::balance<AptosCoin>(launchpad_admin_addr);
        // Assert launchpad admin received all the fees.
        assert!(launchpad_admin_balance == total_cost, 0);
    }
}
