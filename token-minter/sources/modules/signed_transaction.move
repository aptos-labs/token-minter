/// This module, `minter::signed_transaction`, provides functionality for creating and verifying signed transactions.
/// It allows users to configure a list of keys to verify signed transactions submitted.
///
/// # Features
/// - Initializes proof data with authority public keys and provides functions to manage these keys dynamically.
/// - Uses registered public keys to verify signed transactionss, ensuring that they are executed only if signed by a authorized key.
/// - Generates proof challenges that must be signed, providing an additional layer of security for transaction verification.
///
/// # Example Usage
///
/// ```
/// let (sk, vpk) = ed25519::generate_keys();
/// let pk = ed25519::public_key_into_unvalidated(vpk);
/// let authority_public_key = ed25519::unvalidated_public_key_to_bytes(&pk);
///
/// ## Extend the object by passing it's `signer` and key.
/// let proof_data = signed_transaction::extend(&object_signer, vector![authority_public_key]);
///
/// ## Creating a proof challenge to be signed
/// let mut data = bcs::to_bytes(&collection);
/// vector::append(&mut data, bcs::to_bytes(&token_name));
/// vector::append(&mut data, bcs::to_bytes(&token_description));
/// vector::append(&mut data, bcs::to_bytes(&token_uri));
/// vector::append(&mut data, bcs::to_bytes(&user_addr));
///
/// let challenge = signed_transaction::create_proof_challenge(data);
/// let sig = ed25519::signature_to_bytes(
///     &ed25519::sign_struct(&sk, &challenge),
/// );
///
/// ## Verifying the signed transaction
/// signed_transaction::verify_signed_transaction(proof_data, data, sig);
/// ```
///
module minter::signed_transaction {
    use std::ed25519;
    use std::error;
    use std::signer;
    use std::vector;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};

    /// The proof challenge is invalid.
    const EINVALID_CHALLENGE: u64 = 1;
    /// The proof data does not exist.
    const EPROOF_DATA_DOES_NOT_EXIST: u64 = 2;
    /// The proof data already exists.
    const EPROOF_DATA_ALREADY_EXISTS: u64 = 3;
    /// The signer is not the owner of the object.
    const ENOT_OWNER: u64 = 4;
    /// The key was not found in the authority public keys.
    const EKEY_NOT_FOUND: u64 = 5;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ProofData has key {
        authority_public_keys: vector<ed25519::UnvalidatedPublicKey>,
    }

    struct ProofChallenge has copy, drop {
        challenge_data: vector<u8>,
    }

    /// Initializes the collection object's constructor ref with proof data.
    public fun init(constructor_ref: &ConstructorRef, authority_public_keys: vector<vector<u8>>): Object<ProofData> {
        let object_signer = object::generate_signer(constructor_ref);
        extend(&object_signer, authority_public_keys)
    }

    /// Extends the collection object with proof data via the collection signer.
    public fun extend(object_signer: &signer, authority_public_keys: vector<vector<u8>>): Object<ProofData> {
        let object_signer_addr = signer::address_of(object_signer);
        assert!(!proof_data_exists(object_signer_addr), EPROOF_DATA_ALREADY_EXISTS);

        let unvalidated_authority_public_keys = vector[];
        for (i in 0..vector::length(&authority_public_keys)) {
            let key = *vector::borrow(&mut authority_public_keys, i);
            vector::push_back(
                &mut unvalidated_authority_public_keys,
                ed25519::new_unvalidated_public_key_from_bytes(key),
            );
        };

        move_to(object_signer, ProofData {
            authority_public_keys: unvalidated_authority_public_keys,
        });

        object::address_to_object(object_signer_addr)
    }

    public fun add_public_key(
        owner: &signer,
        proof_data: Object<ProofData>,
        authority_public_key: vector<u8>,
    ) acquires ProofData {
        let proof_data = authorized_borrow_mut(owner, proof_data);
        vector::push_back(
            &mut proof_data.authority_public_keys,
            ed25519::new_unvalidated_public_key_from_bytes(authority_public_key),
        );
    }

    public fun remove_public_key(
        owner: &signer,
        proof_data: Object<ProofData>,
        authority_public_key: vector<u8>,
    ) acquires ProofData {
        let proof_data = authorized_borrow_mut(owner, proof_data);
        let authority_public_key = ed25519::new_unvalidated_public_key_from_bytes(authority_public_key);
        let (found, index) = vector::index_of(&proof_data.authority_public_keys, &authority_public_key);
        assert!(found, error::invalid_state(EKEY_NOT_FOUND));

        vector::remove(&mut proof_data.authority_public_keys, index);
    }

    public fun verify_signed_transaction(
        proof_data_obj: Object<ProofData>,
        challenge_data: vector<u8>,
        signed_transaction: vector<u8>,
    ) acquires ProofData {
        let challenge = ProofChallenge { challenge_data };
        let proof_data = borrow(proof_data_obj);

        let is_valid = vector::any(&proof_data.authority_public_keys, |key| {
            ed25519::signature_verify_strict_t(
                &ed25519::new_signature_from_bytes(signed_transaction),
                key,
                challenge,
            )
        });

        assert!(is_valid, error::unauthenticated(EINVALID_CHALLENGE));
    }

    public fun create_proof_challenge(challenge_data: vector<u8>): ProofChallenge {
        ProofChallenge { challenge_data }
    }

    #[view]
    public fun proof_data_exists(addr: address): bool {
        exists<ProofData>(addr)
    }

    inline fun authorized_borrow_mut<T: key>(owner: &signer, obj: Object<T>): &mut ProofData {
        assert_owner(owner, obj);
        borrow_global_mut<ProofData>(proof_data_addr(obj))
    }

    inline fun borrow<T: key>(obj: Object<T>): &ProofData {
        borrow_global<ProofData>(proof_data_addr(obj))
    }

    inline fun proof_data_addr<T: key>(obj: Object<T>): address {
        let obj_addr = object::object_address(&obj);
        assert!(proof_data_exists(obj_addr), EPROOF_DATA_DOES_NOT_EXIST);
        obj_addr
    }

    inline fun assert_owner<T: key>(owner: &signer, obj: Object<T>) {
        assert!(
            object::owner(obj) == signer::address_of(owner),
            error::permission_denied(ENOT_OWNER),
        );
    }
}
