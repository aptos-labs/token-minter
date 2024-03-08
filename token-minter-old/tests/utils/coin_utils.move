#[test_only]
module minter::coin_utils {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::aptos_coin;
    use aptos_framework::coin;
    use aptos_framework::coin::{BurnCapability, MintCapability};

    public fun setup_user_and_creator_coin_balances(
        fx: &signer,
        user: &signer,
        creator: &signer,
        launchpad: &signer,
        user_initial_balance: u64,
        creator_initial_balance: u64,
        launchpad_initial_balance: u64,
    ) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(fx);
        fund_account(&mint_cap, user, user_initial_balance);
        fund_account(&mint_cap, creator, creator_initial_balance);
        fund_account(&mint_cap, launchpad, launchpad_initial_balance);
        clean_up_caps(burn_cap, mint_cap);
    }

    public fun fund_account<CoinType>(mint_cap: &MintCapability<CoinType>, to: &signer, amount: u64) {
        let to_address = signer::address_of(to);
        if (!account::exists_at(to_address)) {
            account::create_account_for_test(to_address);
        };

        coin::register<CoinType>(to);
        coin::deposit(to_address, coin::mint(amount, mint_cap));
    }

    public fun clean_up_caps<CoinType>(burn_cap: BurnCapability<CoinType>, mint_cap: MintCapability<CoinType>) {
        coin::destroy_burn_cap<CoinType>(burn_cap);
        coin::destroy_mint_cap<CoinType>(mint_cap);
    }
}
