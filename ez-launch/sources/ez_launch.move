/// This module provides a no-code solution for creating and managing collections of tokens.
/// It allows for the creation of pre-minted collections, where tokens are pre-minted to the collection address.
/// This no-code solution will work hand in hand with SDK support to provide a seamless experience for creators to create colletions.
/// The flow looks like:
/// 1. creators are prompted to prepare metadata files for each token and collection in csv file
/// 2. creators are prompted to upload these files to a decentralized storage
/// 3. creators are prompted to decide on below configurations
/// 4. collections created
/// 5. creators are prompted to pre-mint tokens to the collection
/// 6. creators are prompted to the question whether pre-minting has completed, if so, users can mint
/// Features it supports:
/// 1. random mint or sequential mint
/// 2. soulbound or transferrable
/// 3. mutable token and collection metadata
/// 4. optional mint fee payments minters pay
/// 5. configurable royalty
/// 6. max supply or unlimited supply collection
/// 7. whitelist - in future
module ez_launch::ez_launch {
    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string;
    use std::string::String;
    use std::vector;

    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::aptos_coin::AptosCoin;

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::royalty;
    use aptos_token_objects::royalty::Royalty;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

    use minter::coin_payment::{Self, CoinPayment};
    use minter::collection_components;
    use minter::collection_properties;
    use minter::token_components;
    use minter::transfer_token;
    
    /// The provided signer is not the collection owner during pre-minting.
    const ENOT_OWNER: u64 = 1;
    /// The provided collection does not have a EZLaunchConfig resource. Are you sure this Collection was created with ez_launch?
    const EEZ_LAUNCH_CONFIG_DOES_NOT_EXIST: u64 = 2;
    /// CollectionProperties resource does not exist in the object address.
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 3;
    /// Token Metadata configuration is invalid with different metadata length.
    const ETOKEN_METADATA_CONFIGURATION_INVALID: u64 = 4;
    /// Token Minting has not yet started.
    const EMINTING_HAS_NOT_STARTED_YET: u64 = 5;
    /// Tokens are all minted.
    const ETOKENS_ALL_MINTED: u64 = 6;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct EZLaunchConfig has key {
        extend_ref: object::ExtendRef, // creator owned object extend ref
        collection: Object<Collection>,
        coin_payments: vector<CoinPayment<AptosCoin>>,
        available_tokens: vector<Object<Token>>, // to be minted token
        random_mint: bool,
        is_soulbound: bool,
        ready_to_mint: bool,
    }

    // ================================= Entry Functions ================================= //

    public entry fun create_collection(
        creator: &signer,
        description: String,
        name: String,
        uri: String,
        mutable_collection_metadata: bool, // including description, uri, royalty, to make creator life easier
        mutable_token_metadata: bool, // including description, name, properties, uri, to make creator life easier
        random_mint: bool,
        is_soulbound: bool,
        tokens_burnable_by_collection_owner: bool,
        tokens_transferrable_by_collection_owner: bool,
        max_supply: Option<u64>,
        mint_fee: Option<u64>,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
    ) acquires EZLaunchConfig {
        create_collection_impl(
            creator,
            description,
            name,
            uri,
            mutable_collection_metadata,
            mutable_token_metadata,
            random_mint,
            is_soulbound,
            tokens_burnable_by_collection_owner,
            tokens_transferrable_by_collection_owner,
            max_supply,
            mint_fee,
            royalty_numerator,
            royalty_denominator,
        );
    }

    public entry fun pre_mint_tokens(
        creator: &signer,
        ez_launch_config_obj: Object<EZLaunchConfig>,
        token_name_vec: vector<String>, // not provided by creator, we could parse from metadata json file
        token_uri_vec: vector<String>, // not provided by creator, we could parse from metadata json file
        token_description_vec: vector<String>, // not provided by creator, we could parse from metadata json file
        num_tokens: u64,
    ) acquires EZLaunchConfig {
        pre_mint_tokens_impl(
            creator,
            ez_launch_config_obj,
            token_name_vec,
            token_uri_vec,
            token_description_vec,
            num_tokens,
        )
    }

    public entry fun mint(
        user: &signer,
        ez_launch_config_obj: Object<EZLaunchConfig>,
    ) acquires EZLaunchConfig {
        mint_impl(user, ez_launch_config_obj);
    }

    public entry fun set_minting_status(config_owner: &signer, ez_launch_config_obj: Object<EZLaunchConfig>, ready_to_mint: bool) acquires EZLaunchConfig {
        let ez_launch_config = authorized_borrow_mut(config_owner, ez_launch_config_obj);

        ez_launch_config.ready_to_mint = ready_to_mint;
    }

    // ================================= Helper  ================================= //

    public fun create_collection_impl(
        creator: &signer,
        description: String,
        name: String,
        uri: String,
        mutable_collection_metadata: bool,
        mutable_token_metadata: bool,
        random_mint: bool,
        is_soulbound: bool,
        tokens_burnable_by_collection_owner: bool,
        tokens_transferrable_by_collection_owner: bool,
        max_supply: Option<u64>,
        mint_fee: Option<u64>,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
    ): Object<EZLaunchConfig> acquires EZLaunchConfig {
        let creator_addr = signer::address_of(creator);
        let object_constructor_ref = &object::create_object(creator_addr);
        let object_signer = object::generate_signer(object_constructor_ref);

        let royalty = royalty(&mut royalty_numerator, &mut royalty_denominator, creator_addr);

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

        move_to(&object_signer, EZLaunchConfig {
            extend_ref: object::generate_extend_ref(object_constructor_ref),
            collection,
            available_tokens: vector[],
            coin_payments: vector[],
            random_mint,
            is_soulbound,
            ready_to_mint: false,
        });

        let object_addr = signer::address_of(&object_signer);
        let ez_launch_config_obj = object::address_to_object(object_addr);
        
        add_mint_fee(creator, &mut mint_fee, creator_addr, ez_launch_config_obj);

        // (jill) add whitelist

        ez_launch_config_obj
    }

    public fun pre_mint_tokens_impl(
        creator: &signer,
        ez_launch_config_obj: Object<EZLaunchConfig>,
        token_name_vec: vector<String>,
        token_uri_vec: vector<String>,
        token_description_vec: vector<String>,
        num_tokens: u64,
    ) acquires EZLaunchConfig {
        assert!(vector::length(&token_name_vec) == num_tokens, error::invalid_argument(ETOKEN_METADATA_CONFIGURATION_INVALID));
        assert!(vector::length(&token_uri_vec) == num_tokens, error::invalid_argument(ETOKEN_METADATA_CONFIGURATION_INVALID));
        assert!(vector::length(&token_description_vec) == num_tokens, error::invalid_argument(ETOKEN_METADATA_CONFIGURATION_INVALID));
        // not check against the ready_to_mint so that we enable creators to pre_mint anytime even when minting has already started

        let i = 0;
        let length = vector::length(&token_name_vec);
        while (i < length) {
            let token = pre_mint_token(
                creator,
                ez_launch_config_obj,
                *vector::borrow(&token_description_vec, i),
                *vector::borrow(&token_name_vec, i),
                *vector::borrow(&token_uri_vec, i),
            );
            vector::push_back(&mut borrow_mut(ez_launch_config_obj).available_tokens, token);
            i = i + 1;
        };
    }

    public fun pre_mint_token(
        creator: &signer,
        ez_launch_config_obj: Object<EZLaunchConfig>,
        description: String,
        name: String,
        uri: String,
    ): Object<Token> acquires EZLaunchConfig {
        let object_signer = authorized_ez_launch_config_signer(creator, ez_launch_config_obj);
        let collection = collection(ez_launch_config_obj);

        let constructor_ref = &token::create(
            &object_signer,
            collection::name(collection),
            description,
            name,
            royalty::get(collection),
            uri,
        );

        token_components::create_refs(constructor_ref);
        let ez_launch_config_address = object::object_address(&ez_launch_config_obj);
        transfer_token::transfer(&object_signer, ez_launch_config_address, constructor_ref);

        object::object_from_constructor_ref(constructor_ref)
    }
    
    public fun mint_impl(
        user: &signer,
        ez_launch_config_obj: Object<EZLaunchConfig>,
    ): Object<Token> acquires EZLaunchConfig {
        let object_signer = ez_launch_config_signer(ez_launch_config_obj);
        let borrowed_ez_launch_config = borrow(ez_launch_config_obj);

        let available_tokens = borrowed_ez_launch_config.available_tokens;
        let length = vector::length(&available_tokens);

        assert!(length > 0, error::permission_denied(ETOKENS_ALL_MINTED));
        assert!(borrowed_ez_launch_config.ready_to_mint, error::permission_denied(EMINTING_HAS_NOT_STARTED_YET));

        // (jill) check against whitelist

        execute_coin_payments(user, ez_launch_config_obj);
        let borrowed_ez_launch_config = borrow(ez_launch_config_obj);

        let token = if (borrowed_ez_launch_config.random_mint) {
            let random_index = timestamp::now_seconds() % length;
            vector::remove(&mut available_tokens, random_index)
        } else {
            vector::pop_back(&mut available_tokens)
        };
        object::transfer(&object_signer, token, signer::address_of(user));

        if (borrowed_ez_launch_config.is_soulbound) {
            token_components::freeze_transfer(&object_signer, token);
        };

        token
    }

    fun assert_owner<T: key>(owner: address, object: Object<T>) {
        assert!(object::owner(object) == owner, error::permission_denied(ENOT_OWNER));
    }

    fun authorized_ez_launch_config_signer(config_owner: &signer, ez_launch_config_obj: Object<EZLaunchConfig>): signer acquires EZLaunchConfig {
        let ez_launch_config = authorized_borrow(config_owner, ez_launch_config_obj);
        object::generate_signer_for_extending(&ez_launch_config.extend_ref)
    }

    fun ez_launch_config_signer(ez_launch_config_obj: Object<EZLaunchConfig>): signer acquires EZLaunchConfig {
        let ez_launch_config = borrow(ez_launch_config_obj);
        object::generate_signer_for_extending(&ez_launch_config.extend_ref)
    }

    fun add_mint_fee(
        creator: &signer,
        mint_fee: &mut Option<u64>,
        creator_addr: address,
        ez_launch_config_obj: Object<EZLaunchConfig>,
    ) acquires EZLaunchConfig {
        let ez_launch_config = borrow_mut(ez_launch_config_obj);
        if (option::is_some(mint_fee)) {
            let mint_fee_category = b"Mint Fee";
            let coin_payment = coin_payment::create<AptosCoin>(
                creator,
                option::extract(mint_fee),
                creator_addr,
                string::utf8(mint_fee_category),
            );
            vector::push_back(&mut ez_launch_config.coin_payments, coin_payment);
        };
    }

    fun execute_coin_payments(
        user: &signer,
        ez_launch_config_obj: Object<EZLaunchConfig>,
    ) acquires EZLaunchConfig {
        let ez_launch_config = borrow_mut(ez_launch_config_obj);
        vector::for_each_ref(&ez_launch_config.coin_payments, |coin_payment| {
            let coin_payment: &CoinPayment<AptosCoin> = coin_payment;
            coin_payment::execute(user, coin_payment);
        });
    }

    fun royalty(
        royalty_numerator: &mut Option<u64>, 
        royalty_denominator: &mut Option<u64>, 
        admin_addr: address,
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
        creator: &signer,
        collection: Object<Collection>,
        mutable_collection_metadata: bool,
        mutable_token_metadata: bool,
        tokens_burnable_by_collection_owner: bool,
        tokens_transferrable_by_collection_owner: bool,
    ) {
        collection_properties::set_mutable_description(creator, collection, mutable_collection_metadata);
        collection_properties::set_mutable_uri(creator, collection, mutable_collection_metadata);
        collection_properties::set_mutable_royalty(creator, collection, mutable_collection_metadata);
        collection_properties::set_mutable_token_name(creator, collection, mutable_token_metadata);
        collection_properties::set_mutable_token_properties(creator, collection, mutable_token_metadata);
        collection_properties::set_mutable_token_description(creator, collection, mutable_token_metadata);
        collection_properties::set_mutable_token_uri(creator, collection, mutable_token_metadata);
        collection_properties::set_tokens_transferable_by_collection_owner(creator, collection, tokens_transferrable_by_collection_owner);
        collection_properties::set_tokens_burnable_by_collection_owner(creator, collection, tokens_burnable_by_collection_owner);
    }

    fun collection(ez_launch_config_obj: Object<EZLaunchConfig>): Object<Collection> acquires EZLaunchConfig {
        borrow(ez_launch_config_obj).collection
    }

    inline fun authorized_borrow(config_owner: &signer, ez_launch_config_obj: Object<EZLaunchConfig>): &EZLaunchConfig {
        assert_owner(signer::address_of(config_owner), ez_launch_config_obj);
        borrow(ez_launch_config_obj)
    }

    inline fun authorized_borrow_mut(config_owner: &signer, ez_launch_config_obj: Object<EZLaunchConfig>): &mut EZLaunchConfig {
        assert_owner(signer::address_of(config_owner), ez_launch_config_obj);
        borrow_mut(ez_launch_config_obj)
    }

    inline fun borrow(ez_launch_config_obj: Object<EZLaunchConfig>): &EZLaunchConfig {
        let ez_launch_config_obj_address = object::object_address(&ez_launch_config_obj);
        assert!(
            exists<EZLaunchConfig>(ez_launch_config_obj_address),
            error::not_found(EEZ_LAUNCH_CONFIG_DOES_NOT_EXIST)
        );

        borrow_global<EZLaunchConfig>(ez_launch_config_obj_address)
    }

    inline fun borrow_mut(ez_launch_config_obj: Object<EZLaunchConfig>): &mut EZLaunchConfig acquires EZLaunchConfig {
        let ez_launch_config_obj_address = object::object_address(&ez_launch_config_obj);
        assert!(
            exists<EZLaunchConfig>(ez_launch_config_obj_address),
            error::not_found(EEZ_LAUNCH_CONFIG_DOES_NOT_EXIST)
        );

        borrow_global_mut<EZLaunchConfig>(ez_launch_config_obj_address)
    }
           
    // ================================= View  ================================= //

    #[view]
    public fun minting_ended(ez_launch_config_obj: Object<EZLaunchConfig>): bool acquires EZLaunchConfig {
        vector::length(&borrow(ez_launch_config_obj).available_tokens) == 0
    }

    #[view]
    public fun authorized_collection(config_owner: &signer, ez_launch_config_obj: Object<EZLaunchConfig>): Object<Collection> acquires EZLaunchConfig {
        authorized_borrow(config_owner, ez_launch_config_obj).collection
    }
}