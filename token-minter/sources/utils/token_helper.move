module minter::token_helper {

    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};

    use aptos_token_objects::token::Token;

    public fun transfer_token(
        owner: &signer,
        to: address,
        soulbound: bool,
        token_constructor_ref: &ConstructorRef,
    ): Object<Token> {
        let token = object::object_from_constructor_ref(token_constructor_ref);
        if (soulbound) {
            transfer_soulbound_token(to, token_constructor_ref);
        } else {
            object::transfer(owner, token, to);
        };

        token
    }

    fun transfer_soulbound_token(to: address, token_constructor_ref: &ConstructorRef) {
        let transfer_ref = &object::generate_transfer_ref(token_constructor_ref);
        let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, to);
        object::disable_ungated_transfer(transfer_ref);
    }
}
