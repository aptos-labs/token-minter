module minter_v2::collection_properties_v2 {

    use std::error;
    use std::signer;
    use std::string;
    use std::string::String;
    use aptos_framework::event;
    use aptos_framework::object::{Self, ConstructorRef, Object};

    use minter::collection_components;
    use minter::collection_properties;

    /// Collection properties does not exist on this object.
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 1;
    /// The signer is not the owner of the object.
    const ENOT_OBJECT_OWNER: u64 = 2;
    /// The collection property is already initialized.
    const ECOLLECTION_PROPERTY_ALREADY_INITIALIZED: u64 = 3;
    /// Collection properties already exists on this object.
    const ECOLLECTION_PROPERTIES_ALREADY_EXISTS: u64 = 4;

    struct CollectionProperty has copy, drop, store {
        value: bool,
        initialized: bool,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionProperties has copy, drop, key {
        /// Determines if the collection owner can mutate the collection_properties's description
        mutable_description: CollectionProperty,
        /// Determines if the collection owner can mutate the collection_properties's uri
        mutable_uri: CollectionProperty,
        /// Determines if the collection owner can mutate token descriptions
        mutable_token_description: CollectionProperty,
        /// Determines if the collection owner can mutate token names
        mutable_token_name: CollectionProperty,
        /// Determines if the collection owner can mutate token properties
        mutable_token_properties: CollectionProperty,
        /// Determines if the collection owner can mutate token uris
        mutable_token_uri: CollectionProperty,
        /// Determines if the collection owner can change royalties
        mutable_royalty: CollectionProperty,
        /// Determines if the collection owner can burn tokens
        tokens_burnable_by_collection_owner: CollectionProperty,
        /// Determines if the collection owner can transfer tokens
        tokens_transferable_by_collection_owner: CollectionProperty,
    }

    #[event]
    /// Event emitted when CollectionProperties are created.
    struct InitCollectionProperties has drop, store {
        mutable_description: CollectionProperty,
        mutable_uri: CollectionProperty,
        mutable_token_description: CollectionProperty,
        mutable_token_name: CollectionProperty,
        mutable_token_properties: CollectionProperty,
        mutable_token_uri: CollectionProperty,
        mutable_royalty: CollectionProperty,
        tokens_burnable_by_collection_owner: CollectionProperty,
        tokens_transferable_by_collection_owner: CollectionProperty,
    }

    #[event]
    /// Contains the mutated fields name. This makes the life of indexers easier, so that they can
    /// directly understand the behavior in a writeset.
    struct Mutation has drop, store {
        mutated_field_name: String,
    }

    /// Creates a new CollectionProperties resource with the values provided.
    /// These are initialized as `false`, and can only be changed once with the setter functions.
    public fun create_properties(
        mutable_description: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        mutable_royalty: bool,
        tokens_burnable_by_collection_owner: bool,
        tokens_transferable_by_collection_owner: bool,
    ): CollectionProperties {
        CollectionProperties {
            mutable_description: create_property(mutable_description, false),
            mutable_uri: create_property(mutable_uri, false),
            mutable_token_description: create_property(mutable_token_description, false),
            mutable_token_name: create_property(mutable_token_name, false),
            mutable_token_properties: create_property(mutable_token_properties, false),
            mutable_token_uri: create_property(mutable_token_uri, false),
            mutable_royalty: create_property(mutable_royalty, false),
            tokens_burnable_by_collection_owner: create_property(tokens_burnable_by_collection_owner, false),
            tokens_transferable_by_collection_owner: create_property(tokens_transferable_by_collection_owner, false),
        }
    }

    fun create_property(value: bool, initialized: bool): CollectionProperty {
        CollectionProperty { value, initialized }
    }

    public fun init(constructor_ref: &ConstructorRef, properties: CollectionProperties): Object<CollectionProperties> {
        let collection_signer = &object::generate_signer(constructor_ref);
        move_to(collection_signer, properties);

        event::emit(InitCollectionProperties {
            mutable_description: properties.mutable_description,
            mutable_uri: properties.mutable_uri,
            mutable_token_description: properties.mutable_token_description,
            mutable_token_name: properties.mutable_token_name,
            mutable_token_properties: properties.mutable_token_properties,
            mutable_token_uri: properties.mutable_token_uri,
            mutable_royalty: properties.mutable_royalty,
            tokens_burnable_by_collection_owner: properties.tokens_burnable_by_collection_owner,
            tokens_transferable_by_collection_owner: properties.tokens_transferable_by_collection_owner,
        });

        object::object_from_constructor_ref(constructor_ref)
    }

    public fun set_mutable_description<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
        mutable_description: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(collection_owner, obj).mutable_description;
        set_property(property, mutable_description, string::utf8(b"mutable_description"));
    }

    public fun set_mutable_uri<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
        mutable_uri: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(collection_owner, obj).mutable_uri;
        set_property(property, mutable_uri, string::utf8(b"mutable_uri"));
    }

    public fun set_mutable_token_description<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
        mutable_token_description: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(collection_owner, obj).mutable_token_description;
        set_property(property, mutable_token_description, string::utf8(b"mutable_token_description"));
    }

    public fun set_mutable_token_name<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
        mutable_token_name: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(collection_owner, obj).mutable_token_name;
        set_property(property, mutable_token_name, string::utf8(b"mutable_token_name"));
    }

    public fun set_mutable_token_properties<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
        mutable_token_properties: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(collection_owner, obj).mutable_token_properties;
        set_property(property, mutable_token_properties, string::utf8(b"mutable_token_properties"));
    }

    public fun set_mutable_token_uri<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
        mutable_token_uri: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(collection_owner, obj).mutable_token_uri;
        set_property(property, mutable_token_uri, string::utf8(b"mutable_uri"));
    }

    public fun set_mutable_royalty<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
        mutable_royalty: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(collection_owner, obj).mutable_royalty;
        set_property(property, mutable_royalty, string::utf8(b"mutable_royalty"));
    }

    public fun set_tokens_burnable_by_collection_owner<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
        tokens_burnable_by_collection_owner: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(collection_owner, obj).tokens_burnable_by_collection_owner;
        set_property(
            property,
            tokens_burnable_by_collection_owner,
            string::utf8(b"tokens_burnable_by_collection_owner"),
        );
    }

    public fun set_tokens_transferable_by_collection_owner<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
        tokens_transferable_by_collection_owner: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(collection_owner, obj).tokens_transferable_by_collection_owner;
        set_property(
            property,
            tokens_transferable_by_collection_owner,
            string::utf8(b"tokens_transferable_by_collection_owner"),
        );
    }

    fun set_property(property: &mut CollectionProperty, value: bool, mutated_field_name: String) {
        assert!(!property.initialized, error::invalid_state(ECOLLECTION_PROPERTY_ALREADY_INITIALIZED));

        property.value = value;
        property.initialized = true;

        event::emit(Mutation { mutated_field_name });
    }

    inline fun borrow<T: key>(obj: Object<T>): &CollectionProperties acquires CollectionProperties {
        assert!(collection_properties_exists(obj), error::not_found(ECOLLECTION_PROPERTIES_DOES_NOT_EXIST));
        borrow_global<CollectionProperties>(object::object_address(&obj))
    }

    inline fun authorized_borrow_mut<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
    ): &mut CollectionProperties acquires CollectionProperties {
        assert!(object::owner(obj) == signer::address_of(collection_owner), error::unauthenticated(ENOT_OBJECT_OWNER));
        assert!(collection_properties_exists(obj), error::not_found(ECOLLECTION_PROPERTIES_DOES_NOT_EXIST));

        borrow_global_mut<CollectionProperties>(object::object_address(&obj))
    }

    public fun mutable_description(properties: &CollectionProperties): (bool, bool) {
        (properties.mutable_description.value, properties.mutable_description.initialized)
    }

    public fun mutable_uri(properties: &CollectionProperties): (bool, bool) {
        (properties.mutable_uri.value, properties.mutable_uri.initialized)
    }

    public fun mutable_token_description(properties: &CollectionProperties): (bool, bool) {
        (properties.mutable_token_description.value, properties.mutable_token_description.initialized)
    }

    public fun mutable_token_name(properties: &CollectionProperties): (bool, bool) {
        (properties.mutable_token_name.value, properties.mutable_token_name.initialized)
    }

    public fun mutable_token_properties(properties: &CollectionProperties): (bool, bool) {
        (properties.mutable_token_properties.value, properties.mutable_token_properties.initialized)
    }

    public fun mutable_token_uri(properties: &CollectionProperties): (bool, bool) {
        (properties.mutable_token_uri.value, properties.mutable_token_uri.initialized)
    }

    public fun mutable_royalty(properties: &CollectionProperties): (bool, bool) {
        (properties.mutable_royalty.value, properties.mutable_royalty.initialized)
    }

    public fun tokens_burnable_by_collection_owner(properties: &CollectionProperties): (bool, bool) {
        (properties.tokens_burnable_by_collection_owner.value, properties.tokens_burnable_by_collection_owner.initialized)
    }

    public fun tokens_transferable_by_collection_owner(properties: &CollectionProperties): (bool, bool) {
        (properties.tokens_transferable_by_collection_owner.value, properties.tokens_transferable_by_collection_owner.initialized)
    }

    #[view]
    public fun collection_properties_exists<T: key>(obj: Object<T>): bool {
        exists<CollectionProperties>(object::object_address(&obj))
    }

    #[view]
    public fun is_mutable_description<T: key>(obj: Object<T>): bool acquires CollectionProperties {
        borrow(obj).mutable_description.value
    }

    #[view]
    public fun is_mutable_uri<T: key>(obj: Object<T>): bool acquires CollectionProperties {
        borrow(obj).mutable_uri.value
    }

    #[view]
    public fun is_mutable_token_description<T: key>(obj: Object<T>): bool acquires CollectionProperties {
        borrow(obj).mutable_token_description.value
    }

    #[view]
    public fun is_mutable_token_name<T: key>(properties: Object<T>): bool acquires CollectionProperties {
        borrow(properties).mutable_token_name.value
    }

    #[view]
    public fun is_mutable_token_properties<T: key>(obj: Object<T>): bool acquires CollectionProperties {
        borrow(obj).mutable_token_properties.value
    }

    #[view]
    public fun is_mutable_token_uri<T: key>(obj: Object<T>): bool acquires CollectionProperties {
        borrow(obj).mutable_token_uri.value
    }

    #[view]
    public fun is_mutable_royalty<T: key>(obj: Object<T>): bool acquires CollectionProperties {
        borrow(obj).mutable_royalty.value
    }

    #[view]
    public fun is_tokens_burnable_by_collection_owner<T: key>(obj: Object<T>): bool acquires CollectionProperties {
        borrow(obj).tokens_burnable_by_collection_owner.value
    }

    #[view]
    public fun is_tokens_transferable_by_collection_owner<T: key>(obj: Object<T>): bool acquires CollectionProperties {
        borrow(obj).tokens_transferable_by_collection_owner.value
    }

    // ================================== MIGRATE IN FUNCTIONS ================================== //

    /// Migration function used for migrating the refs from one object to another.
    /// This is called when the contract has been upgraded to a new address and version.
    /// This function is used to migrate the refs from the old object to the new object.
    public fun migrate_v1_collection_properties_to_v2<T: key>(
        creator: &signer,
        collection: Object<T>,
    ) {
        let collection_signer = &collection_components::collection_object_signer(creator, collection);
        let properties = &collection_properties::migrate_collection_properties(creator, collection);

        assert!(!collection_properties_exists(collection), error::invalid_state(ECOLLECTION_PROPERTIES_ALREADY_EXISTS));
        let (mutable_description_value, mutable_description_initialized) =
            collection_properties::mutable_description(properties);
        let (mutable_uri_value, mutable_uri_initialized) =
            collection_properties::mutable_uri(properties);
        let (mutable_token_description_value, mutable_token_description_initialized) =
            collection_properties::mutable_token_description(properties);
        let (mutable_token_name_value, mutable_token_name_initialized) =
            collection_properties::mutable_token_name(properties);
        let (mutable_token_properties_value, mutable_token_properties_initialized) =
            collection_properties::mutable_token_properties(properties);
        let (mutable_token_uri_value, mutable_token_uri_initialized) =
            collection_properties::mutable_token_uri(properties);
        let (mutable_royalty_value, mutable_royalty_initialized) =
            collection_properties::mutable_royalty(properties);
        let (tokens_burnable_by_collection_owner_value, tokens_burnable_by_collection_owner_initialized) =
            collection_properties::tokens_burnable_by_collection_owner(properties);
        let (tokens_transferable_by_collection_owner_value, tokens_transferable_by_collection_owner_initialized) =
            collection_properties::tokens_transferable_by_collection_owner(properties);

        move_to(collection_signer, CollectionProperties {
            mutable_description: create_property(mutable_description_value, mutable_description_initialized),
            mutable_uri: create_property(mutable_uri_value, mutable_uri_initialized),
            mutable_token_description: create_property(
                mutable_token_description_value,
                mutable_token_description_initialized,
            ),
            mutable_token_name: create_property(mutable_token_name_value, mutable_token_name_initialized),
            mutable_token_properties: create_property(
                mutable_token_properties_value,
                mutable_token_properties_initialized,
            ),
            mutable_token_uri: create_property(mutable_token_uri_value, mutable_token_uri_initialized),
            mutable_royalty: create_property(mutable_royalty_value, mutable_royalty_initialized),
            tokens_burnable_by_collection_owner: create_property(
                tokens_burnable_by_collection_owner_value,
                tokens_burnable_by_collection_owner_initialized,
            ),
            tokens_transferable_by_collection_owner: create_property(
                tokens_transferable_by_collection_owner_value,
                tokens_transferable_by_collection_owner_initialized,
            ),
        });
    }

    /// Get extend ref from v1 to v2 contract. The creator must be the owner of the collection.

    // ================================== MIGRATE OUT FUNCTIONS ================================== //

    public fun migrate_collection_properties<T: key>(
        collection_owner: &signer,
        obj: Object<T>,
    ): CollectionProperties acquires CollectionProperties {
        let properties = *authorized_borrow_mut(collection_owner, obj);

        let CollectionProperties {
            mutable_description: _,
            mutable_uri: _,
            mutable_token_description: _,
            mutable_token_name: _,
            mutable_token_properties: _,
            mutable_token_uri: _,
            mutable_royalty: _,
            tokens_burnable_by_collection_owner: _,
            tokens_transferable_by_collection_owner: _,
        } = move_from<CollectionProperties>(object::object_address(&obj));

        properties
    }
}