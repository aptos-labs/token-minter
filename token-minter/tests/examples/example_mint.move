module minter::example_mint {
    #[test_only]
    use std::option;
    #[test_only]
    use std::signer;
    #[test_only]
    use std::string;
    #[test_only]
    use std::string::{String, utf8};
    #[test_only]
    use std::vector;
    #[test_only]
    use aptos_framework::aptos_coin::AptosCoin;
    #[test_only]
    use aptos_framework::coin;
    #[test_only]
    use aptos_framework::object;
    #[test_only]
    use aptos_framework::object::{ExtendRef, Object};
    #[test_only]
    use aptos_token_objects::collection::Collection;
    #[test_only]
    use aptos_token_objects::token::Token;
    #[test_only]
    use minter::coin_payment::{Self,CoinPayment};
    #[test_only]
    use minter::coin_utils::setup_user_and_creator_coin_balances;
    #[test_only]
    use minter::collection::{Self};
    #[test_only]
    use minter::token::{Self};

    #[test_only]
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct AdminData has key {
        extend_ref: ExtendRef,
    }

    #[test_only]
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Launchpad has key {
        collection: Object<Collection>,
        soulbound: bool,
    }

    #[test_only]
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct FeeExtensions<phantom T> has key {
        coin_payments: vector<CoinPayment<T>>,
    }

    #[test_only]
    fun create_admin_object(creator: &signer): Object<AdminData> {
        let creator_addr = signer::address_of(creator);
        let constructor_ref = &object::create_object(creator_addr);
        let admin_signer = &object::generate_signer(constructor_ref);
        move_to(admin_signer, AdminData { extend_ref: object::generate_extend_ref(constructor_ref) });

        object::object_from_constructor_ref(constructor_ref)
    }

    #[test_only]
    /// Create collection with the creator as the admin object.
    fun create_collection(creator: &signer, admin_data: Object<AdminData>): Object<Collection> acquires AdminData {
        assert!(object::owner(admin_data) == signer::address_of(creator), 0);

        let admin_refs = borrow_global<AdminData>(object::object_address(&admin_data));
        let admin_signer = &object::generate_signer_for_extending(&admin_refs.extend_ref);
        collection::create_collection(
            admin_signer,
            utf8(b"test collection description"),
            option::none(), // unlimited supply
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
        )
    }

    #[test_only]
    fun create_launchpad(creator: &signer, collection: Object<Collection>, soulbound: bool): Object<Launchpad> {
        move_to(creator, Launchpad { collection, soulbound });
        object::address_to_object(signer::address_of(creator))
    }

    #[test_only]
    fun generate_coin_payment_extensions<T>(
        admin_signer: &signer,
        creator_addr: address,
        launchpad_addr: address,
        mint_fee: u64,
        launchpad_fee: u64,
    ): Object<FeeExtensions<T>> {
        let mint_fee_coin_payment = coin_payment::create<T>(
            mint_fee,
            creator_addr,
            string::utf8(b"Mint fee"),
        );
        let launchpad_fee_coin_payment = coin_payment::create<T>(
            launchpad_fee,
            launchpad_addr,
            string::utf8(b"Launchpad fee"),
        );

        move_to(admin_signer, FeeExtensions<T> {
            coin_payments: vector[mint_fee_coin_payment, launchpad_fee_coin_payment],
        });

        object::address_to_object(signer::address_of(admin_signer))
    }

    #[test_only]
    fun admin_signer(admin_data: Object<AdminData>): signer acquires AdminData {
        let admin_refs = borrow_global<AdminData>(object::object_address(&admin_data));
        object::generate_signer_for_extending(&admin_refs.extend_ref)
    }

    #[test_only]
    /// Create token with custom extension logic - example mint function
    public fun mint(
        minter: &signer,
        lauchpad: Object<Launchpad>,
        description: String,
        name: String,
        uri: String,
        recipient_addr: address,
    ): Object<Token> acquires FeeExtensions, AdminData, Launchpad {
        let launchpad_addr = object::object_address(&lauchpad);
        let launchpad = borrow_global<Launchpad>(launchpad_addr);

        // First execute all extensions with user as minter
        // All extensions should reside under the launchpad address.
        let fee_extensions = borrow_global<FeeExtensions<AptosCoin>>(launchpad_addr);
        vector::for_each_ref(&fee_extensions.coin_payments, |coin_payment| {
            let coin_payment: &CoinPayment<AptosCoin> = coin_payment;
            coin_payment::execute(minter, coin_payment);
        });

        let admin_data = object::address_to_object<AdminData>(launchpad_addr);
        let admin_signer = &admin_signer(admin_data);
        token::create(
            admin_signer,
            launchpad.collection,
            description,
            name,
            uri,
            recipient_addr,
            launchpad.soulbound,
        )
    }

    // ========================================= Tests =======================================================//

    #[test(creator = @0x123, minter = @0x456, launchpad = @0x789, fx = @0x1)]
    /// Example of how to use the token minter extensions to create collection and mint tokens
    /// The admin object will hold the `AdminData`, `FeeExtensions`, `Launchpad` resources.
    fun example_mint(
        creator: &signer,
        minter: &signer,
        launchpad: &signer,
        fx: &signer,
    ) acquires AdminData, FeeExtensions, Launchpad {
        let creator_addr = signer::address_of(creator);
        let minter_addr = signer::address_of(minter);
        let launchpad_addr = signer::address_of(launchpad);
        let soulbound = true;

        // Initialize user and creator balances
        let user_initial_balance = 130;
        let creator_initial_balance = 0;
        let launchpad_initial_balance = 0;
        setup_user_and_creator_coin_balances(
            fx,
            minter,
            creator,
            launchpad,
            user_initial_balance,
            creator_initial_balance,
            launchpad_initial_balance,
        );

        // First create an admin signer to execute mint on demand.
        // You can configure the mint to only execute once the conditions are met - Such as coin payment.
        let admin_data = create_admin_object(creator);
        let admin_signer = &admin_signer(admin_data);

        // Create collection with the creator as the admin object.
        let collection = create_collection(creator, admin_data);
        // After creating collection, creating launchpad with collection details
        let launchpad = create_launchpad(admin_signer, collection, soulbound);

        let mint_fee = 50;
        let launchpad_fee = 10;
        // Create extensions to execute before mint
        generate_coin_payment_extensions<AptosCoin>(
            admin_signer,
            creator_addr,
            launchpad_addr,
            mint_fee,
            launchpad_fee,
        );

        // Create token with custom extension logic - example mint function
        // First execute all extensions with user as minter
        let token = mint(
            minter,
            launchpad,
            utf8(b"test token"),
            utf8(b"test token description"),
            utf8(b"https://www.google.com"),
            minter_addr, // recipient_addr
        );

        let total_cost = mint_fee + launchpad_fee;
        let minter_balance = coin::balance<AptosCoin>(minter_addr);
        assert!(minter_balance == user_initial_balance - total_cost, 0);
    }
}
