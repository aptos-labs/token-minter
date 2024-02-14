module minter::whitelist {

    use std::error;
    use std::signer;
    use std::vector;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::object;
    use aptos_framework::object::Object;

    friend minter::token_minter;

    const ENOT_OBJECT_OWNER: u64 = 1;
    const EWHITELIST_ARGUMENT_MISMATCH: u64 = 2;
    const EWHITELIST_MAX_MINT_MISMATCH: u64 = 3;
    const EWHITELIST_DOES_NOT_EXIST: u64 = 4;
    const EINSUFFICIENT_MINT_REMAINING: u64 = 5;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Whitelist has key {
        minters: SmartTable<address, u64>,
    }

    public(friend) fun init_whitelist(object_signer: &signer) {
        if (!is_whitelist_enabled(signer::address_of(object_signer))) {
            move_to(object_signer, Whitelist { minters: smart_table::new() });
        }
    }

    public(friend) fun add_to_whitelist<T: key>(
        token_minter: Object<T>,
        whitelisted_addresses: vector<address>,
        max_mints_per_whitelist: vector<u64>,
    ) acquires Whitelist {
        let whitelist_length = vector::length(&whitelisted_addresses);
        assert!(
            whitelist_length == vector::length(&max_mints_per_whitelist),
            error::invalid_argument(EWHITELIST_MAX_MINT_MISMATCH),
        );

        let whitelist = borrow_mut<T>(token_minter);
        let i = 0;
        while (i < whitelist_length) {
            smart_table::add(
                &mut whitelist.minters,
                *vector::borrow(&whitelisted_addresses, i),
                *vector::borrow(&max_mints_per_whitelist, i),
            );
            i = i + 1;
        };
    }

    public(friend) fun remove_whitelist<T: key>(creator: &signer, token_minter: Object<T>) acquires Whitelist {
        assert!(object::owner(token_minter) == signer::address_of(creator), error::invalid_argument(ENOT_OBJECT_OWNER));

        let token_minter_address = object::object_address(&token_minter);
        assert!(is_whitelist_enabled(token_minter_address), error::not_found(EWHITELIST_DOES_NOT_EXIST));

        let Whitelist { minters } = move_from<Whitelist>(token_minter_address);
        smart_table::destroy(minters);
    }

    public(friend) fun execute<T: key>(
        token_minter: Object<T>,
        amount: u64,
        to: address,
    ) acquires Whitelist {
        let whitelist = borrow_mut<T>(token_minter);
        let remaining_amount = smart_table::borrow_mut(&mut whitelist.minters, to);
        assert!(*remaining_amount >= amount, error::invalid_argument(EINSUFFICIENT_MINT_REMAINING));

        *remaining_amount = *remaining_amount - amount;
    }

    /// Assert `Whitelist` object exists within `token_minter`.
    /// Return a mutable reference to it.
    inline fun borrow_mut<T: key>(token_minter: Object<T>): &mut Whitelist acquires Whitelist {
        let whitelist_address = object::object_address(&token_minter);
        assert!(is_whitelist_enabled(whitelist_address), error::not_found(EWHITELIST_DOES_NOT_EXIST));

        borrow_global_mut<Whitelist>(whitelist_address)
    }

    fun assert_token_minter_owner<T: key>(creator: address, token_minter: Object<T>) {
        assert!(object::owner(token_minter) == creator, error::invalid_argument(ENOT_OBJECT_OWNER));
    }

    #[view]
    public fun is_whitelist_enabled(token_minter: address): bool {
        exists<Whitelist>(token_minter)
    }
}
