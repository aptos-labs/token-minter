#[test_only]
module minter::collection_utils {
    use std::option;
    use std::string::utf8;
    use aptos_framework::object::ConstructorRef;

    use aptos_token_objects::collection;

    public fun create_unlimited_collection(creator: &signer): ConstructorRef {
        collection::create_unlimited_collection(
            creator,
            utf8(b"test collection description"),
            utf8(b"test collection name"),
            option::none(),
            utf8(b"https://www.google.com"),
        )
    }
}
