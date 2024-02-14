module minter::token_minter {

    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, ExtendRef, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::royalty;
    use aptos_token_objects::royalty::Royalty;
    use aptos_token_objects::token;

    use minter::apt_payment;
    use minter::whitelist;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinter has key {
        version: u64,
        collection: Object<Collection>,
        creator: address,
        paused: bool,
        soulbound: bool,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinterProperties has key {
        /// Used to generate signer, needed for adding additional guards.
        extend_ref: object::ExtendRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionProperties has key {
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
    struct TokenProperties has key {
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

    public entry fun init_token_minter(
        creator: &signer,
        description: String,
        max_supply: Option<u64>, // If value is present, collection configured to have a fixed supply.
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
        apt_payment_amount: Option<u64>,
        apt_payment_destination: address,
        soulbound: bool,
        paused: bool,
    ) {
        let creator_address = signer::address_of(creator);
        let (extend_ref, object_signer) = create_object_from_creator(creator_address);

        let collection_constructor_ref = create_collection(
            &object_signer,
            description,
            max_supply,
            name,
            royalty::create(royalty_numerator, royalty_denominator, creator_address),
            uri,
            mutable_description,
            mutable_royalty,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_freezable_by_creator,
        );

        let token_minter = TokenMinter {
            version: VERSION,
            collection: object::object_from_constructor_ref(&collection_constructor_ref),
            creator: creator_address,
            paused,
            soulbound,
        };
        move_to(&object_signer, token_minter);
        move_to(&object_signer, TokenMinterProperties { extend_ref });

        // Add guards
        if (whitelist_enabled) {
            whitelist::init_whitelist(&object_signer);
        };
        if (option::is_some(&apt_payment_amount)) {
            apt_payment::init_apt_payment(
                &object_signer,
                option::extract(&mut apt_payment_amount),
                apt_payment_destination
            );
        };
    }

    public entry fun mint(
        minter: &signer,
        token_minter_object: Object<TokenMinter>,
        description: String,
        name: String,
        uri: String,
        amount: u64,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
    ) acquires TokenMinter, TokenMinterProperties, CollectionProperties {
        let token_minter = borrow(&token_minter_object);
        assert!(!token_minter.paused, error::invalid_state(ETOKEN_MINTER_IS_PAUSED));

        let token_minter_address = object::object_address(&token_minter_object);

        // Check guards first before minting
        if (whitelist::is_whitelist_enabled(token_minter_address)) {
            whitelist::execute(token_minter_object, amount, signer::address_of(minter));
        };
        if (apt_payment::is_apt_payment_enabled(token_minter_address)) {
            apt_payment::execute(minter, token_minter_object, amount);
        };

        // Create Token
        mint_token(
            token_minter_object,
            description,
            name,
            uri,
            property_keys,
            property_types,
            property_values,
            token_minter.soulbound,
        );
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

    inline fun borrow_properties<T: key>(token_minter: &Object<T>): &TokenMinterProperties {
        let token_minter_address = object::object_address(token_minter);
        check_token_minter_exists(token_minter_address);

        borrow_global<TokenMinterProperties>(token_minter_address)
    }

    inline fun borrow_collection<T: key>(token_minter: &Object<T>): &CollectionProperties {
        let token_minter_address = object::object_address(token_minter);
        check_token_minter_exists(token_minter_address);

        borrow_global<CollectionProperties>(token_minter_address)
    }

    fun mint_token(
        token_minter_object: Object<TokenMinter>,
        description: String,
        name: String,
        uri: String,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
        _soulbound: bool,
    ): ConstructorRef acquires TokenMinter, TokenMinterProperties, CollectionProperties {
        // TODO: Mint soulbound token if true

        let token_minter = borrow(&token_minter_object);
        let extend_ref = &borrow_properties(&token_minter_object).extend_ref;
        let token_minter_signer = &object::generate_signer_for_extending(extend_ref);

        let constructor_ref = token::create(
            token_minter_signer,
            collection::name(token_minter.collection),
            description,
            name,
            royalty::get(token_minter.collection),
            uri
        );

        let collection = borrow_collection(&token_minter_object);
        let mutator_ref = if (
            collection.mutable_token_description
                || collection.mutable_token_name
                || collection.mutable_token_uri
        ) {
            option::some(token::generate_mutator_ref(&constructor_ref))
        } else {
            option::none()
        };

        let burn_ref = if (collection.tokens_burnable_by_creator) {
            option::some(token::generate_burn_ref(&constructor_ref))
        } else {
            option::none()
        };

        let token_signer = object::generate_signer(&constructor_ref);
        let token_properties = TokenProperties {
            burn_ref,
            transfer_ref: option::none(),
            mutator_ref,
            property_mutator_ref: property_map::generate_mutator_ref(&constructor_ref),
        };
        move_to(&token_signer, token_properties);

        let properties = property_map::prepare_input(property_keys, property_types, property_values);
        property_map::init(&constructor_ref, properties);

        constructor_ref
    }

    fun create_collection(
        object_signer: &signer,
        description: String,
        max_supply: Option<u64>,
        name: String,
        royalty: Royalty,
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
    ): ConstructorRef {
        let collection_constructor_ref = if (option::is_some(&max_supply)) {
            collection::create_fixed_collection(
                object_signer,
                description,
                option::extract(&mut max_supply),
                name,
                option::some(royalty),
                uri,
            )
        } else {
            collection::create_unlimited_collection(
                object_signer,
                description,
                name,
                option::some(royalty),
                uri,
            )
        };

        // Build refs for Collection
        let mutator_ref = if (mutable_description || mutable_uri) {
            option::some(collection::generate_mutator_ref(&collection_constructor_ref))
        } else {
            option::none()
        };
        let royalty_mutator_ref = if (mutable_royalty) {
            option::some(royalty::generate_mutator_ref(object::generate_extend_ref(&collection_constructor_ref)))
        } else {
            option::none()
        };

        let token_minter_collection = CollectionProperties {
            mutator_ref,
            royalty_mutator_ref,
            extend_ref: object::generate_extend_ref(&collection_constructor_ref),
            mutable_description,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_freezable_by_creator,
        };
        move_to(object_signer, token_minter_collection);

        collection_constructor_ref
    }

    fun create_object_from_creator(creator_addr: address): (ExtendRef, signer) {
        let constructor_ref = &object::create_object(creator_addr);
        let extend_ref = object::generate_extend_ref(constructor_ref);
        let object_signer = object::generate_signer(constructor_ref);
        (extend_ref, object_signer)
    }

    fun check_token_minter_exists(addr: address) {
        assert!(exists<TokenMinter>(addr), error::not_found(ETOKEN_MINTER_DOES_NOT_EXIST));
    }

    public fun assert_token_minter_owner<T: key>(creator: address, token_minter: Object<T>) {
        assert!(object::owner(token_minter) == creator, error::invalid_argument(ENOT_TOKEN_MINTER_OWNER));
    }
}
