module minter::mint_stage {

    use std::error;
    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, DeleteRef, ExtendRef, Object};
    use aptos_framework::timestamp;

    use aptos_token_objects::collection::Collection;

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
    /// Allowlist does not exist on the collection
    const EALLOWLIST_DOES_NOT_EXIST: u64 = 12;
    /// Public stage with limit does not exist on the collection
    const EPUBLIC_STAGE_WITH_LIMIT_DOES_NOT_EXIST: u64 = 13;
    /// The mint stage does not exist on the collection
    const EMINT_STAGE_DOES_NOT_EXIST: u64 = 14;
    /// A mint stage cannot have multiple stages
    const ESTAGE_CANNOT_HAVE_MULTIPLE_STAGES: u64 = 15;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct MintStageData has key {
        mint_stages: vector<Object<MintStage>>,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct MintStage has key {
        name: String,
        start_time: u64,
        end_time: u64,
        extend_ref: ExtendRef,
        delete_ref: DeleteRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Allowlist has key {
        /// Mapping from user address to remaining mint amount
        mint_allowances: SmartTable<address, u64>,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct PublicMintStageWithLimit has key {
        max_per_user: u64,
        user_balances: SmartTable<address, u64>,
    }

    #[event]
    struct CreateMintStage has drop, store {
        mint_stage_data: Object<MintStageData>,
        mint_stage: Object<MintStage>,
        name: String,
        start_time: u64,
        end_time: u64,
    }

    #[event]
    struct RemoveMintStage has drop, store {
        mint_stage_data: Object<MintStageData>,
        mint_stage: Object<MintStage>,
        name: String,
    }

    #[event]
    struct UpdateMintStage has drop, store {
        mint_stage_data: Object<MintStageData>,
        mint_stage: Object<MintStage>,
        old_name: String,
        new_name: String,
        old_start_time: u64,
        new_start_time: u64,
        old_end_time: u64,
        new_end_time: u64,
    }

    public fun init(
        collection_constructor_ref: &ConstructorRef,
        name: String,
        start_time: u64,
        end_time: u64,
    ): Object<MintStageData> acquires MintStageData, MintStage {
        let collection_signer = &object::generate_signer(collection_constructor_ref);
        create(collection_signer, name, start_time, end_time)
    }

    public fun create(
        collection_signer: &signer,
        name: String,
        start_time: u64,
        end_time: u64,
    ): Object<MintStageData> acquires MintStageData, MintStage {
        valid_start_and_end_time(start_time, end_time);

        let collection_addr = signer::address_of(collection_signer);
        if (!exists<MintStageData>(collection_addr)) {
            move_to(collection_signer, MintStageData {
                mint_stages: vector[],
            });
        };

        let mint_stage_data = object::address_to_object(collection_addr);
        let mint_stage = create_mint_stage_object(collection_addr, name, start_time, end_time);
        add_to_stages(&mut borrow_mut(mint_stage_data).mint_stages, mint_stage);

        let mint_stage_data = object::convert(mint_stage_data);
        event::emit(CreateMintStage {
            mint_stage_data: object::convert(mint_stage_data),
            mint_stage,
            name,
            start_time,
            end_time,
        });

        mint_stage_data
    }

    public fun remove(
        owner: &signer,
        collection: Object<Collection>,
        index: u64,
    ) acquires MintStageData, MintStage, Allowlist, PublicMintStageWithLimit {
        let mint_stages = &mut authorized_borrow_mut(owner, collection).mint_stages;
        let mint_stage_obj = vector::remove(mint_stages, index);
        let name = mint_stage_name(mint_stage_obj);
        destroy_mint_stage(mint_stage_obj);

        event::emit(RemoveMintStage { mint_stage_data: object::convert(collection), mint_stage: mint_stage_obj, name });
    }

    public fun update(
        owner: &signer,
        collection: Object<Collection>,
        index: u64,
        new_name: String,
        new_start_time: u64,
        new_end_time: u64,
    ) acquires MintStageData, MintStage {
        valid_start_and_end_time(new_start_time, new_end_time);

        let mint_stages = &mut authorized_borrow_mut(owner, collection).mint_stages;
        let mint_stage_obj = vector::remove(mint_stages, index);

        let mint_stage = borrow_mut_mint_stage_from_object(mint_stage_obj);
        let old_name = mint_stage.name;
        let old_start_time = mint_stage.start_time;
        let old_end_time = mint_stage.end_time;
        mint_stage.name = new_name;
        mint_stage.start_time = new_start_time;
        mint_stage.end_time = new_end_time;

        add_to_stages(mint_stages, mint_stage_obj);

        event::emit(UpdateMintStage {
            mint_stage_data: object::convert(collection),
            mint_stage: mint_stage_obj,
            old_name,
            new_name,
            old_start_time,
            new_start_time,
            old_end_time,
            new_end_time,
        });
    }

    public fun execute_earliest_stage(
        user: &signer,
        collection: Object<Collection>,
        amount: u64,
    ): Option<u64> acquires MintStageData, MintStage, Allowlist, PublicMintStageWithLimit {
        let stages = stages(collection);
        let inactive_indexes = vector[];
        for (index in 0..vector::length(&stages)) {
            if (is_active(collection, index)) {
                assert_active_and_execute(user, collection, index, amount);
                remove_inactive_indexes(&mut borrow_mut(collection).mint_stages, &mut inactive_indexes);
                return option::some(index)
            } else {
                let (_, mint_stage_obj) = borrow_mut_mint_stage(collection, index);
                if (timestamp::now_seconds() >= mint_stage_end_time(mint_stage_obj)) {
                    // Delete mint stage object if the mint stage has ended
                    destroy_mint_stage(mint_stage_obj);
                    vector::push_back(&mut inactive_indexes, index);
                }
            }
        };
        remove_inactive_indexes(&mut borrow_mut(collection).mint_stages, &mut inactive_indexes);
        option::none()
    }

    public fun assert_active_and_execute(
        user: &signer,
        collection: Object<Collection>,
        index: u64,
        amount: u64,
    ) acquires MintStageData, MintStage, Allowlist, PublicMintStageWithLimit {
        let (mint_stage, mint_stage_obj) = get_mint_stage(&mut borrow_mut(collection).mint_stages, index);
        let current_time = timestamp::now_seconds();
        assert!(amount > 0, error::invalid_argument(EINSUFFICIENT_AMOUNT));
        assert!(current_time >= mint_stage.start_time, error::invalid_state(EMINT_STAGE_NOT_STARTED));
        assert!(current_time < mint_stage.end_time, error::invalid_state(EMINT_STAGE_ENDED));

        let user_addr = signer::address_of(user);

        if (allowlist_exists(mint_stage_obj)) {
            let allowlist = borrow_mut_allowlist(mint_stage_obj);
            let remaining = allowlist_balance_internal(&allowlist.mint_allowances, user_addr);
            assert!(
                remaining >= amount,
                error::invalid_state(EINSUFFICIENT_ALLOWLIST_BALANCE),
            );
            smart_table::upsert(&mut allowlist.mint_allowances, user_addr, remaining - amount);
        };
        if (public_stage_with_limit_exists(mint_stage_obj)) {
            let public_stage = borrow_mut_public_stage_with_limit(mint_stage_obj);
            let balance = *smart_table::borrow_mut_with_default(
                &mut public_stage.user_balances,
                user_addr,
                0,
            );
            let total_balance = balance + amount;
            assert!(
                total_balance <= public_stage.max_per_user,
                error::invalid_state(EINSUFFICIENT_MAX_PER_USER_BALANCE),
            );
            smart_table::upsert(&mut public_stage.user_balances, user_addr, total_balance);
        };
    }

    public fun upsert_allowlist(
        owner: &signer,
        collection: Object<Collection>,
        index: u64,
        addr: address,
        amount: u64
    ) acquires MintStageData, MintStage, Allowlist {
        let (_, mint_stage_obj) = authorized_borrow_mut_mint_stage(owner, collection, index);
        assert!(!public_stage_with_limit_exists(mint_stage_obj), ESTAGE_CANNOT_HAVE_MULTIPLE_STAGES);

        if (!allowlist_exists(mint_stage_obj)) {
            move_to(&mint_stage_signer(mint_stage_obj), Allowlist {
                mint_allowances: smart_table::new(),
            });
        };
        smart_table::upsert(&mut borrow_mut_allowlist(mint_stage_obj).mint_allowances, addr, amount);
    }

    public fun remove_from_allowlist(
        owner: &signer,
        collection: Object<Collection>,
        index: u64,
        addr: address,
    ) acquires MintStageData, Allowlist, MintStage {
        let (_, mint_stage_obj) = authorized_borrow_mut_mint_stage(owner, collection, index);
        smart_table::remove(&mut borrow_mut_allowlist(mint_stage_obj).mint_allowances, addr);
    }

    public fun clear_allowlist(
        owner: &signer,
        collection: Object<Collection>,
        index: u64,
    ) acquires MintStageData, MintStage, Allowlist {
        let (_, mint_stage_obj) = authorized_borrow_mut_mint_stage(owner, collection, index);
        smart_table::clear(&mut borrow_mut_allowlist(mint_stage_obj).mint_allowances);
    }

    public fun upsert_public_stage_max_per_user(
        owner: &signer,
        collection: Object<Collection>,
        index: u64,
        max_per_user: u64,
    ) acquires MintStageData, MintStage, PublicMintStageWithLimit {
        let (_, mint_stage_obj) = authorized_borrow_mut_mint_stage(owner, collection, index);
        assert!(!allowlist_exists(mint_stage_obj), ESTAGE_CANNOT_HAVE_MULTIPLE_STAGES);

        if (!public_stage_with_limit_exists(mint_stage_obj)) {
            move_to(&mint_stage_signer(mint_stage_obj), PublicMintStageWithLimit {
                max_per_user,
                user_balances: smart_table::new(),
            });
        } else {
            borrow_mut_public_stage_with_limit(mint_stage_obj).max_per_user = max_per_user;
        }
    }

    public fun destroy(
        owner: &signer,
        collection: Object<Collection>,
    ) acquires MintStageData, MintStage, Allowlist, PublicMintStageWithLimit {
        assert_owner(owner, collection);

        let MintStageData {
            mint_stages,
        } = move_from<MintStageData>(object::object_address(&collection));

        vector::destroy(mint_stages, |mint_stage| {
            destroy_mint_stage(mint_stage);
        });
    }

    inline fun destroy_mint_stage(mint_stage: Object<MintStage>) acquires MintStage {
        let mint_stage_addr = object::object_address(&mint_stage);
        let MintStage { name: _, start_time: _, end_time: _, extend_ref: _, delete_ref } = move_from<MintStage>(
            mint_stage_addr
        );
        if (allowlist_exists(mint_stage)) {
            remove_allowlist_internal(mint_stage);
        };
        if (public_stage_with_limit_exists(mint_stage)) {
            remove_public_stage_with_limit_internal(mint_stage);
        };
        object::delete(delete_ref);
    }

    public fun remove_allowlist_stage(
        owner: &signer,
        collection: Object<Collection>,
        index: u64,
    ) acquires MintStageData, Allowlist, MintStage {
        let (_, mint_stage_obj) = authorized_borrow_mut_mint_stage(owner, collection, index);
        remove_allowlist_internal(mint_stage_obj);
    }

    fun remove_allowlist_internal(mint_stage: Object<MintStage>) acquires Allowlist {
        let Allowlist { mint_allowances } = move_from<Allowlist>(object::object_address(&mint_stage));
        smart_table::destroy(mint_allowances);
    }

    public fun remove_public_stage_with_limit(
        owner: &signer,
        collection: Object<Collection>,
        index: u64,
    ) acquires MintStageData, PublicMintStageWithLimit, MintStage {
        let (_, mint_stage_obj) = authorized_borrow_mut_mint_stage(owner, collection, index);
        remove_public_stage_with_limit_internal(mint_stage_obj);
    }

    fun remove_public_stage_with_limit_internal(mint_stage: Object<MintStage>) acquires PublicMintStageWithLimit {
        let PublicMintStageWithLimit { max_per_user: _, user_balances } = move_from<PublicMintStageWithLimit>(
            object::object_address(&mint_stage),
        );
        smart_table::destroy(user_balances);
    }

    // ====================================== View Functions ====================================== //

    #[view]
    public fun is_active(collection: Object<Collection>, index: u64): bool acquires MintStageData, MintStage {
        let (_, mint_stage_obj) = borrow_mint_stage(collection, index);
        let current_time = timestamp::now_seconds();
        current_time >= mint_stage_start_time(mint_stage_obj) && current_time < mint_stage_end_time(mint_stage_obj)
    }

    #[view]
    public fun allowlist_balance(
        collection: Object<Collection>,
        index: u64,
        addr: address,
    ): u64 acquires MintStageData, MintStage, Allowlist {
        let (_, mint_stage_obj) = borrow_mint_stage(collection, index);
        allowlist_balance_internal(&borrow_allowlist(mint_stage_obj).mint_allowances, addr)
    }

    #[view]
    public fun is_allowlisted(
        collection: Object<Collection>,
        index: u64,
        addr: address
    ): bool acquires MintStageData, MintStage, Allowlist {
        let (_, mint_stage_obj) = borrow_mint_stage(collection, index);
        smart_table::contains(&borrow_allowlist(mint_stage_obj).mint_allowances, addr)
    }

    #[view]
    public fun allowlist_count(
        collection: Object<Collection>,
        index: u64
    ): u64 acquires MintStageData, MintStage, Allowlist {
        let (_, mint_stage_obj) = borrow_mint_stage(collection, index);
        smart_table::length(&borrow_allowlist(mint_stage_obj).mint_allowances)
    }

    #[view]
    public fun is_stage_allowlisted(
        collection: Object<Collection>,
        index: u64
    ): bool acquires MintStageData, MintStage {
        let (_, mint_stage_obj) = borrow_mint_stage(collection, index);
        allowlist_exists(mint_stage_obj)
    }

    #[view]
    public fun start_time(collection: Object<Collection>, index: u64): u64 acquires MintStageData, MintStage {
        let (_, mint_stage_obj) = borrow_mint_stage(collection, index);
        mint_stage_start_time(mint_stage_obj)
    }

    #[view]
    public fun end_time(collection: Object<Collection>, index: u64): u64 acquires MintStageData, MintStage {
        let (_, mint_stage_obj) = borrow_mint_stage(collection, index);
        mint_stage_end_time(mint_stage_obj)
    }

    #[view]
    /// This function returns the categories sorted from the earliest start time.
    public fun stages(collection: Object<Collection>): vector<String> acquires MintStageData, MintStage {
        vector::map_ref(&borrow(collection).mint_stages, |mint_stage| {
            let mint_stage: &Object<MintStage> = mint_stage;
            mint_stage_name(*mint_stage)
        })
    }

    #[view]
    public fun mint_stage_data_exists(collection: Object<Collection>): bool {
        exists<MintStageData>(object::object_address(&collection))
    }

    #[view]
    public fun public_stage_with_limit_user_balance(
        collection: Object<Collection>,
        index: u64,
        user: address,
    ): u64 acquires MintStageData, MintStage, PublicMintStageWithLimit {
        let (_, mint_stage_obj) = borrow_mint_stage(collection, index);
        let public_stage = borrow_public_stage_with_limit(mint_stage_obj);
        if (smart_table::contains(&public_stage.user_balances, user)) {
            let user_balance = *smart_table::borrow(&public_stage.user_balances, user);
            public_stage.max_per_user - user_balance
        } else {
            public_stage.max_per_user
        }
    }

    #[view]
    public fun public_stage_max_per_user(
        collection: Object<Collection>,
        index: u64,
    ): u64 acquires PublicMintStageWithLimit, MintStageData, MintStage {
        let (_, mint_stage_obj) = borrow_mint_stage(collection, index);
        borrow_public_stage_with_limit(mint_stage_obj).max_per_user
    }

    #[view]
    public fun allowlist_exists_with_index(collection: Object<Collection>, index: u64): bool acquires MintStageData {
        let mint_stages = borrow(collection).mint_stages;
        let mint_stage = *vector::borrow(&mint_stages, index);
        allowlist_exists(mint_stage)
    }

    #[view]
    public fun allowlist_exists(mint_stage: Object<MintStage>): bool {
        exists<Allowlist>(object::object_address(&mint_stage))
    }

    #[view]
    public fun public_stage_with_limit_exists_with_index(
        collection: Object<Collection>,
        index: u64,
    ): bool acquires MintStageData {
        let mint_stages = borrow(collection).mint_stages;
        let mint_stage = *vector::borrow(&mint_stages, index);
        public_stage_with_limit_exists(mint_stage)
    }

    #[view]
    public fun public_stage_with_limit_exists(mint_stage: Object<MintStage>): bool {
        exists<PublicMintStageWithLimit>(object::object_address(&mint_stage))
    }

    #[view]
    public fun mint_stage_name(mint_stage: Object<MintStage>): String acquires MintStage {
        borrow_mint_stage_from_object(mint_stage).name
    }

    #[view]
    public fun mint_stage_start_time(mint_stage: Object<MintStage>): u64 acquires MintStage {
        borrow_mint_stage_from_object(mint_stage).start_time
    }

    #[view]
    public fun mint_stage_end_time(mint_stage: Object<MintStage>): u64 acquires MintStage {
        borrow_mint_stage_from_object(mint_stage).end_time
    }

    #[view]
    public fun find_mint_stage_index_by_name(
        collection: Object<Collection>,
        name: String,
    ): u64 acquires MintStageData, MintStage {
        let (is_found, index) = vector::find(&borrow(collection).mint_stages, |mint_stage| {
            let mint_stage: &Object<MintStage> = mint_stage;
            let mint_stage = borrow_mint_stage_from_object(*mint_stage);
            mint_stage.name == name
        });
        assert!(is_found, ESTAGE_DOES_NOT_EXIST);
        index
    }

    #[view]
    public fun find_mint_stage_by_index(
        collection: Object<Collection>,
        index: u64,
    ): Object<MintStage> acquires MintStageData {
        *vector::borrow(&borrow(collection).mint_stages, index)
    }

    inline fun remove_inactive_indexes(stages: &mut vector<Object<MintStage>>, inactive_indexes: &mut vector<u64>) {
        vector::reverse(inactive_indexes);
        for (i in 0..vector::length(inactive_indexes)) {
            vector::remove(stages, *vector::borrow(inactive_indexes, i));
        }
    }

    inline fun get_mint_stage(
        mint_stages: &mut vector<Object<MintStage>>,
        index: u64,
    ): (&mut MintStage, Object<MintStage>) acquires MintStage {
        let mint_stage_obj = *vector::borrow(mint_stages, index);
        let mint_stage = borrow_mut_mint_stage_from_object(mint_stage_obj);
        (mint_stage, mint_stage_obj)
    }

    inline fun borrow_mut_allowlist(mint_stage: Object<MintStage>): &mut Allowlist {
        assert!(allowlist_exists(mint_stage), EALLOWLIST_DOES_NOT_EXIST);
        borrow_global_mut<Allowlist>(object::object_address(&mint_stage))
    }

    inline fun borrow_allowlist(mint_stage: Object<MintStage>): &Allowlist {
        freeze(borrow_mut_allowlist(mint_stage))
    }

    inline fun borrow_mut_public_stage_with_limit(mint_stage: Object<MintStage>): &mut PublicMintStageWithLimit {
        assert!(public_stage_with_limit_exists(mint_stage), EPUBLIC_STAGE_WITH_LIMIT_DOES_NOT_EXIST);
        borrow_global_mut<PublicMintStageWithLimit>(object::object_address(&mint_stage))
    }

    inline fun borrow_public_stage_with_limit(mint_stage: Object<MintStage>): &PublicMintStageWithLimit {
        freeze(borrow_mut_public_stage_with_limit(mint_stage))
    }

    inline fun create_mint_stage_object(
        collection_addr: address,
        name: String,
        start_time: u64,
        end_time: u64,
    ): Object<MintStage> {
        let constructor_ref = &object::create_object(collection_addr);
        move_to(&object::generate_signer(constructor_ref), MintStage {
            name,
            start_time,
            end_time,
            extend_ref: object::generate_extend_ref(constructor_ref),
            delete_ref: object::generate_delete_ref(constructor_ref),
        });
        object::object_from_constructor_ref(constructor_ref)
    }

    inline fun mint_stage_signer(mint_stage: Object<MintStage>): signer acquires MintStage {
        let mint_stage = borrow_mint_stage_from_object(mint_stage);
        object::generate_signer_for_extending(&mint_stage.extend_ref)
    }

    /// This function adds the new stage based on the start and end time of the mint stage.
    /// The categories are sorted from the earliest start time to the latest.
    fun add_to_stages(
        mint_stages: &mut vector<Object<MintStage>>,
        new_stage: Object<MintStage>,
    ) acquires MintStage {
        let len = vector::length(mint_stages);
        let index = 0;

        while (index < len) {
            let current_stage = *vector::borrow(mint_stages, index);
            let current_stage_start_time = mint_stage_start_time(current_stage);
            let new_start_time = mint_stage_start_time(new_stage);
            let new_end_time = mint_stage_end_time(new_stage);
            if (new_start_time < current_stage_start_time
                || (new_start_time == current_stage_start_time && new_end_time < mint_stage_end_time(current_stage))) {
                break
            };
            index = index + 1;
        };

        vector::insert(mint_stages, index, new_stage);
    }

    inline fun allowlist_balance_internal(allowlist: &SmartTable<address, u64>, addr: address): u64 {
        assert!(smart_table::contains(allowlist, addr), error::invalid_state(EUSER_NOT_ALLOWLISTED));
        *smart_table::borrow(allowlist, addr)
    }

    inline fun authorized_borrow_mut_mint_stage(
        owner: &signer,
        collection: Object<Collection>,
        index: u64,
    ): (&mut MintStage, Object<MintStage>) acquires MintStageData {
        let mint_stages = &mut authorized_borrow_mut(owner, collection).mint_stages;
        get_mint_stage(mint_stages, index)
    }

    inline fun authorized_borrow_mut(owner: &signer, collection: Object<Collection>): &mut MintStageData {
        assert_owner(owner, collection);

        assert!(mint_stage_data_exists(collection), error::not_found(EMINT_STAGE_DATA_DOES_NOT_EXIST));
        borrow_global_mut<MintStageData>(object::object_address(&collection))
    }

    inline fun borrow(collection: Object<Collection>): &MintStageData {
        freeze(borrow_mut(collection))
    }

    inline fun borrow_mut(collection: Object<Collection>): &mut MintStageData {
        assert!(mint_stage_data_exists(collection), error::not_found(EMINT_STAGE_DATA_DOES_NOT_EXIST));
        borrow_global_mut<MintStageData>(object::object_address(&collection))
    }

    inline fun borrow_mut_mint_stage_from_object(mint_stage: Object<MintStage>): &mut MintStage {
        let mint_stage_addr = object::object_address(&mint_stage);
        assert!(exists<MintStage>(mint_stage_addr), EMINT_STAGE_DOES_NOT_EXIST);
        borrow_global_mut<MintStage>(mint_stage_addr)
    }

    inline fun borrow_mut_mint_stage(
        collection: Object<Collection>,
        index: u64,
    ): (&mut MintStage, Object<MintStage>) acquires MintStageData {
        let mint_stages = &mut borrow_mut(collection).mint_stages;
        get_mint_stage(mint_stages, index)
    }

    inline fun borrow_mint_stage(
        collection: Object<Collection>,
        index: u64,
    ): (&MintStage, Object<MintStage>) acquires MintStageData {
        borrow_mut_mint_stage(collection, index)
    }

    inline fun borrow_mint_stage_from_object(mint_stage: Object<MintStage>): &MintStage {
        borrow_mut_mint_stage_from_object(mint_stage)
    }

    inline fun valid_start_and_end_time(start_time: u64, end_time: u64) {
        assert!(start_time < end_time, error::invalid_argument(EINVALID_START_TIME));
        assert!(end_time > timestamp::now_seconds(), error::invalid_argument(EINVALID_END_TIME));
    }

    inline fun assert_owner(owner: &signer, collection: Object<Collection>) {
        assert!(object::owner(collection) == signer::address_of(owner), error::unauthenticated(ENOT_OWNER));
    }
}
