/// This module provides a no-code solution for creating and managing collections of tokens.
/// It allows for the creation of pre-minted collections, where tokens are pre-minted to the collection address.
/// This no-code solution will work hand in hand with SDK support to provide a seamless experience for creators to create colletions.
/// The flow looks like:
/// 1. creators are prompted to prepare metadata files for each token and collection in csv file
/// 2. creators are prompted to upload these files to a decentralized storage
/// 3. creators are prompted to decide on below configurations
/// 4. collections created
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
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;
    use minter::coin_payment::{Self, CoinPayment};
    use minter::collection_components;
    use minter::token_components;
    use minter::transfer_token;

    const ENOT_OWNER: u64 = 1;
    const ECOLLECTION_DETAILS_DOES_NOT_EXIST: u64 = 2;
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 3;
    const ETOKEN_REFS_DOES_NOT_EXIST: u64 = 4;
    const ETOKEN_TRANSFER_REFS_DOES_NOT_EXIST: u64 = 5;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionDetails has key {
        coin_payments: vector<CoinPayment<AptosCoin>>,
        to_be_minted_vec: vector<address>, // to be minted token addr
        random_mint: bool,
        is_soulbound: bool,
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
        mutable_collection_metadata: bool, // including description, uri, royalty, to make creator life easier lol
        mutable_token_metadata: bool, // including description, name, properties, uri, to make creator life easier lol
        random_mint: bool,
        is_soulbound: bool,
        token_name_vec: vector<String>, // not provided by creator, we could parse from metadata json file, this vec need to be ordered if order is enforced
        token_uri_vec: vector<String>, // not provided by creator, we could parse from metadata json file
        token_description_vec: vector<String>, // not provided by creator, we could parse from metadata json file
        max_supply: Option<u64>,
        mint_fee: Option<u64>,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
    ) acquires CollectionDetails {
        create_pre_minted_collection_helper(
            creator,
            description,
            name,
            uri,
            mutable_collection_metadata,
            mutable_token_metadata,
            random_mint,
            is_soulbound,
            token_name_vec,
            token_uri_vec,
            token_description_vec,
            max_supply,
            mint_fee,
            royalty_numerator,
            royalty_denominator,
        );
    }

    public entry fun mint(
        user: &signer,
        collection: Object<Collection>,
    ) acquires EZLaunchRefs, CollectionDetails {
        mint_helper(user, collection);
    }

    // ================================= Helper  ================================= //

    public fun create_pre_minted_collection_helper(
        creator: &signer,
        description: String,
        name: String,
        uri: String,
        mutable_collection_metadata: bool,
        mutable_token_metadata: bool,
        random_mint: bool,
        is_soulbound: bool,
        token_name_vec: vector<String>,
        token_uri_vec: vector<String>,
        token_description_vec: vector<String>,
        max_supply: Option<u64>,
        mint_fee: Option<u64>,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
    ): Object<Collection> acquires CollectionDetails {
        let creator_addr = signer::address_of(creator);

        let royalty = if (option::is_some(&royalty_numerator) && option::is_some(&royalty_denominator)) {
            option::some(royalty::create(option::extract(&mut royalty_numerator), option::extract(&mut royalty_denominator), creator_addr))
        } else {
            option::none()
        };
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

        collection_components::create_refs(
            &constructor_ref,
            mutable_collection_metadata, // mutable_description
            mutable_collection_metadata, // mutable_uri
            mutable_collection_metadata, // mutable_royalty
        );

        let collection_properties = collection_components::create_properties(
            mutable_collection_metadata, // mutable_description
            mutable_collection_metadata, // mutable_uri
            mutable_token_metadata, // mutable_token_description
            mutable_token_metadata, // mutable_token_name
            mutable_token_metadata, // mutable_token_properties
            mutable_token_metadata, // mutable_token_uri
            mutable_collection_metadata, // mutable_royalty
            true, // tokens_burnable_by_creator, just in case creator makes a mistake in minting?
            true, // tokens_transferable_by_creator, so that we could pre mint to creator and then transfer to user as user mint
        );
        collection_components::init_collection_properties(&constructor_ref, collection_properties);

        let object_signer = object::generate_signer(&constructor_ref);

        move_to(&object_signer, CollectionDetails {
            to_be_minted_vec: vector[],
            coin_payments: vector[],
            random_mint,
            is_soulbound,
        });

        let object_addr = signer::address_of(&object_signer);
        let collection_details = borrow_global_mut<CollectionDetails>(object_addr);
        
        if (option::is_some(&mint_fee)) {
            let mint_fee_category = b"Mint Fee";
            let coin_payment = coin_payment::create<AptosCoin>(option::extract(&mut mint_fee), creator_addr, string::utf8(mint_fee_category));
            vector::push_back(&mut collection_details.coin_payments, coin_payment);
        };

        let length = vector::length(&token_name_vec);
        let i = 0;
        let collection = object::object_from_constructor_ref(&constructor_ref);
        let collection_address = object::object_address<Collection>(&collection);

        move_to(&object_signer, EZLaunchRefs { extend_ref: object::generate_extend_ref(&constructor_ref) });

        // pre mint all the tokens to the collection address
        while (i < length) {
            let token = pre_mint_helper(
                creator,
                collection,
                *vector::borrow(&token_description_vec, i),
                *vector::borrow(&token_name_vec, i),
                *vector::borrow(&token_uri_vec, i),
                collection_address,
            );
            vector::push_back(&mut collection_details.to_be_minted_vec, object::object_address<Token>(&token));
            i = i + 1;
        };

        // (jill) add whitelist

        collection
    }
    
    public fun mint_helper(
        user: &signer,
        collection: Object<Collection>,
    ): Object<Token> acquires EZLaunchRefs, CollectionDetails {
        let object_signer = object_signer(collection);
        let object_signer_address = signer::address_of(&object_signer);

        // (jill) check against whitelist

        assert!(exists<CollectionDetails>(object_signer_address), error::invalid_state(ECOLLECTION_DETAILS_DOES_NOT_EXIST));
        let collection_details_obj = borrow_global_mut<CollectionDetails>(object_signer_address);
        vector::for_each_ref(&collection_details_obj.coin_payments, |coin_payment| {
            let coin_payment: &CoinPayment<AptosCoin> = coin_payment;
            coin_payment::execute(user, coin_payment);
        });

        let index = if (collection_details_obj.random_mint) {
            timestamp::now_seconds() % vector::length<address>(&collection_details_obj.to_be_minted_vec)
        } else {
            0
        };
        let token_address = *vector::borrow<address>(&collection_details_obj.to_be_minted_vec, index);
        let token = object::address_to_object<Token>(token_address);
        let user_address = signer::address_of(user);
        object::transfer(&object_signer, token, user_address);

        if (collection_details_obj.is_soulbound) {
            assert!(token_components::contains_token_refs(token_address), ETOKEN_REFS_DOES_NOT_EXIST);
            token_components::disable_ungated_transfer<Token>(&object_signer, token);
        };

        token
    }

    public fun pre_mint_helper(
        creator: &signer,
        collection: Object<Collection>,
        description: String,
        name: String,
        uri: String,
        recipient_addr: address,
    ): Object<Token> {
        assert_owner<Collection>(signer::address_of(creator), collection);
        let constructor_ref = &token::create(
            creator,
            collection::name(collection),
            description,
            name,
            royalty::get(collection),
            uri,
        );

        token_components::create_refs_and_properties(constructor_ref, collection);
        transfer_token::transfer(creator, recipient_addr, constructor_ref);

        object::object_from_constructor_ref(constructor_ref)
    }

    fun object_signer(collection: Object<Collection>): signer acquires EZLaunchRefs {
        let collection_address = object::object_address<Collection>(&collection);
        let refs = borrow_global<EZLaunchRefs>(collection_address);
        object::generate_signer_for_extending(&refs.extend_ref)
    }

    fun assert_owner<T: key>(owner: address, object: Object<T>) {
        assert!(object::owner(object) == owner, error::invalid_argument(ENOT_OWNER));
    }
}
