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
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

    use minter::apt_payment;
    use minter::collection_helper;
    use minter::whitelist;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinter has key {
        version: u64,
        collection: Object<Collection>,
        creator: address,
        paused: bool,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinterProperties has key {
        /// Used to generate signer, needed for adding additional guards.
        extend_ref: Option<object::ExtendRef>,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionProperties has key {
        /// Used to mutate collection fields
        mutator_ref: Option<collection::MutatorRef>,
        /// Used to mutate royalties
        royalty_mutator_ref: Option<royalty::MutatorRef>,
        /// Used to generate signer, need for extending object.
        extend_ref: Option<object::ExtendRef>,
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
        /// If the collection is soulbound
        soulbound: bool,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenProperties has key {
        /// Used to generate signer, need for extending object.
        extend_ref: Option<object::ExtendRef>,
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

    const ENOT_OBJECT_OWNER: u64 = 1;
    const ETOKEN_MINTER_DOES_NOT_EXIST: u64 = 2;
    const ECOLLECTION_DOES_NOT_EXIST: u64 = 3;
    const ETOKEN_MINTER_IS_PAUSED: u64 = 4;
    /// The token does not exist
    const ETOKEN_DOES_NOT_EXIST: u64 = 5;
    /// The provided signer is not the creator
    const ENOT_CREATOR: u64 = 6;
    /// The field being changed is not mutable
    const EFIELD_NOT_MUTABLE: u64 = 7;
    /// The token being burned is not burnable
    const ETOKEN_NOT_BURNABLE: u64 = 8;
    /// The property map being mutated is not mutable
    const EPROPERTIES_NOT_MUTABLE: u64 = 9;

    /// Creates a new collection and token minter.
    /// The `Collection` `TokenMinter` and  created will each be contained in separate objects.
    /// The collection object will contain the `Collection` and `CollectionProperties`.
    /// The token minter object will contain the `TokenMinter` and `TokenMinterProperties`.
    public entry fun create_token_minter(
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
        royalty_numerator: u64,
        royalty_denominator: u64,
    ) {
        let creator_address = signer::address_of(creator);
        let collection_constructor_ref = &collection_helper::create_collection(
            creator,
            description,
            max_supply,
            name,
            option::some(royalty::create(royalty_numerator, royalty_denominator, creator_address)),
            uri,
        );

        create_collection_properties(
            collection_constructor_ref,
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

        // Create new object and store `TokenMinter` and `TokenMinterProperties`
        let (extend_ref, object_signer) = create_object_from_creator(creator_address);
        let token_minter = TokenMinter {
            version: VERSION,
            collection: object::object_from_constructor_ref(collection_constructor_ref),
            creator: creator_address,
            paused: false,
        };
        move_to(&object_signer, token_minter);
        move_to(&object_signer, TokenMinterProperties { extend_ref: option::some(extend_ref) });
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
        let minter_address = signer::address_of(minter);

        // Check guards first before minting
        if (whitelist::is_whitelist_enabled(token_minter_address)) {
            whitelist::execute(token_minter_object, amount, minter_address);
        };
        if (apt_payment::is_apt_payment_enabled(token_minter_address)) {
            apt_payment::execute(minter, token_minter_object, amount);
        };

        mint_token(
            minter_address,
            token_minter_object,
            description,
            name,
            uri,
            property_keys,
            property_types,
            property_values,
        );
    }

    public entry fun set_soulbound(
        creator: &signer,
        collection_props: Object<CollectionProperties>,
        soulbound: bool,
    ) acquires CollectionProperties {
        assert_object_owner(signer::address_of(creator), collection_props);

        let collection_props = borrow_collection_props_mut(&collection_props);
        collection_props.soulbound = soulbound;
    }

    // ================================= Guards ================================= //

    public fun add_or_update_whitelist(
        creator: &signer,
        token_minter: Object<TokenMinter>,
        whitelisted_addresses: vector<address>,
        max_mint_per_whitelists: vector<u64>,
    ) {
        assert_object_owner(signer::address_of(creator), token_minter);
        whitelist::add_or_update_whitelist(creator, token_minter, whitelisted_addresses, max_mint_per_whitelists);
    }

    public entry fun remove_whitelist_guard(creator: &signer, token_minter: Object<TokenMinter>) {
        assert_object_owner(signer::address_of(creator), token_minter);
        whitelist::remove_whitelist(token_minter);
    }

    public entry fun add_or_update_apt_payment_guard(
        creator: &signer,
        token_minter: Object<TokenMinter>,
        amount: u64,
        destination: address,
    ) {
        assert_object_owner(signer::address_of(creator), token_minter);
        apt_payment::add_or_update_apt_payment(creator, token_minter, amount, destination);
    }

    public entry fun remove_apt_payment_guard(creator: &signer, token_minter: Object<TokenMinter>) {
        assert_object_owner(signer::address_of(creator), token_minter);
        apt_payment::remove_apt_payment(token_minter);
    }

    // ================================= Token Mutators ================================= //

    public entry fun set_description<T: key>(
        creator: &signer,
        token: Object<T>,
        description: String,
    ) acquires CollectionProperties, TokenProperties {
        assert!(
            is_mutable_description(token),
            error::permission_denied(EFIELD_NOT_MUTABLE),
        );
        let token_props = authorized_borrow_token_props(token, creator);
        token::set_description(option::borrow(&token_props.mutator_ref), description);
    }

    // ================================= Private functions ================================= //
    fun create_collection_properties(
        collection_constructor_ref: &ConstructorRef,
        mutable_description: bool,
        mutable_royalty: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_freezable_by_creator: bool,
    ) {
        let mutator_ref = if (mutable_description || mutable_uri) {
            option::some(collection::generate_mutator_ref(collection_constructor_ref))
        } else {
            option::none()
        };
        let royalty_mutator_ref = if (mutable_royalty) {
            option::some(royalty::generate_mutator_ref(object::generate_extend_ref(collection_constructor_ref)))
        } else {
            option::none()
        };

        let collection_props = CollectionProperties {
            mutator_ref,
            royalty_mutator_ref,
            extend_ref: option::some(object::generate_extend_ref(collection_constructor_ref)),
            mutable_description,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_freezable_by_creator,
            soulbound: false,
        };
        move_to(&object::generate_signer(collection_constructor_ref), collection_props);
    }

    fun mint_token(
        minter: address,
        token_minter_object: Object<TokenMinter>,
        description: String,
        name: String,
        uri: String,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
    ) acquires TokenMinter, TokenMinterProperties, CollectionProperties {
        let token_minter = borrow(&token_minter_object);
        let extend_ref = &borrow_props(&token_minter_object).extend_ref;
        let token_minter_signer = &object::generate_signer_for_extending(option::borrow(extend_ref));

        let token_constructor_ref = &token::create(
            token_minter_signer,
            collection::name(token_minter.collection),
            description,
            name,
            royalty::get(token_minter.collection),
            uri
        );

        let collection_props = borrow_collection_props(&token_minter_object);
        let mutator_ref = if (
            collection_props.mutable_token_description
                || collection_props.mutable_token_name
                || collection_props.mutable_token_uri
        ) {
            option::some(token::generate_mutator_ref(token_constructor_ref))
        } else {
            option::none()
        };

        let burn_ref = if (collection_props.tokens_burnable_by_creator) {
            option::some(token::generate_burn_ref(token_constructor_ref))
        } else {
            option::none()
        };

        let token_signer = object::generate_signer(token_constructor_ref);
        let token_properties = TokenProperties {
            extend_ref: option::some(object::generate_extend_ref(token_constructor_ref)),
            burn_ref,
            transfer_ref: option::none(),
            mutator_ref,
            property_mutator_ref: property_map::generate_mutator_ref(token_constructor_ref),
        };
        move_to(&token_signer, token_properties);

        let properties = property_map::prepare_input(property_keys, property_types, property_values);
        property_map::init(token_constructor_ref, properties);

        transfer_token_to_minter(collection_props.soulbound, token_constructor_ref, minter, token_minter_signer);
    }

    fun transfer_token_to_minter(
        soulbound: bool,
        token_constructor_ref: &ConstructorRef,
        minter: address,
        token_minter_signer: &signer,
    ) {
        if (soulbound) {
            let transfer_ref = &object::generate_transfer_ref(token_constructor_ref);
            let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);
            object::transfer_with_ref(linear_transfer_ref, minter);
            object::disable_ungated_transfer(transfer_ref);
        } else {
            let token = object::object_from_constructor_ref<Token>(token_constructor_ref);
            object::transfer(token_minter_signer, token, minter);
        };
    }

    inline fun borrow<T: key>(token_minter: &Object<T>): &TokenMinter acquires TokenMinter {
        borrow_global<TokenMinter>(token_minter_address(token_minter))
    }

    inline fun borrow_props<T: key>(token_minter: &Object<T>): &TokenMinterProperties {
        borrow_global<TokenMinterProperties>(token_minter_address(token_minter))
    }

    inline fun borrow_collection_props<T: key>(collection_props: &Object<T>): &CollectionProperties {
        borrow_global<CollectionProperties>(collection_props_address(collection_props))
    }

    inline fun borrow_collection_props_mut<T: key>(collection_props: &Object<T>): &mut CollectionProperties {
        borrow_global_mut<CollectionProperties>(collection_props_address(collection_props))
    }

    inline fun borrow_token_props_mut<T: key>(token_props: &Object<T>): &mut TokenProperties {
        borrow_global_mut<TokenProperties>(token_props_address(token_props))
    }

    inline fun authorized_borrow_token_props<T: key>(token: Object<T>, creator: &signer): &TokenProperties {
        let token_props = borrow_token_props_mut(&token);
        assert_creator(token, signer::address_of(creator));
        token_props
    }

    fun create_object_from_creator(creator_address: address): (ExtendRef, signer) {
        let constructor_ref = &object::create_object(creator_address);
        let extend_ref = object::generate_extend_ref(constructor_ref);
        let object_signer = object::generate_signer(constructor_ref);
        (extend_ref, object_signer)
    }

    fun token_minter_address<T: key>(token_minter: &Object<T>): address {
        let token_minter_address = object::object_address(token_minter);
        assert!(exists<TokenMinter>(token_minter_address), error::not_found(ETOKEN_MINTER_DOES_NOT_EXIST));
        token_minter_address
    }

    fun collection_props_address<T: key>(collection: &Object<T>): address {
        let collection_address = object::object_address(collection);
        assert!(exists<CollectionProperties>(collection_address), error::not_found(ECOLLECTION_DOES_NOT_EXIST));
        collection_address
    }

    fun token_props_address<T: key>(token: &Object<T>): address {
        let token_address = object::object_address(token);
        assert!(exists<TokenProperties>(token_address), error::not_found(ETOKEN_DOES_NOT_EXIST));
        token_address
    }

    fun assert_object_owner<T: key>(creator: address, object: Object<T>) {
        assert!(object::owner(object) == creator, error::invalid_argument(ENOT_OBJECT_OWNER));
    }

    fun assert_creator<T: key>(object: Object<T>, creator: address) {
        assert!(object::owner(object) == creator, error::invalid_argument(ENOT_CREATOR));
    }

    public fun is_mutable_collection_token_description<T: key>(
        collection: Object<T>,
    ): bool acquires CollectionProperties {
        borrow_collection_props(&collection).mutable_token_description
    }

    #[view]
    public fun is_mutable_description<T: key>(token: Object<T>): bool acquires CollectionProperties {
        is_mutable_collection_token_description(token::collection_object(token))
    }
}
