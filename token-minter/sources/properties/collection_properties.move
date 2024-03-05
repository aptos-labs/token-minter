module minter::collection_properties {
    use std::error;
    use aptos_framework::object::{Self, Object};
    use aptos_token_objects::collection::Collection;

    /// Collection properties does not exist on this object.
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 1;

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
        /// Determines if the creator can transfer tokens
        tokens_transferable_by_creator: bool,
    }

    public fun create_properties(
        collection_signer: &signer,
        mutable_description: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_transferable_by_creator: bool,
    ) {
        move_to(collection_signer, CollectionProperties {
            mutable_description,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_transferable_by_creator,
        });
    }

    // ================================== View functions ================================== //

    #[view]
    public fun mutable_description(collection: Object<Collection>): bool acquires CollectionProperties {
        borrow(collection).mutable_description
    }

    #[view]
    public fun mutable_uri(collection: Object<Collection>): bool acquires CollectionProperties {
        borrow(collection).mutable_uri
    }

    #[view]
    public fun mutable_token_description(collection: Object<Collection>): bool acquires CollectionProperties {
        borrow(collection).mutable_token_description
    }

    #[view]
    public fun mutable_token_name(collection: Object<Collection>): bool acquires CollectionProperties {
        borrow(collection).mutable_token_name
    }

    #[view]
    public fun mutable_token_properties(collection: Object<Collection>): bool acquires CollectionProperties {
        borrow(collection).mutable_token_properties
    }

    #[view]
    public fun mutable_token_uri(collection: Object<Collection>): bool acquires CollectionProperties {
        borrow(collection).mutable_token_uri
    }

    #[view]
    public fun tokens_burnable_by_creator(collection: Object<Collection>): bool acquires CollectionProperties {
        borrow(collection).tokens_burnable_by_creator
    }

    #[view]
    public fun tokens_transferable_by_creator(collection: Object<Collection>): bool acquires CollectionProperties {
        borrow(collection).tokens_transferable_by_creator
    }

    #[view]
    public fun is_collection_properties_enabled(collection: Object<Collection>): bool {
        exists<CollectionProperties>(object::object_address(&collection))
    }

    // ================================== Private functions ================================== //

    inline fun borrow(collection: Object<Collection>): &CollectionProperties {
        let collection_address = object::object_address(&collection);
        assert!(
            is_collection_properties_enabled(collection),
            error::not_found(ECOLLECTION_PROPERTIES_DOES_NOT_EXIST)
        );

        borrow_global<CollectionProperties>(collection_address)
    }
}
