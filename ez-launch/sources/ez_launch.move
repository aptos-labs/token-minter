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
    /// The provided collection does not have a CollectionDetails resource. Are you sure this Collection was created with ez_launch?
    const ECOLLECTION_DETAILS_DOES_NOT_EXIST: u64 = 2;
    /// CollectionProperties resource does not exist in the object address.
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 3;
    /// The provided collection does not have a EZLaunchRefs resource. Are you sure this Collection was created with ez_launch?
    const EEZ_LAUNCH_REFS_DOES_NOT_EXIST: u64 = 4;
    /// Royalty configuration is invalid because either numerator and denominator should be none or not none.
    const EROYALTY_CONFIGURATION_INVALID: u64 = 5;
    /// Token Metadata configuration is invalid with different metadata length.
    const ETOKEN_METADATA_CONFIGURATION_INVALID: u64 = 6;
    /// Token Minting has not yet started.
    const EMINTING_HAS_NOT_STARTED_YET: u64 = 7;
    /// Tokens are all minted.
    const ETOKENS_ALL_MINTED: u64 = 8;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionDetails has key {
        coin_payments: vector<CoinPayment<AptosCoin>>,
        available_tokens: vector<Object<Token>>, // to be minted token
        random_mint: bool,
        is_soulbound: bool,
        ready_to_mint: bool,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct EZLaunchRefs has key {
        extend_ref: object::ExtendRef,
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
    ) acquires CollectionDetails {
        create_collection_helper(
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
        collection: Object<Collection>,
        token_name_vec: vector<String>, // not provided by creator, we could parse from metadata json file
        token_uri_vec: vector<String>, // not provided by creator, we could parse from metadata json file
        token_description_vec: vector<String>, // not provided by creator, we could parse from metadata json file
        num_tokens: u64,
    ) acquires CollectionDetails, EZLaunchRefs {
        pre_mint_tokens_helper(
            creator,
            collection,
            token_name_vec,
            token_uri_vec,
            token_description_vec,
            num_tokens,
        )
    }

    public entry fun mint(
        user: &signer,
        collection: Object<Collection>,
    ) acquires CollectionDetails, EZLaunchRefs {
        mint_helper(user, collection);
    }

    public entry fun set_minting_status(creator: &signer, collection: Object<Collection>, ready_to_mint: bool) acquires CollectionDetails, EZLaunchRefs {
        assert_owner(signer::address_of(creator), collection);
        let object_signer = authorized_collection_signer(creator, collection);
        let object_signer_address = signer::address_of(&object_signer);
        let collection_details_obj = borrow_global_mut<CollectionDetails>(object_signer_address);

        collection_details_obj.ready_to_mint = ready_to_mint;
    }

    // ================================= Helper  ================================= //

    public fun create_collection_helper(
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
    ): Object<Collection> acquires CollectionDetails {
        let creator_addr = signer::address_of(creator);

        let royalty = royalty(&mut royalty_numerator, &mut royalty_denominator, creator_addr);

        let constructor_ref = if (option::is_some(&max_supply)) {
            collection::create_fixed_collection(
                creator,
                description,
                option::extract(&mut max_supply),
                name,
                royalty,
                uri,
            )
        } else {
            collection::create_unlimited_collection(
                creator,
                description,
                name,
                royalty,
                uri,
            )
        };

        collection_components::create_refs_and_properties(&constructor_ref);
        let collection = object::object_from_constructor_ref(&constructor_ref);
        configure_collection_and_token_properties(
            creator,
            collection,
            mutable_collection_metadata,
            mutable_token_metadata,
            tokens_burnable_by_collection_owner,
            tokens_transferrable_by_collection_owner,
        );

        let object_signer = object::generate_signer(&constructor_ref);

        move_to(&object_signer, CollectionDetails {
            available_tokens: vector[],
            coin_payments: vector[],
            random_mint,
            is_soulbound,
            ready_to_mint: false,
        });

        let object_addr = signer::address_of(&object_signer);
        let collection_details = borrow_global_mut<CollectionDetails>(object_addr);
        
        add_mint_fee(&mut mint_fee, creator_addr, collection_details);

        // (jill) add whitelist

        move_to(&object_signer, EZLaunchRefs {
            extend_ref: object::generate_extend_ref(&constructor_ref),
        });

        collection
    }

    public fun pre_mint_tokens_helper(
        creator: &signer,
        collection: Object<Collection>,
        token_name_vec: vector<String>,
        token_uri_vec: vector<String>,
        token_description_vec: vector<String>,
        num_tokens: u64,
    ) acquires CollectionDetails, EZLaunchRefs {
        assert_owner(signer::address_of(creator), collection);
        assert!(vector::length(&token_name_vec) == num_tokens, error::invalid_argument(ETOKEN_METADATA_CONFIGURATION_INVALID));
        assert!(vector::length(&token_uri_vec) == num_tokens, error::invalid_argument(ETOKEN_METADATA_CONFIGURATION_INVALID));
        assert!(vector::length(&token_description_vec) == num_tokens, error::invalid_argument(ETOKEN_METADATA_CONFIGURATION_INVALID));

        let object_signer = authorized_collection_signer(creator, collection);
        let object_signer_address = signer::address_of(&object_signer);
        let collection_details_obj = borrow_global_mut<CollectionDetails>(object_signer_address);
        // not check against the ready_to_mint so that we enable creators to pre_mint anytime even when minting has already started

        let i = 0;
        let length = vector::length(&token_name_vec);
        while (i < length) {
            let token = pre_mint_token(
                creator,
                collection,
                *vector::borrow(&token_description_vec, i),
                *vector::borrow(&token_name_vec, i),
                *vector::borrow(&token_uri_vec, i),
            );
            vector::push_back(&mut collection_details_obj.available_tokens, token);
            i = i + 1;
        };
    }

    public fun pre_mint_token(
        creator: &signer,
        collection: Object<Collection>,
        description: String,
        name: String,
        uri: String,
    ): Object<Token> {
        assert_owner(signer::address_of(creator), collection);
        let constructor_ref = &token::create(
            creator,
            collection::name(collection),
            description,
            name,
            royalty::get(collection),
            uri,
        );

        token_components::create_refs(constructor_ref);
        let collection_address = object::object_address(&collection);
        transfer_token::transfer(creator, collection_address, constructor_ref);

        object::object_from_constructor_ref(constructor_ref)
    }
    
    public fun mint_helper(
        user: &signer,
        collection: Object<Collection>,
    ): Object<Token> acquires CollectionDetails, EZLaunchRefs {
        let object_signer = collection_signer(collection);
        let object_signer_address = signer::address_of(&object_signer);
        assert!(exists<CollectionDetails>(object_signer_address), error::invalid_state(ECOLLECTION_DETAILS_DOES_NOT_EXIST));

        let collection_details_obj = borrow_global_mut<CollectionDetails>(object_signer_address);
        let available_tokens = collection_details_obj.available_tokens;
        let length = vector::length(&available_tokens);

        assert!(length > 0, error::permission_denied(ETOKENS_ALL_MINTED));
        assert!(collection_details_obj.ready_to_mint, error::permission_denied(EMINTING_HAS_NOT_STARTED_YET));

        // (jill) check against whitelist

        execute_coin_payments(user, collection_details_obj);

        let token_index = if (collection_details_obj.random_mint) {
            timestamp::now_seconds() % length
        } else {
            length - 1
        };
        let token = *vector::borrow(&available_tokens, token_index);
        let user_address = signer::address_of(user);
        object::transfer(&object_signer, token, user_address);
        vector::pop_back(&mut available_tokens);

        if (collection_details_obj.is_soulbound) {
            token_components::freeze_transfer(&object_signer, token);
        };

        token
    }

    fun assert_owner<T: key>(owner: address, object: Object<T>) {
        assert!(object::owner(object) == owner, error::permission_denied(ENOT_OWNER));
    }

    fun authorized_collection_signer(creator: &signer, collection: Object<Collection>): signer acquires EZLaunchRefs {
        let refs = authorized_borrow(creator, collection);
        object::generate_signer_for_extending(&refs.extend_ref)
    }

    fun collection_signer(collection: Object<Collection>): signer acquires EZLaunchRefs {
        let refs = borrow(collection);
        object::generate_signer_for_extending(&refs.extend_ref)
    }

    fun add_mint_fee(
        mint_fee: &mut Option<u64>,
        creator_addr: address,
        collection_details: &mut CollectionDetails,
    ) {
        if (option::is_some(mint_fee)) {
            let mint_fee_category = b"Mint Fee";
            let coin_payment = coin_payment::create<AptosCoin>(
                option::extract(mint_fee),
                creator_addr,
                string::utf8(mint_fee_category),
            );
            vector::push_back(&mut collection_details.coin_payments, coin_payment);
        };
    }

    fun execute_coin_payments(
        user: &signer,
        collection_details: &mut CollectionDetails,
    ) {
        vector::for_each_ref(&collection_details.coin_payments, |coin_payment| {
            let coin_payment: &CoinPayment<AptosCoin> = coin_payment;
            coin_payment::execute(user, coin_payment);
        });
    }

    fun royalty(
        royalty_numerator: &mut Option<u64>, 
        royalty_denominator: &mut Option<u64>, 
        creator_addr: address
    ): Option<Royalty> {
        assert!(option::is_some(royalty_numerator) == option::is_some(royalty_denominator), error::invalid_argument(EROYALTY_CONFIGURATION_INVALID));
        if (option::is_some(royalty_numerator) && option::is_some(royalty_denominator) && option::extract(royalty_numerator) != 0 && option::extract(royalty_denominator) != 0) {
            option::some(royalty::create(option::extract(royalty_numerator), option::extract(royalty_denominator), creator_addr))
        } else {
            option::none()
        }
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

    inline fun authorized_borrow(creator: &signer, collection: Object<Collection>): &EZLaunchRefs acquires EZLaunchRefs {
        assert_owner(signer::address_of(creator), collection);
        borrow(collection)
    }

    inline fun borrow(collection: Object<Collection>): &EZLaunchRefs acquires EZLaunchRefs {
        let collection_address = object::object_address(&collection);
        assert!(
            exists<EZLaunchRefs>(collection_address),
            error::not_found(EEZ_LAUNCH_REFS_DOES_NOT_EXIST)
        );

        borrow_global<EZLaunchRefs>(collection_address)
    }
           
    // ================================= View  ================================= //

    #[view]
    public fun minting_ended(collection: Object<Collection>): bool acquires CollectionDetails, EZLaunchRefs {
        let object_signer = collection_signer(collection);
        let object_signer_address = signer::address_of(&object_signer);
        let collection_details_obj = borrow_global_mut<CollectionDetails>(object_signer_address);

        vector::length(&collection_details_obj.available_tokens) == 0
    }
}