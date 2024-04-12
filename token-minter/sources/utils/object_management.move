module minter::object_management {

    use std::error;
    use aptos_framework::object;
    use aptos_framework::object::Object;

    /// The address does not own the object.
    const ENOT_OBJECT_OWNER: u64 = 1;

    public fun assert_owner<T: key>(owner: address, obj: Object<T>) {
        assert!(
            object::owner(obj) == owner,
            error::permission_denied(ENOT_OBJECT_OWNER),
        );
    }
}
