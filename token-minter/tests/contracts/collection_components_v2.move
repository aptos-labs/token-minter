/// This module is an example of the v2 contract upgrade for `collection_components.move`.
module minter_v2::collection_components_v2 {

    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use aptos_framework::object::{Self, ConstructorRef, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::royalty;

    use minter::collection_components;
    use minter::collection_properties;
    use minter::collection_properties::CollectionProperties;

    /// Collection refs does not exist on this object.
    const ECOLLECTION_REFS_DOES_NOT_EXIST: u64 = 1;
    /// The provided signer does not own the object.
    const ENOT_OBJECT_OWNER: u64 = 2;
    /// The field being changed is not mutable.
    const EFIELD_NOT_MUTABLE: u64 = 3;
    /// The collection does not have ExtendRef, so it is not extendable.
    const ECOLLECTION_NOT_EXTENDABLE: u64 = 4;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct CollectionRefs has key {
        /// Used to mutate collection fields
        mutator_ref: Option<collection::MutatorRef>,
        /// Used to mutate royalties
        royalty_mutator_ref: Option<royalty::MutatorRef>,
        /// Used to generate signer, needed for extending object if needed in the future.
        extend_ref: Option<object::ExtendRef>,
    }

    /// Collection properties does not exist on this object.
    const ECOLLECTION_PROPERTIES_DOES_NOT_EXIST: u64 = 1;

    /// This function creates all the refs to extend the collection, mutate the collection and royalties.
    public fun create_refs_and_properties(constructor_ref: &ConstructorRef): Object<CollectionRefs> {
        let collection_signer = &object::generate_signer(constructor_ref);

        move_to(collection_signer, CollectionRefs {
            mutator_ref: option::some(collection::generate_mutator_ref(constructor_ref)),
            royalty_mutator_ref: option::some(
                royalty::generate_mutator_ref(object::generate_extend_ref(constructor_ref))
            ),
            extend_ref: option::some(object::generate_extend_ref(constructor_ref)),
        });

        let properties = create_default_properties(true);
        collection_properties::init(constructor_ref, properties);

        object::object_from_constructor_ref(constructor_ref)
    }

    fun create_default_properties(value: bool): CollectionProperties {
        collection_properties::create_properties(value, value, value, value, value, value, value, value, value)
    }

    public fun set_collection_description(
        collection_owner: &signer,
        collection: Object<Collection>,
        description: String,
    ) acquires CollectionRefs {
        assert!(is_mutable_description(collection), error::permission_denied(EFIELD_NOT_MUTABLE));
        collection::set_description(
            option::borrow(&authorized_borrow_refs(collection, collection_owner).mutator_ref),
            description,
        );
    }

    public fun set_collection_uri(
        collection_owner: &signer,
        collection: Object<Collection>,
        uri: String,
    ) acquires CollectionRefs {
        assert!(is_mutable_uri(collection), error::permission_denied(EFIELD_NOT_MUTABLE));
        collection::set_uri(option::borrow(&authorized_borrow_refs(collection, collection_owner).mutator_ref), uri);
    }

    public fun set_collection_royalties(
        collection_owner: &signer,
        collection: Object<Collection>,
        royalty: royalty::Royalty,
    ) acquires CollectionRefs {
        assert!(is_mutable_royalty(collection), error::permission_denied(EFIELD_NOT_MUTABLE));
        royalty::update(
            option::borrow(&authorized_borrow_refs(collection, collection_owner).royalty_mutator_ref),
            royalty
        );
    }

    inline fun authorized_borrow_refs<T: key>(collection: Object<T>, collection_owner: &signer): &CollectionRefs {
        assert_owner(signer::address_of(collection_owner), collection);

        let collection_address = collection_refs_address(collection);
        borrow_global<CollectionRefs>(collection_address)
    }

    fun assert_owner<T: key>(collection_owner: address, obj: Object<T>) {
        assert!(
            object::owner(obj) == collection_owner,
            error::permission_denied(ENOT_OBJECT_OWNER),
        );
    }

    #[view]
    /// Can only be called if the `collection_owner` is the owner of the collection.
    public fun collection_object_signer<T: key>(
        collection_owner: &signer,
        collection: Object<T>,
    ): signer acquires CollectionRefs {
        let extend_ref = &authorized_borrow_refs(collection, collection_owner).extend_ref;
        assert!(option::is_some(extend_ref), ECOLLECTION_NOT_EXTENDABLE);

        object::generate_signer_for_extending(option::borrow(extend_ref))
    }

    #[view]
    public fun collection_refs_exist(obj_address: address): bool {
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

    // ================================== MIGRATE IN FUNCTIONS ================================== //

    /// Migration function used for migrating the refs from one object to another.
    /// This is called when the contract has been upgraded to a new address and version.
    /// This function is used to migrate the refs from the old object to the new object.

    /// Get extend ref from v1 to v2 contract. The creator must be the owner of the collection.
    public fun migrate_v1_extend_ref_to_v2(creator: &signer, collection: Object<Collection>) acquires CollectionRefs {
        let collection_signer = &collection_components::collection_object_signer(creator, collection);
        let collection_addr = signer::address_of(collection_signer);
        let extend_ref = collection_components::migrate_extend_ref(creator, collection);

        if (!collection_refs_exist(collection_addr)) {
            move_to(collection_signer, CollectionRefs {
                mutator_ref: option::none(),
                royalty_mutator_ref: option::none(),
                extend_ref,
            });
        } else {
            borrow_global_mut<CollectionRefs>(collection_addr).extend_ref = extend_ref;
        }
    }

    /// Get mutator ref from v1 to v2 contract. The creator must be the owner of the collection.
    public fun migrate_v1_mutator_ref_to_v2(creator: &signer, collection: Object<Collection>) acquires CollectionRefs {
        let collection_signer = &collection_components::collection_object_signer(creator, collection);
        let collection_addr = signer::address_of(collection_signer);
        let mutator_ref = collection_components::migrate_mutator_ref(creator, collection);

        if (!collection_refs_exist(collection_addr)) {
            move_to(collection_signer, CollectionRefs {
                mutator_ref,
                royalty_mutator_ref: option::none(),
                extend_ref: option::none(),
            });
        } else {
            borrow_global_mut<CollectionRefs>(collection_addr).mutator_ref = mutator_ref;
        }
    }

    /// Get royalty mutator ref from v1 to v2 contract. The creator must be the owner of the collection.
    public fun migrate_v1_royalty_mutator_ref_to_v2(
        creator: &signer,
        collection: Object<Collection>,
    ) acquires CollectionRefs {
        let collection_signer = &collection_components::collection_object_signer(creator, collection);
        let collection_addr = signer::address_of(collection_signer);
        let royalty_mutator_ref = collection_components::migrate_royalty_mutator_ref(creator, collection);

        if (!collection_refs_exist(collection_addr)) {
            move_to(collection_signer, CollectionRefs {
                mutator_ref: option::none(),
                royalty_mutator_ref,
                extend_ref: option::none(),
            });
        } else {
            borrow_global_mut<CollectionRefs>(collection_addr).royalty_mutator_ref = royalty_mutator_ref;
        }
    }

    // ================================== MIGRATE OUT FUNCTIONS ================================== //

    public fun migrate_extend_ref(
        collection_owner: &signer,
        collection: Object<Collection>,
    ): Option<object::ExtendRef> acquires CollectionRefs {
        assert_owner(signer::address_of(collection_owner), collection);
        let collection_address = collection_refs_address(collection);

        let refs = borrow_global_mut<CollectionRefs>(collection_address);
        let extend_ref = extract_ref_if_present(&mut refs.extend_ref);
        destroy_collection_refs_if_all_refs_migrated(refs, collection_address);
        extend_ref
    }

    public fun migrate_mutator_ref(
        collection_owner: &signer,
        collection: Object<Collection>,
    ): Option<collection::MutatorRef> acquires CollectionRefs {
        assert_owner(signer::address_of(collection_owner), collection);
        let collection_address = collection_refs_address(collection);

        let refs = borrow_global_mut<CollectionRefs>(collection_address);
        let mutator_ref = extract_ref_if_present(&mut refs.mutator_ref);
        destroy_collection_refs_if_all_refs_migrated(refs, collection_address);
        mutator_ref
    }

    public fun migrate_royalty_mutator_ref(
        collection_owner: &signer,
        collection: Object<Collection>,
    ): Option<royalty::MutatorRef> acquires CollectionRefs {
        assert_owner(signer::address_of(collection_owner), collection);
        let collection_address = collection_refs_address(collection);

        let refs = borrow_global_mut<CollectionRefs>(collection_address);
        let royalty_mutator_ref = extract_ref_if_present(&mut refs.royalty_mutator_ref);
        destroy_collection_refs_if_all_refs_migrated(refs, collection_address);
        royalty_mutator_ref
    }

    fun extract_ref_if_present<T: drop + store>(ref: &mut Option<T>): Option<T> {
        if (option::is_some(ref)) {
            option::some(option::extract(ref))
        } else {
            option::none()
        }
    }

    inline fun destroy_collection_refs_if_all_refs_migrated(
        collection_refs: &mut CollectionRefs,
        collection_address: address,
    ) acquires CollectionRefs {
        if (option::is_none(&collection_refs.mutator_ref)
            && option::is_none(&collection_refs.royalty_mutator_ref)
            && option::is_none(&collection_refs.extend_ref)) {
            let CollectionRefs {
                mutator_ref: _,
                royalty_mutator_ref: _,
                extend_ref: _,
            } = move_from<CollectionRefs>(collection_address);
        }
    }

    fun collection_refs_address<T: key>(collection: Object<T>): address {
        let collection_address = object::object_address(&collection);
        assert!(
            collection_refs_exist(collection_address),
            error::not_found(ECOLLECTION_REFS_DOES_NOT_EXIST)
        );
        collection_address
    }
}
