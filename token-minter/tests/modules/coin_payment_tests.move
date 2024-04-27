#[test_only]
module minter::coin_payment_tests {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::aptos_coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;

    use minter::coin_payment::{Self, CoinPayment};
    use minter::coin_utils;

    fun setup_test_environment(
        fx: &signer,
        user: &signer,
        creator: &signer,
        user_initial_balance: u64,
        creator_initial_balance: u64,
    ) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(fx);
        coin_utils::fund_account(&mint_cap, user, user_initial_balance);
        coin_utils::fund_account(&mint_cap, creator, creator_initial_balance);
        coin_utils::clean_up_caps(burn_cap, mint_cap);
    }

    #[test(creator = @0x123, user = @0x456, fx = @0x1)]
    fun test_create_coin_payment_with_mint_and_launchpad_fee(creator: &signer, user: &signer, fx: &signer) {
        let mint_fee = 50;
        let launchpad_fee = 10;
        let user_initial_balance = 130;
        let creator_initial_balance = 0;
        setup_test_environment(fx, user, creator, user_initial_balance, creator_initial_balance);

        let destination = signer::address_of(creator);
        let coin_payments = vector<CoinPayment<AptosCoin>>[];
        let mint_coin_payment = coin_payment::create<AptosCoin>(
            mint_fee,
            destination,
            string::utf8(b"Mint fee"),
        );
        vector::push_back(&mut coin_payments, mint_coin_payment);
        let launchpad_coin_payment = coin_payment::create<AptosCoin>(
            launchpad_fee,
            destination,
            string::utf8(b"Launchpad fee"),
        );
        vector::push_back(&mut coin_payments, launchpad_coin_payment);

        vector::for_each_ref(&coin_payments, |coin_payment| {
            let coin_payment: &CoinPayment<AptosCoin> = coin_payment;
            coin_payment::execute(user, coin_payment)
        });

        let total_cost = mint_fee + launchpad_fee;
        let user_balance = coin::balance<AptosCoin>(signer::address_of(user));
        assert!(user_balance == user_initial_balance - total_cost, 0);

        destroy_coin_payments(coin_payments);
    }

    fun destroy_coin_payments(coin_payments: vector<CoinPayment<AptosCoin>>) {
        vector::destroy(coin_payments, |coin_payment| {
            coin_payment::destroy(coin_payment)
        });
    }
}
