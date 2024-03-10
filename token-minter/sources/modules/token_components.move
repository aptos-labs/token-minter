module minter::token_components {

    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};

    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::token;

    use minter::collection_components;
    use minter::collection_components::CollectionProperties;

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

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenRefs has key {
        /// Used to generate signer for the token. Can be used for extending the
        /// token or transferring out objects from the token
        extend_ref: object::ExtendRef,
        /// Used to burn.
        burn_ref: Option<token::BurnRef>,
        /// Used to control freeze.
        transfer_ref: Option<object::TransferRef>,
        /// Used to mutate fields
        mutator_ref: Option<token::MutatorRef>,
        /// Used to mutate properties
        property_mutator_ref: property_map::MutatorRef,
    }

    #[event]
    /// Event emitted when CollectionRefs are created.
    struct CreateTokenRefs has drop, store {
        extend_ref_exists: bool,
        burn_ref_exists: bool,
        transfer_ref_exists: bool,
        mutator_ref_exists: bool,
        property_mutator_ref_exists: bool,
    }

    public fun create_refs_and_properties(
        constructor_ref: &ConstructorRef,
        collection: Object<Collection>,
    ): Object<TokenRefs> {
        init_token_properties(constructor_ref);

        let mutator_ref = option::none();
        let burn_ref = option::none();
        let transfer_ref = option::none();

        let option_properties = collection_components::collection_properties(collection);
        if (option::is_some(&option_properties)) {
            let properties = &option::extract(&mut option_properties);
            mutator_ref = generate_mutator_ref(constructor_ref, properties);
            burn_ref = generate_burn_ref(constructor_ref, properties);
            transfer_ref = generate_transfer_ref(constructor_ref, properties);
        };

        event::emit(CreateTokenRefs {
            extend_ref_exists: true,
            burn_ref_exists: option::is_some(&burn_ref),
            transfer_ref_exists: option::is_some(&transfer_ref),
            mutator_ref_exists: option::is_some(&mutator_ref),
            property_mutator_ref_exists: true,
        });

        move_to(&object::generate_signer(constructor_ref), TokenRefs {
            extend_ref: object::generate_extend_ref(constructor_ref),
            burn_ref,
            transfer_ref,
            mutator_ref,
            property_mutator_ref: property_map::generate_mutator_ref(constructor_ref),
        });

        object::object_from_constructor_ref(constructor_ref)
    }

    fun init_token_properties(constructor_ref: &ConstructorRef) {
        property_map::init(constructor_ref, property_map::prepare_input(vector[], vector[], vector[]));
    }

    fun generate_mutator_ref(
        constructor_ref: &ConstructorRef,
        properties: &CollectionProperties,
    ): Option<token::MutatorRef> {
        if (collection_components::mutable_token_description(properties)
            || collection_components::mutable_token_name(properties)
            || collection_components::mutable_token_uri(properties)) {
            option::some(token::generate_mutator_ref(constructor_ref))
        } else {
            option::none()
        }
    }

    fun generate_burn_ref(constructor_ref: &ConstructorRef, properties: &CollectionProperties): Option<token::BurnRef> {
        if (collection_components::tokens_burnable_by_creator(properties)) {
            option::some(token::generate_burn_ref(constructor_ref))
        } else {
            option::none()
        }
    }

    fun generate_transfer_ref(
        constructor_ref: &ConstructorRef,
        properties: &CollectionProperties,
    ): Option<object::TransferRef> {
        if (collection_components::tokens_transferable_by_creator(properties)) {
            option::some(object::generate_transfer_ref(constructor_ref))
        } else {
            option::none()
        }
    }

    /// Force transfer a token as the collection creator. Feature only works if
    /// the `TransferRef` is stored in the `TokenRefs`.
    public entry fun transfer_as_creator<T: key>(
        creator: &signer,
        token: Object<T>,
        to_addr: address,
    ) acquires TokenRefs {
        assert!(is_transferable_by_creator(token), error::permission_denied(EFIELD_NOT_MUTABLE));

        let token_refs = authorized_borrow(creator, token);
        let transfer_ref = option::borrow(&token_refs.transfer_ref);
        let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, to_addr)
    }

    public entry fun freeze_transfer<T: key>(creator: &signer, token: Object<T>) acquires TokenRefs {
        assert!(is_transferable_by_creator(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        object::disable_ungated_transfer(option::borrow(&authorized_borrow(creator, token).transfer_ref));
    }

    public entry fun unfreeze_transfer<T: key>(creator: &signer, token: Object<T>) acquires TokenRefs {
        assert!(is_transferable_by_creator(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        object::enable_ungated_transfer(option::borrow(&authorized_borrow(creator, token).transfer_ref));
    }

    public entry fun set_description<T: key>(
        creator: &signer,
        token: Object<T>,
        description: String,
    ) acquires TokenRefs {
        assert!(is_mutable_description(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        token::set_description(option::borrow(&authorized_borrow(creator, token).mutator_ref), description);
    }

    public entry fun set_name<T: key>(creator: &signer, token: Object<T>, name: String) acquires TokenRefs {
        assert!(is_mutable_name(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        token::set_name(option::borrow(&authorized_borrow(creator, token).mutator_ref), name);
    }

    public entry fun set_uri<T: key>(creator: &signer, token: Object<T>, uri: String) acquires TokenRefs {
        assert!(is_mutable_uri(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        token::set_uri(option::borrow(&authorized_borrow(creator, token).mutator_ref), uri);
    }

    public entry fun add_property<T: key>(
        creator: &signer,
        token: Object<T>,
        key: String,
        type: String,
        value: vector<u8>,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        property_map::add(&authorized_borrow(creator, token).property_mutator_ref, key, type, value);
    }

    public entry fun add_typed_property<T: key, V: drop>(
        creator: &signer,
        token: Object<T>,
        key: String,
        value: V,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        property_map::add_typed(&authorized_borrow(creator, token).property_mutator_ref, key, value);
    }

    public entry fun remove_property<T: key>(creator: &signer, token: Object<T>, key: String) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        property_map::remove(&authorized_borrow(creator, token).property_mutator_ref, &key);
    }

    public entry fun update_property<T: key>(
        creator: &signer,
        token: Object<T>,
        key: String,
        type: String,
        value: vector<u8>,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        property_map::update(&authorized_borrow(creator, token).property_mutator_ref, &key, type, value);
    }

    public entry fun update_typed_property<T: key, V: drop>(
        creator: &signer,
        token: Object<T>,
        key: String,
        value: V,
    ) acquires TokenRefs {
        assert!(are_properties_mutable(token), error::permission_denied(EPROPERTIES_NOT_MUTABLE));
        property_map::update_typed(&authorized_borrow(creator, token).property_mutator_ref, &key, value);
    }

    /// Burn the `TokenRef` object, making the Token immutable
    public entry fun burn<T: key>(creator: &signer, token: Object<T>) acquires TokenRefs {
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
        token::burn(option::extract(&mut burn_ref));
    }

    /// Allow borrowing the `TokenRefs` resource if the `creator` owns the `token`.
    inline fun authorized_borrow<T: key>(creator: &signer, token: Object<T>): &TokenRefs {
        assert_token_collection_owner(signer::address_of(creator), token);
        borrow(token)
    }

    inline fun borrow<T: key>(token: Object<T>): &TokenRefs {
        let token_address = object::object_address(&token);
        assert!(
            contains_token_refs(token_address),
            error::not_found(ETOKEN_REFS_DOES_NOT_EXIST),
        );
        borrow_global<TokenRefs>(token_address)
    }

    /// This function checks the whole object hierarchy, checking if the creator
    /// has indirect or direct ownership of the token's collection object.
    fun assert_token_collection_owner<T: key>(creator: address, token: Object<T>) {
        assert!(
            object::owner(token::collection_object(token)) == creator,
            error::permission_denied(ENOT_TOKEN_COLLECTION_OWNER),
        );
    }

    #[view]
    /// Can only be called if the `creator` is the owner of the collection the `token` belongs to.
    public fun token_signer<T: key>(creator: &signer, token: Object<T>): signer acquires TokenRefs {
        object::generate_signer_for_extending(&authorized_borrow(creator, token).extend_ref)
    }

    #[view]
    public fun contains_token_refs(obj_address: address): bool {
        exists<TokenRefs>(obj_address)
    }

    #[view]
    public fun are_properties_mutable<T: key>(token: Object<T>): bool {
        let collection_properties = &collection_components::collection_properties(token::collection_object(token));
        if (option::is_some(collection_properties)) {
            collection_components::mutable_token_properties(option::borrow(collection_properties))
        } else {
            false
        }
    }

    #[view]
    public fun is_burnable<T: key>(token: Object<T>): bool acquires TokenRefs {
        let collection_properties = &collection_components::collection_properties(token::collection_object(token));
        if (option::is_some(collection_properties)) {
            collection_components::tokens_burnable_by_creator(option::borrow(collection_properties))
                && option::is_some(&borrow(token).burn_ref)
        } else {
            false
        }
    }

    #[view]
    public fun is_transferable_by_creator<T: key>(token: Object<T>): bool acquires TokenRefs {
        let collection_properties = &collection_components::collection_properties(token::collection_object(token));
        if (option::is_some(collection_properties)) {
            collection_components::tokens_transferable_by_creator(option::borrow(collection_properties))
                && option::is_some(&borrow(token).transfer_ref)
        } else {
            false
        }
    }

    #[view]
    public fun is_mutable_description<T: key>(token: Object<T>): bool acquires TokenRefs {
        let collection_properties = &collection_components::collection_properties(token::collection_object(token));
        if (option::is_some(collection_properties)) {
            collection_components::mutable_token_description(option::borrow(collection_properties))
                && option::is_some(&borrow(token).mutator_ref)
        } else {
            false
        }
    }

    #[view]
    public fun is_mutable_name<T: key>(token: Object<T>): bool acquires TokenRefs {
        let collection_properties = &collection_components::collection_properties(token::collection_object(token));
        if (option::is_some(collection_properties)) {
            collection_components::mutable_token_name(option::borrow(collection_properties))
                && option::is_some(&borrow(token).mutator_ref)
        } else {
            false
        }
    }

    #[view]
    public fun is_mutable_uri<T: key>(token: Object<T>): bool acquires TokenRefs {
        let collection_properties = &collection_components::collection_properties(token::collection_object(token));
        if (option::is_some(collection_properties)) {
            collection_components::mutable_token_uri(option::borrow(collection_properties))
                && option::is_some(&borrow(token).mutator_ref)
        } else {
            false
        }
    }
}
