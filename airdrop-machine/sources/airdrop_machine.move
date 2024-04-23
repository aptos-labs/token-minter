module airdrop_machine::airdrop_machine {
    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::utf8;
    use std::string::String;
    use std::vector;

    use aptos_framework::event;
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
    /// Token Metadata URIs and Weights have different size.
    const ETOKEN_METADATA_MISMATCH: u64 = 4;
    /// MetadataConfig resource does not exist in the object address.
    const EMETADATA_CONFIG_DOES_NOT_EXIST: u64 = 5;

    struct TokenMetadata has copy, store, drop {
        uri: String,
        weight: u64, // to add different probabilities of getting randomly selected
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct MetadataConfig has key {
        collection_name: String,
        collection_description: String,
        collection_uri: String,
        token_name_prefix: String,
        token_description: String,
        token_metadatas: vector<TokenMetadata>,
        token_total_weight: u64, // memoization on uri weights to avoid repeated computation
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionConfig has key {
        collection: Object<Collection>,
        extend_ref: object::ExtendRef,
        ready_to_mint: bool,
    }

    #[event]
    /// Emitted when a collection and collection config has been created.
    struct CreateCollectionConfig has drop, store {
        collection_config: Object<CollectionConfig>,
        collection: Object<Collection>,
        ready_to_mint: bool,
    }

    #[event]
    /// Emitted when the minting status has been updated.
    struct SetMintingStatus has drop, store {
        collection_config: Object<CollectionConfig>,
        ready_to_mint: bool,
    }

    #[event]
    /// Emitted when a token has been minted by a user.
    struct Mint has drop, store {
        token: Object<Token>,
        to: address,
        referrer: String,
    }

    public entry fun create_collection(
        admin: &signer,
        collection_name: String,
        collection_description: String,
        collection_uri: String,
        token_name_prefix: String,
        token_description: String,
        token_uris: vector<String>,
        token_uris_weights: vector<u64>,
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
            token_uris_weights,
            mutable_collection_metadata,
            mutable_token_metadata,
            tokens_burnable_by_collection_owner,
            tokens_transferrable_by_collection_owner,
            max_supply,
            royalty_numerator,
            royalty_denominator,
        );
    }

    entry fun mint(
        user: &signer,
        collection_config_object: Object<CollectionConfig>,
        referrer: String,
    ) acquires CollectionConfig, MetadataConfig {
        let user_addr = signer::address_of(user);
        let token = mint_impl(
            user,
            collection_config_object,
            user_addr,
        );

        event::emit(Mint {
            token,
            to: user_addr,
            referrer,
        });
    }

    // only used by txn emitter for load testing
    public entry fun mint_with_admin_worker(
        _worker: &signer,
        admin: &signer,
        collection_config_object: Object<CollectionConfig>,
        recipient_addr: address,
    ) acquires CollectionConfig, MetadataConfig {
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
    ) acquires CollectionConfig, MetadataConfig {
        mint_with_admin_impl(
            admin,
            collection_config_object,
            recipient_addr,
        );
    }

    public entry fun set_minting_status(
        admin: &signer,
        collection_config_object: Object<CollectionConfig>,
        ready_to_mint: bool
    ) acquires CollectionConfig {
        assert_owner(signer::address_of(admin), collection_config_object);
        let collection_config = borrow_mut(collection_config_object);
        collection_config.ready_to_mint = ready_to_mint;

        event::emit(SetMintingStatus { collection_config: collection_config_object, ready_to_mint });
    }

    public entry fun burn_with_admin_worker(
        _worker: &signer,
        admin: &signer,
        collection_config_object: Object<CollectionConfig>,
        token: Object<Token>,
    ) acquires CollectionConfig {
        burn_with_admin(admin, collection_config_object, token);
    }

    public entry fun burn_with_admin(
        admin: &signer,
        collection_config_object: Object<CollectionConfig>,
        token: Object<Token>,
    ) acquires CollectionConfig {
        assert_owner(signer::address_of(admin), collection_config_object);
        let collection_signer = collection_owner_signer(borrow(collection_config_object));
        token_components::burn(&collection_signer, token);
    }

    public fun mint_with_admin_impl(
        admin: &signer,
        collection_config_object: Object<CollectionConfig>,
        recipient_addr: address,
    ): Object<Token> acquires CollectionConfig, MetadataConfig {
        assert_owner(signer::address_of(admin), collection_config_object);
        mint_impl(admin, collection_config_object, recipient_addr)
    }

    fun mint_impl(
        _minter: &signer,
        collection_config_object: Object<CollectionConfig>,
        recipient_addr: address,
    ): Object<Token> acquires CollectionConfig, MetadataConfig {
        assert!(minting_started(collection_config_object), error::permission_denied(EMINTING_HAS_NOT_STARTED));

        let collection_config = borrow(collection_config_object);
        let collection_owner_signer = collection_owner_signer(collection_config);
        let metadata_config = borrow_metadata_config(collection_config_object);
        let collection = collection_config.collection;
        let index = get_weighted_pseudo_random_index(
            &metadata_config.token_metadatas,
            metadata_config.token_total_weight
        );
        let uri = vector::borrow(&metadata_config.token_metadatas, index).uri;
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
        token_uris_weights: vector<u64>,
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

        let (token_metadatas, token_total_weight) = create_token_metadatas_and_compute_total_weight(
            token_uris,
            token_uris_weights
        );
        move_to(&object_signer, MetadataConfig {
            collection_name,
            collection_description,
            collection_uri,
            token_name_prefix,
            token_description,
            token_metadatas,
            token_total_weight,
        });

        move_to(&object_signer, CollectionConfig {
            collection,
            extend_ref: object::generate_extend_ref(object_constructor_ref),
            ready_to_mint: false,
        });

        let collection_config = object::object_from_constructor_ref(object_constructor_ref);
        event::emit(CreateCollectionConfig {
            collection_config,
            collection,
            ready_to_mint: false,
        });

        collection_config
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
        collection_properties::set_tokens_transferable_by_collection_owner(
            admin,
            collection,
            tokens_transferrable_by_collection_owner
        );
        collection_properties::set_tokens_burnable_by_collection_owner(
            admin,
            collection,
            tokens_burnable_by_collection_owner
        );
    }

    fun assert_owner<T: key>(owner: address, object: Object<T>) {
        assert!(object::owner(object) == owner, error::permission_denied(ENOT_OWNER));
    }

    inline fun collection_owner_signer(collection_config: &CollectionConfig): signer {
        object::generate_signer_for_extending(&collection_config.extend_ref)
    }

    inline fun borrow(collection_config_object: Object<CollectionConfig>): &CollectionConfig acquires CollectionConfig {
        borrow_global<CollectionConfig>(object::object_address(&collection_config_object))
    }

    inline fun borrow_metadata_config(collection_config_object: Object<CollectionConfig>): &MetadataConfig {
        let obj_addr = object::object_address(&collection_config_object);
        assert!(exists<MetadataConfig>(obj_addr), EMETADATA_CONFIG_DOES_NOT_EXIST);
        borrow_global<MetadataConfig>(obj_addr)
    }

    inline fun borrow_mut(
        collection_config_object: Object<CollectionConfig>
    ): &mut CollectionConfig acquires CollectionConfig {
        borrow_global_mut<CollectionConfig>(object::object_address(&collection_config_object))
    }

    fun get_weighted_pseudo_random_index(token_metadatas: &vector<TokenMetadata>, total_weight: u64): u64 {
        // Obtain a pseudo-random value using the transaction hash
        let txn_hash = transaction_context::get_transaction_hash();
        // Initialize the seed used to compute the pseudo-random index.
        // This seed is computed by aggregating bytes from the transaction hash.
        let seed = 0u64;
        let j = 0;

        // Iterate over the first 4 bytes of the transaction hash to generate a sufficiently random seed.
        // The loop uses a maximum of 4 bytes because larger sizes would not significantly increase randomness
        // and would complicate the calculation unnecessarily.
        while (j < 4 && j < vector::length(&txn_hash)) {
            let byte = (*vector::borrow(&txn_hash, j) as u64);
            // Shift the byte by its position times 8 bits. This distributes the randomness evenly across the seed.
            seed = seed + (byte << ((j * 8) as u8));
            j = j + 1;
        };
        let random_weight = seed % total_weight;

        // Iterate through each metadata's weight and accumulate until we surpass the random weight.
        // This loop guarantees that each token's chance of being selected is proportional to its weight.
        let cumulative_weight = 0u64;
        let index = 0;
        while (index < vector::length(token_metadatas)) {
            let weight = vector::borrow(token_metadatas, index).weight;
            cumulative_weight = cumulative_weight + weight;
            if (random_weight < cumulative_weight) {
                return index
            };
            index = index + 1;
        };
        // Fallback if no valid index is found, though it should not happen
        0
    }

    public fun create_token_metadatas_and_compute_total_weight(
        token_uris: vector<String>,
        token_uris_weights: vector<u64>
    ): (vector<TokenMetadata>, u64) {
        let token_metadatas: vector<TokenMetadata> = vector::empty();
        let total_weight = 0u64;

        let len = vector::length(&token_uris);
        assert!(len == vector::length(&token_uris_weights), ETOKEN_METADATA_MISMATCH);

        let i = 0;
        while (i < len) {
            let uri = *vector::borrow(&token_uris, i);
            let weight = *vector::borrow(&token_uris_weights, i);

            vector::push_back(&mut token_metadatas, TokenMetadata {
                uri,
                weight,
            });

            total_weight = total_weight + weight;
            i = i + 1;
        };

        (token_metadatas, total_weight)
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
    ): Object<Token> acquires CollectionConfig, MetadataConfig {
        mint_impl(minter, collection_config_object, recipient_addr)
    }
}
