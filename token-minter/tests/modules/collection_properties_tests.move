#[test_only]
module minter::collection_properties_tests {
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};
    use aptos_token_objects::collection::Collection;

    use minter::collection_properties;
    use minter::collection_properties::CollectionProperties;
    use minter::collection_utils;

    #[test(creator = @0x1)]
    public fun test_set_mutable_description(creator: &signer) {
        // Initialize with all true values, and then setting property `mutable_description` with false.
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_description(creator, properties, false);

        // Assert that `is_mutable_description` has been set to false
        let is_mutable_description = collection_properties::is_mutable_description(properties);
        assert!(!is_mutable_description, 0);
    }

    #[test(creator = @0x1)]
    #[expected_failure(abort_code = 196611, location = minter::collection_properties)]
    public fun test_reinitialize_set_mutable_description_fails(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        // Setting `mutable_description` to false
        collection_properties::set_mutable_description(creator, properties, false);

        let is_mutable_description = collection_properties::is_mutable_description(properties);
        assert!(!is_mutable_description, 0);

        // Setting `mutable_description` to true, this should abort as it's already initialized
        collection_properties::set_mutable_description(creator, properties, true);
    }

    #[test(creator = @0x1)]
    public fun test_set_mutable_uri(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_uri(creator, properties, false);
        assert!(!collection_properties::is_mutable_uri(properties), 0);
    }

    #[test(creator = @0x1)]
    #[expected_failure(abort_code = 196611, location = minter::collection_properties)]
    public fun test_reinitialize_mutable_uri_fails(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_uri(creator, properties, false); // First initialization
        collection_properties::set_mutable_uri(creator, properties, true); // Attempt to reinitialize
    }

    #[test(creator = @0x1)]
    public fun test_set_mutable_token_description(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_token_description(creator, properties, false);
        assert!(!collection_properties::is_mutable_token_description(properties), 0);
    }

    #[test(creator = @0x1)]
    #[expected_failure(abort_code = 196611, location = minter::collection_properties)]
    public fun test_reinitialize_mutable_token_description_fails(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_token_description(creator, properties, false); // First initialization
        collection_properties::set_mutable_token_description(creator, properties, true); // Attempt to reinitialize
    }

    #[test(creator = @0x1)]
    public fun test_set_mutable_token_name(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_token_name(creator, properties, false);
        assert!(!collection_properties::is_mutable_token_name(properties), 0);
    }

    #[test(creator = @0x1)]
    #[expected_failure(abort_code = 196611, location = minter::collection_properties)]
    public fun test_reinitialize_mutable_token_name_fails(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_token_name(creator, properties, false); // First initialization
        collection_properties::set_mutable_token_name(creator, properties, true); // Attempt to reinitialize
    }

    #[test(creator = @0x1)]
    public fun test_set_mutable_token_properties(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_token_properties(creator, properties, false);
        assert!(!collection_properties::is_mutable_token_properties(properties), 0);
    }

    #[test(creator = @0x1)]
    #[expected_failure(abort_code = 196611, location = minter::collection_properties)]
    public fun test_reinitialize_mutable_token_properties_fails(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_token_properties(creator, properties, false); // First initialization
        collection_properties::set_mutable_token_properties(creator, properties, true); // Attempt to reinitialize
    }

    #[test(creator = @0x1)]
    public fun test_set_mutable_token_uri(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_token_uri(creator, properties, false);
        assert!(!collection_properties::is_mutable_token_uri(properties), 0);
    }

    #[test(creator = @0x1)]
    #[expected_failure(abort_code = 196611, location = minter::collection_properties)]
    public fun test_reinitialize_mutable_token_uri_fails(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_token_uri(creator, properties, false); // First initialization
        collection_properties::set_mutable_token_uri(creator, properties, true); // Attempt to reinitialize
    }

    #[test(creator = @0x1)]
    public fun test_set_mutable_royalty(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_royalty(creator, properties, false);
        assert!(!collection_properties::is_mutable_royalty(properties), 0);
    }

    #[test(creator = @0x1)]
    #[expected_failure(abort_code = 196611, location = minter::collection_properties)]
    public fun test_reinitialize_mutable_royalty_fails(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_mutable_royalty(creator, properties, false); // First initialization
        collection_properties::set_mutable_royalty(creator, properties, true); // Attempt to reinitialize
    }

    #[test(creator = @0x1)]
    public fun test_set_tokens_burnable_by_creator(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_tokens_burnable_by_collection_owner(creator, properties, false);
        assert!(!collection_properties::is_tokens_burnable_by_collection_owner(properties), 0);
    }

    #[test(creator = @0x1)]
    #[expected_failure(abort_code = 196611, location = minter::collection_properties)]
    public fun test_reinitialize_tokens_burnable_by_creator_fails(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_tokens_burnable_by_collection_owner(creator, properties, false); // First initialization
        collection_properties::set_tokens_burnable_by_collection_owner(creator, properties, true); // Attempt to reinitialize
    }

    #[test(creator = @0x1)]
    public fun test_set_tokens_transferable_by_collection_owner(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_tokens_transferable_by_collection_owner(creator, properties, false);
        assert!(!collection_properties::is_tokens_transferable_by_collection_owner(properties), 0);
    }

    #[test(creator = @0x1)]
    #[expected_failure(abort_code = 196611, location = minter::collection_properties)]
    public fun test_reinitialize_tokens_transferable_by_collection_owner_fails(creator: &signer) {
        let (_, properties) = create_collection_with_default_properties(creator, true);
        collection_properties::set_tokens_transferable_by_collection_owner(creator, properties, false); // First initialization
        collection_properties::set_tokens_transferable_by_collection_owner(creator, properties, true); // Attempt to reinitialize
    }

    fun create_collection_with_default_properties(
        creator: &signer,
        value: bool,
    ): (ConstructorRef, Object<Collection>) {
        let props = default_properties(value);
        let constructor_ref = collection_utils::create_unlimited_collection(creator);
        let properties_object = collection_properties::init(&constructor_ref, props);
        let collection = object::convert(properties_object);
        (constructor_ref, collection)
    }

    fun default_properties(value: bool): CollectionProperties {
        collection_properties::create_uninitialized_properties(value, value, value, value, value, value, value, value, value, value)
    }
}
