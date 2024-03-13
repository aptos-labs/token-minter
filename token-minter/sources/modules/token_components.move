module minter::token_components {

    use std::error;
    use std::signer;
    use std::string::String;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};

    use aptos_token_objects::property_map;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

    use minter::collection_properties;

    /// Object has no TokenRefs (capabilities) defined.
    const EOBJECT_HAS_NO_REFS: u64 = 1;
    /// Token refs does not exist on this object.
    const ETOKEN_REFS_DOES_NOT_EXIST: u64 = 2;
    /// The provided signer is not the creator
    const ENOT_CREATOR: u64 = 3;
    /// The provided signer does not own the collection of the token
    const ENOT_TOKEN_COLLECTION_OWNER: u64 = 4;
    /// The field being changed is not mutable
    const EFIELD_NOT_MUTABLE: u64 = 5;
    /// The token being burned is not burnable
    const ETOKEN_NOT_BURNABLE: u64 = 6;
    /// The property map being mutated is not mutable
    const EPROPERTIES_NOT_MUTABLE: u64 = 7;
    /// The token does not support forced transfers
    const ETOKEN_NOT_TRANSFERABLE_BY_CREATOR: u64 = 8;
    /// The provided signer is not the collection creator
    const ENOT_COLLECTION_CREATOR: u64 = 9;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenRefs has key {
        /// Used to generate signer for the token. Can be used for extending the
        /// token or transferring out objects from the token
        extend_ref: object::ExtendRef,
        /// Used to burn.
        burn_ref: token::BurnRef,
        /// Used to control freeze.
        transfer_ref: object::TransferRef,
        /// Used to mutate fields
        mutator_ref: token::MutatorRef,
        /// Used to mutate properties
        property_mutator_ref: property_map::MutatorRef,
    }

    public fun create_refs(constructor_ref: &ConstructorRef): Object<TokenRefs> {
        let token_signer = &object::generate_signer(constructor_ref);

        move_to(token_signer, TokenRefs {
            extend_ref: object::generate_extend_ref(constructor_ref),
            burn_ref: token::generate_burn_ref(constructor_ref),
            transfer_ref: object::generate_transfer_ref(constructor_ref),
            mutator_ref: token::generate_mutator_ref(constructor_ref),
            property_mutator_ref: property_map::generate_mutator_ref(constructor_ref),
        });

        object::object_from_constructor_ref(constructor_ref)
    }

    /// Force transfer a token as the collection creator. Feature only works if
    /// the `TransferRef` is stored in the `TokenRefs`.
    public fun transfer_as_creator(
        creator: &signer,
        token: Object<Token>,
        to_addr: address,
    ) acquires TokenRefs {
        assert!(is_transferable_by_creator(token), error::permission_denied(EFIELD_NOT_MUTABLE));

        let token_refs = authorized_borrow(creator, token);
        let transfer_ref = &token_refs.transfer_ref;
        let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, to_addr)
    }

    public fun freeze_transfer(creator: &signer, token: Object<Token>) acquires TokenRefs {
        assert!(is_transferable_by_creator(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        object::disable_ungated_transfer(&authorized_borrow(creator, token).transfer_ref);
    }

    public fun unfreeze_transfer(creator: &signer, token: Object<Token>) acquires TokenRefs {
        assert!(is_transferable_by_creator(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        object::enable_ungated_transfer(&authorized_borrow(creator, token).transfer_ref);
    }

    public fun set_description(
        creator: &signer,
        token: Object<Token>,
        description: String,
    ) acquires TokenRefs {
        assert!(is_mutable_description(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        token::set_description(&authorized_borrow(creator, token).mutator_ref, description);
    }

    public fun set_name(creator: &signer, token: Object<Token>, name: String) acquires TokenRefs {
        assert!(is_mutable_name(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        token::set_name(&authorized_borrow(creator, token).mutator_ref, name);
    }

    public fun set_uri(creator: &signer, token: Object<Token>, uri: String) acquires TokenRefs {
        assert!(is_mutable_uri(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        token::set_uri(&authorized_borrow(creator, token).mutator_ref, uri);
    }

    public fun add_property(
        creator: &signer,
        token: Object<Token>,
        key: String,
        type: String,
        value: vector<u8>,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        property_map::add(&authorized_borrow(creator, token).property_mutator_ref, key, type, value);
    }

    public fun add_typed_property<T: key, V: drop>(
        creator: &signer,
        token: Object<Token>,
        key: String,
        value: V,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        property_map::add_typed(&authorized_borrow(creator, token).property_mutator_ref, key, value);
    }

    public fun remove_property(creator: &signer, token: Object<Token>, key: String) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        property_map::remove(&authorized_borrow(creator, token).property_mutator_ref, &key);
    }

    public fun update_property(
        creator: &signer,
        token: Object<Token>,
        key: String,
        type: String,
        value: vector<u8>,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        property_map::update(&authorized_borrow(creator, token).property_mutator_ref, &key, type, value);
    }

    public fun update_typed_property<T: key, V: drop>(
        creator: &signer,
        token: Object<Token>,
        key: String,
        value: V,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        property_map::update_typed(&authorized_borrow(creator, token).property_mutator_ref, &key, value);
    }

    /// Burn the `TokenRef` object, making the Token immutable
    public fun burn(creator: &signer, token: Object<Token>) acquires TokenRefs {
        assert_token_collection_owner(signer::address_of(creator), token);
        assert!(is_burnable(token), error::permission_denied(ETOKEN_NOT_BURNABLE));

        let token_refs = move_from<TokenRefs>(object::object_address(&token));
        let TokenRefs {
            extend_ref: _,
            burn_ref,
            transfer_ref: _,
            mutator_ref: _,
            property_mutator_ref,
        } = token_refs;
        property_map::burn(property_mutator_ref);
        token::burn(burn_ref);
    }

    /// Allow borrowing the `TokenRefs` resource if the `creator` owns the `token`.
    inline fun authorized_borrow(creator: &signer, token: Object<Token>): &TokenRefs {
        assert_token_collection_owner(signer::address_of(creator), token);
        borrow(token)
    }

    inline fun borrow(token: Object<Token>): &TokenRefs {
        let token_address = object::object_address(&token);
        assert!(
            contains_token_refs(token_address),
            error::not_found(ETOKEN_REFS_DOES_NOT_EXIST),
        );
        borrow_global<TokenRefs>(token_address)
    }

    /// This function checks the whole object hierarchy, checking if the creator
    /// has indirect or direct ownership of the token's collection object.
    fun assert_token_collection_owner(creator: address, token: Object<Token>) {
        assert!(
            object::owner(token::collection_object(token)) == creator,
            error::permission_denied(ENOT_TOKEN_COLLECTION_OWNER),
        );
    }

    #[view]
    /// Can only be called if the `creator` is the owner of the collection the `token` belongs to.
    public fun token_signer(creator: &signer, token: Object<Token>): signer acquires TokenRefs {
        object::generate_signer_for_extending(&authorized_borrow(creator, token).extend_ref)
    }

    #[view]
    public fun contains_token_refs(obj_address: address): bool {
        exists<TokenRefs>(obj_address)
    }

    #[view]
    public fun are_properties_mutable(token: Object<Token>): bool {
        collection_properties::is_mutable_token_properties(token::collection_object(token))
    }

    #[view]
    public fun is_burnable(token: Object<Token>): bool {
        collection_properties::is_tokens_burnable_by_creator(token::collection_object(token))
    }

    #[view]
    public fun is_transferable_by_creator(token: Object<Token>): bool {
        collection_properties::is_tokens_transferable_by_creator(token::collection_object(token))
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

    fun assert_collection_creator(creator: address, token: Object<Token>) {
        assert!(token::creator(token) == creator, error::permission_denied(ENOT_COLLECTION_CREATOR));
    }

    /// Migration function used for migrating the refs from one object to another.
    /// This is called when the contract has been upgraded to a new address and version.
    /// This function is used to migrate the refs from the old object to the new object.
    public fun migrate_refs(
        creator: &signer,
        token: Object<Token>,
    ): (object::ExtendRef, token::BurnRef, object::TransferRef, token::MutatorRef, property_map::MutatorRef) acquires TokenRefs {
        assert!(
            token::creator(token) == signer::address_of(creator),
            error::permission_denied(ENOT_COLLECTION_CREATOR),
        );
        let token_addr = object::object_address(&token);
        assert!(contains_token_refs(token_addr), error::not_found(ETOKEN_REFS_DOES_NOT_EXIST));

        let TokenRefs {
            extend_ref,
            burn_ref,
            transfer_ref,
            mutator_ref,
            property_mutator_ref,
        } = move_from<TokenRefs>(token_addr);

        (extend_ref, burn_ref, transfer_ref, mutator_ref, property_mutator_ref)
    }
}
