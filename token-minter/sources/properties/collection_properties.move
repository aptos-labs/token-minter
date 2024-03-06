module minter::collection_properties {
    use std::option;
    use std::option::Option;
    use aptos_framework::event;
    use aptos_framework::object::{Self, ConstructorRef, Object};

    /// Collection properties does not exist on this object.
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 1;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionProperties has copy, drop, key {
        /// Determines if the creator can mutate the collection_properties's description
        mutable_description: bool,
        /// Determines if the creator can mutate the collection_properties's uri
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

    #[event]
    /// Event emitted when CollectionProperties are created.
    struct InitCollectionProperties has drop, store {
        mutable_description: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_transferable_by_creator: bool,
    }

    public fun create(
        mutable_description: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_transferable_by_creator: bool,
    ): CollectionProperties {
        CollectionProperties {
            mutable_description,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_transferable_by_creator,
        }
    }

    public fun init(constructor_ref: &ConstructorRef, properties: CollectionProperties) {
        let collection_signer = object::generate_signer(constructor_ref);
        move_to(&collection_signer, properties);

        event::emit(InitCollectionProperties {
            mutable_description: properties.mutable_description,
            mutable_uri: properties.mutable_uri,
            mutable_token_description: properties.mutable_token_description,
            mutable_token_name: properties.mutable_token_name,
            mutable_token_properties: properties.mutable_token_properties,
            mutable_token_uri: properties.mutable_token_uri,
            tokens_burnable_by_creator: properties.tokens_burnable_by_creator,
            tokens_transferable_by_creator: properties.tokens_transferable_by_creator,
        });
    }

    // ================================== View functions ================================== //

    #[view]
    public fun get<T: key>(obj: Object<T>): Option<CollectionProperties> acquires CollectionProperties {
        if (collection_properties_exists(obj)) {
            option::some(*borrow_global<CollectionProperties>(object::object_address(&obj)))
        } else {
            option::none()
        }
    }

    public fun mutable_description(properties: &CollectionProperties): bool {
        properties.mutable_description
    }

    public fun mutable_uri(properties: &CollectionProperties): bool {
        properties.mutable_uri
    }

    public fun mutable_token_description(properties: &CollectionProperties): bool {
        properties.mutable_token_description
    }

    public fun mutable_token_name(properties: &CollectionProperties): bool {
        properties.mutable_token_name
    }

    public fun mutable_token_properties(properties: &CollectionProperties): bool {
        properties.mutable_token_properties
    }

    public fun mutable_token_uri(properties: &CollectionProperties): bool {
        properties.mutable_token_uri
    }

    public fun tokens_burnable_by_creator(properties: &CollectionProperties): bool {
        properties.tokens_burnable_by_creator
    }

    public fun tokens_transferable_by_creator(properties: &CollectionProperties): bool {
        properties.tokens_transferable_by_creator
    }

    #[view]
    public fun collection_properties_exists<T: key>(obj: Object<T>): bool {
        exists<CollectionProperties>(object::object_address(&obj))
    }
}
