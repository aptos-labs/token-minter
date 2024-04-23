module minter::mint_stage {

    use std::error;
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
    /// The mint stage allowance is insufficient.
    const EINSUFFICIENT_ALLOWANCE: u64 = 5;
    /// The user is not allowlisted.
    const EUSER_NOT_ALLOWLISTED: u64 = 6;
    /// The caller is not the owner of the mint stage.
    const ENOT_OWNER: u64 = 7;
    /// The mint stage category does not exist.
    const ECATEGORY_DOES_NOT_EXIST: u64 = 8;
    /// The mint stage data does not exist.
    const EMINT_STAGE_DATA_DOES_NOT_EXIST: u64 = 9;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct MintStageData has key {
        /// Category ("private", "presale", "public", etc.) to mint stage mapping.
        mint_stages: SimpleMap<String, MintStage>,
        /// Categories sorted from the earliest start time.
        categories: vector<String>,
    }

    struct MintStage has store {
        /// The start time of the mint stage.
        start_time: u64,
        /// The end time of the mint stage.
        end_time: u64,
        /// Allowlist of addresses with their mint allowance.
        /// Empty allowlist means there are no restrictions.
        allowlist: SmartTable<address, u64>,
    }

    #[event]
    /// Event emitted when a new mint stage is created.
    struct CreateMintStage has drop, store {
        mint_stage_data: Object<MintStageData>,
        category: String,
        start_time: u64,
        end_time: u64,
    }

    #[event]
    /// Event emitted when a mint stage is removed.
    struct RemoveMintStage has drop, store {
        mint_stage_data: Object<MintStageData>,
        category: String,
    }

    /// Create a new mint stage with the specified start and end time.
    /// The `MintStageData` resource is stored under the constructor ref address.
    public fun init(
        constructor_ref: &ConstructorRef,
        start_time: u64,
        end_time: u64,
        category: String,
    ): Object<MintStageData> acquires MintStageData {
        let object_signer = &object::generate_signer(constructor_ref);
        create(object_signer, start_time, end_time, category)
    }

    /// Create a new mint stage with the specified start and end time.
    /// The `MintStageData` resource is stored under the object signer address.
    /// This function is used to extend the current object.
    public fun create(
        object_signer: &signer,
        start_time: u64,
        end_time: u64,
        category: String,
    ): Object<MintStageData> acquires MintStageData {
        valid_start_and_end_time(start_time, end_time);

        let object_addr = signer::address_of(object_signer);
        if (!exists<MintStageData>(object_addr)) {
            move_to(object_signer, MintStageData {
                mint_stages: simple_map::new(),
                categories: vector[]
            });
        };

        let mint_stage_data = borrow_global_mut<MintStageData>(object_addr);
        simple_map::add(&mut mint_stage_data.mint_stages, category, MintStage {
            start_time,
            end_time,
            allowlist: smart_table::new(),
        });

        add_to_categories(
            &mut mint_stage_data.categories,
            category,
            start_time,
            end_time,
            &mint_stage_data.mint_stages,
        );

        let mint_stage_data = object::address_to_object(object_addr);
        event::emit(CreateMintStage {
            mint_stage_data,
            category,
            start_time,
            end_time,
        });

        mint_stage_data
    }

    public fun remove_stage<T: key>(owner: &signer, obj: Object<T>, category: String) acquires MintStageData {
        let stages = &mut authorized_borrow_mut(owner, obj).mint_stages;
        assert!(simple_map::contains_key(stages, &category), error::not_found(ECATEGORY_DOES_NOT_EXIST));

        let (_, mint_stage) = simple_map::remove(stages, &category);
        let MintStage { start_time: _, end_time: _, allowlist } = mint_stage;
        smart_table::destroy(allowlist);

        event::emit(RemoveMintStage { mint_stage_data: object::convert(obj), category });
    }

    /// This function is to be called to verify if the user is allowed to mint tokens in the specified category stage.
    /// The stage must be active, and the user must be in the allowlist with enough allowance.
    /// If allowlist is empty, this means there is no allowlist and only start and end times are verified.
    public fun assert_active_and_execute<T: key>(
        owner: &signer,
        obj: Object<T>,
        category: String,
        address: address,
        amount: u64,
    ) acquires MintStageData {
        let mint_stage = authorized_borrow_mut_mint_stage(owner, obj, category);
        let current_time = timestamp::now_seconds();

        assert!(current_time >= mint_stage.start_time, error::invalid_state(EMINT_STAGE_NOT_STARTED));
        assert!(current_time < mint_stage.end_time, error::invalid_state(EMINT_STAGE_ENDED));

        // Check if the user is in the allowlist and has enough allowance.
        // If the allowlist is empty, this means there is no allowlist and everyone can mint.
        if (smart_table::length(&mint_stage.allowlist) > 0) {
            let remaining = balance_internal(&mint_stage.allowlist, address);
            assert!(remaining >= amount, error::invalid_state(EINSUFFICIENT_ALLOWANCE));
            smart_table::upsert(&mut mint_stage.allowlist, address, remaining - amount);
        };
    }

    public fun set_start_and_end_time<T: key>(
        owner: &signer,
        obj: Object<T>,
        category: String,
        start_time: u64,
        end_time: u64,
    ) acquires MintStageData {
        valid_start_and_end_time(start_time, end_time);

        let mint_stage = authorized_borrow_mut_mint_stage(owner, obj, category);
        mint_stage.start_time = start_time;
        mint_stage.end_time = end_time;
    }

    /// Add an address to the allowlist with a specific allowance.
    /// If the allowlist is not set in the `mint_stage`, it will be created for the mint stage.
    public fun add_to_allowlist<T: key>(
        owner: &signer,
        obj: Object<T>,
        category: String,
        address: address,
        amount: u64
    ) acquires MintStageData {
        let mint_stage = authorized_borrow_mut_mint_stage(owner, obj, category);
        smart_table::upsert(&mut mint_stage.allowlist, address, amount);
    }

    public fun remove_from_allowlist<T: key>(
        owner: &signer,
        obj: Object<T>,
        category: String,
        address: address,
    ) acquires MintStageData {
        let mint_stage = authorized_borrow_mut_mint_stage(owner, obj, category);
        smart_table::remove(&mut mint_stage.allowlist, address);
    }

    public fun destroy<T: key>(owner: &signer, obj: Object<T>) acquires MintStageData {
        assert_owner(owner, obj);

        let MintStageData {
            mint_stages,
            categories: _,
        } = move_from<MintStageData>(object::object_address(&obj));

        simple_map::destroy(mint_stages, |_category| {}, |mint_stage| {
            let MintStage { start_time: _, end_time: _, allowlist } = mint_stage;
            smart_table::destroy(allowlist);
        });
    }

    // ====================================== View Functions ====================================== //

    #[view]
    public fun is_active<T: key>(obj: Object<T>, category: String): bool acquires MintStageData {
        let mint_stage = borrow_mint_stage(obj, category);
        let current_time = timestamp::now_seconds();
        current_time >= mint_stage.start_time && current_time < mint_stage.end_time
    }

    #[view]
    public fun balance<T: key>(
        obj: Object<T>,
        category: String,
        addr: address,
    ): u64 acquires MintStageData {
        let mint_stage = borrow_mint_stage(obj, category);
        balance_internal(&mint_stage.allowlist, addr)
    }

    #[view]
    public fun is_allowlisted<T: key>(
        obj: Object<T>,
        category: String,
        addr: address
    ): bool acquires MintStageData {
        let mint_stage = simple_map::borrow(&borrow(obj).mint_stages, &category);
        smart_table::contains(&mint_stage.allowlist, addr)
    }

    #[view]
    public fun start_time<T: key>(obj: Object<T>, category: String): u64 acquires MintStageData {
        borrow_mint_stage(obj, category).start_time
    }

    #[view]
    public fun end_time<T: key>(obj: Object<T>, category: String): u64 acquires MintStageData {
        borrow_mint_stage(obj, category).end_time
    }

    #[view]
    /// This function returns the categories sorted from the earliest start time.
    public fun categories<T: key>(obj: Object<T>): vector<String> acquires MintStageData {
        borrow(obj).categories
    }

    #[view]
    public fun mint_stage_data_exists(obj_addr: address): bool {
        exists<MintStageData>(obj_addr)
    }

    /// This function adds the new category based on the start and end time of the mint stage.
    /// The categories are sorted from the earliest start time to the latest.
    inline fun add_to_categories(
        categories: &mut vector<String>,
        new_category: String,
        new_start_time: u64,
        new_end_time: u64,
        mint_stages: &SimpleMap<String, MintStage>,
    ) {
        let len = vector::length(categories);
        let index = 0;

        while (index < len) {
            let current_category = vector::borrow(categories, index);
            let current_stage = simple_map::borrow(mint_stages, current_category);
            if (new_start_time < current_stage.start_time
                    || (new_start_time == current_stage.start_time && new_end_time < current_stage.end_time)) {
                break;
            };
            index = index + 1;
        };

        vector::insert(categories, index, new_category);
    }

    inline fun balance_internal(allowlist: &SmartTable<address, u64>, addr: address): u64 {
        assert!(smart_table::contains(allowlist, addr), error::invalid_state(EUSER_NOT_ALLOWLISTED));
        *smart_table::borrow(allowlist, addr)
    }

    inline fun authorized_borrow_mut_mint_stage<T: key>(
        owner: &signer,
        obj: Object<T>,
        category: String,
    ): &mut MintStage acquires MintStageData {
        let mint_stages = &mut authorized_borrow_mut(owner, obj).mint_stages;
        assert!(simple_map::contains_key(mint_stages, &category), error::not_found(ECATEGORY_DOES_NOT_EXIST));
        simple_map::borrow_mut(mint_stages, &category)
    }

    inline fun authorized_borrow_mut<T: key>(owner: &signer, obj: Object<T>): &mut MintStageData {
        assert_owner(owner, obj);

        let obj_addr = object::object_address(&obj);
        assert!(mint_stage_data_exists(obj_addr), error::not_found(EMINT_STAGE_DATA_DOES_NOT_EXIST));
        borrow_global_mut(obj_addr)
    }

    inline fun borrow<T: key>(obj: Object<T>): &MintStageData {
        let obj_addr = object::object_address(&obj);
        assert!(mint_stage_data_exists(obj_addr), error::not_found(EMINT_STAGE_DATA_DOES_NOT_EXIST));
        borrow_global(obj_addr)
    }

    inline fun borrow_mint_stage<T: key>(obj: Object<T>, category: String): &MintStage acquires MintStageData {
        let mint_stages = &borrow(obj).mint_stages;
        assert!(simple_map::contains_key(mint_stages, &category), error::not_found(ECATEGORY_DOES_NOT_EXIST));
        simple_map::borrow(mint_stages, &category)
    }

    inline fun valid_start_and_end_time(start_time: u64, end_time: u64) {
        assert!(start_time < end_time, error::invalid_argument(EINVALID_START_TIME));
        assert!(end_time > timestamp::now_seconds(), error::invalid_argument(EINVALID_END_TIME));
    }

    inline fun assert_owner<T: key>(owner: &signer, obj: Object<T>) {
        assert!(object::is_owner(obj, signer::address_of(owner)), error::unauthenticated(ENOT_OWNER));
    }
}
