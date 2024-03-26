/// Migration function used for migrating the refs from one object to another.
/// This is called when the contract has been upgraded to a new address and version.
/// This function is used to migrate the refs from the old object to the new object.
///
/// This module migrate the token refs from version x to version y contract.
module migration::migration {

    use std::signer;
    use std::string::String;
    use aptos_framework::object;
    use aptos_framework::object::ExtendRef;

    #[test_only]
    use std::string;
    #[test_only]
    use aptos_framework::event;
    #[test_only]
    use aptos_framework::object::Object;
    #[test_only]
    use aptos_token_objects::collection::Collection;
    #[test_only]
    use aptos_token_objects::token::Token;
    #[test_only]
    use minter::collection_components;
    #[test_only]
    use minter::collection_properties;
    #[test_only]
    use minter::token_components;
    #[test_only]
    use minter_v2::collection_components_v2;
    #[test_only]
    use minter_v2::collection_properties_v2;
    #[test_only]
    use minter_v2::token_components_v2;

    /// Not the owner of the migration contract.
    const ENOT_MIGRATION_CONTRACT_OWNER: u64 = 1;

    const MIGRATION_CONTRACT_SEED: vector<u8> = b"minter::migration_contract";

    struct MigrationRefs has key {
        extend_ref: ExtendRef,
    }

    #[event]
    /// Event emitted when code is published to an object.
    struct Migrate has drop, store {
        module_name: String,
        old_address: address,
        new_address: address,
    }

    fun init_module(creator: &signer) {
        assert!(signer::address_of(creator) == @migration, ENOT_MIGRATION_CONTRACT_OWNER);

        let constructor_ref = &object::create_named_object(creator, MIGRATION_CONTRACT_SEED);
        let migration_signer = &object::generate_signer(constructor_ref);

        move_to(migration_signer, MigrationRefs {
            extend_ref: object::generate_extend_ref(constructor_ref),
        });
    }

    #[view]
    public fun migration_object_address(): address {
        object::create_object_address(&@migration, MIGRATION_CONTRACT_SEED)
    }


    // =========================== Migration function examples for testing =========================== //

    #[test_only]
    /// Migrate `TokenRefs` from vx to vy contract - anyone can call this/migrate their contracts,
    /// as long as the `collection_owner` is the owner of the token's collection.
    public fun migrate_vx_to_vy_token_refs_and_properties(
        collection_owner: &signer,
        token: Object<Token>
    ) acquires MigrationRefs {
        // Get migration signer object
        let migration_refs = borrow_global<MigrationRefs>(migration_object_address());
        let migration_signer = &object::generate_signer_for_extending(&migration_refs.extend_ref);

        let token_signer = &token_components::token_object_signer(collection_owner, token);

        // Migrate out the token refs from vx contract
        let extend_ref = token_components::migrate_out_extend_ref(migration_signer, collection_owner, token);
        let burn_ref = token_components::migrate_out_burn_ref(migration_signer, collection_owner, token);
        let transfer_ref = token_components::migrate_out_transfer_ref(migration_signer, collection_owner, token);
        let mutator_ref = token_components::migrate_out_mutator_ref(migration_signer, collection_owner, token);
        let property_mutator_ref = token_components::migrate_out_property_mutator_ref(
            migration_signer,
            collection_owner,
            token
        );

        // Migrate in the token refs to vy contract
        token_components_v2::migrate_in_extend_ref(migration_signer, collection_owner, token_signer, token, extend_ref);
        token_components_v2::migrate_in_burn_ref(migration_signer, collection_owner, token_signer, token, burn_ref);
        token_components_v2::migrate_in_transfer_ref(
            migration_signer,
            collection_owner,
            token_signer,
            token,
            transfer_ref
        );
        token_components_v2::migrate_in_mutator_ref(
            migration_signer,
            collection_owner,
            token_signer,
            token,
            mutator_ref
        );
        token_components_v2::migrate_in_property_mutator_ref(
            migration_signer,
            collection_owner,
            token_signer,
            token,
            property_mutator_ref
        );

        event::emit(Migrate {
            module_name: string::utf8(b"token_migration"),
            old_address: @minter,
            new_address: @minter_v2,
        });
    }

    #[test_only]
    /// Migrate `CollectionRefs` and `CollectionProperties` from v1 to v2 contract.
    /// The creator must be the owner of the collection.
    public fun migrate_vx_to_vy_collection_refs_and_properties(
        collection_owner: &signer,
        collection: Object<Collection>
    ) acquires MigrationRefs {
        // Get migration signer object
        let migration_refs = borrow_global<MigrationRefs>(migration_object_address());
        let migration_signer = &object::generate_signer_for_extending(&migration_refs.extend_ref);

        let collection_signer = &collection_components::collection_object_signer(collection_owner, collection);

        // Migrate collection properties from vx to vy contract
        migrate_vx_to_vy_collection_properties(migration_signer, collection_owner, collection_signer, collection);

        // Migrate out the collection refs from vx contract
        let mutator_ref = collection_components::migrate_out_mutator_ref(
            migration_signer,
            collection_owner,
            collection,
        );
        let royalty_mutator_ref = collection_components::migrate_out_royalty_mutator_ref(
            migration_signer,
            collection_owner,
            collection,
        );
        let extend_ref = collection_components::migrate_out_extend_ref(migration_signer, collection_owner, collection);

        // Migrate in the collection refs to vy contract
        collection_components_v2::migrate_in_mutator_ref(
            migration_signer,
            collection_owner,
            collection_signer,
            collection,
            mutator_ref,
        );
        collection_components_v2::migrate_in_royalty_mutator_ref(
            migration_signer,
            collection_owner,
            collection_signer,
            collection,
            royalty_mutator_ref,
        );
        collection_components_v2::migrate_in_extend_ref(
            migration_signer,
            collection_owner,
            collection_signer,
            collection,
            extend_ref
        );

        event::emit(Migrate {
            module_name: string::utf8(b"collection_components"),
            old_address: @minter,
            new_address: @minter_v2,
        });
    }

    #[test_only]
    /// Migration function used for migrating the properties from one object to another.
    fun migrate_vx_to_vy_collection_properties(
        migration_signer: &signer,
        collection_owner: &signer,
        collection_signer: &signer,
        collection: Object<Collection>,
    ) {
        // Migrate out the collection properties from v1 contract
        let properties_v1 = &collection_properties::migrate_out_collection_properties(
            migration_signer,
            collection_owner,
            collection
        );
        let (mutable_description_value, mutable_description_initialized) =
            collection_properties::mutable_description(properties_v1);
        let (mutable_uri_value, mutable_uri_initialized) =
            collection_properties::mutable_uri(properties_v1);
        let (mutable_token_description_value, mutable_token_description_initialized) =
            collection_properties::mutable_token_description(properties_v1);
        let (mutable_token_name_value, mutable_token_name_initialized) =
            collection_properties::mutable_token_name(properties_v1);
        let (mutable_token_properties_value, mutable_token_properties_initialized) =
            collection_properties::mutable_token_properties(properties_v1);
        let (mutable_token_uri_value, mutable_token_uri_initialized) =
            collection_properties::mutable_token_uri(properties_v1);
        let (mutable_royalty_value, mutable_royalty_initialized) =
            collection_properties::mutable_royalty(properties_v1);
        let (tokens_burnable_by_collection_owner_value, tokens_burnable_by_collection_owner_initialized) =
            collection_properties::tokens_burnable_by_collection_owner(properties_v1);
        let (tokens_transferable_by_collection_owner_value, tokens_transferable_by_collection_owner_initialized) =
            collection_properties::tokens_transferable_by_collection_owner(properties_v1);

        // Create CollectionProperties V2 values
        let mutable_description = collection_properties_v2::create_property(
            mutable_description_value,
            mutable_description_initialized
        );
        let mutable_uri = collection_properties_v2::create_property(mutable_uri_value, mutable_uri_initialized);
        let mutable_token_description = collection_properties_v2::create_property(
            mutable_token_description_value,
            mutable_token_description_initialized,
        );
        let mutable_token_name = collection_properties_v2::create_property(
            mutable_token_name_value,
            mutable_token_name_initialized
        );
        let mutable_token_properties = collection_properties_v2::create_property(
            mutable_token_properties_value,
            mutable_token_properties_initialized,
        );
        let mutable_token_uri = collection_properties_v2::create_property(
            mutable_token_uri_value,
            mutable_token_uri_initialized
        );
        let mutable_royalty = collection_properties_v2::create_property(
            mutable_royalty_value,
            mutable_royalty_initialized
        );
        let tokens_burnable_by_collection_owner = collection_properties_v2::create_property(
            tokens_burnable_by_collection_owner_value,
            tokens_burnable_by_collection_owner_initialized,
        );
        let tokens_transferable_by_collection_owner = collection_properties_v2::create_property(
            tokens_transferable_by_collection_owner_value,
            tokens_transferable_by_collection_owner_initialized,
        );

        // Migrate in the collection properties to v2 contract
        collection_properties_v2::migrate_in_collection_properties(
            migration_signer,
            collection_owner,
            collection_signer,
            collection,
            mutable_description,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            mutable_royalty,
            tokens_burnable_by_collection_owner,
            tokens_transferable_by_collection_owner,
        );

        event::emit(Migrate {
            module_name: string::utf8(b"collection_properties"),
            old_address: @minter,
            new_address: @minter_v2,
        });
    }

    #[test_only]
    public fun init_module_for_testing(creator: &signer) {
        init_module(creator)
    }
}
