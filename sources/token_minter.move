module minter::token_minter {

    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use aptos_token::token::Royalty;

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::royalty;
    use aptos_token_objects::token;
    use minter::apt_payment;
    use minter::whitelist;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinter has key {
        version: u64,
        collection: Object<Collection>,
        creator: address,
        paused: bool,
        is_soulbound: bool,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinterCollection has key {
        /// Used to mutate collection fields
        mutator_ref: Option<collection::MutatorRef>,
        /// Used to mutate royalties
        royalty_mutator_ref: Option<royalty::MutatorRef>,
        /// Used to generate signer, needed for adding additional guards.
        extend_ref: object::ExtendRef,
        /// Determines if the creator can mutate the collection's description
        mutable_description: bool,
        /// Determines if the creator can mutate the collection's uri
        mutable_uri: bool,
        /// Determines if the creator can mutate token descriptions
        mutable_token_description: bool,
        /// Determines if the creator can mutate token names
        mutable_token_name: bool,
        /// Determines if the creator can mutate token properties
        mutable_token_properties: bool,
        /// Determines if the creator can mutate token uris
        mutable_token_uri: bool,
        /// Determines if the creator can burn tokens
        tokens_burnable_by_creator: bool,
        /// Determines if the creator can freeze tokens
        tokens_freezable_by_creator: bool,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Storage state for managing the no-code Token.
    struct TokenMinterToken has key {
        /// Used to burn.
        burn_ref: Option<token::BurnRef>,
        /// Used to control freeze.
        transfer_ref: Option<object::TransferRef>,
        /// Used to mutate fields
        mutator_ref: Option<token::MutatorRef>,
        /// Used to mutate properties
        property_mutator_ref: property_map::MutatorRef,
    }

    const VERSION: u64 = 1;

    const ENOT_TOKEN_MINTER_OWNER: u64 = 1;
    const ETOKEN_MINTER_DOES_NOT_EXIST: u64 = 2;
    const ETOKEN_MINTER_IS_PAUSED: u64 = 3;

    /// If `max_supply` is 0, then collection supply is unlimited.
    public entry fun init_token_minter(
        creator: &signer,
        description: String,
        max_supply: u64,
        name: String,
        uri: String,
        mutable_description: bool,
        mutable_royalty: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_freezable_by_creator: bool,
        whitelist_enabled: bool,
        royalty_numerator: u64,
        royalty_denominator: u64,
        apt_payment_amount: u64,
        apt_payment_destination: address,
        is_soulbound: bool,
    ) {
        let creator_addr = signer::address_of(creator);
        let royalty = royalty::create(royalty_numerator, royalty_denominator, creator_addr);

        let constructor_ref = if (max_supply > 0) {
            collection::create_fixed_collection(
                creator,
                description,
                max_supply,
                name,
                option::some(royalty),
                uri,
            )
        } else {
            collection::create_unlimited_collection(
                creator,
                description,
                name,
                option::some(royalty),
                uri,
            )
        };

        let object_signer = &object::generate_signer(&constructor_ref);

        let token_minter = TokenMinter {
            version: VERSION,
            collection: object::object_from_constructor_ref(&constructor_ref),
            creator: creator_addr,
            paused: false,
            is_soulbound,
        };
        move_to(object_signer, token_minter);

        // Build refs
        let mutator_ref = if (mutable_description || mutable_uri) {
            option::some(collection::generate_mutator_ref(&constructor_ref))
        } else {
            option::none()
        };
        let royalty_mutator_ref = if (mutable_royalty) {
            option::some(royalty::generate_mutator_ref(object::generate_extend_ref(&constructor_ref)))
        } else {
            option::none()
        };

        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // Add guards
        if (whitelist_enabled) {
            whitelist::init_whitelist(object_signer);
        };
        if (apt_payment_amount > 0) {
            apt_payment::init_apt_payment(object_signer, apt_payment_amount, apt_payment_destination);
        };

        let aptos_collection = TokenMinterCollection {
            mutator_ref,
            royalty_mutator_ref,
            extend_ref,
            mutable_description,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_freezable_by_creator,
        };

        move_to(object_signer, aptos_collection);
    }

    public fun mint(
        minter: &signer,
        token_minter_object: Object<TokenMinter>,
        description: String,
        name: String,
        royalty: Option<Royalty>,
        uri: String,
        amount: u64,
    ) acquires TokenMinter {
        let token_minter = borrow(&token_minter_object);
        assert!(!token_minter.paused, error::invalid_state(ETOKEN_MINTER_IS_PAUSED));

        let token_minter_address = object::object_address(&token_minter_object);
        // Check guards
        if (whitelist::is_whitelist_enabled(token_minter_address)) {
            whitelist::execute(token_minter_object, amount, signer::address_of(minter));
        };
        if (apt_payment::is_apt_payment_enabled(token_minter_address)) {
            apt_payment::execute(minter, token_minter_object, amount);
        };

        // Create Token
        // let collection = token_minter.collection;
        // let constructor_ref = token::create(
        //     creator,
        //     collection::name(collection),
        //     description,
        //     name,
        //     option::none(),
        //     uri
        // );
    }

    public fun add_to_whitelist(
        creator: &signer,
        token_minter: Object<TokenMinter>,
        whitelisted_addresses: vector<address>,
        max_mint_per_whitelists: vector<u64>,
    ) {
        assert_token_minter_owner(signer::address_of(creator), token_minter);
        whitelist::add_to_whitelist(token_minter, whitelisted_addresses, max_mint_per_whitelists);
    }

    inline fun borrow<T: key>(token_minter: &Object<T>): &TokenMinter acquires TokenMinter {
        let token_minter_address = object::object_address(token_minter);
        check_token_minter_exists(token_minter_address);
        borrow_global<TokenMinter>(token_minter_address)
    }

    fun check_token_minter_exists(addr: address) {
        assert!(exists<TokenMinter>(addr), error::not_found(ETOKEN_MINTER_DOES_NOT_EXIST));
    }

    public fun assert_token_minter_owner<T: key>(creator: address, token_minter: Object<T>) {
        assert!(object::owner(token_minter) == creator, error::invalid_argument(ENOT_TOKEN_MINTER_OWNER));
    }
}
