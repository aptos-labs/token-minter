module airdrop_machine::airdrop_machine {
    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::{String, utf8};

    use aptos_framework::object::{Self, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::royalty;
    use aptos_token_objects::royalty::Royalty;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

    use minter::collection_components;
    use minter::collection_properties;
    use minter::token_components;
    use minter::transfer_token;

    /// The provided signer is not the collection owner.
    const ENOT_OWNER: u64 = 1;
    /// CollectionConfig resource does not exist in the object address.
    const ECOLLECTION_CONFIG_DOES_NOT_EXIST: u64 = 2;
    /// Royalty configuration is invalid because either numerator and denominator should be none or not none.
    const EROYALTY_CONFIGURATION_INVALID: u64 = 3;
    /// Token Minting has not yet started.
    const EMINTING_HAS_NOT_STARTED: u64 = 7;

    struct CollectionConfig has key {
        extend_ref: object::ExtendRef,
        ready_to_mint: bool,
    }

    public entry fun create_collection(
        admin: &signer,
        description: String,
        name: String,
        uri: String,
        mutable_collection_metadata: bool, // including description, uri, royalty, to make admin life easier
        mutable_token_metadata: bool, // including description, name, properties, uri, to make admin life easier
        tokens_burnable_by_collection_owner: bool,
        tokens_transferrable_by_collection_owner: bool,
        max_supply: Option<u64>,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
    ) {
        create_collection_impl(
            admin,
            description,
            name,
            uri,
            mutable_collection_metadata,
            mutable_token_metadata,
            tokens_burnable_by_collection_owner,
            tokens_transferrable_by_collection_owner,
            max_supply,
            royalty_numerator,
            royalty_denominator,
        );
    }

    public entry fun mint(
        user: &signer,
        name: String,
        description: String,
        uri: String,
        collection: Object<Collection>,
    ) acquires CollectionConfig {
        mint_impl(
            user,
            collection,
            name,
            description,
            uri,
            signer::address_of(user),
        );
    }

    // only used by txn emitter for load testing
     public entry fun mint_with_admin_worker(
        _worker: &signer,
        admin: &signer,
        collection: Object<Collection>,
        name: String,
        description: String,
        uri: String,
        recipient_addr: address,
    ) acquires CollectionConfig {
        mint_with_admin_impl(
            admin,
            collection,
            name,
            description,
            uri,
            recipient_addr,
        );
    }

    public entry fun mint_with_admin(
        admin: &signer,
        collection: Object<Collection>,
        name: String,
        description: String,
        uri: String,
        recipient_addr: address,
    ) acquires CollectionConfig {
        mint_with_admin_impl(
            admin,
            collection,
            name,
            description,
            uri,
            recipient_addr,
        );
    }

    public entry fun set_minting_status(admin: &signer, collection: Object<Collection>, ready_to_mint: bool) acquires CollectionConfig {
        assert_owner(signer::address_of(admin), collection);
        let collection_config = borrow_mut(collection);
        collection_config.ready_to_mint = ready_to_mint;
    }

    public fun mint_with_admin_impl(
        admin: &signer,
        collection: Object<Collection>,
        name: String,
        description: String,
        uri: String,
        recipient_addr: address,
    ): Object<Token> acquires CollectionConfig {
        assert_owner(signer::address_of(admin), collection);
        mint_impl(admin, collection, name, description, uri, recipient_addr)
    }

    public fun mint_impl(
        _minter: &signer,
        collection: Object<Collection>,
        name: String,
        description: String,
        uri: String,
        recipient_addr: address,
    ): Object<Token> acquires CollectionConfig {
        assert!(minting_started(collection), error::permission_denied(EMINTING_HAS_NOT_STARTED));

        let collection_signer = collection_signer(collection);
        
        let constructor_ref = &token::create_numbered_token(
            &collection_signer,
            collection::name(collection),
            description,
            name,
            utf8(b""), // name_with_index_suffix 
            royalty::get(collection),
            uri,
        );

        token_components::create_refs(constructor_ref);
        transfer_token::transfer(&collection_signer, recipient_addr, constructor_ref);
        object::object_from_constructor_ref(constructor_ref)
    }

    public fun create_collection_impl(
        admin: &signer,
        description: String,
        name: String,
        uri: String,
        mutable_collection_metadata: bool,
        mutable_token_metadata: bool,
        tokens_burnable_by_collection_owner: bool,
        tokens_transferrable_by_collection_owner: bool,
        max_supply: Option<u64>,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
    ): Object<Collection> {
        let admin_addr = signer::address_of(admin);
        let object_constructor_ref = &object::create_object(admin_addr);
        let object_signer = object::generate_signer(object_constructor_ref);
        let royalty = royalty(&mut royalty_numerator, &mut royalty_denominator, admin_addr);

        let constructor_ref = if (option::is_some(&max_supply)) {
            collection::create_fixed_collection(
                &object_signer,
                description,
                option::extract(&mut max_supply),
                name,
                royalty,
                uri,
            )
        } else {
            collection::create_unlimited_collection(
                &object_signer,
                description,
                name,
                royalty,
                uri,
            )
        };

        collection_components::create_refs_and_properties(&constructor_ref);
        let collection = object::object_from_constructor_ref(&constructor_ref);
        configure_collection_and_token_properties(
            &object_signer,
            collection,
            mutable_collection_metadata,
            mutable_token_metadata,
            tokens_burnable_by_collection_owner,
            tokens_transferrable_by_collection_owner,
        );

        let object_signer = object::generate_signer(&constructor_ref);

        move_to(&object_signer, CollectionConfig {
            extend_ref: object::generate_extend_ref(object_constructor_ref),
            ready_to_mint: false,
        });

        collection
    }

    fun royalty(
        royalty_numerator: &mut Option<u64>, 
        royalty_denominator: &mut Option<u64>, 
        admin_addr: address
    ): Option<Royalty> {
        assert!(option::is_some(royalty_numerator) == option::is_some(royalty_denominator), error::invalid_argument(EROYALTY_CONFIGURATION_INVALID));
        if (option::is_some(royalty_numerator) && option::is_some(royalty_denominator) && option::extract(royalty_numerator) != 0 && option::extract(royalty_denominator) != 0) {
            option::some(royalty::create(option::extract(royalty_numerator), option::extract(royalty_denominator), admin_addr))
        } else {
            option::none()
        }
    }

    fun configure_collection_and_token_properties(
        admin: &signer,
        collection: Object<Collection>,
        mutable_collection_metadata: bool,
        mutable_token_metadata: bool,
        tokens_burnable_by_collection_owner: bool,
        tokens_transferrable_by_collection_owner: bool,
    ) {
        collection_properties::set_mutable_description(admin, collection, mutable_collection_metadata);
        collection_properties::set_mutable_uri(admin, collection, mutable_collection_metadata);
        collection_properties::set_mutable_royalty(admin, collection, mutable_collection_metadata);
        collection_properties::set_mutable_token_name(admin, collection, mutable_token_metadata);
        collection_properties::set_mutable_token_properties(admin, collection, mutable_token_metadata);
        collection_properties::set_mutable_token_description(admin, collection, mutable_token_metadata);
        collection_properties::set_mutable_token_uri(admin, collection, mutable_token_metadata);
        collection_properties::set_tokens_transferable_by_collection_owner(admin, collection, tokens_transferrable_by_collection_owner);
        collection_properties::set_tokens_burnable_by_collection_owner(admin, collection, tokens_burnable_by_collection_owner);
    }

    fun assert_owner<T: key>(owner: address, object: Object<T>) {
        assert!(object::owner(object) == owner || object::owns(object, owner), error::permission_denied(ENOT_OWNER));
    }

    fun collection_signer(collection: Object<Collection>): signer acquires CollectionConfig {
        let refs = borrow(collection);
        object::generate_signer_for_extending(&refs.extend_ref)
    }

    inline fun borrow(collection: Object<Collection>): &CollectionConfig acquires CollectionConfig {
        let collection_address = object::object_address(&collection);
        assert!(
            exists<CollectionConfig>(collection_address),
            error::not_found(ECOLLECTION_CONFIG_DOES_NOT_EXIST)
        );

        borrow_global<CollectionConfig>(collection_address)
    }

    inline fun borrow_mut(collection: Object<Collection>): &mut CollectionConfig acquires CollectionConfig {
        let collection_address = object::object_address(&collection);
        assert!(
            exists<CollectionConfig>(collection_address),
            error::not_found(ECOLLECTION_CONFIG_DOES_NOT_EXIST)
        );

        borrow_global_mut<CollectionConfig>(collection_address)
    }

    #[view]
    public fun minting_started(collection: Object<Collection>): bool acquires CollectionConfig {
        let collection_config = borrow(collection);

        collection_config.ready_to_mint == true
    }
}
