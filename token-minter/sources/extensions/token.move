module minter::token {

    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::object::ConstructorRef;
    use aptos_framework::object::Object;

    use aptos_token_objects::collection::{Self, Collection};
    use aptos_token_objects::property_map;
    use aptos_token_objects::royalty::{Self};
    use aptos_token_objects::token::{Self, Token};

    use minter::collection_properties;
    use minter::token_helper;

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
    const ETOKEN_NOT_TRANSFERABLE: u64 = 8;

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
    /// Event emitted when a token is created.
    struct CreateTokenEvent has drop, store {
        token: Object<Token>,
        description: String,
        name: String,
        uri: String,
        recipient_addr: address,
        soulbound: bool,
    }

    public fun create(
        creator: &signer,
        collection: Object<Collection>,
        description: String,
        name: String,
        uri: String,
        recipient_addr: address,
        soulbound: bool,
    ): Object<Token> {
        let token_constructor_ref = &token::create(
            creator,
            collection::name(collection),
            description,
            name,
            royalty::get(collection),
            uri
        );

        create_refs_and_property_map(token_constructor_ref, collection);

        let token = token_helper::transfer_token(
            creator,
            recipient_addr,
            soulbound,
            token_constructor_ref,
        );

        event::emit(CreateTokenEvent {
            token,
            description,
            name,
            uri,
            recipient_addr,
            soulbound,
        });

        token
    }

    public fun create_refs_and_property_map(token_constructor_ref: &ConstructorRef, collection: Object<Collection>) {
        /// Initialize the property map
        property_map::init(token_constructor_ref, property_map::prepare_input(vector[], vector[], vector[]));

        let mutator_ref = if (
            collection_properties::mutable_token_description(collection)
                || collection_properties::mutable_token_name(collection)
                || collection_properties::mutable_token_uri(collection)) {
            option::some(token::generate_mutator_ref(token_constructor_ref))
        } else {
            option::none()
        };

        let burn_ref = if (collection_properties::tokens_burnable_by_creator(collection)) {
            option::some(token::generate_burn_ref(token_constructor_ref))
        } else {
            option::none()
        };

        let transfer_ref = if (collection_properties::tokens_transferable_by_creator(collection)) {
            option::some(object::generate_transfer_ref(token_constructor_ref))
        } else {
            option::none()
        };

        move_to(&object::generate_signer(token_constructor_ref), TokenRefs {
            extend_ref: object::generate_extend_ref(token_constructor_ref),
            burn_ref,
            transfer_ref,
            mutator_ref,
            property_mutator_ref: property_map::generate_mutator_ref(token_constructor_ref),
        });
    }

    /// Force transfer a token as the collection creator.
    /// Feature only works if the `TransferRef` is stored in the `TokenRefs`.
    public fun transfer_as_creator(
        creator: &signer,
        token: Object<Token>,
        to_addr: address,
    ) acquires TokenRefs {
        let token_refs = authorized_borrow(creator, token);
        assert!(option::is_some(&token_refs.transfer_ref), ETOKEN_NOT_TRANSFERABLE);

        let transfer_ref = option::borrow(&token_refs.transfer_ref);
        let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, to_addr)
    }

    public fun freeze_transfer(creator: &signer, token: Object<Token>) acquires TokenRefs {
        let token_refs = authorized_borrow(creator, token);
        assert!(
            is_transferable_by_creator(token) && option::is_some(&token_refs.transfer_ref),
            error::permission_denied(EFIELD_NOT_MUTABLE),
        );
        object::disable_ungated_transfer(option::borrow(&token_refs.transfer_ref));
    }

    public fun unfreeze_transfer(creator: &signer, token: Object<Token>) acquires TokenRefs {
        let token_refs = authorized_borrow(creator, token);
        assert!(
            is_transferable_by_creator(token) && option::is_some(&token_refs.transfer_ref),
            error::permission_denied(EFIELD_NOT_MUTABLE),
        );
        object::enable_ungated_transfer(option::borrow(&token_refs.transfer_ref));
    }

    public fun set_description(creator: &signer, token: Object<Token>, description: String) acquires TokenRefs {
        assert!(is_mutable_description(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        token::set_description(option::borrow(&authorized_borrow(creator, token).mutator_ref), description);
    }

    public fun set_name(creator: &signer, token: Object<Token>, name: String) acquires TokenRefs {
        assert!(is_mutable_name(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        token::set_name(option::borrow(&authorized_borrow(creator, token).mutator_ref), name);
    }

    public fun set_uri(creator: &signer, token: Object<Token>, uri: String) acquires TokenRefs {
        assert!(is_mutable_uri(token), error::permission_denied(EFIELD_NOT_MUTABLE));
        token::set_uri(option::borrow(&authorized_borrow(creator, token).mutator_ref), uri);
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

    public fun update_typed_property<V: drop>(
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
        let token_refs = authorized_borrow(creator, token);
        assert!(
            option::is_some(&token_refs.burn_ref),
            error::permission_denied(ETOKEN_NOT_BURNABLE),
        );
        move token_refs;
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

    inline fun authorized_borrow(creator: &signer, token: Object<Token>): &TokenRefs {
        assert_token_collection_owner(signer::address_of(creator), token);
        borrow(token)
    }

    inline fun borrow(token: Object<Token>): &TokenRefs {
        let token_address = object::object_address(&token);
        assert!(
            contains_token_refs(token_address),
            error::not_found(ETOKEN_REFS_DOES_NOT_EXIST)
        );
        borrow_global<TokenRefs>(token_address)
    }

    fun assert_token_collection_owner(creator: address, token: Object<Token>) {
        assert!(
            object::owner(token::collection_object(token)) == creator,
            error::permission_denied(ENOT_TOKEN_COLLECTION_OWNER),
        );
    }

    #[view]
    /// Can only be called if the `creator` is the owner of the collection the `token` belongs to.
    public fun token_object_signer(creator: &signer, token: Object<Token>): signer acquires TokenRefs {
        object::generate_signer_for_extending(&authorized_borrow(creator, token).extend_ref)
    }

    #[view]
    public fun contains_token_refs(obj_address: address): bool {
        exists<TokenRefs>(obj_address)
    }

    #[view]
    public fun are_properties_mutable(token: Object<Token>): bool {
        collection_properties::mutable_token_properties(token::collection_object(token))
    }

    #[view]
    public fun is_burnable(token: Object<Token>): bool acquires TokenRefs {
        option::is_some(&borrow(token).burn_ref)
    }

    #[view]
    public fun is_transferable_by_creator(token: Object<Token>): bool {
        collection_properties::tokens_transferable_by_creator(token::collection_object(token))
    }

    #[view]
    public fun is_mutable_description(token: Object<Token>): bool {
        collection_properties::mutable_token_description(token::collection_object(token))
    }

    #[view]
    public fun is_mutable_name(token: Object<Token>): bool {
        collection_properties::mutable_token_name(token::collection_object(token))
    }

    #[view]
    public fun is_mutable_uri(token: Object<Token>): bool {
        collection_properties::mutable_token_uri(token::collection_object(token))
    }
}
