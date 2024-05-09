module minter::mint_stage {

    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_std::simple_map;
    use aptos_std::simple_map::SimpleMap;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object};
    use aptos_framework::timestamp;

    /// The mint stage start time must be less than the mint stage end time.
    const EINVALID_START_TIME: u64 = 1;
    /// The mint stage end time must be greater than the current time.
    const EINVALID_END_TIME: u64 = 2;
    /// The mint stage has not started yet.
    const EMINT_STAGE_NOT_STARTED: u64 = 3;
    /// The mint stage has ended.
    const EMINT_STAGE_ENDED: u64 = 4;
    /// The mint stage allowlist balance is insufficient.
    const EINSUFFICIENT_ALLOWLIST_BALANCE: u64 = 5;
    /// The user is not allowlisted.
    const EUSER_NOT_ALLOWLISTED: u64 = 6;
    /// The caller is not the owner of the mint stage.
    const ENOT_OWNER: u64 = 7;
    /// The mint stage does not exist.
    const ESTAGE_DOES_NOT_EXIST: u64 = 8;
    /// The mint stage data does not exist.
    const EMINT_STAGE_DATA_DOES_NOT_EXIST: u64 = 9;
    /// The mint stage max per user balance is insufficient.
    const EINSUFFICIENT_MAX_PER_USER_BALANCE: u64 = 10;
    /// The amount of tokens should be greater than zero.
    const EINSUFFICIENT_AMOUNT: u64 = 11;


    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct MintStageData has key {
        /// stage ("private", "presale", "public", etc.) to mint stage mapping.
        mint_stages: SimpleMap<String, MintStage>,
        /// Stages sorted from the earliest start time.
        stages: vector<String>,
    }

    struct MintStage has store {
        /// The start time of the mint stage.
        start_time: u64,
        /// The end time of the mint stage.
        end_time: u64,
        /// Allowlist of addresses with their mint allowance.
        /// Empty allowlist means there are no restrictions.
        allowlist: SmartTable<address, u64>,
        /// If allowlist is empty, then everyone can mint but configurable with an optional max limit.
        no_allowlist: NoAllowlist,
    }

    struct NoAllowlist has store {
        max_per_user: Option<u64>,
        user_balances: SmartTable<address, u64>,
    }

    #[event]
    /// Event emitted when a new mint stage is created.
    struct CreateMintStage has drop, store {
        mint_stage_data: Object<MintStageData>,
        stage: String,
        start_time: u64,
        end_time: u64,
        no_allowlist_max_per_user: Option<u64>,
    }

    #[event]
    /// Event emitted when a mint stage is removed.
    struct RemoveMintStage has drop, store {
        mint_stage_data: Object<MintStageData>,
        stage: String,
    }

    /// Create a new mint stage with the specified start and end time.
    /// The `MintStageData` resource is stored under the constructor ref address.
    public fun init(
        constructor_ref: &ConstructorRef,
        start_time: u64,
        end_time: u64,
        stage: String,
        max_per_user: Option<u64>,
    ): Object<MintStageData> acquires MintStageData {
        let object_signer = &object::generate_signer(constructor_ref);
        create(object_signer, start_time, end_time, stage, max_per_user)
    }

    /// Create a new mint stage with the specified start and end time.
    /// The `MintStageData` resource is stored under the object signer address.
    /// This function is used to extend the current object.
    public fun create(
        object_signer: &signer,
        start_time: u64,
        end_time: u64,
        stage: String,
        no_allowlist_max_per_user: Option<u64>,
    ): Object<MintStageData> acquires MintStageData {
        valid_start_and_end_time(start_time, end_time);

        let object_addr = signer::address_of(object_signer);
        if (!exists<MintStageData>(object_addr)) {
            move_to(object_signer, MintStageData {
                mint_stages: simple_map::new(),
                stages: vector[],
            });
        };

        let mint_stage_data = borrow_global_mut<MintStageData>(object_addr);
        simple_map::add(&mut mint_stage_data.mint_stages, stage, MintStage {
            start_time,
            end_time,
            allowlist: smart_table::new(),
            no_allowlist: NoAllowlist {
                max_per_user: no_allowlist_max_per_user,
                user_balances: smart_table::new(),
            },
        });

        add_to_stages(
            &mut mint_stage_data.stages,
            stage,
            start_time,
            end_time,
            &mint_stage_data.mint_stages,
        );

        let mint_stage_data = object::address_to_object(object_addr);
        event::emit(CreateMintStage {
            mint_stage_data,
            stage,
            start_time,
            end_time,
            no_allowlist_max_per_user,
        });

        mint_stage_data
    }

    public fun remove_stage<T: key>(owner: &signer, obj: Object<T>, stage: String) acquires MintStageData {
        let stages = &mut authorized_borrow_mut(owner, obj).mint_stages;
        assert!(simple_map::contains_key(stages, &stage), error::not_found(ESTAGE_DOES_NOT_EXIST));

        let (_, mint_stage) = simple_map::remove(stages, &stage);
        let MintStage { start_time: _, end_time: _, allowlist, no_allowlist } = mint_stage;
        let NoAllowlist { max_per_user: _, user_balances } = no_allowlist;
        smart_table::destroy(allowlist);
        smart_table::destroy(user_balances);

        event::emit(RemoveMintStage { mint_stage_data: object::convert(obj), stage });
    }

    /// Executes the earliest stage if it is active.
    /// Returns the stage name if the stage is active and executed, otherwise returns `none`.
    public fun execute_earliest_stage<T: key>(
        user: &signer,
        obj: Object<T>,
        amount: u64,
    ): Option<String> acquires MintStageData {
        let stages = stages(obj);
        for (i in 0..vector::length(&stages)) {
            let stage = *vector::borrow(&stages, i);
            if (is_active(obj, stage)) {
                assert_active_and_execute(user, obj, stage, amount);
                return option::some(stage)
            }
        };
        option::none()
    }

    /// This function is to be called to verify if the user is allowed to mint tokens in the specified stage.
    /// The stage must be active, and the user must be in the allowlist with enough allowance.
    /// If allowlist is empty, this means there is no allowlist and only start and end times are verified.
    public fun assert_active_and_execute<T: key>(
        user: &signer,
        obj: Object<T>,
        stage: String,
        amount: u64,
    ) acquires MintStageData {
        let mint_stage = borrow_mut_mint_stage(obj, stage);
        let current_time = timestamp::now_seconds();
        assert!(amount > 0, error::invalid_argument(EINSUFFICIENT_AMOUNT));
        assert!(current_time >= mint_stage.start_time, error::invalid_state(EMINT_STAGE_NOT_STARTED));
        assert!(current_time < mint_stage.end_time, error::invalid_state(EMINT_STAGE_ENDED));

        let user_addr = signer::address_of(user);
        // Check if the user is in the allowlist and has enough allowance.
        // If the allowlist is empty, this means there is no allowlist and everyone can mint.
        if (smart_table::length(&mint_stage.allowlist) > 0) {
            let remaining = allowlist_balance_internal(&mint_stage.allowlist, user_addr);
            assert!(
                remaining >= amount,
                error::invalid_state(EINSUFFICIENT_ALLOWLIST_BALANCE),
            );
            smart_table::upsert(&mut mint_stage.allowlist, user_addr, remaining - amount);
        } else if (option::is_some(&mint_stage.no_allowlist.max_per_user)) {
            // If the `max_per_user` is set, then check if the user has enough balance.
            let max_per_user = *option::borrow(&mint_stage.no_allowlist.max_per_user);
            let balance = *smart_table::borrow_mut_with_default(
                &mut mint_stage.no_allowlist.user_balances,
                user_addr,
                0,
            );
            let total_balance = balance + amount;
            assert!(
                total_balance <= max_per_user,
                error::invalid_state(EINSUFFICIENT_MAX_PER_USER_BALANCE),
            );
            smart_table::upsert(&mut mint_stage.no_allowlist.user_balances, user_addr, total_balance);
        }
    }

    public fun set_start_and_end_time<T: key>(
        owner: &signer,
        obj: Object<T>,
        stage: String,
        start_time: u64,
        end_time: u64,
    ) acquires MintStageData {
        valid_start_and_end_time(start_time, end_time);

        let mint_stage = authorized_borrow_mut_mint_stage(owner, obj, stage);
        mint_stage.start_time = start_time;
        mint_stage.end_time = end_time;
    }

    /// Add an address to the allowlist with a specific allowance.
    /// If the allowlist is not set in the `mint_stage`, it will be created for the mint stage.
    public fun add_to_allowlist<T: key>(
        owner: &signer,
        obj: Object<T>,
        stage: String,
        addr: address,
        amount: u64
    ) acquires MintStageData {
        let mint_stage = authorized_borrow_mut_mint_stage(owner, obj, stage);
        smart_table::upsert(&mut mint_stage.allowlist, addr, amount);
    }

    public fun remove_from_allowlist<T: key>(
        owner: &signer,
        obj: Object<T>,
        stage: String,
        addr: address,
    ) acquires MintStageData {
        let mint_stage = authorized_borrow_mut_mint_stage(owner, obj, stage);
        smart_table::remove(&mut mint_stage.allowlist, addr);
    }

    public fun remove_everyone_from_allowlist<T: key>(
        owner: &signer,
        obj: Object<T>,
        stage: String,
    ) acquires MintStageData {
        let mint_stage = authorized_borrow_mut_mint_stage(owner, obj, stage);
        smart_table::clear(&mut mint_stage.allowlist);
    }

    public fun set_no_allowlist_max_per_user<T: key>(
        owner: &signer,
        obj: Object<T>,
        stage: String,
        max_per_user: Option<u64>,
    ) acquires MintStageData {
        let mint_stage = authorized_borrow_mut_mint_stage(owner, obj, stage);
        mint_stage.no_allowlist.max_per_user = max_per_user;
    }

    public fun destroy<T: key>(owner: &signer, obj: Object<T>) acquires MintStageData {
        assert_owner(owner, obj);

        let MintStageData {
            mint_stages,
            stages: _,
        } = move_from<MintStageData>(object::object_address(&obj));

        simple_map::destroy(mint_stages, |_stage| {}, |mint_stage| {
            let MintStage { start_time: _, end_time: _, allowlist, no_allowlist } = mint_stage;
            let NoAllowlist { max_per_user: _, user_balances } = no_allowlist;
            smart_table::destroy(allowlist);
            smart_table::destroy(user_balances);
        });
    }

    // ====================================== View Functions ====================================== //

    #[view]
    public fun is_active<T: key>(obj: Object<T>, stage: String): bool acquires MintStageData {
        let mint_stage = borrow_mint_stage(obj, stage);
        let current_time = timestamp::now_seconds();
        current_time >= mint_stage.start_time && current_time < mint_stage.end_time
    }

    #[view]
    public fun allowlist_balance<T: key>(
        obj: Object<T>,
        stage: String,
        addr: address,
    ): u64 acquires MintStageData {
        let mint_stage = borrow_mint_stage(obj, stage);
        allowlist_balance_internal(&mint_stage.allowlist, addr)
    }

    #[view]
    public fun is_allowlisted<T: key>(
        obj: Object<T>,
        stage: String,
        addr: address
    ): bool acquires MintStageData {
        let mint_stage = simple_map::borrow(&borrow(obj).mint_stages, &stage);
        smart_table::contains(&mint_stage.allowlist, addr)
    }

    #[view]
    public fun allowlist_count<T: key>(obj: Object<T>, stage: String): u64 acquires MintStageData {
        let mint_stage = borrow_mint_stage(obj, stage);
        smart_table::length(&mint_stage.allowlist)
    }

    #[view]
    public fun is_stage_allowlisted<T: key>(obj: Object<T>, stage: String): bool acquires MintStageData {
        let mint_stage = simple_map::borrow(&borrow(obj).mint_stages, &stage);
        smart_table::length(&mint_stage.allowlist) > 0
    }

    #[view]
    public fun start_time<T: key>(obj: Object<T>, stage: String): u64 acquires MintStageData {
        borrow_mint_stage(obj, stage).start_time
    }

    #[view]
    public fun end_time<T: key>(obj: Object<T>, stage: String): u64 acquires MintStageData {
        borrow_mint_stage(obj, stage).end_time
    }

    #[view]
    /// This function returns the categories sorted from the earliest start time.
    public fun stages<T: key>(obj: Object<T>): vector<String> acquires MintStageData {
        borrow(obj).stages
    }

    #[view]
    public fun mint_stage_data_exists(obj_addr: address): bool {
        exists<MintStageData>(obj_addr)
    }

    #[view]
    public fun no_allowlist_max_per_user<T: key>(
        obj: Object<T>,
        stage: String,
    ): Option<u64> acquires MintStageData {
        let mint_stage = borrow_mint_stage(obj, stage);
        mint_stage.no_allowlist.max_per_user
    }

    #[view]
    public fun user_balance_in_no_allowlist<T: key>(
        obj: Object<T>,
        stage: String,
        user: address,
    ): Option<u64> acquires MintStageData {
        let mint_stage = borrow_mint_stage(obj, stage);
        if (smart_table::contains(&mint_stage.no_allowlist.user_balances, user)) {
            let max_per_user = *option::borrow(&mint_stage.no_allowlist.max_per_user);
            let balance = *smart_table::borrow(&mint_stage.no_allowlist.user_balances, user);
            option::some(max_per_user - balance)
        } else {
            mint_stage.no_allowlist.max_per_user
        }
    }

    /// This function adds the new stage based on the start and end time of the mint stage.
    /// The categories are sorted from the earliest start time to the latest.
    inline fun add_to_stages(
        stages: &mut vector<String>,
        new_stage: String,
        new_start_time: u64,
        new_end_time: u64,
        mint_stages: &SimpleMap<String, MintStage>,
    ) {
        let len = vector::length(stages);
        let index = 0;

        while (index < len) {
            let current_stage = vector::borrow(stages, index);
            let current_stage = simple_map::borrow(mint_stages, current_stage);
            if (new_start_time < current_stage.start_time
                || (new_start_time == current_stage.start_time && new_end_time < current_stage.end_time)) {
                break
            };
            index = index + 1;
        };

        vector::insert(stages, index, new_stage);
    }

    inline fun allowlist_balance_internal(allowlist: &SmartTable<address, u64>, addr: address): u64 {
        assert!(smart_table::contains(allowlist, addr), error::invalid_state(EUSER_NOT_ALLOWLISTED));
        *smart_table::borrow(allowlist, addr)
    }

    inline fun authorized_borrow_mut_mint_stage<T: key>(
        owner: &signer,
        obj: Object<T>,
        stage: String,
    ): &mut MintStage acquires MintStageData {
        let mint_stages = &mut authorized_borrow_mut(owner, obj).mint_stages;
        assert!(simple_map::contains_key(mint_stages, &stage), error::not_found(ESTAGE_DOES_NOT_EXIST));
        simple_map::borrow_mut(mint_stages, &stage)
    }

    inline fun authorized_borrow_mut<T: key>(owner: &signer, obj: Object<T>): &mut MintStageData {
        assert_owner(owner, obj);

        let obj_addr = object::object_address(&obj);
        assert!(mint_stage_data_exists(obj_addr), error::not_found(EMINT_STAGE_DATA_DOES_NOT_EXIST));
        borrow_global_mut(obj_addr)
    }

    inline fun borrow<T: key>(obj: Object<T>): &MintStageData {
        freeze(borrow_mut(obj))
    }

    inline fun borrow_mut<T: key>(obj: Object<T>): &mut MintStageData {
        let obj_addr = object::object_address(&obj);
        assert!(mint_stage_data_exists(obj_addr), error::not_found(EMINT_STAGE_DATA_DOES_NOT_EXIST));
        borrow_global_mut<MintStageData>(obj_addr)
    }

    inline fun borrow_mut_mint_stage<T: key>(obj: Object<T>, stage: String): &mut MintStage acquires MintStageData {
        let mint_stages = &mut borrow_mut(obj).mint_stages;
        assert!(simple_map::contains_key(mint_stages, &stage), error::not_found(ESTAGE_DOES_NOT_EXIST));
        simple_map::borrow_mut(mint_stages, &stage)
    }

    inline fun borrow_mint_stage<T: key>(obj: Object<T>, stage: String): &MintStage acquires MintStageData {
        borrow_mut_mint_stage(obj, stage)
    }

    inline fun valid_start_and_end_time(start_time: u64, end_time: u64) {
        assert!(start_time < end_time, error::invalid_argument(EINVALID_START_TIME));
        assert!(end_time > timestamp::now_seconds(), error::invalid_argument(EINVALID_END_TIME));
    }

    inline fun assert_owner<T: key>(owner: &signer, obj: Object<T>) {
        assert!(object::is_owner(obj, signer::address_of(owner)), error::unauthenticated(ENOT_OWNER));
    }
}
