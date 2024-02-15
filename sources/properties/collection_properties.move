module minter::collection_properties {
    use std::error;
    use std::signer;
    use aptos_framework::object::{Self, Object};

    friend minter::token_minter;

    /// Collection properties does not exist on this object.
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 1;
    /// The provided signer is not the creator
    const ENOT_CREATOR: u64 = 2;
    /// The provided signer does not own the collection
    const ENOT_COLLECTION_OWNER: u64 = 3;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionProperties has key {
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

    public(friend) fun create_properties(
        collection_signer: &signer,
        mutable_description: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_freezable_by_creator: bool,
        soulbound: bool,
    ) {
        move_to(collection_signer, CollectionProperties {
            mutable_description,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_freezable_by_creator,
            soulbound,
        });
    }

    // ================================== Setters ================================== //
    /// Only the creator of the collection can call this function, as they only own the properties.

    public entry fun set_mutable_description<T: key>(
        creator: &signer,
        collection: Object<T>,
        mutable_description: bool,
    ) acquires CollectionProperties {
        authorized_borrow_mut(creator, collection).mutable_description = mutable_description;
    }

    public entry fun set_mutable_uri<T: key>(
        creator: &signer,
        collection: Object<T>,
        mutable_uri: bool,
    ) acquires CollectionProperties {
        authorized_borrow_mut(creator, collection).mutable_uri = mutable_uri;
    }

    public entry fun set_mutable_token_description<T: key>(
        creator: &signer,
        collection: Object<T>,
        mutable_token_description: bool,
    ) acquires CollectionProperties {
        authorized_borrow_mut(creator, collection).mutable_token_description = mutable_token_description;
    }

    public entry fun set_mutable_token_name<T: key>(
        creator: &signer,
        collection: Object<T>,
        mutable_token_name: bool,
    ) acquires CollectionProperties {
        authorized_borrow_mut(creator, collection).mutable_token_name = mutable_token_name;
    }

    public entry fun set_mutable_token_properties<T: key>(
        creator: &signer,
        collection: Object<T>,
        mutable_token_properties: bool,
    ) acquires CollectionProperties {
        authorized_borrow_mut(creator, collection).mutable_token_properties = mutable_token_properties;
    }

    public entry fun set_mutable_token_uri<T: key>(
        creator: &signer,
        collection: Object<T>,
        mutable_token_uri: bool,
    ) acquires CollectionProperties {
        authorized_borrow_mut(creator, collection).mutable_token_uri = mutable_token_uri;
    }

    public entry fun set_tokens_burnable_by_creator<T: key>(
        creator: &signer,
        collection: Object<T>,
        tokens_burnable_by_creator: bool,
    ) acquires CollectionProperties {
        authorized_borrow_mut(creator, collection).tokens_burnable_by_creator = tokens_burnable_by_creator;
    }

    public entry fun set_tokens_freezable_by_creator<T: key>(
        creator: &signer,
        collection: Object<T>,
        tokens_freezable_by_creator: bool,
    ) acquires CollectionProperties {
        authorized_borrow_mut(creator, collection).tokens_freezable_by_creator = tokens_freezable_by_creator;
    }

    public entry fun set_soulbound<T: key>(
        creator: &signer,
        collection: Object<T>,
        soulbound: bool,
    ) acquires CollectionProperties {
        authorized_borrow_mut(creator, collection).soulbound = soulbound;
    }

    // ================================== View functions ================================== //

    #[view]
    public fun mutable_description<T: key>(collection: Object<T>): bool acquires CollectionProperties {
        borrow(collection).mutable_description
    }

    #[view]
    public fun mutable_uri<T: key>(collection: Object<T>): bool acquires CollectionProperties {
        borrow(collection).mutable_uri
    }

    #[view]
    public fun mutable_token_description<T: key>(collection: Object<T>): bool acquires CollectionProperties {
        borrow(collection).mutable_token_description
    }

    #[view]
    public fun mutable_token_name<T: key>(collection: Object<T>): bool acquires CollectionProperties {
        borrow(collection).mutable_token_name
    }

    #[view]
    public fun mutable_token_properties<T: key>(collection: Object<T>): bool acquires CollectionProperties {
        borrow(collection).mutable_token_properties
    }

    #[view]
    public fun mutable_token_uri<T: key>(collection: Object<T>): bool acquires CollectionProperties {
        borrow(collection).mutable_token_uri
    }

    #[view]
    public fun tokens_burnable_by_creator<T: key>(collection: Object<T>): bool acquires CollectionProperties {
        borrow(collection).tokens_burnable_by_creator
    }

    #[view]
    public fun tokens_freezable_by_creator<T: key>(collection: Object<T>): bool acquires CollectionProperties {
        borrow(collection).tokens_freezable_by_creator
    }

    #[view]
    public fun soulbound<T: key>(collection: Object<T>): bool acquires CollectionProperties {
        borrow(collection).soulbound
    }

    #[view]
    public fun is_collection_properties_enabled<T: key>(token_minter: Object<T>): bool {
        exists<CollectionProperties>(object::object_address(&token_minter))
    }

    // ================================== Private functions ================================== //

    /// Only the creator of the collection can call this function, as they only own the properties
    inline fun authorized_borrow_mut<T: key>(
        creator: &signer,
        collection: Object<T>,
    ): &mut CollectionProperties acquires CollectionProperties {
        assert_collection_owner(signer::address_of(creator), collection);

        borrow_global_mut<CollectionProperties>(collection_address(collection))
    }

    inline fun borrow<T: key>(collection: Object<T>): &CollectionProperties {
        borrow_global<CollectionProperties>(collection_address(collection))
    }

    fun assert_collection_owner<T: key>(creator: address, collection: Object<T>) {
        assert!(
            object::owns(collection, creator),
            error::permission_denied(ENOT_COLLECTION_OWNER),
        );
    }

    fun collection_address<T: key>(token_minter: Object<T>): address {
        let collection_address = object::object_address(&token_minter);
        assert!(
            is_collection_properties_enabled(token_minter),
            error::not_found(ECOLLECTION_PROPERTIES_DOES_NOT_EXIST)
        );

        collection_address
    }
}
