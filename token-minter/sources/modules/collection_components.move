module minter::collection_components {

    use std::error;
    use std::signer;
    use std::string::String;
    use aptos_framework::object::{Self, ConstructorRef, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::royalty;

    use minter::collection_properties;
    use minter::collection_properties::CollectionProperties;

    /// Object has no CollectionRefs (capabilities) defined.
    const EOBJECT_HAS_NO_REFS: u64 = 1;
    /// Collection refs does not exist on this object.
    const ECOLLECTION_REFS_DOES_NOT_EXIST: u64 = 2;
    /// The provided signer is not the creator
    const ENOT_CREATOR: u64 = 3;
    /// The provided signer does not own the object.
    const ENOT_OBJECT_OWNER: u64 = 4;
    /// The field being changed is not mutable
    const EFIELD_NOT_MUTABLE: u64 = 5;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionRefs has key {
        /// Used to mutate collection fields
        mutator_ref: collection::MutatorRef,
        /// Used to mutate royalties
        royalty_mutator_ref: royalty::MutatorRef,
        /// Used to generate signer, needed for extending object if needed in the future.
        extend_ref: object::ExtendRef,
    }

    /// Collection properties does not exist on this object.
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 1;

    /// This function creates all the refs to extend the collection, mutate the collection and royalties.
    public fun create_refs_and_properties(constructor_ref: &ConstructorRef): Object<CollectionRefs> {
        let collection_signer = &object::generate_signer(constructor_ref);

        move_to(collection_signer, CollectionRefs {
            mutator_ref: collection::generate_mutator_ref(constructor_ref),
            royalty_mutator_ref: royalty::generate_mutator_ref(object::generate_extend_ref(constructor_ref)),
            extend_ref: object::generate_extend_ref(constructor_ref),
        });

        let properties = create_default_properties(true);
        collection_properties::init(constructor_ref, properties);

        object::object_from_constructor_ref(constructor_ref)
    }

    fun create_default_properties(value: bool): CollectionProperties {
        collection_properties::create_properties(value, value, value, value, value, value, value, value, value)
    }

    public fun set_collection_description(
        creator: &signer,
        collection: Object<Collection>,
        description: String,
    ) acquires CollectionRefs {
        assert!(is_mutable_description(collection), error::permission_denied(EFIELD_NOT_MUTABLE));
        collection::set_description(&authorized_borrow_refs(collection, creator).mutator_ref, description);
    }

    public fun set_collection_uri(
        creator: &signer,
        collection: Object<Collection>,
        uri: String,
    ) acquires CollectionRefs {
        assert!(is_mutable_uri(collection), error::permission_denied(EFIELD_NOT_MUTABLE));
        collection::set_uri(&authorized_borrow_refs(collection, creator).mutator_ref, uri);
    }

    public fun set_collection_royalties(
        creator: &signer,
        collection: Object<Collection>,
        royalty: royalty::Royalty,
    ) acquires CollectionRefs {
        assert!(is_mutable_royalty(collection), error::permission_denied(EFIELD_NOT_MUTABLE));
        royalty::update(&authorized_borrow_refs(collection, creator).royalty_mutator_ref, royalty);
    }

    inline fun borrow_refs(collection: Object<Collection>): &CollectionRefs {
        let collection_address = object::object_address(&collection);
        assert!(
            contains_collection_refs(collection_address),
            error::not_found(ECOLLECTION_REFS_DOES_NOT_EXIST)
        );
        borrow_global<CollectionRefs>(collection_address)
    }

    inline fun authorized_borrow_refs(collection: Object<Collection>, creator: &signer): &CollectionRefs {
        assert_owner(signer::address_of(creator), collection);
        borrow_refs(collection)
    }

    /// This function checks the whole object hierarchy, checking if the creator
    /// has indirect or direct ownership of the provided object.
    fun assert_owner(creator: address, obj: Object<Collection>) {
        assert!(
            object::owns(obj, creator),
            error::permission_denied(ENOT_OBJECT_OWNER),
        );
    }

    #[view]
    /// Can only be called if the `creator` is the owner of the collection.
    public fun collection_object_signer(
        creator: &signer,
        collection: Object<Collection>,
    ): signer acquires CollectionRefs {
        let refs = authorized_borrow_refs(collection, creator);
        object::generate_signer_for_extending(&refs.extend_ref)
    }

    #[view]
    public fun contains_collection_refs(obj_address: address): bool {
        exists<CollectionRefs>(obj_address)
    }

    #[view]
    public fun is_mutable_description(obj: Object<Collection>): bool {
        collection_properties::is_mutable_description(obj)
    }

    #[view]
    public fun is_mutable_uri(obj: Object<Collection>): bool {
        collection_properties::is_mutable_uri(obj)
    }

    #[view]
    public fun is_mutable_royalty(obj: Object<Collection>): bool {
        collection_properties::is_mutable_royalty(obj)
    }

    /// Migration function used for migrating the refs from one object to another.
    /// This is called when the contract has been upgraded to a new address and version.
    /// This function is used to migrate the refs from the old object to the new object.
    public fun migrate_refs(
        creator: &signer,
        collection: Object<Collection>,
    ): (collection::MutatorRef, royalty::MutatorRef, object::ExtendRef) acquires CollectionRefs {
        assert_owner(signer::address_of(creator), collection);

        let collection_address = object::object_address(&collection);
        assert!(
            contains_collection_refs(collection_address),
            error::not_found(ECOLLECTION_REFS_DOES_NOT_EXIST)
        );

        let CollectionRefs {
            mutator_ref,
            royalty_mutator_ref,
            extend_ref,
        } = move_from<CollectionRefs>(collection_address);

        (mutator_ref, royalty_mutator_ref, extend_ref)
    }
}
