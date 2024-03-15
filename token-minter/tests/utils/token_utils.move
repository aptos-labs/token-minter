#[test_only]
module minter::token_utils {
    use std::string::utf8;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::royalty;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;

    use minter::token_components;

    /// Create a token with the given collection and return the token object
    public fun create_token_with_refs(creator: &signer, collection: Object<Collection>): Object<Token> {
        let token_constructor_ref = &create_token(creator, collection);
        token_components::create_refs(token_constructor_ref);
        object::object_from_constructor_ref<Token>(token_constructor_ref)
    }

    public fun create_token(creator: &signer, collection: Object<Collection>): ConstructorRef {
        token::create(
            creator,
            collection::name(collection),
            utf8(b"test token description"),
            utf8(b"test token"),
            royalty::get(collection),
            utf8(b"https://www.google.com"),
        )
    }
}
