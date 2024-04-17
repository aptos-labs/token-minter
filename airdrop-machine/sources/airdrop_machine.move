module airdrop_machine::airdrop_machine {
    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::utf8;
    use std::string::String;
    use std::vector;

    use aptos_framework::transaction_context;
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
    /// Token Minting has not yet started.
    const EMINTING_HAS_NOT_STARTED: u64 = 3;
    
    struct MetadataConfig has store, copy, drop {
        collection_name: String,
        collection_description: String,
        collection_uri: String,
        token_name_prefix: String,
        token_description: String,
        token_uris: vector<String>,
    }

    struct CollectionConfig has key {
        metadata_config: MetadataConfig,
        collection: Object<Collection>,
        extend_ref: object::ExtendRef,
        ready_to_mint: bool,
    }

    public entry fun create_collection(
        admin: &signer,
        collection_name: String,
        collection_description: String,
        collection_uri: String,
        token_name_prefix: String,
        token_description: String,
        token_uris: vector<String>,
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
            collection_name,
            collection_description,
            collection_uri,
            token_name_prefix,
            token_description,
            token_uris,
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
        collection_config_object: Object<CollectionConfig>,
    ) acquires CollectionConfig {
        mint_impl(
            user,
            collection_config_object,
            signer::address_of(user),
        );
    }

    // only used by txn emitter for load testing
     public entry fun mint_with_admin_worker(
        _worker: &signer,
        admin: &signer,
        collection_config_object: Object<CollectionConfig>,
        recipient_addr: address,
    ) acquires CollectionConfig {
        mint_with_admin_impl(
            admin,
            collection_config_object,
            recipient_addr,
        );
    }

    public entry fun mint_with_admin(
        admin: &signer,
        collection_config_object: Object<CollectionConfig>,
        recipient_addr: address,
    ) acquires CollectionConfig {
        mint_with_admin_impl(
            admin,
            collection_config_object,
            recipient_addr,
        );
    }

    public entry fun set_minting_status(admin: &signer, collection_config_object: Object<CollectionConfig>, ready_to_mint: bool) acquires CollectionConfig {
        assert_owner(signer::address_of(admin), collection_config_object);
        let collection_config = borrow_mut(collection_config_object);
        collection_config.ready_to_mint = ready_to_mint;
    }

    public fun mint_with_admin_impl(
        admin: &signer,
        collection_config_object: Object<CollectionConfig>,
        recipient_addr: address,
    ): Object<Token> acquires CollectionConfig {
        assert_owner(signer::address_of(admin), collection_config_object);
        mint_impl(admin, collection_config_object, recipient_addr)
    }

    fun mint_impl(
        _minter: &signer,
        collection_config_object: Object<CollectionConfig>,
        recipient_addr: address,
    ): Object<Token> acquires CollectionConfig {
        assert!(minting_started(collection_config_object), error::permission_denied(EMINTING_HAS_NOT_STARTED));
        
        let collection_config = borrow(collection_config_object);
        let collection_owner_signer = collection_owner_signer(collection_config);
        let metadata_config = collection_config.metadata_config;
        let collection = collection_config.collection;
        let index = get_pseudo_random_index(vector::length(&metadata_config.token_uris));
        let uri = *vector::borrow(&metadata_config.token_uris, (index as u64));
        let constructor_ref = &token::create_numbered_token(
            &collection_owner_signer,
            collection::name(collection),
            metadata_config.token_description,
            metadata_config.token_name_prefix,
            utf8(b""), // name_with_index_suffix 
            royalty::get(collection),
            uri,
        );

        token_components::create_refs(constructor_ref);
        transfer_token::transfer(&collection_owner_signer, recipient_addr, constructor_ref);
        object::object_from_constructor_ref(constructor_ref)
    }

    public fun create_collection_impl(
        admin: &signer,
        collection_name: String,
        collection_description: String,
        collection_uri: String,
        token_name_prefix: String,
        token_description: String,
        token_uris: vector<String>,
        mutable_collection_metadata: bool,
        mutable_token_metadata: bool,
        tokens_burnable_by_collection_owner: bool,
        tokens_transferrable_by_collection_owner: bool,
        max_supply: Option<u64>,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
    ): Object<CollectionConfig> {
        let admin_addr = signer::address_of(admin);
        let object_constructor_ref = &object::create_object(admin_addr);
        let object_signer = object::generate_signer(object_constructor_ref);
        let royalty = royalty(&mut royalty_numerator, &mut royalty_denominator, admin_addr);

        let constructor_ref = if (option::is_some(&max_supply)) {
            collection::create_fixed_collection(
                &object_signer,
                collection_description,
                option::extract(&mut max_supply),
                collection_name,
                royalty,
                collection_uri,
            )
        } else {
            collection::create_unlimited_collection(
                &object_signer,
                collection_description,
                collection_name,
                royalty,
                collection_uri,
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

        let metadata_config = MetadataConfig {
            collection_name,
            collection_description,
            collection_uri,
            token_name_prefix,
            token_description,
            token_uris,
        };
        move_to(&object_signer, CollectionConfig {
            metadata_config,
            collection,
            extend_ref: object::generate_extend_ref(object_constructor_ref),
            ready_to_mint: false,
        });

        object::address_to_object(signer::address_of(&object_signer))
    }

    fun royalty(
        royalty_numerator: &mut Option<u64>, 
        royalty_denominator: &mut Option<u64>, 
        admin_addr: address
    ): Option<Royalty> {
        if (option::is_some(royalty_numerator) && option::is_some(royalty_denominator)) {
            let num = option::extract(royalty_numerator);
            let den = option::extract(royalty_denominator);
            if (num != 0 && den != 0) {
                option::some(royalty::create(num, den, admin_addr));
            };
        };
        option::none()
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
        assert!(object::owner(object) == owner, error::permission_denied(ENOT_OWNER));
    }

    inline fun collection_owner_signer(collection_config: &CollectionConfig): signer acquires CollectionConfig {
        object::generate_signer_for_extending(&collection_config.extend_ref)
    }

    inline fun borrow(collection_config_object: Object<CollectionConfig>): &CollectionConfig acquires CollectionConfig {
        borrow_global<CollectionConfig>(object::object_address(&collection_config_object))
    }

    inline fun borrow_mut(collection_config_object: Object<CollectionConfig>): &mut CollectionConfig acquires CollectionConfig {
        borrow_global_mut<CollectionConfig>(object::object_address(&collection_config_object))
    }

    fun get_pseudo_random_index(length: u64): u64 {
        let txn_hash = transaction_context::get_transaction_hash();
        ((*vector::borrow(&txn_hash, 0) as u64) * 256u64) % length
    }

    #[view]
    public fun minting_started(collection_config_object: Object<CollectionConfig>): bool acquires CollectionConfig {
        borrow(collection_config_object).ready_to_mint
    }

    #[test_only]
    public fun mint_impl_for_testing(
        minter: &signer,
        collection_config_object: Object<CollectionConfig>,
        recipient_addr: address,
    ): Object<Token> acquires CollectionConfig {
       mint_impl(minter,collection_config_object,recipient_addr)
    }
}
