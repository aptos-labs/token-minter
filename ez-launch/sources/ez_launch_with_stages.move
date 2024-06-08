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
/// 7. mint stages and allowlists
module ez_launch::ez_launch_with_stages {
    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_std::simple_map;
    use aptos_std::simple_map::SimpleMap;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::timestamp;

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::royalty;
    use aptos_token_objects::royalty::Royalty;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;
    use minter::coin_payment::{Self, CoinPayment};
    use minter::collection_components;
    use minter::collection_properties;
    use minter::mint_stage;
    use minter::token_components;

    /// The provided signer is not the collection owner during pre-minting.
    const ENOT_OWNER: u64 = 1;
    /// The provided collection does not have a EZLaunchConfig resource. Are you sure this Collection was created with ez_launch?
    const ECONFIG_DOES_NOT_EXIST: u64 = 2;
    /// CollectionProperties resource does not exist in the object address.
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 3;
    /// Token Metadata configuration is invalid with different metadata length.
    const ETOKEN_METADATA_CONFIGURATION_INVALID: u64 = 4;
    /// Token Minting has not yet started.
    const EMINTING_HAS_NOT_STARTED_YET: u64 = 5;
    /// Tokens are all minted.
    const ETOKENS_ALL_MINTED: u64 = 6;
    /// Mint fee category is required when mint fee is provided.
    const EMINT_FEE_CATEGORY_REQUIRED: u64 = 7;
    /// The provided arguments are invalid
    const EINVALID_ARGUMENTS: u64 = 8;
    /// No active mint stages.
    const ENO_ACTIVE_STAGES: u64 = 9;

    const PRESALE_MINT_STAGE_CATEGORY: vector<u8> = b"Presale mint stage";
    const PUBLIC_SALE_MINT_STAGE_CATEGORY: vector<u8> = b"Public sale mint stage";
    const PRESALE_COIN_PAYMENT_CATEGORY: vector<u8> = b"Presale mint fee";
    const PUBLIC_SALE_COIN_PAYMENT_CATEGORY: vector<u8> = b"Public sale mint fee";

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct EZLaunchConfig has key {
        extend_ref: object::ExtendRef,
        collection: Object<Collection>,
        fees: SimpleMap<String, vector<CoinPayment<AptosCoin>>>,
        available_tokens: vector<Object<Token>>,
        random_mint: bool,
        is_soulbound: bool,
        ready_to_mint: bool,
    }

    // ================================= Entry Functions ================================= //

    public entry fun create_collection(
        owner: &signer,
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
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
    ) {
        create_collection_impl(
            owner, description, name, uri, mutable_collection_metadata, mutable_token_metadata,
            random_mint, is_soulbound, tokens_burnable_by_collection_owner, tokens_transferrable_by_collection_owner,
            max_supply, royalty_numerator, royalty_denominator,
        );
    }

    public entry fun pre_mint_tokens(
        owner: &signer,
        config: Object<EZLaunchConfig>,
        token_names: vector<String>, // not provided by creator, we could parse from metadata json file
        token_uris: vector<String>, // not provided by creator, we could parse from metadata json file
        token_descriptions: vector<String>, // not provided by creator, we could parse from metadata json file
        num_tokens: u64,
    ) acquires EZLaunchConfig {
        pre_mint_tokens_impl(owner, config, token_names, token_uris, token_descriptions, num_tokens)
    }

    public entry fun mint(minter: &signer, config: Object<EZLaunchConfig>, amount: u64) acquires EZLaunchConfig {
        mint_impl(minter, config, amount);
    }

    // ================================= Helpers ================================= //

    public fun create_collection_impl(
        owner: &signer,
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
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
    ): Object<EZLaunchConfig> {
        let creator_addr = signer::address_of(owner);
        let object_constructor_ref = &object::create_object(creator_addr);
        let object_signer = &object::generate_signer(object_constructor_ref);
        let royalty = royalty(&mut royalty_numerator, &mut royalty_denominator, creator_addr);

        let collection = create_collection_and_refs(
            object_signer,
            description,
            name,
            uri,
            max_supply,
            royalty,
        );

        configure_collection_and_token_properties(
            object_signer,
            collection,
            mutable_collection_metadata,
            mutable_token_metadata,
            tokens_burnable_by_collection_owner,
            tokens_transferrable_by_collection_owner,
        );

        move_to(object_signer, EZLaunchConfig {
            extend_ref: object::generate_extend_ref(object_constructor_ref),
            collection,
            available_tokens: vector[],
            fees: simple_map::new(),
            random_mint,
            is_soulbound,
            ready_to_mint: false,
        });

        object::object_from_constructor_ref(object_constructor_ref)
    }

    /// Add a mint stage to the launch configuration.
    /// `no_allowlist_max_mint` is the maximum number of tokens that can be minted in this stage without an allowlist.
    public entry fun add_stage(
        owner: &signer,
        config: Object<EZLaunchConfig>,
        stage_category: String,
        start_time: u64,
        end_time: u64,
    ) acquires EZLaunchConfig {
        let ez_launch_signer = &authorized_config_signer(owner, config);
        let collection_signer = &collection_components::collection_object_signer(ez_launch_signer, borrow(config).collection);
        mint_stage::create(collection_signer, stage_category, start_time, end_time);
    }

    /// Add mint fee for a mint stage. Stage should be the same as the mint stage.
    public entry fun add_fee(
        owner: &signer,
        config: Object<EZLaunchConfig>,
        mint_fee: u64,
        destination: address,
        stage: String,
    ) acquires EZLaunchConfig {
        let config = authorized_borrow_mut(owner, config);
        let fee = coin_payment::create<AptosCoin>(mint_fee, destination, stage);
        if (simple_map::contains_key(&config.fees, &stage)) {
            let fees = simple_map::borrow_mut(&mut config.fees, &stage);
            vector::push_back(fees, fee);
        } else {
            simple_map::add(&mut config.fees, stage, vector[fee]);
        };
    }

    /// If this function is called, `no_allowlist_max_mint` will be ignored as an allowlist exists.
    public entry fun add_to_allowlist(
        owner: &signer,
        config: Object<EZLaunchConfig>,
        stage_index: u64,
        addrs: vector<address>,
        amounts: vector<u64>,
    ) acquires EZLaunchConfig {
        let addrs_length = vector::length(&addrs);
        assert!(addrs_length == vector::length(&amounts), EINVALID_ARGUMENTS);

        let ez_launch_signer = &authorized_config_signer(owner, config);
        for (i in 0..addrs_length) {
            let addr = *vector::borrow(&addrs, i);
            let amount = *vector::borrow(&amounts, i);
            mint_stage::add_to_allowlist(ez_launch_signer, borrow(config).collection, stage_index, addr, amount);
        };
    }

    public entry fun remove_from_allowlist(
        owner: &signer,
        config: Object<EZLaunchConfig>,
        stage_index: u64,
        addrs: vector<address>,
    ) acquires EZLaunchConfig {
        let ez_launch_signer = &authorized_config_signer(owner, config);
        for (i in 0..vector::length(&addrs)) {
            let addr = *vector::borrow(&addrs, i);
            mint_stage::remove_from_allowlist(ez_launch_signer, borrow(config).collection, stage_index, addr);
        };
    }

    public entry fun repopulate_allowlist(
        owner: &signer,
        config: Object<EZLaunchConfig>,
        stage_index: u64,
        addrs: vector<address>,
        amounts: vector<u64>,
    ) acquires EZLaunchConfig {
        let addrs_length = vector::length(&addrs);
        assert!(addrs_length == vector::length(&amounts), EINVALID_ARGUMENTS);

        let ez_launch_signer = &authorized_config_signer(owner, config);
        mint_stage::clear_allowlist(ez_launch_signer, borrow(config).collection, stage_index);

        for (i in 0..addrs_length) {
            let addr = *vector::borrow(&addrs, i);
            let amount = *vector::borrow(&amounts, i);
            mint_stage::add_to_allowlist(ez_launch_signer, borrow(config).collection, stage_index, addr, amount);
        };
    }

    public entry fun set_public_stage_max_per_user(
        owner: &signer,
        config: Object<EZLaunchConfig>,
        stage_index: u64,
        max_per_user: u64,
    ) acquires EZLaunchConfig {
        let ez_launch_signer = &authorized_config_signer(owner, config);
        mint_stage::set_public_stage_max_per_user(ez_launch_signer, borrow(config).collection, stage_index, max_per_user);
    }

    public fun pre_mint_tokens_impl(
        owner: &signer,
        config: Object<EZLaunchConfig>,
        token_names: vector<String>,
        token_uris: vector<String>,
        token_descriptions: vector<String>,
        num_tokens: u64,
    ) acquires EZLaunchConfig {
        assert!(
            vector::length(&token_names) == num_tokens,
            error::invalid_argument(ETOKEN_METADATA_CONFIGURATION_INVALID)
        );
        assert!(
            vector::length(&token_uris) == num_tokens,
            error::invalid_argument(ETOKEN_METADATA_CONFIGURATION_INVALID)
        );
        assert!(
            vector::length(&token_descriptions) == num_tokens,
            error::invalid_argument(ETOKEN_METADATA_CONFIGURATION_INVALID)
        );

        let i = 0;
        let length = vector::length(&token_names);
        while (i < length) {
            let token = pre_mint_token(
                owner,
                config,
                *vector::borrow(&token_descriptions, i),
                *vector::borrow(&token_names, i),
                *vector::borrow(&token_uris, i),
            );
            vector::push_back(&mut borrow_mut(config).available_tokens, token);
            i = i + 1;
        };
    }

    fun pre_mint_token(
        creator: &signer,
        config: Object<EZLaunchConfig>,
        description: String,
        name: String,
        uri: String,
    ): Object<Token> acquires EZLaunchConfig {
        let object_signer = &authorized_config_signer(creator, config);
        let collection = borrow(config).collection;
        let config_address = object::object_address(&config);

        let constructor_ref = &token::create(
            object_signer,
            collection::name(collection),
            description,
            name,
            royalty::get(collection),
            uri,
        );
        token_components::create_refs(constructor_ref);

        let token = object::object_from_constructor_ref(constructor_ref);
        object::transfer(object_signer, token, config_address);

        token
    }

    /// Minter calls this function to mint the `amount` of tokens.
    /// This function validates that an active mint stage exists. The earliest stage is executed.
    /// If the stage has an allowlist, the minter must be on the allowlist.
    /// If the stage has a mint fee, the minter must pay the fee prior to minting.
    public fun mint_impl(
        minter: &signer,
        config_obj: Object<EZLaunchConfig>,
        amount: u64
    ): Object<Token> acquires EZLaunchConfig {
        let object_signer = config_signer(config_obj);
        let config = borrow(config_obj);
        let available_tokens = config.available_tokens;
        let length = vector::length(&available_tokens);
        assert!(length > 0, error::permission_denied(ETOKENS_ALL_MINTED));

        // Check mint stages configured, in this example, we execute the earliest stage.
        let stage_index = &mint_stage::execute_earliest_stage(minter, config.collection, amount);
        assert!(option::is_some(stage_index), ENO_ACTIVE_STAGES);

        // After stage has been executed, take fee payments from `minter` prior to minting.
        let mint_stage = mint_stage::find_mint_stage_by_index(config.collection, *option::borrow(stage_index));
        execute_payment(minter, &config.fees, &mint_stage::mint_stage_name(mint_stage));

        let token = if (config.random_mint) {
            let random_index = timestamp::now_seconds() % length;
            vector::remove(&mut available_tokens, random_index)
        } else {
            vector::pop_back(&mut available_tokens)
        };
        object::transfer(&object_signer, token, signer::address_of(minter));

        if (config.is_soulbound) {
            token_components::freeze_transfer(&object_signer, token);
        };

        token
    }

    fun authorized_config_signer(
        config_owner: &signer,
        config: Object<EZLaunchConfig>
    ): signer acquires EZLaunchConfig {
        let config = authorized_borrow(config_owner, config);
        object::generate_signer_for_extending(&config.extend_ref)
    }

    /// Unauthorized signer, to be used for on demand minting
    fun config_signer(config: Object<EZLaunchConfig>): signer acquires EZLaunchConfig {
        let config = borrow(config);
        object::generate_signer_for_extending(&config.extend_ref)
    }

    fun execute_payment(
        minter: &signer,
        fees: &SimpleMap<String, vector<CoinPayment<AptosCoin>>>,
        stage: &String,
    ) {
        let fees = simple_map::borrow(fees, stage);
        vector::for_each_ref(fees, |fee| {
            coin_payment::execute(minter, fee)
        });
    }

    fun create_collection_and_refs(
        object_signer: &signer,
        description: String,
        name: String,
        uri: String,
        max_supply: Option<u64>,
        royalty: Option<Royalty>,
    ): Object<Collection> {
        let constructor_ref = if (option::is_some(&max_supply)) {
            collection::create_fixed_collection(
                object_signer,
                description,
                option::extract(&mut max_supply),
                name,
                royalty,
                uri,
            )
        } else {
            collection::create_unlimited_collection(
                object_signer,
                description,
                name,
                royalty,
                uri,
            )
        };
        collection_components::create_refs_and_properties(&constructor_ref);
        object::object_from_constructor_ref(&constructor_ref)
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
        collection_properties::set_tokens_transferable_by_collection_owner(
            creator,
            collection,
            tokens_transferrable_by_collection_owner
        );
        collection_properties::set_tokens_burnable_by_collection_owner(
            creator,
            collection,
            tokens_burnable_by_collection_owner
        );
    }

    inline fun assert_owner<T: key>(owner: address, object: Object<T>) {
        assert!(object::owner(object) == owner, error::permission_denied(ENOT_OWNER));
    }

    inline fun authorized_borrow(config_owner: &signer, config: Object<EZLaunchConfig>): &EZLaunchConfig {
        assert_owner(signer::address_of(config_owner), config);
        borrow(config)
    }

    inline fun authorized_borrow_mut(config_owner: &signer, config: Object<EZLaunchConfig>): &mut EZLaunchConfig {
        assert_owner(signer::address_of(config_owner), config);
        borrow_mut(config)
    }

    inline fun borrow(config: Object<EZLaunchConfig>): &EZLaunchConfig {
        freeze(borrow_mut(config))
    }

    inline fun borrow_mut(config: Object<EZLaunchConfig>): &mut EZLaunchConfig acquires EZLaunchConfig {
        let config_address = object::object_address(&config);
        assert!(
            exists<EZLaunchConfig>(config_address),
            error::not_found(ECONFIG_DOES_NOT_EXIST)
        );
        borrow_global_mut<EZLaunchConfig>(config_address)
    }

    // ================================= View  ================================= //

    #[view]
    public fun minting_ended(config: Object<EZLaunchConfig>): bool acquires EZLaunchConfig {
        vector::length(&borrow(config).available_tokens) == 0
    }

    #[view]
    public fun collection(config: Object<EZLaunchConfig>): Object<Collection> acquires EZLaunchConfig {
        borrow(config).collection
    }

    public fun authorized_collection(
        config_owner: &signer,
        config: Object<EZLaunchConfig>
    ): Object<Collection> acquires EZLaunchConfig {
        authorized_borrow(config_owner, config).collection
    }
}
