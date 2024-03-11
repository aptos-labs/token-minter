module minter::token_components {

    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};

    use aptos_token_objects::property_map;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

    use minter::collection_properties;

    /// Token refs does not exist on this object.
    const ETOKEN_REFS_DOES_NOT_EXIST: u64 = 1;
    /// The provided signer does not own the token's collection.
    const ENOT_TOKEN_COLLECTION_OWNER: u64 = 2;
    /// The field being changed is not mutable.
    const EFIELD_NOT_MUTABLE: u64 = 3;
    /// The token being burned is not burnable.
    const ETOKEN_NOT_BURNABLE: u64 = 4;
    /// The property map being mutated is not mutable.
    const EPROPERTIES_NOT_MUTABLE: u64 = 5;
    /// The token does not support forced transfers by collection owner.
    const ETOKEN_NOT_TRANSFERABLE_BY_COLLECTION_OWNER: u64 = 6;
    /// The token does not have ExtendRef, so it is not extendable.
    const ETOKEN_NOT_EXTENDABLE: u64 = 7;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenRefs has key {
        /// Used to generate signer for the token. Can be used for extending the
        /// token or transferring out objects from the token
        extend_ref: Option<object::ExtendRef>,
        /// Used to burn.
        burn_ref: Option<token::BurnRef>,
        /// Used to control freeze.
        transfer_ref: Option<object::TransferRef>,
        /// Used to mutate fields
        mutator_ref: Option<token::MutatorRef>,
        /// Used to mutate properties
        property_mutator_ref: Option<property_map::MutatorRef>,
    }

    public fun create_refs(constructor_ref: &ConstructorRef): Object<TokenRefs> {
        let token_signer = &object::generate_signer(constructor_ref);

        move_to(token_signer, TokenRefs {
            extend_ref: option::some(object::generate_extend_ref(constructor_ref)),
            burn_ref: option::some(token::generate_burn_ref(constructor_ref)),
            transfer_ref: option::some(object::generate_transfer_ref(constructor_ref)),
            mutator_ref: option::some(token::generate_mutator_ref(constructor_ref)),
            property_mutator_ref: option::some(property_map::generate_mutator_ref(constructor_ref)),
        });

        // Initialize property map with empty properties
        property_map::init(constructor_ref, property_map::prepare_input(vector[], vector[], vector[]));

        object::object_from_constructor_ref(constructor_ref)
    }

    /// Force transfer a token as the collection owner. Feature only works if
    /// the `TransferRef` is stored in the `TokenRefs`.
    public fun transfer_as_collection_owner(
        collection_owner: &signer,
        token: Object<Token>,
        to_addr: address,
    ) acquires TokenRefs {
        assert!(
            is_transferable_by_collection_owner(token),
            error::permission_denied(ETOKEN_NOT_TRANSFERABLE_BY_COLLECTION_OWNER),
        );
        let transfer_ref = &authorized_borrow_refs(collection_owner, token).transfer_ref;
        assert!(option::is_some(transfer_ref), error::not_found(ETOKEN_NOT_TRANSFERABLE_BY_COLLECTION_OWNER));

        let linear_transfer_ref = object::generate_linear_transfer_ref(option::borrow(transfer_ref));
        object::transfer_with_ref(linear_transfer_ref, to_addr)
    }

    public fun freeze_transfer(collection_owner: &signer, token: Object<Token>) acquires TokenRefs {
        assert!(is_transferable_by_collection_owner(token), error::permission_denied(
            ETOKEN_NOT_TRANSFERABLE_BY_COLLECTION_OWNER
        ));
        let transfer_ref = &authorized_borrow_refs(collection_owner, token).transfer_ref;
        assert!(option::is_some(transfer_ref), error::not_found(ETOKEN_NOT_TRANSFERABLE_BY_COLLECTION_OWNER));

        object::disable_ungated_transfer(option::borrow(transfer_ref));
    }

    public fun unfreeze_transfer(collection_owner: &signer, token: Object<Token>) acquires TokenRefs {
        assert!(
            is_transferable_by_collection_owner(token), error::permission_denied(
                ETOKEN_NOT_TRANSFERABLE_BY_COLLECTION_OWNER
            ));
        let transfer_ref = &authorized_borrow_refs(collection_owner, token).transfer_ref;
        assert!(option::is_some(transfer_ref), error::not_found(ETOKEN_NOT_TRANSFERABLE_BY_COLLECTION_OWNER));

        object::enable_ungated_transfer(option::borrow(transfer_ref));
    }

    public fun set_description(
        collection_owner: &signer,
        token: Object<Token>,
        description: String,
    ) acquires TokenRefs {
        assert!(is_mutable_description(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        let mutator_ref = &authorized_borrow_refs(collection_owner, token).mutator_ref;
        assert!(option::is_some(mutator_ref), error::not_found(EFIELD_NOT_MUTABLE));

        token::set_description(option::borrow(mutator_ref), description);
    }

    public fun set_name(collection_owner: &signer, token: Object<Token>, name: String) acquires TokenRefs {
        assert!(is_mutable_name(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        let mutator_ref = &authorized_borrow_refs(collection_owner, token).mutator_ref;
        assert!(option::is_some(mutator_ref), error::not_found(EFIELD_NOT_MUTABLE));

        token::set_name(option::borrow(mutator_ref), name);
    }

    public fun set_uri(collection_owner: &signer, token: Object<Token>, uri: String) acquires TokenRefs {
        assert!(is_mutable_uri(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        let mutator_ref = &authorized_borrow_refs(collection_owner, token).mutator_ref;
        assert!(option::is_some(mutator_ref), error::not_found(EFIELD_NOT_MUTABLE));

        token::set_uri(option::borrow(mutator_ref), uri);
    }

    public fun add_property(
        collection_owner: &signer,
        token: Object<Token>,
        key: String,
        type: String,
        value: vector<u8>,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        let property_mutator_ref = &authorized_borrow_refs(collection_owner, token).property_mutator_ref;
        assert!(option::is_some(property_mutator_ref), error::not_found(EPROPERTIES_NOT_MUTABLE));

        property_map::add(option::borrow(property_mutator_ref), key, type, value);
    }

    public fun add_typed_property<V: drop>(
        collection_owner: &signer,
        token: Object<Token>,
        key: String,
        value: V,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        let property_mutator_ref = &authorized_borrow_refs(collection_owner, token).property_mutator_ref;
        assert!(option::is_some(property_mutator_ref), error::not_found(EPROPERTIES_NOT_MUTABLE));

        property_map::add_typed(option::borrow(property_mutator_ref), key, value);
    }

    public fun remove_property(collection_owner: &signer, token: Object<Token>, key: String) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        let property_mutator_ref = &authorized_borrow_refs(collection_owner, token).property_mutator_ref;
        assert!(option::is_some(property_mutator_ref), error::not_found(EPROPERTIES_NOT_MUTABLE));

        property_map::remove(option::borrow(property_mutator_ref), &key);
    }

    public fun update_property(
        collection_owner: &signer,
        token: Object<Token>,
        key: String,
        type: String,
        value: vector<u8>,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        let property_mutator_ref = &authorized_borrow_refs(collection_owner, token).property_mutator_ref;
        assert!(option::is_some(property_mutator_ref), error::not_found(EPROPERTIES_NOT_MUTABLE));

        property_map::update(option::borrow(property_mutator_ref), &key, type, value);
    }

    public fun update_typed_property<V: drop>(
        collection_owner: &signer,
        token: Object<Token>,
        key: String,
        value: V,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        let property_mutator_ref = &authorized_borrow_refs(collection_owner, token).property_mutator_ref;
        assert!(option::is_some(property_mutator_ref), error::not_found(EPROPERTIES_NOT_MUTABLE));

        property_map::update_typed(option::borrow(property_mutator_ref), &key, value);
    }

    /// Allow borrowing the `TokenRefs` resource if the `collection_owner` owns the token's collection.
    inline fun authorized_borrow_refs(collection_owner: &signer, token: Object<Token>): &TokenRefs {
        assert_token_collection_owner(signer::address_of(collection_owner), token);

        let token_address = object::object_address(&token);
        assert!(token_refs_exist(token_address), error::not_found(ETOKEN_REFS_DOES_NOT_EXIST));

        borrow_global<TokenRefs>(token_address)
    }

    fun assert_token_collection_owner(collection_owner: address, token: Object<Token>) {
        let collection = token::collection_object(token);
        assert!(
            object::owner(collection) == collection_owner,
            error::permission_denied(ENOT_TOKEN_COLLECTION_OWNER),
        );
    }

    /// Burn the `TokenRefs` object, making the Token immutable
    public entry fun burn(collection_owner: &signer, token: Object<Token>) acquires TokenRefs {
        assert_token_collection_owner(signer::address_of(collection_owner), token);
        assert!(is_burnable(token), error::permission_denied(ETOKEN_NOT_BURNABLE));

        let token_address = assert_token_refs_exist(token);
        let token_refs = move_from<TokenRefs>(token_address);
        let TokenRefs {
            extend_ref: _,
            burn_ref,
            transfer_ref: _,
            mutator_ref: _,
            property_mutator_ref,
        } = token_refs;
        if (option::is_some(&property_mutator_ref)) {
            property_map::burn(option::extract(&mut property_mutator_ref));
        };
        if (option::is_some(&burn_ref)) {
            token::burn(option::extract(&mut burn_ref));
        };
    }

    fun assert_token_ownership<T: key>(owner: address, token: Object<T>) {
        assert!(
            object::owns(token::collection_object(token), owner),
            error::permission_denied(ENOT_TOKEN_OWNER),
        );
    }

    #[view]
    /// Can only be called if the `collection_owner` is the owner of the collection the `token` belongs to.
    public fun token_object_signer(collection_owner: &signer, token: Object<Token>): signer acquires TokenRefs {
        let extend_ref = &authorized_borrow_refs(collection_owner, token).extend_ref;
        assert!(option::is_some(extend_ref), ETOKEN_NOT_EXTENDABLE);

        object::generate_signer_for_extending(option::borrow(extend_ref))
    }

    #[view]
    public fun token_refs_exist(obj_address: address): bool {
        exists<TokenRefs>(obj_address)
    }

    #[view]
    public fun are_properties_mutable(token: Object<Token>): bool {
        collection_properties::is_mutable_token_properties(token::collection_object(token))
    }

    #[view]
    public fun is_burnable(token: Object<Token>): bool {
        collection_properties::is_tokens_burnable_by_collection_owner(token::collection_object(token))
    }

    #[view]
    public fun is_transferable_by_collection_owner(token: Object<Token>): bool {
        collection_properties::is_tokens_transferable_by_collection_owner(token::collection_object(token))
    }

    #[view]
    public fun is_mutable_description(token: Object<Token>): bool {
        collection_properties::is_mutable_token_description(token::collection_object(token))
    }

    #[view]
    public fun is_mutable_name(token: Object<Token>): bool {
        collection_properties::is_mutable_token_name(token::collection_object(token))
    }

    #[view]
    public fun is_mutable_uri(token: Object<Token>): bool {
        collection_properties::is_mutable_token_uri(token::collection_object(token))
    }

    // ================================== MIGRATE OUT FUNCTIONS ================================== //
    /// Migration function used for migrating the refs from one object to another.
    /// This is called when the contract has been upgraded to a new address and version.
    /// This function is used to migrate the refs from the old object to the new object.

    public fun migrate_extend_ref(
        collection_owner: &signer,
        token: Object<Token>,
    ): Option<object::ExtendRef> acquires TokenRefs {
        assert_token_collection_owner(signer::address_of(collection_owner), token);
        let token_address = assert_token_refs_exist(token);

        let refs = borrow_global_mut<TokenRefs>(token_address);
        let extend_ref = extract_ref_if_present(&mut refs.extend_ref);
        destroy_token_refs_if_all_refs_migrated(refs, token_address);
        extend_ref
    }

    public fun migrate_burn_ref(
        collection_owner: &signer,
        token: Object<Token>,
    ): Option<token::BurnRef> acquires TokenRefs {
        assert_token_collection_owner(signer::address_of(collection_owner), token);
        let token_address = assert_token_refs_exist(token);

        let refs = borrow_global_mut<TokenRefs>(token_address);
        let burn_ref = extract_ref_if_present(&mut refs.burn_ref);
        destroy_token_refs_if_all_refs_migrated(refs, token_address);
        burn_ref
    }

    public fun migrate_transfer_ref(
        collection_owner: &signer,
        token: Object<Token>,
    ): Option<object::TransferRef> acquires TokenRefs {
        assert_token_collection_owner(signer::address_of(collection_owner), token);
        let token_address = assert_token_refs_exist(token);

        let refs = borrow_global_mut<TokenRefs>(token_address);
        let transfer_ref = extract_ref_if_present(&mut refs.transfer_ref);
        destroy_token_refs_if_all_refs_migrated(refs, token_address);
        transfer_ref
    }

    public fun migrate_mutator_ref(
        collection_owner: &signer,
        token: Object<Token>,
    ): Option<token::MutatorRef> acquires TokenRefs {
        assert_token_collection_owner(signer::address_of(collection_owner), token);
        let token_address = assert_token_refs_exist(token);

        let refs = borrow_global_mut<TokenRefs>(token_address);
        let mutator_ref = extract_ref_if_present(&mut refs.mutator_ref);
        destroy_token_refs_if_all_refs_migrated(refs, token_address);
        mutator_ref
    }

    public fun migrate_property_mutator_ref(
        collection_owner: &signer,
        token: Object<Token>,
    ): Option<property_map::MutatorRef> acquires TokenRefs {
        assert_token_collection_owner(signer::address_of(collection_owner), token);
        let token_address = assert_token_refs_exist(token);

        let refs = borrow_global_mut<TokenRefs>(token_address);
        let property_mutator_ref = extract_ref_if_present(&mut refs.property_mutator_ref);
        destroy_token_refs_if_all_refs_migrated(refs, token_address);
        property_mutator_ref
    }

    fun extract_ref_if_present<T: drop + store>(ref: &mut Option<T>): Option<T> {
        if (option::is_some(ref)) {
            option::some(option::extract(ref))
        } else {
            option::none()
        }
    }

    inline fun destroy_token_refs_if_all_refs_migrated(token_refs: &mut TokenRefs, token_address: address) acquires TokenRefs {
        if (option::is_none(&token_refs.extend_ref)
            && option::is_none(&token_refs.burn_ref)
            && option::is_none(&token_refs.transfer_ref)
            && option::is_none(&token_refs.mutator_ref)
            && option::is_none(&token_refs.property_mutator_ref)) {
            let TokenRefs {
                extend_ref: _,
                burn_ref: _,
                transfer_ref: _,
                mutator_ref: _,
                property_mutator_ref: _,
            } = move_from<TokenRefs>(token_address);
        }
    }

    fun assert_token_refs_exist(token: Object<Token>): address {
        let token_address = object::object_address(&token);
        assert!(
            token_refs_exist(token_address),
            error::not_found(ETOKEN_REFS_DOES_NOT_EXIST)
        );
        token_address
    }
}
