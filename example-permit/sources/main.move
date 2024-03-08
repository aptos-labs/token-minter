module example_permit::main {
    use aptos_framework::object;
    use minter::token_minter;
    use std::ed25519;
    use std::option;
    use std::signer::{address_of};
    use std::string::{String, utf8};

    /// The provided permit is bad.
    const EBAD_PERMIT: u64 = 1;

    struct AppConfig has key {
        authority_public_key: ed25519::UnvalidatedPublicKey,
        extend_ref: object::ExtendRef,
        token_minter_obj: object::Object<token_minter::TokenMinter>,
    }

    struct MintPermit has copy, drop {
        name: String,
        description: String,
        uri: String,
        recipient_addr: address,
    }

    public entry fun init(deployer: &signer, authority_public_key: vector<u8>) {
        let constructor_ref = &object::create_object(address_of(deployer));
        let token_minter_obj = token_minter::init_token_minter_object(
            &object::generate_signer(constructor_ref),
            utf8(b"example permit"),
            option::none(),
            utf8(b"example permit"),
            utf8(b"https://example.com/example_permit"),
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            option::none(),
            true, // creator_mint_only
            false,
        );
        move_to(
            deployer,
            AppConfig {
                authority_public_key: ed25519::new_unvalidated_public_key_from_bytes(authority_public_key),
                extend_ref: object::generate_extend_ref(constructor_ref),
                token_minter_obj,
            },
        )
    }

    public entry fun mint_with_permit(
        name: String,
        description: String,
        uri: String,
        recipient_addr: address,
        permit: vector<u8>,
    ) acquires AppConfig {
        let app_config = borrow_global<AppConfig>(@example_permit);
        let mint_permit = MintPermit {
            name,
            description,
            uri,
            recipient_addr,
        };
        assert!(
            ed25519::signature_verify_strict_t(
                &ed25519::new_signature_from_bytes(permit),
                &app_config.authority_public_key,
                mint_permit,
            ),
            EBAD_PERMIT,
        );

        let creator = object::generate_signer_for_extending(&app_config.extend_ref);
        token_minter::mint_tokens_object(
            &creator,
            app_config.token_minter_obj,
            name,
            description,
            uri,
            1,
            vector[vector[]],
            vector[vector[]],
            vector[vector[]],
            vector[recipient_addr],
        );
    }

    #[test(creator = @example_permit, user = @0x456)]
    fun succeeds(creator: &signer, user: &signer) acquires AppConfig {
        let (sk, vpk) = ed25519::generate_keys();
        let pk = ed25519::public_key_into_unvalidated(vpk);
        let authority_public_key = ed25519::unvalidated_public_key_to_bytes(&pk);

        init(creator, authority_public_key);

        let name = utf8(b"Sword");
        let description = utf8(b"A fancy sword");
        let uri = utf8(b"https://example.com/sword1.png");
        let user_addr = address_of(user);

        let permit = MintPermit {
            name,
            description,
            uri,
            recipient_addr: user_addr,
        };
        let sig = ed25519::signature_to_bytes(
            &ed25519::sign_struct(&sk, permit),
        );

        mint_with_permit(
            name,
            description,
            uri,
            user_addr,
            sig,
        );
    }

    #[test(creator = @example_permit, user = @0x456)]
    #[expected_failure(abort_code = EBAD_PERMIT)]
    fun fails(creator: &signer, user: &signer) acquires AppConfig {
        let (sk, vpk) = ed25519::generate_keys();
        let pk = ed25519::public_key_into_unvalidated(vpk);
        let authority_public_key = ed25519::unvalidated_public_key_to_bytes(&pk);

        init(creator, authority_public_key);

        let name = utf8(b"Sword");
        let description = utf8(b"A fancy sword");
        let uri = utf8(b"https://example.com/sword1.png");
        let user_addr = address_of(user);

        let permit = MintPermit {
            name,
            description,
            uri,
            recipient_addr: user_addr,
        };
        let sig = ed25519::signature_to_bytes(
            &ed25519::sign_struct(&sk, permit),
        );

        mint_with_permit(
            utf8(b"The Best Sword"), // wrong name
            description,
            uri,
            user_addr,
            sig,
        );
    }
}