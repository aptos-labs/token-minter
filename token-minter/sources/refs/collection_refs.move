module minter::collection_refs {

    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::royalty;

    use minter::collection_properties_old;

    friend minter::token_minter;

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

    #[view]
    /// Can only be called if the `creator` is the owner of the collection.
    public fun collection_object_signer<T: key>(
        creator: &signer,
        collection: Object<T>,
    ): Option<signer> acquires CollectionRefs {
        let refs = authorized_borrow(collection, creator);
        if (option::is_some(&refs.extend_ref)) {
            let extend_ref = option::borrow(&refs.extend_ref);
            option::some(object::generate_signer_for_extending(extend_ref))
        } else {
            option::none()
        }
    }

    public(friend) fun create_refs(
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

    public entry fun set_collection_description<T: key>(
        creator: &signer,
        collection: Object<T>,
        description: String,
    ) acquires CollectionRefs {
        let refs = authorized_borrow(collection, creator);
        assert!(
            collection_properties_old::mutable_description(collection),
            error::permission_denied(EFIELD_NOT_MUTABLE),
        );
        collection::set_description(option::borrow(&refs.mutator_ref), description);
    }

    public entry fun set_collection_uri<T: key>(
        creator: &signer,
        collection: Object<T>,
        uri: String,
    ) acquires CollectionRefs {
        let refs = authorized_borrow(collection, creator);
        assert!(
            collection_properties_old::mutable_token_uri(collection),
            error::permission_denied(EFIELD_NOT_MUTABLE),
        );
        collection::set_uri(option::borrow(&refs.mutator_ref), uri);
    }

    public(friend) fun set_collection_royalties<T: key>(
        creator: &signer,
        collection: Object<T>,
        royalty: royalty::Royalty,
    ) acquires CollectionRefs {
        let refs = authorized_borrow(collection, creator);
        assert!(
            option::is_some(&refs.royalty_mutator_ref),
            error::permission_denied(EFIELD_NOT_MUTABLE),
        );
        royalty::update(option::borrow(&refs.royalty_mutator_ref), royalty);
    }

    inline fun borrow<T: key>(collection: Object<T>): &CollectionRefs {
        let collection_address = object::object_address(&collection);
        assert!(
            contains_collection_refs(collection_address),
            error::not_found(ECOLLECTION_REFS_DOES_NOT_EXIST)
        );
        borrow_global<CollectionRefs>(collection_address)
    }

    inline fun authorized_borrow<T: key>(collection: Object<T>, creator: &signer): &CollectionRefs {
        assert_collection_owner(signer::address_of(creator), collection);
        borrow(collection)
    }

    /// This function checks the whole object hierarchy, checking if the creator
    /// has indirect or direct ownership of the provided collection object.
    fun assert_collection_owner<T: key>(creator: address, collection: Object<T>) {
        assert!(
            object::owns(collection, creator),
            error::permission_denied(ENOT_COLLECTION_OWNER),
        );
    }

    #[view]
    public fun contains_collection_refs(obj_address: address): bool {
        exists<CollectionRefs>(obj_address)
    }

    #[view]
    public fun is_mutable_collection_royalty<T: key>(collection: Object<T>): bool acquires CollectionRefs {
        option::is_some(&borrow(collection).royalty_mutator_ref)
    }
}
