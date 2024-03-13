#[test_only]
module minter::collection_utils {
    use std::option;
    use std::string::utf8;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::collection::Collection;
    use minter::collection_components;

    public fun create_collection_with_refs(collection_owner: &signer): Object<Collection> {
        let collection_construtor_ref = &create_unlimited_collection(collection_owner);
        collection_components::create_refs_and_properties(collection_construtor_ref);
        object::object_from_constructor_ref<Collection>(collection_construtor_ref)
    }

    public fun create_unlimited_collection(collection_owner: &signer): ConstructorRef {
        collection::create_unlimited_collection(
            collection_owner,
            utf8(b"test collection description"),
            utf8(b"test collection name"),
            option::none(),
            utf8(b"https://www.google.com"),
        )
    }
}
