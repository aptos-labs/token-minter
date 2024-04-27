#[test_only]
module minter::signed_transaction_tests {
    use std::bcs;
    use std::signer;
    use std::string::utf8;
    use std::vector;
    use aptos_std::ed25519;
    use minter::collection_components;

    use minter::collection_utils::create_collection_with_refs;
    use minter::signed_transaction;

    #[test(creator = @0x123, user = @0x456)]
    fun test_signed_transaction_success(creator: &signer, user: &signer) {
        let (sk, vpk) = ed25519::generate_keys();
        let pk = ed25519::public_key_into_unvalidated(vpk);
        let authority_public_key = ed25519::unvalidated_public_key_to_bytes(&pk);

        let collection = create_collection_with_refs(creator);
        let collection_signer = collection_components::collection_object_signer(creator, collection);
        let proof_data = signed_transaction::extend(&collection_signer, vector[authority_public_key]);

        let token_name = utf8(b"Sword");
        let token_description = utf8(b"A fancy sword");
        let token_uri = utf8(b"https://example.com/sword1.png");
        let user_addr = signer::address_of(user);

        let data = bcs::to_bytes(&collection);
        vector::append(&mut data, bcs::to_bytes(&token_name));
        vector::append(&mut data, bcs::to_bytes(&token_description));
        vector::append(&mut data, bcs::to_bytes(&token_uri));
        vector::append(&mut data, bcs::to_bytes(&user_addr));

        let challenge = signed_transaction::create_proof_challenge(data);
        let sig = ed25519::signature_to_bytes(
            &ed25519::sign_struct(&sk, challenge),
        );
        signed_transaction::verify_signed_transaction(proof_data, data, sig);
    }

    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 0x40001, location = minter::signed_transaction)]
    fun wrong_signed_transaction_should_fail(creator: &signer, user: &signer) {
        let (sk, vpk) = ed25519::generate_keys();
        let pk = ed25519::public_key_into_unvalidated(vpk);
        let authority_public_key = ed25519::unvalidated_public_key_to_bytes(&pk);

        let collection = create_collection_with_refs(creator);
        let collection_signer = collection_components::collection_object_signer(creator, collection);
        let proof_data = signed_transaction::extend(&collection_signer, vector[authority_public_key]);

        let token_name = utf8(b"Sword");
        let token_description = utf8(b"A fancy sword");
        let token_uri = utf8(b"https://example.com/sword1.png");
        let user_addr = signer::address_of(user);

        let data = bcs::to_bytes(&collection);
        vector::append(&mut data, bcs::to_bytes(&token_name));
        vector::append(&mut data, bcs::to_bytes(&token_description));
        vector::append(&mut data, bcs::to_bytes(&token_uri));
        vector::append(&mut data, bcs::to_bytes(&user_addr));

        let challenge = signed_transaction::create_proof_challenge(data);
        let sig = ed25519::signature_to_bytes(
            &ed25519::sign_struct(&sk, challenge),
        );

        // Create wrong data - different from signed data
        let wrong_data = data;
        vector::append(&mut wrong_data, bcs::to_bytes(&utf8(b"Wrong data")));
        signed_transaction::verify_signed_transaction(proof_data, wrong_data, sig);
    }

    /// Test successful verification with the new key after an update
    #[test(creator = @0x123, user = @0x456)]
    fun verify_with_new_key_after_update(creator: &signer, user: &signer) {
        let (_, vpk_old) = ed25519::generate_keys();
        let pk_old = ed25519::public_key_into_unvalidated(vpk_old);
        let authority_public_key_old = ed25519::unvalidated_public_key_to_bytes(&pk_old);
        let collection = create_collection_with_refs(creator);
        let collection_signer = collection_components::collection_object_signer(creator, collection);

        // Update the public key to old first
        let proof_data = signed_transaction::extend(&collection_signer, vector[authority_public_key_old]);

        let (sk_new, vpk_new) = ed25519::generate_keys();
        let pk_new = ed25519::public_key_into_unvalidated(vpk_new);
        let authority_public_key_new = ed25519::unvalidated_public_key_to_bytes(&pk_new);

        // Add the new public key
        signed_transaction::add_public_key(creator, proof_data, authority_public_key_new);

        // Create a challenge and sign with the new key
        let token_name = utf8(b"Sword");
        let token_description = utf8(b"A fancy sword");
        let token_uri = utf8(b"https://example.com/sword1.png");
        let user_addr = signer::address_of(user);

        let data = bcs::to_bytes(&collection);
        vector::append(&mut data, bcs::to_bytes(&token_name));
        vector::append(&mut data, bcs::to_bytes(&token_description));
        vector::append(&mut data, bcs::to_bytes(&token_uri));
        vector::append(&mut data, bcs::to_bytes(&user_addr));

        let challenge = signed_transaction::create_proof_challenge(data);
        let sig = ed25519::signature_to_bytes(
            &ed25519::sign_struct(&sk_new, challenge),
        );

        // Verification should succeed with the new key
        signed_transaction::verify_signed_transaction(proof_data, data, sig);
    }

    // Test updating the public key to a new one and verifying with the old key should fail.
    #[test(creator = @0x123, user = @0x456)]
    #[expected_failure(abort_code = 0x40001, location = minter::signed_transaction)]
    fun update_public_key_and_verify_with_old_key_should_fail(creator: &signer, user: &signer) {
        let (sk_old, vpk_old) = ed25519::generate_keys();
        let pk_old = ed25519::public_key_into_unvalidated(vpk_old);
        let authority_public_key_old = ed25519::unvalidated_public_key_to_bytes(&pk_old);

        let (_, vpk_new) = ed25519::generate_keys();
        let pk_new = ed25519::public_key_into_unvalidated(vpk_new);
        let authority_public_key_new = ed25519::unvalidated_public_key_to_bytes(&pk_new);

        let collection = create_collection_with_refs(creator);
        let collection_signer = collection_components::collection_object_signer(creator, collection);
        let proof_data = signed_transaction::extend(&collection_signer, vector[authority_public_key_old]);

        // Add the new public key
        signed_transaction::add_public_key(creator, proof_data, authority_public_key_new);

        // Remove the old public key
        signed_transaction::remove_public_key(creator, proof_data, authority_public_key_old);

        let token_name = utf8(b"Sword");
        let token_description = utf8(b"A fancy sword");
        let token_uri = utf8(b"https://example.com/sword1.png");
        let user_addr = signer::address_of(user);

        let data = bcs::to_bytes(&collection);
        vector::append(&mut data, bcs::to_bytes(&token_name));
        vector::append(&mut data, bcs::to_bytes(&token_description));
        vector::append(&mut data, bcs::to_bytes(&token_uri));
        vector::append(&mut data, bcs::to_bytes(&user_addr));

        let challenge = signed_transaction::create_proof_challenge(data);

        // Create a mint proof challenge and sign with the old key
        let sig = ed25519::signature_to_bytes(
            &ed25519::sign_struct(&sk_old, challenge),
        );

        // Verification should fail since the old key was removed
        signed_transaction::verify_signed_transaction(proof_data, data, sig);
    }

    #[test(creator = @0x123, non_owner = @0x456)]
    #[expected_failure(abort_code = 0x50004, location = minter::signed_transaction)]
    fun test_non_owner_cannot_add_public_key(creator: &signer, non_owner: &signer) {
        let (_sk, vpk) = ed25519::generate_keys();
        let pk = ed25519::public_key_into_unvalidated(vpk);
        let authority_public_key = ed25519::unvalidated_public_key_to_bytes(&pk);

        let collection = create_collection_with_refs(creator);
        let collection_signer = collection_components::collection_object_signer(creator, collection);
        let proof_data = signed_transaction::extend(&collection_signer, vector[authority_public_key]);

        // Attempt by non-owner to add a new key
        signed_transaction::add_public_key(non_owner, proof_data, authority_public_key);
    }
}
