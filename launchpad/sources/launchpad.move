/// Example of a launchpad module that allows users to create a collection and a launchpad.
/// This uses the extensions provided by the token minter standard.
module launchpad::launchpad {
    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string;
    use std::string::String;
    use std::vector;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use aptos_framework::object::{Self, ExtendRef, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::royalty;
    use aptos_token_objects::royalty::Royalty;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;
    use minter::coin_payment::{Self, CoinPayment};
    use minter::collection_components;
    use minter::token_components;
    use minter::transfer_token;

    /// The caller is not the owner.
    const ENOT_OWNER: u64 = 1;
    /// The caller is not the launchpad admin.
    const ENOT_LAUNCHPAD_ADMIN: u64 = 2;
    /// The fees object does not exist.
    const EFEES_DOES_NOT_EXIST: u64 = 3;
    /// The launchpad object does not exist.
    const ELAUNCHPAD_DOES_NOT_EXIST: u64 = 4;
    /// The launchpad refs object does not exist.
    const ELAUNCHPAD_REFS_DOES_NOT_EXIST: u64 = 5;

    /// If no fees specified for minting, 1000 Octa is the default launchpad fee.
    const DEFAULT_LAUNCHPAD_FEE: u64 = 1000;

    /// 0.3% of total fees go to the launchpad admin as the launchpad fee.
    /// Launchpad fee numerator in basis points.
    const LAUNCHPAD_FEE_BPS_NUMERATOR: u64 = 30;
    /// Launchpad fee denominator in basis points.
    const LAUNCHPAD_FEE_BPS_DENOMINATOR: u64 = 10000;
    const LAUNCHPAD_FEE_CATEGORY: vector<u8> = b"Launchpad Fee";

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct LaunchpadRefs has key {
        extend_ref: ExtendRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Launchpad has key {
        collection: Object<Collection>,
        soulbound: bool,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Fees<phantom T> has key {
        coin_payments: vector<CoinPayment<T>>,
    }

    #[event]
    /// Event emitted when the CreateLaunchpad is initialized.
    struct CreateLaunchpad has drop, store {
        collection: Object<Collection>,
        soulbound: bool,
    }

    /// Creators of the launchpad can call this to create a `CoinPayment` and add this to the list of fees.
    /// This can be multiple fees, such as "Mint fee", "Launch fee", etc.
    public entry fun add_coin_payment_to_fees<T>(
        creator: &signer,
        launchpad: Object<Launchpad>,
        amount: u64,
        destination: address,
        category: String,
    ) acquires LaunchpadRefs, Fees {
        assert_owner(signer::address_of(creator), launchpad);

        let launchpad_addr = object::object_address(&launchpad);
        let launchpad_signer = &launchpad_signer(launchpad);
        if (!exists<Fees<T>>(launchpad_addr)) {
            move_to(launchpad_signer, Fees<T> { coin_payments: vector[] });
        };

        let fees = borrow_global_mut<Fees<T>>(launchpad_addr);
        let coin_payment = coin_payment::create(amount, destination, category);
        vector::push_back(&mut fees.coin_payments, coin_payment);

        // Take launchpad fees - 0.3% of each coin payment amount.
        let launchpad_fee = create_launchpad_fee<T>(
            (amount * LAUNCHPAD_FEE_BPS_NUMERATOR) / LAUNCHPAD_FEE_BPS_DENOMINATOR
        );
        vector::push_back(&mut fees.coin_payments, launchpad_fee);
    }

    public entry fun remove_coin_payment_from_fees<T>(
        creator: &signer,
        launchpad: Object<Launchpad>,
        category: String,
    ) acquires Fees {
        assert_owner(signer::address_of(creator), launchpad);

        let launchpad_addr = object::object_address(&launchpad);
        assert!(exists<Fees<T>>(launchpad_addr), EFEES_DOES_NOT_EXIST);

        let fees = borrow_global_mut<Fees<T>>(launchpad_addr);
        let len = vector::length(&fees.coin_payments);
        let i = 0;
        while (i < len) {
            let coin_payment = vector::borrow(&fees.coin_payments, i);
            if (coin_payment::category(coin_payment) == category) {
                let coin_payment = vector::remove(&mut fees.coin_payments, i);
                coin_payment::destroy(coin_payment);
                return
            };
            i = i + 1;
        };
    }

    /// This function will be called by the minter to mint a new token.
    /// Anyone can call this function, as long as the extension conditions are met.
    /// In this case, there are fees which are created by the `coin_payment` extension.
    /// The user must pay these fees before minting a token.
    public fun mint(
        minter: &signer,
        launchpad_obj: Object<Launchpad>,
        description: String,
        name: String,
        uri: String,
        recipient_addr: address,
    ): Object<Token> acquires Fees, LaunchpadRefs, Launchpad {
        // First execute all extensions with minter as the signer.
        // All extensions should reside under the launchpad address.
        // Creator can decide what fees to pay in. In this case, we will stick with APT fees.
        pay_mint_and_launchpad_fees<AptosCoin>(minter, launchpad_obj);

        let launchpad_addr = object::object_address(&launchpad_obj);
        assert!(exists<Launchpad>(launchpad_addr), error::invalid_argument(ELAUNCHPAD_DOES_NOT_EXIST));
        let launchpad = borrow_global<Launchpad>(launchpad_addr);

        let creator = &launchpad_signer(launchpad_obj);
        // Call the token module from aptos token objects framework
        let constructor_ref = &token::create(
            creator,
            collection::name(launchpad.collection),
            description,
            name,
            royalty::get(launchpad.collection),
            uri,
        );

        // Call token refs module
        token_components::create_refs(constructor_ref);

        // Call token transfer module
        if (launchpad.soulbound) {
            transfer_token::transfer_soulbound(recipient_addr, constructor_ref);
        } else {
            transfer_token::transfer(creator, recipient_addr, constructor_ref);
        };

        object::object_from_constructor_ref(constructor_ref)
    }

    /// Pay the mint and launchpad fees if they exist. If it is a free mint/no fees, it takes the default launchpad fee.
    fun pay_mint_and_launchpad_fees<T>(minter: &signer, launchpad_obj: Object<Launchpad>) acquires Fees {
        let launchpad_addr = object::object_address(&launchpad_obj);
        assert!(exists<Fees<T>>(launchpad_addr), error::invalid_argument(EFEES_DOES_NOT_EXIST));

        let fees = borrow_global<Fees<T>>(launchpad_addr);
        vector::for_each_ref(&fees.coin_payments, |coin_payment| {
            let coin_payment: &CoinPayment<T> = coin_payment;
            coin_payment::execute(minter, coin_payment);
        });
    }

    fun create_launchpad_fee<T>(amount: u64): CoinPayment<T> {
        coin_payment::create(amount, @launchpad_admin, string::utf8(LAUNCHPAD_FEE_CATEGORY))
    }

    /// When calling this function, the `creator` will be have ownership of the collection.
    /// But the `launchpad_admin` will need to sign this transaction. This is because
    /// they are approving that the creator is allowed to create the collection on it's platform.
    public fun create_launchpad_for_collection(
        creator: &signer, // Creator who wishes to launch a collection on the launchpad.
        launchpad_admin: &signer, // Launchpad admin is the one who approves the creator to create a collection.
        description: String,
        max_supply: Option<u64>, // If value is present, collection configured to have a fixed supply.
        name: String,
        uri: String,
        royalty: Option<Royalty>,
        soulbound: bool,
    ): Object<Launchpad> {
        assert!(signer::address_of(launchpad_admin) == @launchpad_admin, error::unauthenticated(ENOT_LAUNCHPAD_ADMIN));

        let (_, launchpad_signer) = create_launchpad_refs(creator);
        let constructor_ref = if (option::is_some(&max_supply)) {
            collection::create_fixed_collection(
                &launchpad_signer,
                description,
                option::extract(&mut max_supply),
                name,
                royalty,
                uri,
            )
        } else {
            collection::create_unlimited_collection(
                &launchpad_signer,
                description,
                name,
                royalty,
                uri,
            )
        };
        collection_components::create_refs_and_properties(&constructor_ref);

        let collection = object::object_from_constructor_ref(&constructor_ref);
        move_to(&launchpad_signer, Launchpad { collection, soulbound });
        event::emit(CreateLaunchpad { collection, soulbound });

        object::address_to_object(signer::address_of(&launchpad_signer))
    }

    fun launchpad_signer(launchpad: Object<Launchpad>): signer acquires LaunchpadRefs {
        let launchpad_addr = object::object_address(&launchpad);
        assert!(exists<LaunchpadRefs>(launchpad_addr), error::invalid_argument(ELAUNCHPAD_REFS_DOES_NOT_EXIST));

        let refs = borrow_global<LaunchpadRefs>(launchpad_addr);
        object::generate_signer_for_extending(&refs.extend_ref)
    }

    fun create_launchpad_refs(creator: &signer): (Object<LaunchpadRefs>, signer) {
        let creator_addr = signer::address_of(creator);
        let constructor_ref = &object::create_object(creator_addr);
        let launchpad_signer = object::generate_signer(constructor_ref);
        move_to(&launchpad_signer, LaunchpadRefs { extend_ref: object::generate_extend_ref(constructor_ref) });

        let launchpad_refs = object::object_from_constructor_ref(constructor_ref);
        (launchpad_refs, launchpad_signer)
    }

    fun assert_owner<T: key>(owner: address, object: Object<T>) {
        assert!(object::owner(object) == owner, error::invalid_argument(ENOT_OWNER));
    }
}
