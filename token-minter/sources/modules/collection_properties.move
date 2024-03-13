module minter::collection_properties {

    use std::error;
    use std::signer;
    use std::string;
    use std::string::String;
    use aptos_framework::event;
    use aptos_framework::object::{Self, ConstructorRef, Object};

    /// Collection properties does not exist on this object.
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 1;
    /// The signer is not the owner of the object.
    const ENOT_OBJECT_OWNER: u64 = 2;
    /// The collection property is already initialized.
    const ECOLLECTION_PROPERTY_ALREADY_INITIALIZED: u64 = 3;

    struct CollectionProperty has copy, drop, store {
        value: bool,
        initialized: bool,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionProperties has copy, drop, key {
        /// Determines if the creator can mutate the collection_properties's description
        mutable_description: CollectionProperty,
        /// Determines if the creator can mutate the collection_properties's uri
        mutable_uri: CollectionProperty,
        /// Determines if the creator can mutate token descriptions
        mutable_token_description: CollectionProperty,
        /// Determines if the creator can mutate token names
        mutable_token_name: CollectionProperty,
        /// Determines if the creator can mutate token properties
        mutable_token_properties: CollectionProperty,
        /// Determines if the creator can mutate token uris
        mutable_token_uri: CollectionProperty,
        /// Determines if the creator can change royalties
        mutable_royalty: CollectionProperty,
        /// Determines if the creator can burn tokens
        tokens_burnable_by_creator: CollectionProperty,
        /// Determines if the creator can transfer tokens
        tokens_transferable_by_creator: CollectionProperty,
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
        tokens_burnable_by_creator: CollectionProperty,
        tokens_transferable_by_creator: CollectionProperty,
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
        tokens_burnable_by_creator: bool,
        tokens_transferable_by_creator: bool,
    ): CollectionProperties {
        CollectionProperties {
            mutable_description: create_default_property(mutable_description),
            mutable_uri: create_default_property(mutable_uri),
            mutable_token_description: create_default_property(mutable_token_description),
            mutable_token_name: create_default_property(mutable_token_name),
            mutable_token_properties: create_default_property(mutable_token_properties),
            mutable_token_uri: create_default_property(mutable_token_uri),
            mutable_royalty: create_default_property(mutable_royalty),
            tokens_burnable_by_creator: create_default_property(tokens_burnable_by_creator),
            tokens_transferable_by_creator: create_default_property(tokens_transferable_by_creator),
        }
    }

    fun create_default_property(value: bool): CollectionProperty {
        CollectionProperty { value, initialized: false }
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
            tokens_burnable_by_creator: properties.tokens_burnable_by_creator,
            tokens_transferable_by_creator: properties.tokens_transferable_by_creator,
        });

        object::object_from_constructor_ref(constructor_ref)
    }

    public fun set_mutable_description(
        creator: &signer,
        obj: Object<CollectionProperties>,
        mutable_description: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(creator, obj).mutable_description;
        set_property(property, mutable_description, string::utf8(b"mutable_description"));
    }

    public fun set_mutable_uri(
        creator: &signer,
        obj: Object<CollectionProperties>,
        mutable_uri: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(creator, obj).mutable_uri;
        set_property(property, mutable_uri, string::utf8(b"mutable_uri"));
    }

    public fun set_mutable_token_description(
        creator: &signer,
        obj: Object<CollectionProperties>,
        mutable_token_description: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(creator, obj).mutable_token_description;
        set_property(property, mutable_token_description, string::utf8(b"mutable_token_description"));
    }

    public fun set_mutable_token_name(
        creator: &signer,
        obj: Object<CollectionProperties>,
        mutable_token_name: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(creator, obj).mutable_token_name;
        set_property(property, mutable_token_name, string::utf8(b"mutable_token_name"));
    }

    public fun set_mutable_token_properties(
        creator: &signer,
        obj: Object<CollectionProperties>,
        mutable_token_properties: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(creator, obj).mutable_token_properties;
        set_property(property, mutable_token_properties, string::utf8(b"mutable_token_properties"));
    }

    public fun set_mutable_token_uri(
        creator: &signer,
        obj: Object<CollectionProperties>,
        mutable_token_uri: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(creator, obj).mutable_token_uri;
        set_property(property, mutable_token_uri, string::utf8(b"mutable_uri"));
    }

    public fun set_mutable_royalty(
        creator: &signer,
        obj: Object<CollectionProperties>,
        mutable_royalty: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(creator, obj).mutable_royalty;
        set_property(property, mutable_royalty, string::utf8(b"mutable_royalty"));
    }

    public fun set_tokens_burnable_by_creator(
        creator: &signer,
        obj: Object<CollectionProperties>,
        tokens_burnable_by_creator: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(creator, obj).tokens_burnable_by_creator;
        set_property(property, tokens_burnable_by_creator, string::utf8(b"tokens_burnable_by_creator"));
    }

    public fun set_tokens_transferable_by_creator(
        creator: &signer,
        obj: Object<CollectionProperties>,
        tokens_transferable_by_creator: bool,
    ) acquires CollectionProperties {
        let property = &mut authorized_borrow_mut(creator, obj).tokens_transferable_by_creator;
        set_property(property, tokens_transferable_by_creator, string::utf8(b"tokens_transferable_by_creator"));
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

    inline fun authorized_borrow_mut(
        creator: &signer,
        obj: Object<CollectionProperties>
    ): &mut CollectionProperties acquires CollectionProperties {
        assert!(object::owns(obj, signer::address_of(creator)), error::unauthenticated(ENOT_OBJECT_OWNER));
        assert!(collection_properties_exists(obj), error::not_found(ECOLLECTION_PROPERTIES_DOES_NOT_EXIST));
        borrow_global_mut<CollectionProperties>(object::object_address(&obj))
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
    public fun is_tokens_burnable_by_creator<T: key>(obj: Object<T>): bool acquires CollectionProperties {
        borrow(obj).tokens_burnable_by_creator.value
    }

    #[view]
    public fun is_tokens_transferable_by_creator<T: key>(obj: Object<T>): bool acquires CollectionProperties {
        borrow(obj).tokens_transferable_by_creator.value
    }
}
