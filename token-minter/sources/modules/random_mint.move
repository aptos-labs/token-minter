module minter::random_mint {

    use std::bcs;
    use std::error;
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};
    use aptos_framework::timestamp;

    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

    /// The random mint map does not exist
    const ERANDOM_MINT_DATA_DOES_NOT_EXIST: u64 = 1;
    /// Property value does not match expected type
    const ENOT_OBJECT_OWNER: u64 = 2;
    /// The caller does not own the token collection
    const ENOT_TOKEN_COLLECTION_OWNER: u64 = 3;
    /// No unique permutation found for random minting.
    const ENO_UNIQUE_PERMUTATION_FOUND: u64 = 4;

    const MAX_ATTEMPTS: u64 = 100;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct RandomMintData has key {
        /// Each property has a number of possible traits to choose from.
        properties: SmartTable<String, Traits>,
        /// Data structure to keep track of all properties that have previously been created.
        hashes: SmartTable<vector<u8>, bool>,
    }

    struct Traits has copy, drop, store {
        // The type of the Trait value.
        type: String,
        /// Contains the possible values to randomly choose from.
        values: vector<vector<u8>>,
    }

    /// Add key and property trait values to the random mint data.
    public fun add_property(
        collection_owner: &signer,
        collection: Object<Collection>,
        key: String,
        type: String,
        values: vector<vector<u8>>,
    ) acquires RandomMintData {
        assert_owner(signer::address_of(collection_owner), collection);
        let collection_addr = object::object_address(&collection);
        assert_exists(collection_addr);

        let data = borrow_global_mut<RandomMintData>(collection_addr);
        if (smart_table::contains(&data.properties, key)) {
            let trait = smart_table::borrow_mut(&mut data.properties, key);
            vector::append(&mut trait.values, values);
        } else {
            smart_table::add(&mut data.properties, key, Traits { type, values });
        };
    }

    /// Chooses a random index from properties and mints a token with the chosen properties.
    public fun generate_random_properties(constructor_ref: &ConstructorRef) acquires RandomMintData {
        let collection_addr = collection_address(constructor_ref);
        let data = borrow_global_mut<RandomMintData>(collection_addr);
        let permutation_found = false;
        let attempts = 0;

        while (!permutation_found) {
            let (keys, types, values) = generate_random_permutation(&mut data.properties);
            let container = property_map::prepare_input(keys, types, values);
            let hash = bcs::to_bytes(&container);

            // Need aggregator `contains` here to parallelize mints.
            if (!smart_table::contains(&data.hashes, hash)) {
                smart_table::add(&mut data.hashes, hash, true);
                property_map::init(constructor_ref, container);
                permutation_found = true;
            } else {
                attempts = attempts + 1;
                if (attempts >= MAX_ATTEMPTS) {
                    abort error::invalid_state(ENO_UNIQUE_PERMUTATION_FOUND)
                }
            }
        }
    }

    // Generate a random permutation of values for each key
    // TODO: Need to generate all possible permutations.
    // TODO: At the moment this uses the same index as `random_index` is the same throughout.
    fun generate_random_permutation(
        properties: &mut SmartTable<String, Traits>
    ): (vector<String>, vector<String>, vector<vector<u8>>) {
        let keys = vector[];
        let types = vector[];
        let values = vector[];

        smart_table::for_each_mut(properties, |k, v| {
            let k: String = *k;
            let v: &mut Traits = v;
            vector::push_back(&mut keys, k);
            vector::push_back(&mut types, v.type);

            let random_index = random_index(vector::length(&v.values));
            let selected_value = *vector::borrow(&v.values, random_index);
            vector::push_back(&mut values, selected_value);
        });

        (keys, types, values)
    }

    // Simple function to generate a random index given a size
    fun random_index(size: u64): u64 {
        timestamp::now_microseconds() % size
    }

    /// Pass in the collection's constructor ref to create a new random mint object.
    public fun create_random_mint(constructor_ref: &ConstructorRef): Object<RandomMintData> {
        let object_signer = &object::generate_signer(constructor_ref);
        move_to(object_signer, RandomMintData {
            properties: smart_table::new(),
            hashes: smart_table::new(),
        });

        object::address_to_object(signer::address_of(object_signer))
    }

    inline fun collection_address(constructor_ref: &ConstructorRef): address {
        let token_addr = object::address_from_constructor_ref(constructor_ref);
        let token = object::address_to_object<Token>(token_addr);
        let collection = token::collection_object(token);
        let collection_addr = object::object_address(&collection);
        assert_exists(collection_addr);

        collection_addr
    }

    inline fun assert_exists(obj_addr: address) {
        assert!(
            exists<RandomMintData>(obj_addr),
            error::not_found(ERANDOM_MINT_DATA_DOES_NOT_EXIST),
        );
    }

    inline fun assert_owner<T: key>(collection_owner: address, obj: Object<T>) {
        assert!(
            object::owner(obj) == collection_owner,
            error::permission_denied(ENOT_OBJECT_OWNER),
        );
    }

    inline fun assert_token_collection_owner(collection_owner: address, token: Object<Token>) {
        let collection = token::collection_object(token);
        assert!(
            object::owner(collection) == collection_owner,
            error::permission_denied(ENOT_TOKEN_COLLECTION_OWNER),
        );
    }
}
