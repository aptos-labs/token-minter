module ez_launch::ez_launch {
    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string;
    use std::string::String;
    use aptos_framework::object::{Self, Object};
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::royalty;
    use aptos_token_objects::token;
    use minter::coin_payment::{Self, CoinPayment};
    use minter::collection_properties;
    use minter::collection_refs;
    use minter::token_refs;
    use minter::transfer_token;

    const ENOT_CREATOR: u64 = 1;
    const ECOLLECTION_DETAILS_DOES_NOT_EXIST: u64 = 2;
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 3;

    // - off-chain storage
    //     upload folder: `manifest_id/x.json` / `manifest_id/x.png`
    //     - x.json
    //     - x.png
    // 
    // options:
    //     - soulbound
    //     - mutable metadata
    //     - coin payments: pay mint fee
    //     - whitelists: before and after mint starts
    //     - on-chain property maps
    //     - user vs creator mint
    // 

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionDetails has key {
        creator_mint_only: bool,
        coin_payment: Option<CoinPayment<AptosCoin>>,
        token_uri_map: SmartTable<String, String>, // token name - token uri
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct EZLaunchRefs has key {
        extend_ref: object::ExtendRef,
    }

    public entry fun create_collection(
        creator: &signer,
        description: String,
        max_supply: Option<u64>,
        name: String,
        uri: String,
        mutable_collection_metadata: bool, // including description, uri, royalty
        mutable_token_metadata: bool, // including description, name, properties, uri
        soulbound: bool,
        creator_mint_only: bool,
        token_name_vec: vector<String>, // not provided by creator, we could deduct from metadata json file
        token_uri_vec: vector<String>, // not provided by creator, we could deduct from metadata json file
        mint_fee: Option<u64>,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
    ) acquires CollectionDetails {
        let creator_addr = signer::address_of(creator);
        let constructor_ref = &object::create_object(creator_addr);
        let object_signer = object::generate_signer(constructor_ref);

        let royalty = if (option::is_some(&royalty_numerator) && option::is_some(&royalty_denominator)) {
            option::some(royalty::create(option::extract(&mut royalty_numerator), option::extract(&mut royalty_denominator), creator_addr))
        } else {
            option::none()
        };
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

        collection_refs::create_refs(
            &constructor_ref,
            mutable_collection_metadata, // mutable_description
            mutable_collection_metadata, // mutable_uri
            mutable_collection_metadata, // mutable_royalty
        );

        let collection_properties = collection_properties::create(
            mutable_collection_metadata, // mutable_description
            mutable_collection_metadata, // mutable_uri
            mutable_token_metadata, // mutable_token_description
            mutable_token_metadata, // mutable_token_name
            mutable_token_metadata, // mutable_token_properties
            mutable_token_metadata, // mutable_token_uri
            false, // tokens_burnable_by_creator
            false, // tokens_transferable_by_creator
            soulbound,
        );

        collection_properties::init(&constructor_ref, collection_properties);

        let coin_payment = if (option::is_some(&mint_fee)) {
            let mint_fee_category = b"Mint Fee";
            option::some(coin_payment::create<AptosCoin>(option::extract(&mut mint_fee), creator_addr, string::utf8(mint_fee_category)))
        } else {
            option::none()
        };


        move_to(&object_signer, CollectionDetails {
            token_uri_map: smart_table::new(),
            creator_mint_only,
            coin_payment,
        });

        let object_addr = signer::address_of(&object_signer);
        let collection_details = borrow_global_mut<CollectionDetails>(object_addr);
        smart_table::add_all(&mut collection_details.token_uri_map, token_name_vec, token_uri_vec);

        // (jill) add whitelist

        move_to(&object_signer, EZLaunchRefs { extend_ref: object::generate_extend_ref(&constructor_ref) })
    }

    public entry fun mint(
        minter: &signer,
        collection: Object<Collection>,
        description: String,
        name: String,
        uri: String,
        recipient_addr: address,
    ) acquires EZLaunchRefs, CollectionDetails {
        let object_signer = object_signer(collection);
        let object_signer_address = signer::address_of(&object_signer);

        assert!(exists<CollectionDetails>(object_signer_address), error::invalid_state(ECOLLECTION_DETAILS_DOES_NOT_EXIST));
        let collection_details = borrow_global<CollectionDetails>(object_signer_address);
        if (collection_details.creator_mint_only) {
            let minter_address = signer::address_of(minter);
            assert!(object::owns(collection, minter_address), error::invalid_argument(ENOT_CREATOR));
        };

        // (jill) check against whitelist

        let collection_details_obj = object::address_to_object<CollectionDetails>(object_signer_address);
        let coin_payment = coin_payment::get<CollectionDetails, AptosCoin>(&collection_details_obj);
        if (option::is_some<CoinPayment<AptosCoin>>(&coin_payment)) {
            coin_payment::execute<AptosCoin>(minter, &option::extract(&mut coin_payment));
        };

        let constructor_ref = &token::create(
            &object_signer,
            token::collection_name(collection),
            description,
            name,
            royalty::get(collection),
            uri,
        );

        token_refs::create_refs_and_properties(constructor_ref, collection);

        assert!(collection_properties::collection_properties_exists<Collection>(collection), error::invalid_state(ECOLLECTION_PROPERTIES_DOES_NOT_EXIST));
        let collection_properties = option::extract(&mut collection_properties::get<Collection>(collection));
        if (collection_properties::is_soulbound(&collection_properties)) {
            transfer_token::transfer_soulbound(recipient_addr, constructor_ref);
        } else {
            transfer_token::transfer(&object_signer, recipient_addr, constructor_ref);
        }
    }

    // public entry fun upsert_property_maps(
    // ) {
    // }

    fun object_signer(collection: Object<Collection>): signer acquires EZLaunchRefs {
        let collection_address = object::object_address<Collection>(&collection);
        let refs = borrow_global<EZLaunchRefs>(collection_address);
        object::generate_signer_for_extending(&refs.extend_ref)
    }

    // after collection mint complete, destroy resources to get refund
}
