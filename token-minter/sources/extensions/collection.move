module minter::collection {
    use std::error;
    use std::option::{Self, Option};
    use std::string::String;
    use std::signer;
    use aptos_framework::event;
    use aptos_framework::object::{Self, ConstructorRef, Object};

    use aptos_token_objects::collection::{Self, Collection};
    use aptos_token_objects::royalty::{Self, Royalty};

    use minter::collection_properties_2;

    /// Object has no CollectionRefs (capabilities) defined.
    const EOBJECT_HAS_NO_REFS: u64 = 1;
    /// Collection refs does not exist on this object.
    const ECOLLECTION_REFS_DOES_NOT_EXIST: u64 = 2;
    /// The provided signer is not the creator
    const ENOT_CREATOR: u64 = 3;
    /// The provided signer does not own the collection
    const ENOT_COLLECTION_OWNER: u64 = 4;
    /// The field being changed is not mutable
    const EFIELD_NOT_MUTABLE: u64 = 5;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionRefs has key {
        /// Used to mutate collection fields
        mutator_ref: Option<collection::MutatorRef>,
        /// Used to mutate royalties
        royalty_mutator_ref: Option<royalty::MutatorRef>,
        /// Used to generate signer, needed for extending object if needed in the future.
        extend_ref: Option<object::ExtendRef>,
    }

    #[event]
    /// Event emitted when a collection is created.
    struct CreateCollectionEvent has drop, store {
        collection: Object<Collection>,
        description: String,
        max_supply: Option<u64>,
        name: String,
        uri: String,
    }

    /// Creates a new collection in a collection object.
    /// This will contain the `Collection`, `CollectionRefs`, CollectionProperties`.
    public fun create_collection(
        creator: &signer,
        description: String,
        max_supply: Option<u64>, // If value is present, collection configured to have a fixed supply.
        name: String,
        uri: String,
        mutable_description: bool,
        mutable_royalty: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_transferable_by_creator: bool,
        royalty: Option<Royalty>,
    ): Object<Collection> {
        let collection_constructor_ref = &create_collection_internal(
            creator,
            description,
            max_supply,
            name,
            royalty,
            uri,
        );

        let collection_signer = create_refs(
            collection_constructor_ref,
            mutable_description,
            mutable_uri,
            mutable_royalty,
        );

        collection_properties_2::create_properties(
            &collection_signer,
            mutable_description,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_transferable_by_creator,
        );

        let collection = object::object_from_constructor_ref(collection_constructor_ref);

        event::emit(CreateCollectionEvent {
            collection,
            description,
            max_supply,
            name,
            uri,
        });

        collection
    }

    fun create_refs(
        constructor_ref: &ConstructorRef,
        mutable_description: bool,
        mutable_uri: bool,
        mutable_royalty: bool,
    ): signer {
        let collection_signer = object::generate_signer(constructor_ref);

        let mutator_ref = if (mutable_description || mutable_uri) {
            option::some(collection::generate_mutator_ref(constructor_ref))
        } else {
            option::none()
        };
        let royalty_mutator_ref = if (mutable_royalty) {
            option::some(royalty::generate_mutator_ref(object::generate_extend_ref(constructor_ref)))
        } else {
            option::none()
        };

        move_to(&collection_signer, CollectionRefs {
            mutator_ref,
            royalty_mutator_ref,
            extend_ref: option::some(object::generate_extend_ref(constructor_ref)),
        });

        collection_signer
    }

    fun create_collection_internal(
        object_signer: &signer,
        description: String,
        max_supply: Option<u64>,
        name: String,
        royalty: Option<Royalty>,
        uri: String,
    ): ConstructorRef {
        if (option::is_some(&max_supply)) {
            collection::create_fixed_collection(
                object_signer,
                description,
                option::extract(&mut max_supply),
                name,
                royalty,
                uri,
            )
        } else {
            collection::create_unlimited_collection(
                object_signer,
                description,
                name,
                royalty,
                uri,
            )
        }
    }

    // ================================= Collection Mutators ================================= //
    // ======= Must have the `CollectionProperties` created in the Collection Object ======= //

    public entry fun set_collection_description(
        creator: &signer,
        collection: Object<Collection>,
        description: String,
    ) acquires CollectionRefs {
        let refs = authorized_borrow(collection, creator);
        assert!(
            collection_properties_2::mutable_description(collection),
            error::permission_denied(EFIELD_NOT_MUTABLE),
        );
        collection::set_description(option::borrow(&refs.mutator_ref), description);
    }

    public entry fun set_collection_uri(
        creator: &signer,
        collection: Object<Collection>,
        uri: String,
    ) acquires CollectionRefs {
        let refs = authorized_borrow(collection, creator);
        assert!(
            collection_properties_2::mutable_token_uri(collection),
            error::permission_denied(EFIELD_NOT_MUTABLE),
        );
        collection::set_uri(option::borrow(&refs.mutator_ref), uri);
    }

    public fun set_collection_royalties(
        creator: &signer,
        collection: Object<Collection>,
        royalty: royalty::Royalty,
    ) acquires CollectionRefs {
        let refs = authorized_borrow(collection, creator);
        assert!(
            option::is_some(&refs.royalty_mutator_ref),
            error::permission_denied(EFIELD_NOT_MUTABLE),
        );
        royalty::update(option::borrow(&refs.royalty_mutator_ref), royalty);
    }

    inline fun borrow(collection: Object<Collection>): &CollectionRefs {
        let collection_address = object::object_address(&collection);
        assert!(
            contains_collection_refs(collection_address),
            error::not_found(ECOLLECTION_REFS_DOES_NOT_EXIST)
        );
        borrow_global<CollectionRefs>(collection_address)
    }

    inline fun authorized_borrow(collection: Object<Collection>, creator: &signer): &CollectionRefs {
        assert_collection_owner(signer::address_of(creator), collection);
        borrow(collection)
    }

    /// This function checks the whole object hierarchy, checking if the creator
    /// has indirect or direct ownership of the provided collection object.
    fun assert_collection_owner(creator: address, collection: Object<Collection>) {
        assert!(
            object::owns(collection, creator),
            error::permission_denied(ENOT_COLLECTION_OWNER),
        );
    }

    // ================================= View Functions ================================= //

    #[view]
    public fun contains_collection_refs(collection_address: address): bool {
        exists<CollectionRefs>(collection_address)
    }

    #[view]
    public fun is_mutable_collection_royalty(collection: Object<Collection>): bool acquires CollectionRefs {
        option::is_some(&borrow(collection).royalty_mutator_ref)
    }
}
