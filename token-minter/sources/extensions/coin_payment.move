module minter::coin_payment {

    use std::error;
    use std::signer;
    use std::string::String;
    use aptos_framework::coin;
    use aptos_framework::event;

    /// Amount must be greater than zero.
    const EINVALID_AMOUNT: u64 = 1;
    /// Insufficient coin balance to make the payment.
    const EINSUFFICIENT_BALANCE: u64 = 2;

    struct CoinPayment<phantom T> has copy, drop, store {
        /// The amount of coin to be paid.
        amount: u64,
        /// The address to which the coin is to be paid to.
        destination: address,
        /// The category of this payment, e.g. mint fee, launchpad fee
        category: String,
    }

    #[event]
    /// Event emitted when a coin payment of type `T` is made.
    struct CoinPaymentEvent<phantom T> has drop, store {
        amount: u64,
        destination: address,
        category: String,
    }

    public fun create<T>(amount: u64, destination: address, category: String): CoinPayment<T> {
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));

        CoinPayment<T> { amount, destination, category }
    }

    public fun execute<T>(minter: &signer, coin_payment: &CoinPayment<T>) {
        let amount = amount(coin_payment);
        assert!(
            coin::balance<T>(signer::address_of(minter)) >= amount,
            error::invalid_state(EINSUFFICIENT_BALANCE),
        );

        let destination = destination(coin_payment);
        coin::transfer<T>(minter, destination, amount);

        event::emit(CoinPaymentEvent<T> {
            amount,
            destination,
            category: category(coin_payment),
        });
    }

    public fun amount<T>(coin_payment: &CoinPayment<T>): u64 {
        coin_payment.amount
    }

    public fun destination<T>(coin_payment: &CoinPayment<T>): address {
        coin_payment.destination
    }

    public fun category<T>(coin_payment: &CoinPayment<T>): String {
        coin_payment.category
    }
}
