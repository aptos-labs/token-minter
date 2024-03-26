module minter::collection_components {

    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use aptos_framework::object::{Self, ConstructorRef, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::royalty;
    use minter::migration_helper;

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
    /// Caller not authorized to call migration functions.
    const ENOT_MIGRATION_SIGNER: u64 = 5;

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

        init_collection_refs(
            collection_signer,
            option::some(collection::generate_mutator_ref(constructor_ref)),
            option::some(royalty::generate_mutator_ref(object::generate_extend_ref(constructor_ref))),
            option::some(object::generate_extend_ref(constructor_ref)),
        );

        let properties = create_default_properties(true);
        collection_properties::init(constructor_ref, properties);

        object::object_from_constructor_ref(constructor_ref)
    }

    fun create_default_properties(value: bool): CollectionProperties {
        collection_properties::create_uninitialized_properties(value, value, value, value, value, value, value, value, value)
    }

    public fun set_collection_description(
        collection_owner: &signer,
        collection: Object<Collection>,
        description: String,
    ) acquires CollectionRefs {
        assert!(is_mutable_description(collection), error::permission_denied(EFIELD_NOT_MUTABLE));
        collection::set_description(
            option::borrow(&authorized_borrow_refs_mut(collection, collection_owner).mutator_ref),
            description,
        );
    }

    public fun set_collection_uri(
        collection_owner: &signer,
        collection: Object<Collection>,
        uri: String,
    ) acquires CollectionRefs {
        assert!(is_mutable_uri(collection), error::permission_denied(EFIELD_NOT_MUTABLE));
        collection::set_uri(option::borrow(&authorized_borrow_refs_mut(collection, collection_owner).mutator_ref), uri);
    }

    public fun set_collection_royalties(
        collection_owner: &signer,
        collection: Object<Collection>,
        royalty: royalty::Royalty,
    ) acquires CollectionRefs {
        assert!(is_mutable_royalty(collection), error::permission_denied(EFIELD_NOT_MUTABLE));
        royalty::update(
            option::borrow(&authorized_borrow_refs_mut(collection, collection_owner).royalty_mutator_ref),
            royalty
        );
    }

    inline fun authorized_borrow_refs_mut<T: key>(
        collection: Object<T>,
        collection_owner: &signer
    ): &mut CollectionRefs {
        assert_owner(signer::address_of(collection_owner), collection);
        borrow_global_mut<CollectionRefs>(collection_refs_address(collection))
    }

    fun assert_owner<T: key>(collection_owner: address, obj: Object<T>) {
        assert!(
            object::owner(obj) == collection_owner,
            error::permission_denied(ENOT_OBJECT_OWNER),
        );
    }

    fun init_collection_refs(
        collection_object_signer: &signer,
        mutator_ref: Option<collection::MutatorRef>,
        royalty_mutator_ref: Option<royalty::MutatorRef>,
        extend_ref: Option<object::ExtendRef>,
    ) {
        move_to(collection_object_signer, CollectionRefs {
            mutator_ref,
            royalty_mutator_ref,
            extend_ref,
        });
    }

    #[view]
    /// Can only be called if the `collection_owner` is the owner of the collection.
    public fun collection_object_signer<T: key>(
        collection_owner: &signer,
        collection: Object<T>,
    ): signer acquires CollectionRefs {
        let extend_ref = &authorized_borrow_refs_mut(collection, collection_owner).extend_ref;
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

    // ================================== MIGRATE OUT FUNCTIONS ================================== //
    /// Migration function used for migrating the refs from one object to another.
    /// This is called when the contract has been upgraded to a new address and version.
    /// This function is used to migrate the refs from the old object to the new object.
    ///
    /// Only the migration contract is allowed to call migration functions. The user must
    /// call the migration function on the migration contract to migrate.
    ///
    /// To migrate in to the new contract, the `ExtendRef` must be present as the `ExtendRef`
    /// is used to generate the collection object signer.

    public fun migrate_out_extend_ref(
        migration_signer: &signer,
        collection_owner: &signer,
        collection: Object<Collection>,
    ): Option<object::ExtendRef> acquires CollectionRefs {
        assert_migration_object_signer(migration_signer);

        let refs = authorized_borrow_refs_mut(collection, collection_owner);
        let extend_ref = extract_ref_if_present(&mut refs.extend_ref);
        destroy_collection_refs_if_all_refs_migrated(refs, object::object_address(&collection));
        extend_ref
    }

    public fun migrate_out_mutator_ref(
        migration_signer: &signer,
        collection_owner: &signer,
        collection: Object<Collection>,
    ): Option<collection::MutatorRef> acquires CollectionRefs {
        assert_migration_object_signer(migration_signer);

        let refs = authorized_borrow_refs_mut(collection, collection_owner);
        let mutator_ref = extract_ref_if_present(&mut refs.mutator_ref);
        destroy_collection_refs_if_all_refs_migrated(refs, object::object_address(&collection));
        mutator_ref
    }

    public fun migrate_out_royalty_mutator_ref(
        migration_signer: &signer,
        collection_owner: &signer,
        collection: Object<Collection>,
    ): Option<royalty::MutatorRef> acquires CollectionRefs {
        assert_migration_object_signer(migration_signer);

        let refs = authorized_borrow_refs_mut(collection, collection_owner);
        let royalty_mutator_ref = extract_ref_if_present(&mut refs.royalty_mutator_ref);
        destroy_collection_refs_if_all_refs_migrated(refs, object::object_address(&collection));
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

    fun assert_migration_object_signer(migration_signer: &signer) {
        let migration_object_signer = migration_helper::migration_object_address();
        assert!(signer::address_of(migration_signer) == migration_object_signer, ENOT_MIGRATION_SIGNER);
    }
}
