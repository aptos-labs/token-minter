module minter::signed_transaction {
    use std::ed25519;
    use std::error;
    use std::signer;
    use std::string::String;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};

    /// The proof challenge is invalid.
    const EINVALID_CHALLENGE: u64 = 1;
    /// The proof data does not exist.
    const EPROOF_DATA_DOES_NOT_EXIST: u64 = 2;
    /// The proof data already exists.
    const EPROOF_DATA_ALREADY_EXISTS: u64 = 3;
    /// The signer is not the owner of the object.
    const ENOT_OBJECT_OWNER: u64 = 4;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ProofData has key {
        authority_public_key: ed25519::UnvalidatedPublicKey,
    }

    struct ProofChallenge has copy, drop {
        data: vector<u8>,
    }

    /// Initializes the collection object's constructor ref with proof data.
    public fun init(constructor_ref: &ConstructorRef, authority_public_key: vector<u8>): Object<ProofData> {
        let object_signer = object::generate_signer(constructor_ref);
        extend(&object_signer, authority_public_key)
    }

    /// Extends the collection object with proof data via the collection signer.
    public fun extend(object_signer: &signer, authority_public_key: vector<u8>): Object<ProofData> {
        let object_signer_addr = signer::address_of(object_signer);
        assert!(!proof_data_exists(object_signer_addr), EPROOF_DATA_ALREADY_EXISTS);

        move_to(object_signer, ProofData {
            authority_public_key: ed25519::new_unvalidated_public_key_from_bytes(authority_public_key),
        });

        object::address_to_object(object_signer_addr)
    }

    public fun set_public_key(
        owner: &signer,
        proof_data: Object<ProofData>,
        authority_public_key: vector<u8>,
    ) acquires ProofData {
        assert_owner(signer::address_of(owner), proof_data);

        let proof_data = borrow_mut(proof_data);
        proof_data.authority_public_key = ed25519::new_unvalidated_public_key_from_bytes(authority_public_key);
    }

    public fun verify_signed_transaction(
        proof_data: Object<ProofData>,
        data: vector<u8>,
        signed_transaction: vector<u8>,
    ) acquires ProofData {
        let challenge = ProofChallenge { data };
        let proof_data = borrow(proof_data);
        assert!(
            ed25519::signature_verify_strict_t(
                &ed25519::new_signature_from_bytes(signed_transaction),
                &proof_data.authority_public_key,
                challenge,
            ),
            EINVALID_CHALLENGE,
        );
    }

    public fun create_proof_challenge(data: vector<u8>): ProofChallenge {
        ProofChallenge { data }
    }

    public fun proof_data_exists(addr: address): bool {
        exists<ProofData>(addr)
    }

    inline fun borrow_mut<T: key>(obj: Object<T>): &mut ProofData {
        let obj_addr = object::object_address(&obj);
        assert!(proof_data_exists(obj_addr), EPROOF_DATA_DOES_NOT_EXIST);
        borrow_global_mut<ProofData>(obj_addr)
    }

    inline fun borrow<T: key>(obj: Object<T>): &ProofData {
        freeze(borrow_mut(obj))
    }

    inline fun assert_owner<T: key>(owner: address, obj: Object<T>) {
        assert!(
            object::owner(obj) == owner,
            error::permission_denied(ENOT_OBJECT_OWNER),
        );
    }
}
