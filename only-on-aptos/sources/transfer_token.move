module only_on_aptos::transfer_token {

    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};

    use aptos_token_objects::token::Token;

    public fun transfer(
        owner: &signer,
        to: address,
        token_constructor_ref: &ConstructorRef,
    ): Object<Token> {
        let token = object::object_from_constructor_ref(token_constructor_ref);
        object::transfer(owner, token, to);

        token
    }

    public fun transfer_soulbound(
        to: address,
        token_constructor_ref: &ConstructorRef,
    ): Object<Token> {
        let token = object::object_from_constructor_ref(token_constructor_ref);
        let transfer_ref = &object::generate_transfer_ref(token_constructor_ref);
        let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);

        object::transfer_with_ref(linear_transfer_ref, to);
        object::disable_ungated_transfer(transfer_ref);

        token
    }
}
