module minter::apt_payment {

    use std::error;
    use std::signer;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::object;
    use aptos_framework::object::Object;

    friend minter::token_minter;

    const ENOT_OBJECT_OWNER: u64 = 1;
    const EAPT_PAYMENT_DOES_NOT_EXIST: u64 = 2;
    const EINSUFFICIENT_PAYMENT: u64 = 3;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct AptPayment has key {
        amount: u64,
        destination: address,
    }

    public(friend) fun add_or_update_apt_payment<T: key>(
        object_signer: &signer,
        token_minter: Object<T>,
        amount: u64,
        destination: address,
    ) acquires AptPayment {
        if (is_apt_payment_enabled(signer::address_of(object_signer))) {
            let apt_payment = borrow_mut<T>(token_minter);
            apt_payment.amount = amount;
            apt_payment.destination = destination;
        } else {
            move_to(object_signer, AptPayment { amount, destination });
        }
    }

    public(friend) fun remove_apt_payment<T: key>(token_minter: Object<T>) acquires AptPayment {
        let token_minter_address = object::object_address(&token_minter);
        assert!(is_apt_payment_enabled(token_minter_address), error::not_found(EAPT_PAYMENT_DOES_NOT_EXIST));

        let AptPayment { amount: _, destination: _ } = move_from<AptPayment>(token_minter_address);
    }

    public(friend) fun execute<T: key>(
        minter: &signer,
        token_minter: Object<T>,
        amount: u64,
    ) acquires AptPayment {
        let apt_payment = borrow_mut<T>(token_minter);
        assert!(apt_payment.amount >= amount, error::invalid_argument(EINSUFFICIENT_PAYMENT));

        coin::transfer<AptosCoin>(minter, apt_payment.destination, amount);
    }

    inline fun borrow_mut<T: key>(token_minter: Object<T>): &mut AptPayment acquires AptPayment {
        let token_minter_address = object::object_address(&token_minter);
        assert!(exists<AptPayment>(token_minter_address), error::not_found(EAPT_PAYMENT_DOES_NOT_EXIST));

        borrow_global_mut<AptPayment>(token_minter_address)
    }

    #[view]
    public fun is_apt_payment_enabled(token_minter: address): bool {
        exists<AptPayment>(token_minter)
    }
}
